-- =====================================================================
-- Mahim Packaging ERP — 0019_granular_permissions
-- Replaces the fixed role tiers (manager/store/production/sales/accounts/
-- viewer) with a per-user, per-page checklist an admin toggles freely —
-- not a predefined bundle. `admin` is unchanged: always full access,
-- can't be locked out, manages everyone else's grants. Every other
-- member starts with nothing granted (closed by default) except the
-- dashboard landing page, and gets exactly what's switched on.
--
-- Two actions per module: 'view' (module exists for this user at all —
-- hidden from nav, RLS denies reads if off) and 'write' (can create/
-- edit within it; implies view). This does not yet retrofit the small
-- set of sensitive multi-step RPCs (issuing challans, closing LCs,
-- posting journals, running payroll, LBPD approval) — those keep their
-- existing role-based can_write_company() gate for now, unchanged.
-- =====================================================================

create table permission_modules (
  key         text primary key,
  label       text not null,
  group_label text not null,
  sort_order  int not null
);

insert into permission_modules (key, group_label, label, sort_order) values
  ('dashboard',   'Operations',       'Dashboard',                  10),
  ('ceo',         'Executive',        'CEO overview',                0),
  ('items',       'Operations',       'Items',                      20),
  ('stock',       'Operations',       'Stock',                      30),
  ('boms',        'Operations',       'BOMs',                       40),
  ('production',  'Operations',       'Production',                 50),
  ('parties',     'Procurement',      'Parties',                    60),
  ('procurement', 'Procurement',      'GRNs',                       70),
  ('quotations',  'Sales & Local LC', 'Quotations / PI',             80),
  ('sales_orders','Sales & Local LC', 'Sales orders',                90),
  ('challans',    'Sales & Local LC', 'Challans',                   100),
  ('lcs',         'Sales & Local LC', 'LCs',                        110),
  ('invoices',    'Sales & Local LC', 'Invoices',                   120),
  ('banking',     'Finance',          'Banking / LBPD',             130),
  ('accounting',  'Finance',          'Accounting',                 140),
  ('bank_accounts','Finance',         'Bank & cash accounts',        150),
  ('cash_sales',  'Finance',          'Cash sales',                 160),
  ('transfers',   'Finance',          'Transfers',                  170),
  ('bank_charges','Finance',          'Bank charges & fees',         180),
  ('pnl',         'Finance',          'Profit & Loss',               190),
  ('vat_return',  'Finance',          'VAT return',                 200),
  ('ait_summary', 'Finance',          'AIT summary',                 210),
  ('hr',          'HR',               'Employees',                  220),
  ('attendance',  'HR',               'Attendance',                  230),
  ('payroll',     'HR',               'Payroll',                    240),
  ('stationery',  'HR',               'Office stationery',           250),
  ('audit',       'Admin',            'Audit trail',                 260),
  ('company',     'Admin',            'Company & structure',         270),
  ('directors',   'Admin',            'Directors & partners',        280),
  ('resolutions', 'Admin',            'Board resolutions',           290),
  ('documents',   'Admin',            'Company documents',           300),
  ('forwarding',  'Admin',            'Forwarding pad',              310),
  ('bank_requests','Admin',           'Bank service requests',       320),
  ('tax_it10b',   'Admin',            'Tax — IT-10B',                330),
  ('tax_corporate','Admin',           'Corporate tax computation',   340);

alter table permission_modules enable row level security;
create policy permission_modules_read on permission_modules for select to authenticated using (true);

-- ==================== GRANTS (per user, per company) ==================
create table user_permissions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id),
  module_key text not null references permission_modules(key),
  action     text not null check (action in ('view', 'write')),
  created_at timestamptz not null default now(),
  unique (user_id, company_id, module_key, action)
);

alter table user_permissions enable row level security;

-- A user reads their own grants (needed client-side to build the nav);
-- admins read/manage everyone's in their company.
create policy user_permissions_read_own on user_permissions for select to authenticated
  using (user_id = auth.uid() or can_write_company(company_id));
