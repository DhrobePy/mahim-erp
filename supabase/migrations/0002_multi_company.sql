-- =====================================================================
-- Mahim Packaging ERP — 0002_multi_company
-- Retrofits the group structure and shared patterns every later module
-- depends on:
--   1. companies (mother + subsidiaries) and per-company memberships;
--      RLS moves from a global profiles.role to (user, company, role).
--   2. parties — unified counterparty master (absorbs suppliers/customers).
--   3. document_series — per-company gapless numbering (Mushak-ready).
--   4. cost_centers — costing dimension on movements and orders.
--   5. batches — roll/lot identity on stock (FSC / moisture traceability).
--
-- All existing rows are assigned to the mother company. company_id columns
-- carry a TEMPORARY default of the mother company so the current UI (which
-- never sends company_id) keeps working; the default is dropped once the
-- company switcher ships.
-- =====================================================================

-- ========================= 1. COMPANIES ==============================
create table companies (
  id                uuid primary key default gen_random_uuid(),
  parent_company_id uuid references companies(id),
  code              text not null unique,
  name              text not null,
  legal_name        text,
  bin_no            text,        -- NBR VAT registration
  tin_no            text,        -- income tax registration
  address           text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create trigger trg_companies_updated before update on companies
  for each row execute function set_updated_at();

-- Mother company with a fixed id so column defaults can reference it.
insert into companies (id, code, name, legal_name)
values ('00000000-0000-0000-0000-000000000001', 'MAHIM', 'Mahim Packaging',
        'Mahim Packaging Ltd.');

create table company_members (
  user_id    uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  role       user_role not null default 'viewer',
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (user_id, company_id)
);

-- Carry existing global roles over as mother-company memberships.
insert into company_members (user_id, company_id, role)
select id, '00000000-0000-0000-0000-000000000001', role from profiles;

-- Membership helpers. SECURITY DEFINER so they can read company_members
-- from inside RLS policies without recursion.
create or replace function member_role(p_company uuid) returns user_role
language sql stable security definer set search_path = public as $$
  select role from company_members
   where user_id = auth.uid() and company_id = p_company and is_active;
$$;

create or replace function is_member(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select member_role(p_company) is not null;
$$;

create or replace function can_write_company(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select member_role(p_company) in ('admin','manager','store','production');
$$;

create or replace function is_any_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from company_members
                  where user_id = auth.uid() and role = 'admin' and is_active);
$$;

-- profiles.role is superseded by company_members. Drop every policy that
-- depends on app_role() (the 0001 generic read/write pairs), then the
-- function, then the column itself. New membership-scoped policies are
-- created in section 8.
do $$
declare t text;
begin
  foreach t in array array[
    'uoms','item_categories','items','warehouses','suppliers','customers',
    'stock_movements','boms','bom_lines','production_orders','production_materials'
  ] loop
    execute format('drop policy %I on %I;', t || '_read',  t);
    execute format('drop policy %I on %I;', t || '_write', t);
  end loop;
end $$;
drop policy p_profiles_admin on profiles;
drop function app_role();
alter table profiles drop column role;

create policy p_profiles_admin on profiles for all to authenticated
  using (is_any_admin()) with check (is_any_admin());

-- New signups get a profile but NO membership: they see nothing until a
-- company admin grants one (see README).
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end; $$;

-- ============== 2. company_id ON EVERY BUSINESS TABLE ================
-- Uniqueness that was global becomes per-company.
alter table uoms
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
alter table uoms drop constraint uoms_code_key;
alter table uoms add constraint uoms_company_code_key unique (company_id, code);

alter table item_categories
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
alter table item_categories drop constraint item_categories_name_key;
alter table item_categories add constraint item_categories_company_name_key unique (company_id, name);

alter table items
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
alter table items drop constraint items_sku_key;
alter table items add constraint items_company_sku_key unique (company_id, sku);

alter table warehouses
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
alter table warehouses drop constraint warehouses_code_key;
alter table warehouses add constraint warehouses_company_code_key unique (company_id, code);

alter table stock_movements
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
create index idx_sm_company on stock_movements(company_id);

alter table boms
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
alter table bom_lines
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);

alter table production_orders
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);
alter table production_orders drop constraint production_orders_order_no_key;
alter table production_orders add constraint production_orders_company_order_no_key unique (company_id, order_no);

