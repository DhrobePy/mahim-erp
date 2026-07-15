-- =====================================================================
-- Mahim Packaging ERP — 0005_sales_lc
-- Sales spine with BOTH delivery realities:
--   Flow A (LC in hand):   standard challan → invoice.
--   Flow B (verbal order): original challan (internal series, posts
--     stock out into Goods-Delivered-Not-Invoiced) → LC arrives →
--     covering challan (official series, marked + linked, NO posting)
--     → invoice (posts revenue, clears GDNI).
-- Stock moves exactly once and revenue posts exactly once per delivery;
-- the posting engine decides by challan kind, not user discipline.
-- LCs are versioned master-child (lc_amendments); documents validate
-- against the latest version via lc_active_terms.
-- =====================================================================

create type challan_kind   as enum ('standard','original','covering');
create type challan_status as enum ('draft','issued','delivered_unbilled','covered','invoiced','cancelled');
create type so_status      as enum ('open','partially_delivered','delivered','closed','cancelled');
create type lc_status      as enum ('active','closed','cancelled');

-- ======================== SALES ORDERS ==============================
create table sales_orders (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  so_no             text,
  customer_party_id uuid not null references parties(id),
  order_date        date not null default current_date,
  lc_id             uuid,               -- may arrive AFTER delivery (flow B)
  status            so_status not null default 'open',
  is_deemed_export  boolean not null default true,
  note              text,
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  unique (company_id, so_no)
);

create or replace function fill_so_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.so_no is null then
    new.so_no := next_document_number(new.company_id, 'sales_order', 'SO');
  end if;
  return new;
end; $$;
create trigger trg_so_no before insert on sales_orders
  for each row execute function fill_so_no();

create table sales_order_lines (
  id            uuid primary key default gen_random_uuid(),
  so_id         uuid not null references sales_orders(id) on delete cascade,
  company_id    uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id       uuid not null references items(id),
  qty           numeric not null,
  unit_price    numeric not null default 0,
  delivered_qty numeric not null default 0
);

-- ====================== LOCAL LCs (versioned) =======================
create table lcs (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  lc_no           text not null,          -- issuing bank's LC number
  buyer_party_id  uuid not null references parties(id),
  bank_party_id   uuid references parties(id),   -- issuing bank
  lc_type         text not null default 'usance',  -- sight | usance
  usance_days     int  not null default 90,
  currency        text not null default 'BDT',
  status          lc_status not null default 'active',
  opened_at       date not null default current_date,
  note            text,
  created_at      timestamptz not null default now(),
  unique (company_id, lc_no)
);

alter table sales_orders
  add constraint sales_orders_lc_fk foreign key (lc_id) references lcs(id);

-- Master-child versioning: v1 = original terms, v2+ = MT707 amendments.
-- Documents always validate against the LATEST version.
create table lc_amendments (
  id            uuid primary key default gen_random_uuid(),
  lc_id         uuid not null references lcs(id) on delete cascade,
  company_id    uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  version       int not null,
  amount        numeric not null default 0,
  quantity      numeric,
  tolerance_pct numeric not null default 5,
  expiry_date   date,
  ship_date     date,
  bank_fee      numeric not null default 0,   -- MT707 fee if on beneficiary
  note          text,
  created_at    timestamptz not null default now(),
  unique (lc_id, version)
);

create view lc_active_terms with (security_invoker = true) as
  select distinct on (a.lc_id)
    a.lc_id, l.lc_no, l.company_id, l.buyer_party_id, l.bank_party_id,
    l.lc_type, l.usance_days, l.status,
    a.version, a.amount, a.quantity, a.tolerance_pct, a.expiry_date, a.ship_date
  from lc_amendments a
  join lcs l on l.id = a.lc_id
  order by a.lc_id, a.version desc;

-- Amendment bank fees on beneficiary account hit the P&L immediately.
create or replace function record_lc_amendment_fee() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.bank_fee > 0 then
    perform post_journal(new.company_id, current_date,
      'LC amendment fee v' || new.version || ' (MT707)',
      'lc_amendments', new.id,
      jsonb_build_array(
        jsonb_build_object('account','5400','debit', new.bank_fee),
        jsonb_build_object('account','1100','credit', new.bank_fee)));
  end if;
  return new;
