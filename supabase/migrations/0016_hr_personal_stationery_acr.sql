-- ============================================================================
-- Migration 0016 — Employee personal file, office stationery costing,
-- Annual Confidential Report (ACR), welfare/medical assistance.
-- ============================================================================

-- =================== 1. EMPLOYEE PERSONAL INFORMATION =====================
alter table employees add column if not exists date_of_birth date;
alter table employees add column if not exists blood_group text;
alter table employees add column if not exists marital_status text;
alter table employees add column if not exists father_name text;
alter table employees add column if not exists present_address text;
alter table employees add column if not exists permanent_address text;
alter table employees add column if not exists emergency_contact_name text;
alter table employees add column if not exists emergency_contact_phone text;

-- ========================= 2. NEW COA LINES ================================
insert into accounts (company_id, code, name, account_type, is_postable)
select id, '1340', 'Inventory - Office Stationery & Consumables', 'asset', true from companies
on conflict (company_id, code) do nothing;
insert into accounts (company_id, code, name, account_type, is_postable)
select id, '5230', 'Staff Welfare & Medical Assistance', 'expense', true from companies
on conflict (company_id, code) do nothing;
insert into accounts (company_id, code, name, account_type, is_postable)
select id, '5800', 'Office Supplies & Stationery Expense', 'expense', true from companies
on conflict (company_id, code) do nothing;