create policy user_permissions_admin_write on user_permissions for all to authenticated
  using (can_write_company(company_id) and member_role(company_id) = 'admin')
  with check (can_write_company(company_id) and member_role(company_id) = 'admin');

-- Every new member gets the dashboard by default so they have somewhere
-- to land; everything else is closed until an admin opts them in.
create or replace function grant_default_permissions() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into user_permissions (user_id, company_id, module_key, action)
  values (new.user_id, new.company_id, 'dashboard', 'view')
  on conflict do nothing;
  return new;
end; $$;
create trigger trg_grant_default_permissions after insert on company_members
  for each row execute function grant_default_permissions();

-- ========================= CHECK FUNCTIONS ============================
-- Admins always pass — never lockable out of their own company.
create or replace function has_permission(p_company uuid, p_module text, p_action text)
returns boolean language sql stable security definer set search_path = public as $$
  select
    coalesce(member_role(p_company) = 'admin', false)
    or exists (
      select 1 from user_permissions
      where user_id = auth.uid() and company_id = p_company
        and module_key = p_module and action = p_action
    );
$$;

create or replace function has_module_view(p_company uuid, p_module text)
returns boolean language sql stable security definer set search_path = public as $$
  select has_permission(p_company, p_module, 'view') or has_permission(p_company, p_module, 'write');
$$;

-- ==================== RETROFIT: per-module RLS ========================
-- Replaces the coarse "any writer role" table policies with per-module
-- view/write checks, for every table backing a directly toggleable page.
-- The handful of sensitive RPCs listed above are untouched by this loop.
do $$
declare
  pair text;
  tbl text;
  mod text;
begin
  foreach pair in array array[
    'items:items', 'items:item_categories', 'items:uoms', 'items:warehouses',
    'stock:stock_movements',
    'boms:boms', 'boms:bom_lines', 'boms:carton_specs', 'boms:carton_spec_layers', 'boms:carton_recipe_templates',
    'production:production_orders', 'production:production_materials',
    'parties:parties',
    'procurement:gate_entries', 'procurement:grns', 'procurement:grn_lines', 'procurement:debit_notes',
    'quotations:sales_documents', 'quotations:sales_document_lines',
    'sales_orders:sales_orders', 'sales_orders:sales_order_lines',
    'challans:delivery_challans', 'challans:delivery_challan_lines',
    'lcs:lcs', 'lcs:lc_amendments',
    'invoices:invoices', 'invoices:invoice_lines', 'invoices:credit_notes',
    'banking:bank_facilities', 'banking:bills', 'banking:lbpd_disbursements',
    'bank_accounts:cash_bank_accounts',
    'cash_sales:cash_sales',
    'transfers:account_transfers',
    'bank_charges:bank_charge_entries', 'bank_charges:bank_statement_lines',
    'hr:employees',
    'attendance:attendance',
    'payroll:payroll_runs', 'payroll:payroll_lines', 'payroll:employee_loans',
    'stationery:stationery_receipts', 'stationery:stationery_issues',
    'directors:company_directors',
    'resolutions:board_resolutions',
    'documents:company_documents', 'documents:legal_reviews',
    'forwarding:forwarding_letters',
    'bank_requests:bank_service_requests', 'bank_requests:bank_branches',
    'tax_it10b:it10b_statements',
    'tax_corporate:company_tax_computations'
  ] loop
    mod := split_part(pair, ':', 1);
    tbl := split_part(pair, ':', 2);
    execute format('drop policy if exists %I on %I;', tbl || '_read', tbl);
    execute format('drop policy if exists %I on %I;', tbl || '_write', tbl);
    execute format(
      'create policy %I on %I for select to authenticated using (has_module_view(company_id, %L));',
      tbl || '_read', tbl, mod);
    execute format(
      'create policy %I on %I for all to authenticated using (has_permission(company_id, %L, ''write'')) with check (has_permission(company_id, %L, ''write''));',
      tbl || '_write', tbl, mod, mod);
  end loop;
end $$;