end; $$;
create trigger trg_lc_amendment_fee after insert on lc_amendments
  for each row execute function record_lc_amendment_fee();

-- ====================== DELIVERY CHALLANS ===========================
create table delivery_challans (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  challan_no           text,
  challan_kind         challan_kind not null default 'standard',
  covers_challan_id    uuid references delivery_challans(id),
  so_id                uuid references sales_orders(id),
  lc_id                uuid references lcs(id),
  customer_party_id    uuid not null references parties(id),
  warehouse_id         uuid references warehouses(id),
  status               challan_status not null default 'draft',
  actual_delivery_date date not null default current_date,  -- reality
  document_date        date not null default current_date,  -- what prints
  note                 text,
  created_by           uuid references auth.users(id),
  created_at           timestamptz not null default now(),
  unique (company_id, challan_no),
  -- covering docs must reference an original; others must not
  check ((challan_kind = 'covering') = (covers_challan_id is not null))
);

-- Official (Mushak 6.3) series for standard + covering; internal series
-- for pre-LC originals, so the statutory sequence never gaps.
create or replace function fill_challan_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.challan_no is null then
    if new.challan_kind = 'original' then
      new.challan_no := next_document_number(new.company_id, 'challan_internal', 'IDC');
    else
      new.challan_no := next_document_number(new.company_id, 'challan_official', 'DC');
    end if;
  end if;
  return new;
end; $$;
create trigger trg_challan_no before insert on delivery_challans
  for each row execute function fill_challan_no();

create table delivery_challan_lines (
  id         uuid primary key default gen_random_uuid(),
  challan_id uuid not null references delivery_challans(id) on delete cascade,
  company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id    uuid not null references items(id),
  qty        numeric not null,
  unit_price numeric not null default 0,
  batch_id   uuid references batches(id)
);

-- ========================= INVOICES =================================
create table invoices (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id),
  invoice_no        text,
  customer_party_id uuid not null references parties(id),
  challan_id        uuid not null references delivery_challans(id),
  so_id             uuid references sales_orders(id),
  lc_id             uuid references lcs(id),
  invoice_date      date not null default current_date,
  is_deemed_export  boolean not null default true,
  total             numeric not null default 0,
  cogs_total        numeric not null default 0,
  status            text not null default 'open',   -- open | billed | settled
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  unique (company_id, invoice_no)
);

create table invoice_lines (
  id         uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references invoices(id) on delete cascade,
  company_id uuid not null references companies(id),
  item_id    uuid not null references items(id),
  qty        numeric not null,
  unit_price numeric not null default 0
);

-- ==================== CREDIT NOTES (returns) ========================
create table credit_notes (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id),
  cn_no             text,
  invoice_id        uuid not null references invoices(id),
  customer_party_id uuid not null references parties(id),
  item_id           uuid not null references items(id),
  qty               numeric not null,
  unit_price        numeric not null,      -- invoiced price being reversed
  scrap_unit_value  numeric not null default 0,
  reason            text,
  created_at        timestamptz not null default now(),
  unique (company_id, cn_no)
);

