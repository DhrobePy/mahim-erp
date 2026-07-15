-- =====================================================================
-- Mahim Packaging ERP — 0001_init
-- Scope: Inventory + Production core (single company, multi-user)
-- Designed so Sales/Local-LC and LBPD modules bolt on later without
-- restructuring: stock_movements is the single source of truth for stock,
-- and customers/suppliers/documents share the same reference pattern.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ============================ ENUMS ==================================
create type user_role           as enum ('admin','manager','store','production','sales','accounts','viewer');
create type item_type           as enum ('raw_material','wip','finished_good','consumable','packaging');
create type stock_movement_type as enum ('opening','grn_in','production_in','production_out','sales_out','adjustment','transfer_in','transfer_out');
create type po_status           as enum ('draft','approved','partially_received','received','closed','cancelled');
create type production_status    as enum ('planned','released','in_progress','completed','cancelled');

-- ===================== SHARED HELPERS ================================
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

-- ========================= PROFILES =================================
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  role       user_role   not null default 'viewer',
  is_active  boolean     not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_profiles_updated before update on profiles
  for each row execute function set_updated_at();

-- Current user's application role (defaults to 'viewer' if no profile row).
create or replace function app_role() returns user_role
language sql stable security definer set search_path = public as $$
  select coalesce((select role from profiles where id = auth.uid()), 'viewer'::user_role);
$$;

-- Auto-create a profile whenever a new auth user signs up.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), 'viewer')
  on conflict (id) do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ==================== MASTER: UOM / CATEGORY ========================
create table uoms (
  id         uuid primary key default gen_random_uuid(),
  code       text unique not null,
  name       text not null,
  created_at timestamptz not null default now()
);

create table item_categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  parent_id  uuid references item_categories(id),
  created_at timestamptz not null default now()
);