-- cash_sale_lines / company_tax_adjustment_lines: policies are keyed off
-- their parent row's company_id via a subquery rather than their own
-- column, so they're retrofit individually instead of via the loop above.
drop policy if exists cash_sale_lines_write on cash_sale_lines;
create policy cash_sale_lines_write on cash_sale_lines for all to authenticated
  using (exists (select 1 from cash_sales s where s.id = cash_sale_lines.cash_sale_id and has_permission(s.company_id, 'cash_sales', 'write')))
  with check (exists (select 1 from cash_sales s where s.id = cash_sale_lines.cash_sale_id and has_permission(s.company_id, 'cash_sales', 'write')));

drop policy if exists company_tax_adjustment_lines_write on company_tax_adjustment_lines;
create policy company_tax_adjustment_lines_write on company_tax_adjustment_lines for all to authenticated
  using (exists (select 1 from company_tax_computations c where c.id = company_tax_adjustment_lines.computation_id and has_permission(c.company_id, 'tax_corporate', 'write')))
  with check (exists (select 1 from company_tax_computations c where c.id = company_tax_adjustment_lines.computation_id and has_permission(c.company_id, 'tax_corporate', 'write')));

drop policy if exists it10b_lines_read on it10b_lines;
drop policy if exists it10b_lines_write on it10b_lines;
create policy it10b_lines_read on it10b_lines for select to authenticated
  using (exists (select 1 from it10b_statements s where s.id = it10b_lines.statement_id and has_module_view(s.company_id, 'tax_it10b')));
create policy it10b_lines_write on it10b_lines for all to authenticated
  using (exists (select 1 from it10b_statements s where s.id = it10b_lines.statement_id and has_permission(s.company_id, 'tax_it10b', 'write')))
  with check (exists (select 1 from it10b_statements s where s.id = it10b_lines.statement_id and has_permission(s.company_id, 'tax_it10b', 'write')));

drop policy if exists board_resolution_agendas_read on board_resolution_agendas;
drop policy if exists board_resolution_agendas_write on board_resolution_agendas;
create policy board_resolution_agendas_read on board_resolution_agendas for select to authenticated
  using (exists (select 1 from board_resolutions r where r.id = board_resolution_agendas.resolution_id and has_module_view(r.company_id, 'resolutions')));
create policy board_resolution_agendas_write on board_resolution_agendas for all to authenticated
  using (exists (select 1 from board_resolutions r where r.id = board_resolution_agendas.resolution_id and has_permission(r.company_id, 'resolutions', 'write')))
  with check (exists (select 1 from board_resolutions r where r.id = board_resolution_agendas.resolution_id and has_permission(r.company_id, 'resolutions', 'write')));

drop policy if exists board_resolution_attendees_read on board_resolution_attendees;
drop policy if exists board_resolution_attendees_write on board_resolution_attendees;
create policy board_resolution_attendees_read on board_resolution_attendees for select to authenticated
  using (exists (select 1 from board_resolutions r where r.id = board_resolution_attendees.resolution_id and has_module_view(r.company_id, 'resolutions')));
create policy board_resolution_attendees_write on board_resolution_attendees for all to authenticated
  using (exists (select 1 from board_resolutions r where r.id = board_resolution_attendees.resolution_id and has_permission(r.company_id, 'resolutions', 'write')))
  with check (exists (select 1 from board_resolutions r where r.id = board_resolution_attendees.resolution_id and has_permission(r.company_id, 'resolutions', 'write')));

-- GL core (chart of accounts, journals) — read gated by the 'accounting'
-- module; journals/journal_lines stay insert/update/delete-free exactly
-- as before (post_journal() is the only writer, unchanged).
drop policy if exists accounts_read on accounts;
drop policy if exists accounts_write on accounts;
create policy accounts_read on accounts for select to authenticated
  using (has_module_view(company_id, 'accounting'));
create policy accounts_write on accounts for all to authenticated
  using (has_permission(company_id, 'accounting', 'write')) with check (has_permission(company_id, 'accounting', 'write'));

drop policy if exists journals_read on journals;
create policy journals_read on journals for select to authenticated
  using (has_module_view(company_id, 'accounting'));

drop policy if exists journal_lines_read on journal_lines;
create policy journal_lines_read on journal_lines for select to authenticated
  using (has_module_view(company_id, 'accounting'));