-- ======================== ISSUE A CHALLAN ===========================
-- Physically dispatches goods. Posting by kind:
--   standard → stock OUT only (COGS + inventory GL land at invoice)
--   original → stock OUT + Dr GDNI / Cr Inventory-FG at standard cost
--   covering → REFUSED here: covering docs never move stock
create or replace function issue_challan(p_challan_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ch    delivery_challans;
  v_line  record;
  v_wh    uuid;
  v_cost  numeric := 0;
begin
  select * into v_ch from delivery_challans where id = p_challan_id for update;
  if not found then raise exception 'Challan not found'; end if;
  if v_ch.status <> 'draft' then raise exception 'Challan is not draft'; end if;
  if v_ch.challan_kind = 'covering' then
    raise exception 'Covering challans are documentation only — use create_covering_set';
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_ch.company_id), false) then
    raise exception 'Not permitted to issue challans for this company';
  end if;

  v_wh := coalesce(v_ch.warehouse_id,
                   (select id from warehouses
                     where company_id = v_ch.company_id and code = 'FG' limit 1),
                   (select id from warehouses
                     where company_id = v_ch.company_id order by created_at limit 1));
  if v_wh is null then raise exception 'No warehouse configured'; end if;

  if not exists (select 1 from delivery_challan_lines where challan_id = p_challan_id) then
    raise exception 'Challan has no lines';
  end if;

  for v_line in
    select dcl.*, i.standard_cost from delivery_challan_lines dcl
    join items i on i.id = dcl.item_id where dcl.challan_id = p_challan_id
  loop
    if v_line.qty <= 0 then raise exception 'Challan line qty must be positive'; end if;
    insert into stock_movements (company_id, item_id, warehouse_id, movement_type,
                                 quantity, unit_cost, batch_id, ref_table, ref_id,
                                 ref_no, created_by, note)
    values (v_ch.company_id, v_line.item_id, v_wh, 'sales_out', -v_line.qty,
            v_line.standard_cost, v_line.batch_id, 'delivery_challans', v_ch.id,
            v_ch.challan_no, auth.uid(),
            case v_ch.challan_kind when 'original' then 'Pre-LC delivery (GDNI)'
                                   else 'Delivery against ' || coalesce((select lc_no from lcs where id = v_ch.lc_id), 'order') end);
    v_cost := v_cost + v_line.qty * coalesce(v_line.standard_cost, 0);

    -- keep SO fulfilment in step with physical dispatch
    if v_ch.so_id is not null then
      update sales_order_lines
         set delivered_qty = delivered_qty + v_line.qty
       where so_id = v_ch.so_id and item_id = v_line.item_id;
    end if;
  end loop;

  if v_ch.challan_kind = 'original' then
    if v_cost > 0 then
      perform post_journal(v_ch.company_id, v_ch.actual_delivery_date,
        'Pre-LC delivery ' || v_ch.challan_no || ' → GDNI',
        'delivery_challans', v_ch.id,
        jsonb_build_array(
          jsonb_build_object('account','1220','debit', round(v_cost,2)),
          jsonb_build_object('account','1310','credit', round(v_cost,2))));
    end if;
    update delivery_challans set status = 'delivered_unbilled' where id = p_challan_id;
  else
    update delivery_challans set status = 'issued' where id = p_challan_id;
  end if;

  if v_ch.so_id is not null then
    update sales_orders so set status =
      case when not exists (select 1 from sales_order_lines l
                             where l.so_id = so.id and l.delivered_qty < l.qty * 0.95)
           then 'delivered'::so_status else 'partially_delivered'::so_status end
     where so.id = v_ch.so_id and so.status in ('open','partially_delivered');
  end if;
end; $$;
revoke execute on function issue_challan(uuid) from anon;

