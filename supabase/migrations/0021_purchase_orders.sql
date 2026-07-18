-- =====================================================================
-- Mahim Packaging ERP — 0021_purchase_orders
-- Procurement previously started only at physical goods arrival (Gate
-- Entry → GRN), with price typed in ad hoc at the GRN line. This adds
-- the missing upstream step: raise a PO to a supplier, get it approved,
-- then receive against it — with landed costs (freight/duty/clearing)
-- allocated across lines so the price that lands on the GRN (and so on
-- stock/GL) reflects true landed cost, not just the ex-factory price.
--
-- po_status enum already existed (0001_init.sql) but was never wired to
-- anything — this is what it was scaffolded for.
-- =====================================================================

create table purchase_orders (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  po_no               text,
  supplier_party_id   uuid not null references parties(id),
  status              po_status not null default 'draft',
  order_date          date not null default current_date,
  expected_date       date,
  currency            text not null default 'BDT',
  -- Landed costs: company-level totals for this PO, allocated across
  -- lines by value share (see v_purchase_order_lines below).
  freight_cost        numeric not null default 0,
  customs_duty        numeric not null default 0,
  clearing_agent_fee  numeric not null default 0,
  other_landed_cost   numeric not null default 0,
  note                text,
  approved_by         uuid references auth.users(id),
  approved_at         timestamptz,
  created_by          uuid references auth.users(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (company_id, po_no)
);
create trigger trg_purchase_orders_updated before update on purchase_orders
  for each row execute function set_updated_at();

create or replace function fill_po_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.po_no is null then
    new.po_no := next_document_number(new.company_id, 'purchase_order', 'PO');
  end if;
  return new;
end; $$;
create trigger trg_po_no before insert on purchase_orders
  for each row execute function fill_po_no();

create table purchase_order_lines (
  id           uuid primary key default gen_random_uuid(),
  po_id        uuid not null references purchase_orders(id) on delete cascade,
  company_id   uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id      uuid not null references items(id),
  qty          numeric not null check (qty > 0),
  unit_price   numeric not null default 0,   -- supplier-quoted, ex-factory
  received_qty numeric not null default 0,   -- running total, updated on GRN completion
  note         text
);

-- Effective landed unit cost per line: ex-factory price plus this
-- line's value-weighted share of the PO's freight/duty/clearing/other,
-- spread over the line's quantity. Recomputes live if landed costs are
-- edited later — nothing is stored/frozen at PO-creation time.
create view v_purchase_order_lines with (security_invoker = true) as
  select
    l.*,
    (l.qty * l.unit_price) as line_value,
    case when totals.total_value > 0
      then l.unit_price + (l.qty * l.unit_price / totals.total_value) * totals.total_landed / nullif(l.qty, 0)
      else l.unit_price
    end as landed_unit_cost
  from purchase_order_lines l
  join (
    select po_id,
      sum(qty * unit_price) as total_value,
      max(freight_cost + customs_duty + clearing_agent_fee + other_landed_cost) as total_landed
    from purchase_order_lines pl
    join purchase_orders po on po.id = pl.po_id
    group by po_id
  ) totals on totals.po_id = l.po_id;

-- Link a GRN line back to what was actually ordered (nullable — a GRN
-- can still be entered standalone with no prior PO, exactly as before).
alter table grn_lines add column if not exists po_line_id uuid references purchase_order_lines(id);

-- ==================== APPROVE / CANCEL ================================
create or replace function approve_purchase_order(p_po_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_po purchase_orders;
begin
  select * into v_po from purchase_orders where id = p_po_id for update;
  if not found then raise exception 'Purchase order not found'; end if;
  if v_po.status <> 'draft' then raise exception 'Only a draft PO can be approved'; end if;
  if not coalesce(has_permission(v_po.company_id, 'purchase_orders', 'write'), false) then
    raise exception 'Not permitted to approve purchase orders for this company';
  end if;
  update purchase_orders
     set status = 'approved', approved_by = auth.uid(), approved_at = now()
   where id = p_po_id;
end; $$;

create or replace function cancel_purchase_order(p_po_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_po purchase_orders;
begin
  select * into v_po from purchase_orders where id = p_po_id for update;
  if not found then raise exception 'Purchase order not found'; end if;
  if v_po.status in ('received', 'closed', 'cancelled') then
    raise exception 'Cannot cancel a % purchase order', v_po.status;
  end if;
  if exists (select 1 from purchase_order_lines where po_id = p_po_id and received_qty > 0) then
    raise exception 'Cannot cancel — some lines already have receipts against them';
  end if;
  if not coalesce(has_permission(v_po.company_id, 'purchase_orders', 'write'), false) then
    raise exception 'Not permitted to cancel purchase orders for this company';
  end if;
  update purchase_orders set status = 'cancelled' where id = p_po_id;
end; $$;

-- ==================== complete_grn: PO receipt bookkeeping =============
-- Additive only — the existing accounting logic (true-net-weight, stock
-- posting, journal, debit note) is untouched byte-for-byte. This adds:
-- after a line posts, if it's linked to a PO line, roll up received_qty
-- and recompute the parent PO's status.
create or replace function complete_grn(p_grn_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_grn        grns;
  v_line       record;
  v_wh         uuid;
  v_batch_id   uuid;
  v_accepted   numeric;
  v_value      numeric := 0;
  v_gap_qty    numeric := 0;
  v_gap_value  numeric := 0;
  v_vat        numeric := 0;
  v_inv_lines  jsonb := '[]'::jsonb;
  v_acc        text;
  v_po_id      uuid;
begin
  select * into v_grn from grns where id = p_grn_id for update;
  if not found then raise exception 'GRN not found'; end if;
  if v_grn.status <> 'draft' then raise exception 'GRN is not draft'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_grn.company_id), false) then
    raise exception 'Not permitted to complete GRNs for this company';
  end if;

  v_wh := coalesce(v_grn.warehouse_id,
                   (select id from warehouses
                     where company_id = v_grn.company_id order by created_at limit 1));
  if v_wh is null then raise exception 'No warehouse configured'; end if;

  for v_line in
    select gl.*, i.item_type from grn_lines gl join items i on i.id = gl.item_id
     where gl.grn_id = p_grn_id
  loop
    v_accepted := coalesce(v_line.accepted_qty,
                           true_net_weight(coalesce(v_line.gross_weight, v_line.invoice_qty),
                                           v_line.core_tare_weight, v_line.moisture_pct));
    if v_accepted <= 0 then raise exception 'Line accepted quantity must be positive'; end if;

    update grn_lines set accepted_qty = v_accepted where id = v_line.id;

    v_batch_id := null;
    if v_line.batch_no is not null then
      insert into batches (company_id, item_id, batch_no, attrs)
      values (v_grn.company_id, v_line.item_id, v_line.batch_no,
              jsonb_build_object('moisture_pct', v_line.moisture_pct,
                                 'is_fsc', v_line.is_fsc,
                                 'grn_no', v_grn.grn_no))
      on conflict (company_id, item_id, batch_no) do update set attrs = excluded.attrs
      returning id into v_batch_id;
    end if;

    insert into stock_movements (company_id, item_id, warehouse_id, movement_type,
                                 quantity, unit_cost, batch_id, ref_table, ref_id,
                                 ref_no, created_by, note)
    values (v_grn.company_id, v_line.item_id, v_wh, 'grn_in', v_accepted,
            v_line.unit_price, v_batch_id, 'grns', v_grn.id, v_grn.grn_no,
            auth.uid(), 'GRN receipt (true net weight)');

    v_value := v_value + v_accepted * v_line.unit_price;

    -- inventory value split by account
    v_acc := inventory_account(v_line.item_type);
    v_inv_lines := v_inv_lines || jsonb_build_array(jsonb_build_object(
      'account', v_acc, 'debit', round(v_accepted * v_line.unit_price, 2)));

    if v_line.invoice_qty > v_accepted then
      v_gap_qty   := v_gap_qty + (v_line.invoice_qty - v_accepted);
      v_gap_value := v_gap_value + (v_line.invoice_qty - v_accepted) * v_line.unit_price;
    end if;

    -- PO receipt bookkeeping (new): roll up received_qty, recompute status.
    if v_line.po_line_id is not null then
      update purchase_order_lines set received_qty = received_qty + v_accepted
       where id = v_line.po_line_id
      returning po_id into v_po_id;

      update purchase_orders po set status = case
          when not exists (
            select 1 from purchase_order_lines l
             where l.po_id = v_po_id and l.received_qty < l.qty
          ) then 'received'::po_status
          else 'partially_received'::po_status
        end
       where po.id = v_po_id and po.status in ('approved', 'partially_received');
    end if;
  end loop;

  if v_value <= 0 then raise exception 'GRN has no value'; end if;

  if v_grn.vat_applicable then
    v_vat := round(v_value * v_grn.vat_rate / 100.0, 2);
    v_inv_lines := v_inv_lines || jsonb_build_array(jsonb_build_object(
      'account', '1260', 'debit', v_vat, 'note', 'Mushak 6.1 ' || coalesce(v_grn.mushak_61_no,'')));
  end if;
  v_inv_lines := v_inv_lines || jsonb_build_array(jsonb_build_object(
    'account', '2100', 'credit', round(v_value + v_vat, 2),
    'party_id', v_grn.supplier_party_id::text));

  perform post_journal(v_grn.company_id, v_grn.grn_date,
                       'GRN ' || v_grn.grn_no || ' (true net weight receipt)',
                       'grns', v_grn.id, v_inv_lines);

  if v_gap_qty > 0 then
    insert into debit_notes (company_id, dn_no, grn_id, supplier_party_id, qty, amount, reason)
    values (v_grn.company_id,
            next_document_number(v_grn.company_id, 'debit_note', 'DN'),
            v_grn.id, v_grn.supplier_party_id, round(v_gap_qty, 3), round(v_gap_value, 2),
            'QA deduction: moisture/tare/short weight vs supplier invoice');
  end if;

  update grns set status = 'completed' where id = p_grn_id;

  if v_grn.gate_entry_id is not null then
    update gate_entries set status = 'received' where id = v_grn.gate_entry_id;
  end if;
end; $$;
revoke execute on function complete_grn(uuid) from anon;

-- ============================ PERMISSIONS =============================
insert into permission_modules (key, group_label, label, sort_order) values
  ('purchase_orders', 'Procurement', 'Purchase orders', 65)
on conflict (key) do nothing;

alter table purchase_orders      enable row level security;
alter table purchase_order_lines enable row level security;

create policy purchase_orders_read on purchase_orders for select to authenticated
  using (has_module_view(company_id, 'purchase_orders'));
create policy purchase_orders_write on purchase_orders for all to authenticated
  using (has_permission(company_id, 'purchase_orders', 'write')) with check (has_permission(company_id, 'purchase_orders', 'write'));

create policy purchase_order_lines_read on purchase_order_lines for select to authenticated
  using (has_module_view(company_id, 'purchase_orders'));
create policy purchase_order_lines_write on purchase_order_lines for all to authenticated
  using (has_permission(company_id, 'purchase_orders', 'write')) with check (has_permission(company_id, 'purchase_orders', 'write'));