alter table production_materials
  add column company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id);

-- ========================= 3. PARTIES ================================
-- One counterparty master: a party can be customer, supplier, transporter
-- and/or bank at once. Absorbs and replaces the suppliers/customers stubs.
create table parties (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  code           text not null,
  name           text not null,
  is_customer    boolean not null default false,
  is_supplier    boolean not null default false,
  is_transporter boolean not null default false,
  is_bank        boolean not null default false,
  phone          text,
  email          text,
  address        text,
  bin_no         text,        -- counterparty VAT registration (Mushak docs)
  tin_no         text,
  is_active      boolean not null default true,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (company_id, code)
);
create trigger trg_parties_updated before update on parties
  for each row execute function set_updated_at();

insert into parties (company_id, code, name, is_supplier, phone, email, address, is_active, created_at)
select '00000000-0000-0000-0000-000000000001', code, name, true, phone, email, address, is_active, created_at
  from suppliers
on conflict (company_id, code) do update set is_supplier = true;

insert into parties (company_id, code, name, is_customer, phone, email, address, is_active, created_at)
select '00000000-0000-0000-0000-000000000001', code, name, true, phone, email, address, is_active, created_at
  from customers
on conflict (company_id, code) do update set is_customer = true;

drop table suppliers;
drop table customers;

-- ===================== 4. DOCUMENT SERIES ============================
-- Per-company gapless numbering. Statutory documents (Mushak 6.3 challans,
-- invoices) MUST come from here; internal series (pre-LC original challans,
-- production orders) use their own doc_type so official sequences stay
-- unbroken. Update-returning under row lock is gapless: a rolled-back
-- document rolls its number back too.
create table document_series (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id),
  doc_type   text not null,          -- e.g. 'production_order','challan_official','challan_internal'
  prefix     text not null,
  pad        int  not null default 5,
  next_no    bigint not null default 1,
  unique (company_id, doc_type)
);

create or replace function next_document_number(
  p_company uuid, p_doc_type text, p_prefix text default null
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_no bigint; v_prefix text; v_pad int;
begin
  -- coalesce matters: a non-member gets NULL from can_write_company(),
  -- and "if not null" would silently skip the check.
  if auth.uid() is not null and not coalesce(can_write_company(p_company), false) then
    raise exception 'Not permitted to issue documents for this company';
  end if;
  if p_prefix is not null then
    insert into document_series (company_id, doc_type, prefix)
    values (p_company, p_doc_type, p_prefix)
    on conflict (company_id, doc_type) do nothing;
  end if;
  update document_series
     set next_no = next_no + 1
   where company_id = p_company and doc_type = p_doc_type
  returning next_no - 1, prefix, pad into v_no, v_prefix, v_pad;
  if not found then
    raise exception 'No document series "%" for company %', p_doc_type, p_company;
  end if;
  return v_prefix || '-' || lpad(v_no::text, v_pad, '0');
end; $$;
revoke execute on function next_document_number(uuid, text, text) from anon;

-- Production orders now number per company through the series.
create or replace function fill_prod_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.order_no is null then
    new.order_no := next_document_number(new.company_id, 'production_order', 'PRD');
  end if;
  return new;
end; $$;
drop sequence if exists seq_prod_no;

-- ======================= 5. COST CENTERS =============================
create table cost_centers (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  code       text not null,
  name       text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code)
);

alter table stock_movements   add column cost_center_id uuid references cost_centers(id);
alter table production_orders add column cost_center_id uuid references cost_centers(id);

-- ========================= 6. BATCHES ================================
-- Roll/lot identity. attrs holds QA facts (moisture_pct, is_fsc, actual
-- gsm, supplier lot no) so FSC allocation locks and moisture history work
-- without schema churn. batch_id stays nullable: aggregate items simply
-- never set it.
create table batches (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id     uuid not null references items(id),
  batch_no    text not null,
  attrs       jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  unique (company_id, item_id, batch_no)
);

alter table stock_movements add column batch_id uuid references batches(id);