-- ===================== COVERING DOCUMENT SET ========================
-- The LC has arrived for goods already delivered on an original challan.
-- Issues the official-series covering challan, dated to the LC, linked
-- to the original. NO stock movement, NO journal — print artifact only.
create or replace function create_covering_set(
  p_original_id uuid, p_lc_id uuid, p_document_date date
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_orig     delivery_challans;
  v_cover_id uuid;
begin
  select * into v_orig from delivery_challans where id = p_original_id for update;
  if not found then raise exception 'Original challan not found'; end if;
  if v_orig.challan_kind <> 'original' then
    raise exception 'Only pre-LC original challans can be covered';
  end if;
  if v_orig.status <> 'delivered_unbilled' then
    raise exception 'Original challan is % — must be delivered_unbilled', v_orig.status;
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_orig.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if (select company_id from lcs where id = p_lc_id) <> v_orig.company_id then
    raise exception 'LC belongs to a different company';
  end if;

  insert into delivery_challans (company_id, challan_kind, covers_challan_id, so_id,
                                 lc_id, customer_party_id, warehouse_id, status,
                                 actual_delivery_date, document_date, created_by, note)
  values (v_orig.company_id, 'covering', v_orig.id, v_orig.so_id, p_lc_id,
          v_orig.customer_party_id, v_orig.warehouse_id, 'issued',
          v_orig.actual_delivery_date, coalesce(p_document_date, current_date),
          auth.uid(), 'Covers ' || v_orig.challan_no)
  returning id into v_cover_id;

  insert into delivery_challan_lines (challan_id, company_id, item_id, qty, unit_price, batch_id)
  select v_cover_id, company_id, item_id, qty, unit_price, batch_id
    from delivery_challan_lines where challan_id = v_orig.id;

  update delivery_challans set status = 'covered', lc_id = p_lc_id
   where id = v_orig.id;
  update sales_orders set lc_id = p_lc_id
   where id = v_orig.so_id and lc_id is null;

  return v_cover_id;
end; $$;
revoke execute on function create_covering_set(uuid, uuid, date) from anon;

-- ====================== INVOICE A CHALLAN ===========================
-- Flow A (standard):  Dr Bills Receivable/AR, Cr Revenue;
--                     Dr COGS, Cr Inventory-FG.
-- Flow B (covering):  Dr Bills Receivable/AR, Cr Revenue;
--                     Dr COGS, Cr GDNI  (stock left at original issue).
create or replace function create_invoice_from_challan(
  p_challan_id uuid, p_invoice_date date default current_date
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_ch      delivery_challans;
  v_so      sales_orders;
  v_line    record;
  v_inv_id  uuid;
  v_total   numeric := 0;
  v_cogs    numeric := 0;
  v_ar      text;
  v_rev     text;
  v_deemed  boolean := true;
begin
  select * into v_ch from delivery_challans where id = p_challan_id for update;
  if not found then raise exception 'Challan not found'; end if;
  if not (v_ch.challan_kind in ('standard','covering') and v_ch.status = 'issued') then
    raise exception 'Challan must be an issued standard or covering challan (got % / %)',
      v_ch.challan_kind, v_ch.status;
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_ch.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  if v_ch.so_id is not null then
    select * into v_so from sales_orders where id = v_ch.so_id;
    v_deemed := coalesce(v_so.is_deemed_export, true);
  end if;

  insert into invoices (company_id, invoice_no, customer_party_id, challan_id, so_id,
                        lc_id, invoice_date, is_deemed_export, created_by)
  values (v_ch.company_id,
          next_document_number(v_ch.company_id, 'invoice', 'INV'),
          v_ch.customer_party_id, v_ch.id, v_ch.so_id, v_ch.lc_id,
          coalesce(p_invoice_date, current_date), v_deemed, auth.uid())
  returning id into v_inv_id;

  for v_line in
    select dcl.*, i.standard_cost from delivery_challan_lines dcl
    join items i on i.id = dcl.item_id where dcl.challan_id = p_challan_id
  loop
    insert into invoice_lines (invoice_id, company_id, item_id, qty, unit_price)
    values (v_inv_id, v_ch.company_id, v_line.item_id, v_line.qty, v_line.unit_price);
    v_total := v_total + v_line.qty * v_line.unit_price;
    v_cogs  := v_cogs  + v_line.qty * coalesce(v_line.standard_cost, 0);
  end loop;
  if v_total <= 0 then raise exception 'Invoice has no value'; end if;

  v_ar  := case when v_ch.lc_id is not null then '1210' else '1200' end;
  v_rev := case when v_deemed then '4100' else '4200' end;

  perform post_journal(v_ch.company_id, coalesce(p_invoice_date, current_date),
    'Invoice for challan ' || v_ch.challan_no ||
      case v_ch.challan_kind when 'covering' then ' (covering set, clears GDNI)' else '' end,
    'invoices', v_inv_id,
    jsonb_build_array(
      jsonb_build_object('account', v_ar, 'debit', round(v_total,2),
                         'party_id', v_ch.customer_party_id::text),
      jsonb_build_object('account', v_rev, 'credit', round(v_total,2)),
      jsonb_build_object('account','5100','debit', round(v_cogs,2)),
      jsonb_build_object('account',
        case v_ch.challan_kind when 'covering' then '1220' else '1310' end,
        'credit', round(v_cogs,2))));

  update invoices set total = round(v_total,2), cogs_total = round(v_cogs,2)
   where id = v_inv_id;
  update delivery_challans set status = 'invoiced' where id = p_challan_id;

  return v_inv_id;
end; $$;
revoke execute on function create_invoice_from_challan(uuid, date) from anon;

-- ===================== SALES RETURN (rejection) =====================
-- RMG buyer rejects branded cartons: reverse revenue, downgrade the
-- returned stock straight to scrap at realizable value (recovery
-- credited against COGS), realized loss visible as the gap.
create or replace function process_sales_return(
  p_invoice_id uuid, p_item_id uuid, p_qty numeric,
  p_scrap_unit_value numeric, p_reason text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_inv   invoices;
  v_price numeric;
  v_wh    uuid;
  v_cn_id uuid;
  v_ar    text;
begin
  select * into v_inv from invoices where id = p_invoice_id;
  if not found then raise exception 'Invoice not found'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_inv.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  select unit_price into v_price from invoice_lines
   where invoice_id = p_invoice_id and item_id = p_item_id limit 1;
  if v_price is null then raise exception 'Item not on this invoice'; end if;
  if p_qty <= 0 then raise exception 'Return qty must be positive'; end if;

  v_wh := (select id from warehouses
            where company_id = v_inv.company_id order by created_at limit 1);

  insert into credit_notes (company_id, cn_no, invoice_id, customer_party_id,
                            item_id, qty, unit_price, scrap_unit_value, reason)
  values (v_inv.company_id,
          next_document_number(v_inv.company_id, 'credit_note', 'CN'),
          p_invoice_id, v_inv.customer_party_id, p_item_id, p_qty, v_price,
          coalesce(p_scrap_unit_value, 0), p_reason)
  returning id into v_cn_id;

  insert into stock_movements (company_id, item_id, warehouse_id, movement_type,
                               quantity, unit_cost, ref_table, ref_id, created_by, note)
  values (v_inv.company_id, p_item_id, v_wh, 'sales_return_in', p_qty,
          coalesce(p_scrap_unit_value,0), 'credit_notes', v_cn_id, auth.uid(),
          'Buyer rejection — downgraded to scrap value');

  v_ar := case when v_inv.lc_id is not null then '1210' else '1200' end;
  perform post_journal(v_inv.company_id, current_date,
    'Sales return / credit note against invoice',
    'credit_notes', v_cn_id,
    jsonb_build_array(
      jsonb_build_object('account', case when v_inv.is_deemed_export then '4100' else '4200' end,
                         'debit', round(p_qty * v_price, 2)),
      jsonb_build_object('account', v_ar, 'credit', round(p_qty * v_price, 2),
                         'party_id', v_inv.customer_party_id::text)
      )
      || case when coalesce(p_scrap_unit_value,0) > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1330','debit', round(p_qty * p_scrap_unit_value, 2)),
          jsonb_build_object('account','5100','credit', round(p_qty * p_scrap_unit_value, 2)))
        else '[]'::jsonb end);

  return v_cn_id;
end; $$;
revoke execute on function process_sales_return(uuid, uuid, numeric, numeric, text) from anon;

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array[
    'sales_orders','sales_order_lines','lcs','lc_amendments',
    'delivery_challans','delivery_challan_lines','invoices','invoice_lines','credit_notes'
  ] loop
    execute format('alter table %I enable row level security;', t);
    execute format(
      'create policy %I on %I for select to authenticated using (is_member(company_id));',
      t || '_read', t);
    execute format(
      'create policy %I on %I for all to authenticated using (can_write_company(company_id)) with check (can_write_company(company_id));',
      t || '_write', t);
  end loop;
end $$;