create or replace function seed_default_coa(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into accounts (company_id, code, name, account_type, is_postable) values
    (p_company,'1000','Assets','asset',false),
    (p_company,'1100','Bank Current Account','asset',true),
    (p_company,'1150','Cash in Hand','asset',true),
    (p_company,'1200','Accounts Receivable','asset',true),
    (p_company,'1210','Bills Receivable under Local LC','asset',true),
    (p_company,'1220','Goods Delivered Not Invoiced','asset',true),
    (p_company,'1230','LC Margin Receivable','asset',true),
    (p_company,'1240','Employee Loans Outstanding','asset',true),
    (p_company,'1250','Advance Income Tax (AIT)','asset',true),
    (p_company,'1260','VAT Input Credit (Mushak 6.1)','asset',true),
    (p_company,'1300','Inventory - Raw Material','asset',true),
    (p_company,'1310','Inventory - Finished Goods','asset',true),
    (p_company,'1320','Inventory - WIP','asset',true),
    (p_company,'1330','Inventory - Scrap','asset',true),
    (p_company,'1340','Inventory - Office Stationery & Consumables','asset',true),
    (p_company,'1400','Fixed Assets','asset',true),
    (p_company,'1410','Accumulated Depreciation','asset',true),
    (p_company,'1900','Data Migration Clearing Suspense','asset',true),
    (p_company,'2000','Liabilities','liability',false),
    (p_company,'2100','Accounts Payable','liability',true),
    (p_company,'2110','Freight Payable','liability',true),
    (p_company,'2200','Salary Payable','liability',true),
    (p_company,'2300','LBPD Loan Liability','liability',true),
    (p_company,'2310','Forced PAD Loan Liability','liability',true),
    (p_company,'2320','Bank OD / CC','liability',true),
    (p_company,'2330','Industrial Term Loans','liability',true),
    (p_company,'2400','Directors Loan Payable','liability',true),
    (p_company,'2500','AIT Payable - Withholding (TDS)','liability',true),
    (p_company,'2510','VAT Payable','liability',true),
    (p_company,'2600','Dividend Payable','liability',true),
    (p_company,'3000','Equity','equity',false),
    (p_company,'3100','Share Capital','equity',true),
    (p_company,'3200','Share Money Deposit','equity',true),
    (p_company,'3300','Retained Earnings','equity',true),
    (p_company,'4000','Income','income',false),
    (p_company,'4100','Revenue - Deemed Exports','income',true),
    (p_company,'4200','Revenue - Domestic','income',true),
    (p_company,'4300','Scrap Sales','income',true),
    (p_company,'4900','Other Income','income',true),
    (p_company,'5000','Expenses','expense',false),
    (p_company,'5100','Cost of Goods Sold','expense',true),
    (p_company,'5200','Salary & Wages','expense',true),
    (p_company,'5210','Overtime','expense',true),
    (p_company,'5220','Festival Bonus','expense',true),
    (p_company,'5230','Staff Welfare & Medical Assistance','expense',true),
    (p_company,'5300','Utilities - Gas / Steam','expense',true),
    (p_company,'5310','Utilities - Power / Fuel','expense',true),
    (p_company,'5400','Bank Charges & LC Fees','expense',true),
    (p_company,'5410','Interest - LBPD Discounting','expense',true),
    (p_company,'5420','Interest - Forced PAD Penalty','expense',true),
    (p_company,'5430','Legal & Professional Fees (Banking)','expense',true),
    (p_company,'5500','Freight & Transit Expenses','expense',true),
    (p_company,'5600','Scrap Valuation Loss','expense',true),
    (p_company,'5700','Depreciation','expense',true),
    (p_company,'5800','Office Supplies & Stationery Expense','expense',true),
    (p_company,'5900','Miscellaneous Expense','expense',true)
  on conflict (company_id, code) do nothing;
end; $$;

-- ===================== 3. OFFICE STATIONERY COSTING ========================
-- Purchase-in of stationery/consumable items (Dr inventory 1340, Cr bank or AP).
create table stationery_receipts (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  receipt_no           text,
  receipt_date         date not null default current_date,
  item_id              uuid not null references items(id),
  qty                  numeric not null check (qty > 0),
  unit_cost            numeric not null default 0,
  party_id             uuid references parties(id),           -- supplier, optional
  cash_bank_account_id uuid references cash_bank_accounts(id), -- null = on credit (AP)
  reference_no         text,
  note                 text,
  created_by           uuid references auth.users(id),
  created_at           timestamptz not null default now(),
  unique (company_id, receipt_no)
);

create or replace function fill_stationery_receipt_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.receipt_no is null then
    new.receipt_no := next_document_number(new.company_id, 'stationery_receipt', 'STR');
  end if;
  return new;
end; $$;
create trigger trg_stationery_receipt_no before insert on stationery_receipts
  for each row execute function fill_stationery_receipt_no();

create or replace function post_stationery_receipt() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_wh uuid;
  v_total numeric;
  v_credit_code text;
begin
  v_wh := (select id from warehouses where company_id = new.company_id order by created_at limit 1);
  if v_wh is not null then
    insert into stock_movements (company_id, item_id, warehouse_id, movement_type,
                                 quantity, unit_cost, ref_table, ref_id, ref_no, created_by, note)
    values (new.company_id, new.item_id, v_wh, 'adjustment', new.qty, new.unit_cost,
            'stationery_receipts', new.id, new.receipt_no, auth.uid(), 'Stationery receipt');
  end if;

  v_total := round(new.qty * new.unit_cost, 2);
  if v_total > 0 then
    v_credit_code := case when new.cash_bank_account_id is not null
      then resolve_bank_code(new.cash_bank_account_id) else '2100' end;
    perform post_journal(new.company_id, new.receipt_date,
      'Stationery receipt ' || new.receipt_no || coalesce(' — ' || new.note, ''),
      'stationery_receipts', new.id,
      jsonb_build_array(
        jsonb_build_object('account','1340','debit', v_total),
        jsonb_build_object('account', v_credit_code, 'credit', v_total, 'party_id', new.party_id)));
  end if;
  return new;
end; $$;
create trigger trg_stationery_receipt_post after insert on stationery_receipts
  for each row execute function post_stationery_receipt();

-- Issue-out to an employee desk: consumption, expensed immediately (Dr 5800, Cr 1340).
create table stationery_issues (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  issue_no     text,
  issue_date   date not null default current_date,
  item_id      uuid not null references items(id),
  employee_id  uuid not null references employees(id),
  qty          numeric not null check (qty > 0),
  unit_cost    numeric not null default 0,
  note         text,
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  unique (company_id, issue_no)
);

create or replace function fill_stationery_issue_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.issue_no is null then
    new.issue_no := next_document_number(new.company_id, 'stationery_issue', 'STI');
  end if;
  if new.unit_cost is null or new.unit_cost = 0 then
    new.unit_cost := coalesce((select standard_cost from items where id = new.item_id), 0);
  end if;
  return new;
end; $$;
create trigger trg_stationery_issue_no before insert on stationery_issues
  for each row execute function fill_stationery_issue_no();

create or replace function post_stationery_issue() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_wh uuid;
  v_total numeric;
begin
  v_wh := (select id from warehouses where company_id = new.company_id order by created_at limit 1);
  if v_wh is not null then
    insert into stock_movements (company_id, item_id, warehouse_id, movement_type,
                                 quantity, unit_cost, ref_table, ref_id, ref_no, created_by, note)
    values (new.company_id, new.item_id, v_wh, 'adjustment', -new.qty, new.unit_cost,
            'stationery_issues', new.id, new.issue_no, auth.uid(), 'Stationery issued to employee desk');
  end if;

  v_total := round(new.qty * new.unit_cost, 2);
  if v_total > 0 then
    perform post_journal(new.company_id, new.issue_date,
      'Stationery issue ' || new.issue_no || coalesce(' — ' || new.note, ''),
      'stationery_issues', new.id,
      jsonb_build_array(
        jsonb_build_object('account','5800','debit', v_total),
        jsonb_build_object('account','1340','credit', v_total)));
  end if;
  return new;
end; $$;
create trigger trg_stationery_issue_post after insert on stationery_issues
  for each row execute function post_stationery_issue();

-- Usage-by-person report.
create view v_stationery_usage_by_employee with (security_invoker = true) as
  select si.company_id, si.employee_id, e.emp_no, e.full_name,
         count(*) as issue_count,
         sum(si.qty) as total_qty,
         sum(si.qty * si.unit_cost) as total_cost
    from stationery_issues si
    join employees e on e.id = si.employee_id
   group by si.company_id, si.employee_id, e.emp_no, e.full_name;

-- ==================== 4. ANNUAL CONFIDENTIAL REPORT (ACR) ==================
create type acr_grade as enum ('outstanding', 'very_good', 'good', 'satisfactory', 'poor');

create table employee_acr (
  id                          uuid primary key default gen_random_uuid(),
  company_id                  uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  employee_id                 uuid not null references employees(id),
  review_year                 int not null,
  reviewing_officer           text,
  job_knowledge_rating        int check (job_knowledge_rating between 1 and 5),
  quality_of_work_rating      int check (quality_of_work_rating between 1 and 5),
  integrity_rating            int check (integrity_rating between 1 and 5),
  punctuality_rating          int check (punctuality_rating between 1 and 5),
  initiative_rating           int check (initiative_rating between 1 and 5),
  overall_grade               acr_grade not null default 'good',
  strengths                   text,
  areas_of_improvement        text,
  reporting_officer_remarks   text,
  employee_remarks            text,
  status                      text not null default 'draft', -- draft | finalized
  created_by                  uuid references auth.users(id),
  created_at                  timestamptz not null default now(),
  unique (company_id, employee_id, review_year)
);

-- ================= 5. WELFARE & MEDICAL ASSISTANCE =========================
create type assistance_type as enum ('welfare', 'medical');

create table employee_assistance (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  request_no           text,
  employee_id          uuid not null references employees(id),
  assistance_type      assistance_type not null default 'welfare',
  request_date         date not null default current_date,
  amount               numeric not null check (amount > 0),
  reason               text,
  status               text not null default 'requested', -- requested | approved | paid | rejected
  cash_bank_account_id uuid references cash_bank_accounts(id),
  paid_date            date,
  created_by           uuid references auth.users(id),
  created_at           timestamptz not null default now(),
  unique (company_id, request_no)
);

create or replace function fill_assistance_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.request_no is null then
    new.request_no := next_document_number(new.company_id, 'employee_assistance', 'WMA');
  end if;
  return new;
end; $$;
create trigger trg_assistance_no before insert on employee_assistance
  for each row execute function fill_assistance_no();

create or replace function pay_employee_assistance(p_id uuid, p_cash_bank_account_id uuid default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_row employee_assistance;
begin
  select * into v_row from employee_assistance where id = p_id for update;
  if not found then raise exception 'Assistance request not found'; end if;
  if v_row.status <> 'approved' then raise exception 'Only approved requests can be paid (is %)', v_row.status; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_row.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  perform post_journal(v_row.company_id, current_date,
    initcap(v_row.assistance_type::text) || ' assistance — ' || v_row.request_no,
    'employee_assistance', p_id,
    jsonb_build_array(
      jsonb_build_object('account','5230','debit', v_row.amount),
      jsonb_build_object('account', resolve_bank_code(p_cash_bank_account_id), 'credit', v_row.amount)));

  update employee_assistance
     set status = 'paid', paid_date = current_date, cash_bank_account_id = p_cash_bank_account_id
   where id = p_id;
end; $$;
revoke execute on function pay_employee_assistance(uuid, uuid) from anon;

-- ============================ RLS + AUDIT ===================================
do $$
declare t text;
begin
  foreach t in array array[
    'stationery_receipts', 'stationery_issues', 'employee_acr', 'employee_assistance'
  ] loop
    execute format('alter table %I enable row level security;', t);
    execute format(
      'create policy %I on %I for select to authenticated using (is_member(company_id));',
      t || '_read', t);
    execute format(
      'create policy %I on %I for all to authenticated using (can_write_company(company_id)) with check (can_write_company(company_id));',
      t || '_write', t);
    execute format(
      'create trigger trg_audit_%s after insert or update or delete on %I
         for each row execute function audit_row_change();', t, t);
  end loop;
end $$;
