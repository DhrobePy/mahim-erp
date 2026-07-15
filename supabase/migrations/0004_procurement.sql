-- =====================================================================
-- Mahim Packaging ERP — 0004_procurement
-- Inbound procurement per the true-net-weight SOP: gate entry (no
-- financial effect) → QA-adjusted GRN (liability ONLY on accepted true
-- net weight; posts inventory + Mushak 6.1 VAT input vs AP) → automatic
-- debit note documenting the invoice-vs-accepted gap.
-- =====================================================================

create type grn_status as enum ('draft','completed','cancelled');

-- True net weight per the QA SOP: deduct core/tare, then deduct moisture
-- in excess of the 12% allowance.
create or replace function true_net_weight(
  p_gross numeric, p_tare numeric, p_moisture_pct numeric
) returns numeric
language sql immutable as $$
  select round((coalesce(p_gross,0) - coalesce(p_tare,0))
         * (1 - greatest(coalesce(p_moisture_pct,0) - 12, 0) / 100.0), 3);
$$;

-- Which inventory account a stock posting hits, by item type.
create or replace function inventory_account(p_type item_type) returns text
language sql immutable as $$
  select case p_type
    when 'finished_good' then '1310'
    when 'wip'           then '1320'
    else '1300'
  end;
$$;

-- ======================== GATE ENTRIES ==============================
create table gate_entries (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  gate_no             text,
  supplier_party_id   uuid references parties(id),
  vehicle_no          text,
  driver_name         text,
  supplier_invoice_no text,
  invoice_weight      numeric,          -- what the supplier's paper says
  weighbridge_weight  numeric,          -- what the scale says
  status              text not null default 'open',   -- open | received | rejected
  note                text,
  created_by          uuid references auth.users(id),
  created_at          timestamptz not null default now(),
  unique (company_id, gate_no)
);

create or replace function fill_gate_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.gate_no is null then
    new.gate_no := next_document_number(new.company_id, 'gate_entry', 'GTE');
  end if;
  return new;
end; $$;
create trigger trg_gate_no before insert on gate_entries
  for each row execute function fill_gate_no();

-- ============================ GRN ===================================
create table grns (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  grn_no            text,
  gate_entry_id     uuid references gate_entries(id),
  supplier_party_id uuid not null references parties(id),
  warehouse_id      uuid references warehouses(id),
  grn_date          date not null default current_date,
  mushak_61_no      text,               -- supplier's Mushak 6.1 for input credit
  vat_applicable    boolean not null default true,
  vat_rate          numeric not null default 15,
  status            grn_status not null default 'draft',
  note              text,
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  unique (company_id, grn_no)
);

create or replace function fill_grn_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.grn_no is null then
    new.grn_no := next_document_number(new.company_id, 'grn', 'GRN');
  end if;
  return new;
end; $$;
create trigger trg_grn_no before insert on grns
  for each row execute function fill_grn_no();

create table grn_lines (
  id               uuid primary key default gen_random_uuid(),
  grn_id           uuid not null references grns(id) on delete cascade,
  company_id       uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id          uuid not null references items(id),
  invoice_qty      numeric not null default 0,   -- supplier-billed quantity
  gross_weight     numeric,                      -- weighbridge, this line
  core_tare_weight numeric not null default 0,   -- cardboard core deduction
  moisture_pct     numeric not null default 0,   -- QA reading (12% allowed)
  accepted_qty     numeric,                      -- true net; computed on completion if null
  unit_price       numeric not null default 0,
  batch_no         text,                         -- roll/lot id → creates a batch
  is_fsc           boolean not null default false,
  note             text
);

-- ========================= DEBIT NOTES ==============================
-- Documents the gap between what the supplier billed and what QA
-- accepted. No GL effect: liability was only ever booked at accepted
-- value (the debit note is the paper the supplier gets).
create table debit_notes (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id),
  dn_no             text,
  grn_id            uuid not null references grns(id),
  supplier_party_id uuid not null references parties(id),
  qty               numeric not null default 0,
  amount            numeric not null default 0,
  reason            text,
  created_at        timestamptz not null default now(),
  unique (company_id, dn_no)
);

-- ======================= COMPLETE A GRN =============================
-- Transactionally: computes true-net accepted qty per line, creates
-- batches for identified rolls, posts stock IN, posts the journal
-- (Dr Inventory + Dr VAT Input / Cr AP at accepted value only), and
-- issues the automatic debit note for any invoice-vs-accepted gap.
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

-- ============================ RLS ===================================
alter table gate_entries enable row level security;
alter table grns         enable row level security;
alter table grn_lines    enable row level security;
alter table debit_notes  enable row level security;

do $$
declare t text;
begin
  foreach t in array array['gate_entries','grns','grn_lines','debit_notes'] loop
    execute format(
      'create policy %I on %I for select to authenticated using (is_member(company_id));',
      t || '_read', t);
    execute format(
      'create policy %I on %I for all to authenticated using (can_write_company(company_id)) with check (can_write_company(company_id));',
      t || '_write', t);
  end loop;
end $$;