-- Rebuild stock views with company scope. security_invoker makes the view
-- respect RLS (default views run as owner and would leak across companies).
drop view current_stock;
create view current_stock with (security_invoker = true) as
  select
    company_id,
    item_id,
    warehouse_id,
    sum(quantity)             as qty,
    sum(quantity * unit_cost) as stock_value
  from stock_movements
  group by company_id, item_id, warehouse_id;

create view batch_stock with (security_invoker = true) as
  select
    company_id,
    item_id,
    warehouse_id,
    batch_id,
    sum(quantity) as qty
  from stock_movements
  where batch_id is not null
  group by company_id, item_id, warehouse_id, batch_id;

-- ============= 7. PRODUCTION COMPLETION (company-aware) ==============
create or replace function complete_production_order(p_order_id uuid, p_qty numeric)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_order    production_orders;
  v_line     record;
  v_factor   numeric;
  v_wh       uuid;
begin
  select * into v_order from production_orders where id = p_order_id for update;
  if not found then raise exception 'Production order not found'; end if;
  if v_order.status = 'completed' then raise exception 'Order already completed'; end if;
  if coalesce(p_qty, 0) <= 0 then raise exception 'Quantity must be positive'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_order.company_id), false) then
    raise exception 'Not permitted to post production for this company';
  end if;

  v_wh := coalesce(v_order.warehouse_id,
                   (select id from warehouses
                     where company_id = v_order.company_id
                     order by created_at limit 1));
  if v_wh is null then raise exception 'No warehouse configured'; end if;

  insert into stock_movements(company_id, item_id, warehouse_id, movement_type, quantity,
                              unit_cost, cost_center_id, ref_table, ref_id, ref_no, created_by, note)
  values (v_order.company_id, v_order.finished_item_id, v_wh, 'production_in', p_qty, 0,
          v_order.cost_center_id, 'production_orders', v_order.id, v_order.order_no,
          auth.uid(), 'Production output');

  if v_order.bom_id is not null then
    select p_qty / nullif(b.output_qty, 0) into v_factor from boms b where b.id = v_order.bom_id;
    for v_line in select * from bom_lines where bom_id = v_order.bom_id loop
      insert into stock_movements(company_id, item_id, warehouse_id, movement_type, quantity,
                                  unit_cost, cost_center_id, ref_table, ref_id, ref_no, created_by, note)
      values (v_order.company_id, v_line.component_item_id, v_wh, 'production_out',
              -1 * v_line.qty_per * v_factor * (1 + coalesce(v_line.wastage_pct, 0) / 100.0),
              0, v_order.cost_center_id, 'production_orders', v_order.id, v_order.order_no,
              auth.uid(), 'Material consumption');
    end loop;
  end if;

  update production_orders
     set produced_qty = produced_qty + p_qty,
         status       = 'completed',
         completed_at = now(),
         updated_at   = now()
   where id = p_order_id;
end; $$;

-- ===================== 8. MEMBERSHIP-SCOPED RLS ======================
alter table companies       enable row level security;
alter table company_members enable row level security;
alter table parties         enable row level security;
alter table document_series enable row level security;
alter table cost_centers    enable row level security;
alter table batches         enable row level security;

create policy p_companies_read on companies for select to authenticated
  using (is_member(id) or is_any_admin());
create policy p_companies_admin on companies for all to authenticated
  using (is_any_admin()) with check (is_any_admin());

create policy p_cm_read_own on company_members for select to authenticated
  using (user_id = auth.uid());
create policy p_cm_admin on company_members for all to authenticated
  using (member_role(company_id) = 'admin')
  with check (member_role(company_id) = 'admin');

-- Membership-scoped read/write policies on every company-carrying table
-- (the 0001 global policies were dropped in section 1).
do $$
declare t text;
begin
  foreach t in array array[
    'uoms','item_categories','items','warehouses',
    'stock_movements','boms','bom_lines','production_orders','production_materials',
    'parties','document_series','cost_centers','batches'
  ] loop
    execute format(
      'create policy %I on %I for select to authenticated using (is_member(company_id));',
      t || '_read', t);
    execute format(
      'create policy %I on %I for all to authenticated using (can_write_company(company_id)) with check (can_write_company(company_id));',
      t || '_write', t);
  end loop;
end $$;