-- ========================== ITEMS ===================================
create table items (
  id             uuid primary key default gen_random_uuid(),
  sku            text unique not null,
  name           text not null,
  item_type      item_type not null default 'raw_material',
  category_id    uuid references item_categories(id),
  uom_id         uuid references uoms(id),
  -- packaging-specific spec attributes
  gsm            numeric,          -- grammage (paper / board / film)
  size_spec      text,             -- reel width / sheet size / dimensions
  color          text,
  reorder_level  numeric not null default 0,
  standard_cost  numeric not null default 0,
  is_active      boolean not null default true,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index idx_items_type on items(item_type);
create trigger trg_items_updated before update on items
  for each row execute function set_updated_at();

-- ======================= WAREHOUSES =================================
create table warehouses (
  id         uuid primary key default gen_random_uuid(),
  code       text unique not null,
  name       text not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- ================== SUPPLIERS / CUSTOMERS ===========================
-- Customers included now as a stub so the Sales/Local-LC module can extend
-- it later (LC fields, credit terms) without a disruptive migration.
create table suppliers (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,
  name         text not null,
  phone        text,
  email        text,
  address      text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table customers (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,
  name         text not null,
  phone        text,
  email        text,
  address      text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

-- ================ STOCK LEDGER (source of truth) ====================
-- Quantity is signed: positive = into stock, negative = out of stock.
create table stock_movements (
  id            uuid primary key default gen_random_uuid(),
  item_id       uuid not null references items(id),
  warehouse_id  uuid not null references warehouses(id),
  movement_type stock_movement_type not null,
  quantity      numeric not null,
  unit_cost     numeric not null default 0,
  ref_table     text,            -- source document table
  ref_id        uuid,            -- source document id
  ref_no        text,            -- human-readable reference
  moved_at      timestamptz not null default now(),
  created_by    uuid references auth.users(id),
  note          text
);
create index idx_sm_item on stock_movements(item_id);
create index idx_sm_wh   on stock_movements(warehouse_id);
create index idx_sm_ref  on stock_movements(ref_table, ref_id);

-- Current stock per item per warehouse.
create view current_stock as
  select
    item_id,
    warehouse_id,
    sum(quantity)               as qty,
    sum(quantity * unit_cost)   as stock_value
  from stock_movements
  group by item_id, warehouse_id;

-- ============================ BOM ===================================
create table boms (
  id               uuid primary key default gen_random_uuid(),
  finished_item_id uuid not null references items(id),
  name             text not null,
  output_qty       numeric not null default 1,   -- yield per one run of the recipe
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger trg_boms_updated before update on boms
  for each row execute function set_updated_at();

create table bom_lines (
  id                uuid primary key default gen_random_uuid(),
  bom_id            uuid not null references boms(id) on delete cascade,
  component_item_id uuid not null references items(id),
  qty_per           numeric not null,             -- consumed per output_qty
  wastage_pct       numeric not null default 0
);

-- ===================== PRODUCTION ORDERS ============================
create sequence if not exists seq_prod_no;

create table production_orders (
  id               uuid primary key default gen_random_uuid(),
  order_no         text unique,
  finished_item_id uuid not null references items(id),
  bom_id           uuid references boms(id),
  warehouse_id     uuid references warehouses(id),
  planned_qty      numeric not null,
  produced_qty     numeric not null default 0,
  status           production_status not null default 'planned',
  planned_date     date,
  completed_at     timestamptz,
  notes            text,
  created_by       uuid references auth.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create trigger trg_prod_updated before update on production_orders
  for each row execute function set_updated_at();

-- Auto-number production orders as PRD-00001 when order_no is left null.
create or replace function fill_prod_no() returns trigger
language plpgsql as $$
begin
  if new.order_no is null then
    new.order_no := 'PRD-' || lpad(nextval('seq_prod_no')::text, 5, '0');
  end if;
  return new;
end; $$;
create trigger trg_prod_no before insert on production_orders
  for each row execute function fill_prod_no();

-- Planned material list for a production order (snapshot of BOM).
create table production_materials (
  id                  uuid primary key default gen_random_uuid(),
  production_order_id uuid not null references production_orders(id) on delete cascade,
  component_item_id   uuid not null references items(id),
  planned_qty         numeric not null default 0,
  issued_qty          numeric not null default 0,
  warehouse_id        uuid references warehouses(id)
);

-- ============ COMPLETE A PRODUCTION ORDER (transactional) ===========
-- Posts finished-good IN and BOM-scaled component OUT movements in one
-- transaction, then marks the order completed. Called from the client
-- via supabase.rpc('complete_production_order', ...).
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

  v_wh := coalesce(v_order.warehouse_id, (select id from warehouses order by created_at limit 1));
  if v_wh is null then raise exception 'No warehouse configured'; end if;

  -- Finished good into stock
  insert into stock_movements(item_id, warehouse_id, movement_type, quantity, unit_cost, ref_table, ref_id, ref_no, created_by, note)
  values (v_order.finished_item_id, v_wh, 'production_in', p_qty, 0,
          'production_orders', v_order.id, v_order.order_no, auth.uid(), 'Production output');

  -- Consume components, scaled from the BOM's output_qty and wastage
  if v_order.bom_id is not null then
    select p_qty / nullif(b.output_qty, 0) into v_factor from boms b where b.id = v_order.bom_id;
    for v_line in select * from bom_lines where bom_id = v_order.bom_id loop
      insert into stock_movements(item_id, warehouse_id, movement_type, quantity, unit_cost, ref_table, ref_id, ref_no, created_by, note)
      values (v_line.component_item_id, v_wh, 'production_out',
              -1 * v_line.qty_per * v_factor * (1 + coalesce(v_line.wastage_pct, 0) / 100.0),
              0, 'production_orders', v_order.id, v_order.order_no, auth.uid(), 'Material consumption');
    end loop;
  end if;

  update production_orders
     set produced_qty = produced_qty + p_qty,
         status       = 'completed',
         completed_at = now(),
         updated_at   = now()
   where id = p_order_id;
end; $$;

-- ============================ RLS ===================================
-- Everyone authenticated can read; writes are gated by application role.
alter table profiles            enable row level security;
alter table uoms                enable row level security;
alter table item_categories     enable row level security;
alter table items               enable row level security;
alter table warehouses          enable row level security;
alter table suppliers           enable row level security;
alter table customers           enable row level security;
alter table stock_movements     enable row level security;
alter table boms                enable row level security;
alter table bom_lines           enable row level security;
alter table production_orders   enable row level security;
alter table production_materials enable row level security;

-- Profiles: read all; users update their own; admins manage everyone.
create policy p_profiles_read   on profiles for select to authenticated using (true);
create policy p_profiles_self   on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy p_profiles_admin  on profiles for all to authenticated
  using (app_role() = 'admin') with check (app_role() = 'admin');

-- Table-level privileges for the API roles. Row visibility is still governed
-- by the RLS policies below; these GRANTs just let RLS run at all.
-- (Hosted Supabase sets these by default; a local migration must be explicit.)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to anon, authenticated;

-- Apply the same defaults to any tables/functions added by later migrations.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant select on tables to anon;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;
alter default privileges in schema public
  grant execute on functions to anon, authenticated;

-- Generic read + role-gated write for operational tables.
do $$
declare t text;
  write_roles text := $q$app_role() in ('admin','manager','store','production')$q$;
begin
  foreach t in array array[
    'uoms','item_categories','items','warehouses','suppliers','customers',
    'stock_movements','boms','bom_lines','production_orders','production_materials'
  ] loop
    execute format('create policy %I on %I for select to authenticated using (true);',
                   t || '_read', t);
    execute format('create policy %I on %I for all to authenticated using (%s) with check (%s);',
                   t || '_write', t, write_roles, write_roles);
  end loop;
end $$;
