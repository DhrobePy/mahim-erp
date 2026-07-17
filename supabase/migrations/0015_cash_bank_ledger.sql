-- =====================================================================
-- Mahim Packaging ERP — 0015_cash_bank_ledger
-- The keystone finance migration: a real per-account cash/bank
-- sub-ledger (each bank account and cash point is its own postable GL
-- leaf under 1100/1150), cash sales, inter-account transfers, bank
-- statement reconciliation, a bank-charge/fee/AIT/legal-fee quick
-- entry, and the reports this all exists to feed — a proper P&L
-- statement, a VAT (Mushak 9.1) input/output summary, an AIT summary,
-- and a corporate tax computation working paper.
--
-- The five existing postings that hardcoded '1100' (LC amendment fee,
-- LBPD disburse/settle, employee loan disbursement, payroll payment)
-- are retrofitted to accept a specific account, falling back to the
-- generic 1100/1150 bucket when none is chosen — non-breaking, but
-- going forward every UI form offers the specific-account choice so
-- reconciliation has something real to reconcile against.
--
-- The tax computation output is a DRAFT WORKING PAPER, not a filing —
-- same posture as IT-10B: verify rates, disallowances and minimum-tax
-- rules with a registered tax practitioner before submission.
-- =====================================================================

-- ==================== 1. CASH / BANK ACCOUNT REGISTER ==================
create type cash_bank_kind as enum ('bank', 'cash');

create table cash_bank_accounts (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  kind            cash_bank_kind not null,
  name            text not null,              -- e.g. "IBBL Current A/C 1234", "Factory Cash Till"
  bank_party_id   uuid references parties(id),      -- null for cash
  branch_id       uuid references bank_branches(id), -- null for cash
  account_no      text,
  currency        text not null default 'BDT',
  gl_account_id   uuid references accounts(id),
  opening_balance numeric not null default 0,
  opening_date    date not null default current_date,
  is_active       boolean not null default true,
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  check ((kind = 'bank') = (bank_party_id is not null))
);

-- Every account gets its own postable leaf under 1100 (bank) or 1150
-- (cash), so trial_balance / reconciliation can operate per real account
-- instead of one undifferentiated bucket.
create or replace function create_cash_bank_gl_account() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_parent_code text := case new.kind when 'bank' then '1100' else '1150' end;
  v_parent_id   uuid;
  v_n           int;
  v_code        text;
  v_gl_id       uuid;
begin
  select id into v_parent_id from accounts
   where company_id = new.company_id and code = v_parent_code;
  if v_parent_id is null then
    raise exception 'Parent account % not found for company', v_parent_code;
  end if;
  select count(*) + 1 into v_n from accounts where parent_id = v_parent_id;
  v_code := v_parent_code || '-' || lpad(v_n::text, 2, '0');
  insert into accounts (company_id, code, name, account_type, parent_id, is_postable)
  values (new.company_id, v_code, new.name, 'asset', v_parent_id, true)
  returning id into v_gl_id;
  new.gl_account_id := v_gl_id;
  return new;
end; $$;
create trigger trg_cash_bank_gl before insert on cash_bank_accounts
  for each row execute function create_cash_bank_gl_account();

-- Opening balance lands via the posting engine against the existing
-- Data Migration Clearing Suspense account (1900) — the same account
-- built for exactly this kind of "balance existed before go-live" entry.
create or replace function post_cash_bank_opening() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if coalesce(new.opening_balance, 0) <> 0 then
    select code into v_code from accounts where id = new.gl_account_id;
    perform post_journal(new.company_id, coalesce(new.opening_date, current_date),
      'Opening balance — ' || new.name, 'cash_bank_accounts', new.id,
      jsonb_build_array(
        jsonb_build_object('account', v_code, 'debit', new.opening_balance),
        jsonb_build_object('account', '1900', 'credit', new.opening_balance)));
  end if;
  return new;
end; $$;
create trigger trg_cash_bank_opening after insert on cash_bank_accounts
  for each row execute function post_cash_bank_opening();

-- Per-account running balance, for the account list and reconciliation.
create view v_cash_bank_balances with (security_invoker = true) as
  select cba.id, cba.company_id, cba.kind, cba.name, cba.is_active,
         a.code as gl_code, coalesce(ab.balance, 0) as balance
    from cash_bank_accounts cba
    join accounts a on a.id = cba.gl_account_id
    left join account_balances ab on ab.account_id = cba.gl_account_id;

-- ================ 2. NEW COA LINE FOR BANKING LEGAL FEES ===============
insert into accounts (company_id, code, name, account_type, is_postable)
select id, '5430', 'Legal & Professional Fees (Banking)', 'expense', true from companies
on conflict (company_id, code) do nothing;

-- Keep new companies' template in step.
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
    (p_company,'5300','Utilities - Gas / Steam','expense',true),
    (p_company,'5310','Utilities - Power / Fuel','expense',true),
    (p_company,'5400','Bank Charges & LC Fees','expense',true),
    (p_company,'5410','Interest - LBPD Discounting','expense',true),
    (p_company,'5420','Interest - Forced PAD Penalty','expense',true),
    (p_company,'5430','Legal & Professional Fees (Banking)','expense',true),
    (p_company,'5500','Freight & Transit Expenses','expense',true),
    (p_company,'5600','Scrap Valuation Loss','expense',true),
    (p_company,'5700','Depreciation','expense',true),
    (p_company,'5900','Miscellaneous Expense','expense',true)
  on conflict (company_id, code) do nothing;
end; $$;

-- ============ 3. RETROFIT: SPECIFIC-ACCOUNT-AWARE POSTINGS =============
-- Each gains an optional cash_bank_account_id; when set, its GL leaf is
-- used instead of the generic 1100 fallback.
alter table lc_amendments      add column if not exists cash_bank_account_id uuid references cash_bank_accounts(id);
alter table lbpd_disbursements add column if not exists cash_bank_account_id uuid references cash_bank_accounts(id);
alter table employee_loans     add column if not exists cash_bank_account_id uuid references cash_bank_accounts(id);
alter table payroll_runs       add column if not exists cash_bank_account_id uuid references cash_bank_accounts(id);

create or replace function resolve_bank_code(p_account_id uuid) returns text
language sql stable as $$
  select coalesce((select code from accounts where id = (select gl_account_id from cash_bank_accounts where id = p_account_id)), '1100');
$$;
create or replace function resolve_cash_code(p_account_id uuid) returns text
language sql stable as $$
  select coalesce((select code from accounts where id = (select gl_account_id from cash_bank_accounts where id = p_account_id)), '1150');
$$;

create or replace function record_lc_amendment_fee() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.bank_fee > 0 then
    perform post_journal(new.company_id, current_date,
      'LC amendment fee v' || new.version || ' (MT707)',
      'lc_amendments', new.id,
      jsonb_build_array(
        jsonb_build_object('account','5400','debit', new.bank_fee),
        jsonb_build_object('account', resolve_bank_code(new.cash_bank_account_id), 'credit', new.bank_fee)));
  end if;
  return new;
end; $$;

create or replace function disburse_lbpd(
  p_bill_id uuid, p_facility_id uuid, p_advance_pct numeric default 85,
  p_cash_bank_account_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_bill      bills;
  v_fac       bank_facilities;
  v_principal numeric;
  v_exposure  numeric;
  v_id        uuid;
begin
  select * into v_bill from bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found'; end if;
  if v_bill.status <> 'accepted' then
    raise exception 'Bill must be accepted before discounting (is %)', v_bill.status;
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_bill.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if p_advance_pct <= 0 or p_advance_pct > 95 then
    raise exception 'Advance must be between 0 and 95%%';
  end if;

  select * into v_fac from bank_facilities where id = p_facility_id and is_active;
  if not found then raise exception 'Facility not found or inactive'; end if;
  if v_fac.company_id <> v_bill.company_id then
    raise exception 'Facility belongs to a different company';
  end if;

  v_principal := round(v_bill.amount * p_advance_pct / 100.0, 2);

  select coalesce(sum(principal), 0) into v_exposure
    from lbpd_disbursements
   where facility_id = p_facility_id and status in ('open','forced_pad');
  if v_exposure + v_principal > v_fac.limit_amount then
    raise exception 'Facility limit exceeded: % + % > limit %',
      v_exposure, v_principal, v_fac.limit_amount;
  end if;

  insert into lbpd_disbursements (company_id, bill_id, facility_id, advance_pct,
                                  principal, interest_rate, cash_bank_account_id)
  values (v_bill.company_id, p_bill_id, p_facility_id, p_advance_pct,
          v_principal, v_fac.interest_rate, p_cash_bank_account_id)
  returning id into v_id;

  perform post_journal(v_bill.company_id, current_date,
    'LBPD disbursement ' || round(p_advance_pct) || '% against bill ' || v_bill.bill_no,
    'lbpd_disbursements', v_id,
    jsonb_build_array(
      jsonb_build_object('account', resolve_bank_code(p_cash_bank_account_id), 'debit', v_principal),
      jsonb_build_object('account','2300','credit', v_principal,
                         'party_id', v_fac.bank_party_id::text)));

  update bills set status = 'discounted' where id = p_bill_id;
  return v_id;
end; $$;
revoke execute on function disburse_lbpd(uuid, uuid, numeric, uuid) from anon;

create or replace function settle_lbpd(p_disbursement_id uuid, p_interest numeric)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_d       lbpd_disbursements;
  v_bill    bills;
  v_net     numeric;
  v_loan    text;
  v_intacc  text;
begin
  select * into v_d from lbpd_disbursements where id = p_disbursement_id for update;
  if not found then raise exception 'Disbursement not found'; end if;
  if v_d.status = 'settled' then raise exception 'Already settled'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_d.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  select * into v_bill from bills where id = v_d.bill_id for update;

  v_loan   := case v_d.status when 'forced_pad' then '2310' else '2300' end;
  v_intacc := case v_d.status when 'forced_pad' then '5420' else '5410' end;
  v_net    := round(v_bill.amount - v_d.principal - coalesce(p_interest, 0), 2);
  if v_net < 0 then
    raise exception 'Interest % exceeds the retained margin %', p_interest,
      v_bill.amount - v_d.principal;
  end if;

  perform post_journal(v_d.company_id, current_date,
    'LBPD settlement of bill ' || v_bill.bill_no ||
      case v_d.status when 'forced_pad' then ' (forced PAD)' else '' end,
    'lbpd_disbursements', v_d.id,
    jsonb_build_array(
      jsonb_build_object('account', v_loan, 'debit', v_d.principal),
      jsonb_build_object('account', v_intacc, 'debit', coalesce(p_interest, 0)),
      jsonb_build_object('account', resolve_bank_code(v_d.cash_bank_account_id), 'debit', v_net),
      jsonb_build_object('account','1210','credit', v_bill.amount)));

  update lbpd_disbursements
     set status = 'settled', settled_at = current_date,
         interest_paid = coalesce(p_interest, 0)
   where id = p_disbursement_id;
  update bills set status = 'realized' where id = v_d.bill_id;
  update invoices set status = 'settled' where id = v_bill.invoice_id;
end; $$;
revoke execute on function settle_lbpd(uuid, numeric) from anon;

create or replace function disburse_employee_loan(
  p_employee_id uuid, p_principal numeric, p_installment numeric, p_note text default null,
  p_cash_bank_account_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_emp employees;
  v_id  uuid;
begin
  select * into v_emp from employees where id = p_employee_id and is_active;
  if not found then raise exception 'Employee not found or inactive'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_emp.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if p_principal <= 0 or p_installment <= 0 then
    raise exception 'Principal and installment must be positive';
  end if;
  if p_principal > v_emp.basic_salary * 6 then
    raise exception 'Loan cap exceeded: max 6 × basic (%.2f)', v_emp.basic_salary * 6;
  end if;
  if exists (select 1 from employee_loans
              where employee_id = p_employee_id and status = 'active') then
    raise exception 'Employee already has an active loan';
  end if;

  insert into employee_loans (company_id, loan_no, employee_id, principal,
                              monthly_installment, balance, note, cash_bank_account_id)
  values (v_emp.company_id,
          next_document_number(v_emp.company_id, 'employee_loan', 'EL'),
          p_employee_id, p_principal, p_installment, p_principal, p_note, p_cash_bank_account_id)
  returning id into v_id;

  perform post_journal(v_emp.company_id, current_date,
    'Employee loan disbursement — ' || v_emp.emp_no || ' ' || v_emp.full_name,
    'employee_loans', v_id,
    jsonb_build_array(
      jsonb_build_object('account','1240','debit', p_principal),
      jsonb_build_object('account', resolve_bank_code(p_cash_bank_account_id), 'credit', p_principal)));

  return v_id;
end; $$;
revoke execute on function disburse_employee_loan(uuid, numeric, numeric, text, uuid) from anon;

create or replace function pay_payroll(p_run_id uuid, p_cash_bank_account_id uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_run payroll_runs;
begin
  select * into v_run from payroll_runs where id = p_run_id for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if v_run.status <> 'posted' then raise exception 'Run must be posted first'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_run.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  perform post_journal(v_run.company_id, current_date,
    'Payroll payment ' || v_run.label || ' (' || v_run.run_no || ')',
    'payroll_runs', v_run.id,
    jsonb_build_array(
      jsonb_build_object('account','2200','debit', v_run.total_net),
      jsonb_build_object('account', resolve_bank_code(p_cash_bank_account_id), 'credit', v_run.total_net)));

  update payroll_runs
     set status = 'paid', cash_bank_account_id = p_cash_bank_account_id
   where id = p_run_id;
end; $$;
revoke execute on function pay_payroll(uuid, uuid) from anon;

-- ========================= 4. CASH SALES ===============================
-- Point-of-sale receipts settled immediately — walk-in buyers, scrap /
-- edge-trim cash sales — with no LC and no receivable step. Domestic,
-- so output VAT applies (unlike zero-rated deemed exports).
create table cash_sales (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  sale_no           text,
  sale_date         date not null default current_date,
  customer_party_id uuid references parties(id),   -- nullable: true walk-in, no party record
  customer_name     text,                            -- free text if no party
  cash_bank_account_id uuid not null references cash_bank_accounts(id),
  vat_applicable    boolean not null default true,
  vat_rate          numeric not null default 15,
  status            text not null default 'draft',   -- draft | completed
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  unique (company_id, sale_no)
);

create or replace function fill_cash_sale_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.sale_no is null then
    new.sale_no := next_document_number(new.company_id, 'cash_sale', 'CS');
  end if;
  return new;
end; $$;
create trigger trg_cash_sale_no before insert on cash_sales
  for each row execute function fill_cash_sale_no();

create table cash_sale_lines (
  id           uuid primary key default gen_random_uuid(),
  cash_sale_id uuid not null references cash_sales(id) on delete cascade,
  company_id   uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id      uuid not null references items(id),
  qty          numeric not null,
  unit_price   numeric not null default 0
);

create or replace function complete_cash_sale(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_sale   cash_sales;
  v_line   record;
  v_wh     uuid;
  v_total  numeric := 0;
  v_cogs   numeric := 0;
  v_vat    numeric := 0;
  v_lines  jsonb := '[]'::jsonb;
begin
  select * into v_sale from cash_sales where id = p_id for update;
  if not found then raise exception 'Cash sale not found'; end if;
  if v_sale.status <> 'draft' then raise exception 'Cash sale is not draft'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_sale.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if not exists (select 1 from cash_sale_lines where cash_sale_id = p_id) then
    raise exception 'Cash sale has no lines';
  end if;

  v_wh := (select id from warehouses where company_id = v_sale.company_id order by created_at limit 1);

  for v_line in
    select csl.*, i.standard_cost from cash_sale_lines csl
    join items i on i.id = csl.item_id where csl.cash_sale_id = p_id
  loop
    if v_wh is not null then
      insert into stock_movements (company_id, item_id, warehouse_id, movement_type,
                                   quantity, unit_cost, ref_table, ref_id, ref_no, created_by, note)
      values (v_sale.company_id, v_line.item_id, v_wh, 'sales_out', -v_line.qty,
              v_line.standard_cost, 'cash_sales', v_sale.id, v_sale.sale_no, auth.uid(), 'Cash sale');
    end if;
    v_total := v_total + v_line.qty * v_line.unit_price;
    v_cogs  := v_cogs + v_line.qty * coalesce(v_line.standard_cost, 0);
  end loop;
  if v_total <= 0 then raise exception 'Cash sale has no value'; end if;

  if v_sale.vat_applicable then
    v_vat := round(v_total * v_sale.vat_rate / 100.0, 2);
  end if;

  v_lines := jsonb_build_array(
    jsonb_build_object('account', resolve_bank_code(v_sale.cash_bank_account_id), 'debit', round(v_total + v_vat, 2)),
    jsonb_build_object('account','4200','credit', round(v_total, 2)));
  if v_vat > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account','2510','credit', v_vat));
  end if;
  if v_cogs > 0 then
    v_lines := v_lines || jsonb_build_array(
      jsonb_build_object('account','5100','debit', round(v_cogs, 2)),
      jsonb_build_object('account','1310','credit', round(v_cogs, 2)));
  end if;

  perform post_journal(v_sale.company_id, v_sale.sale_date,
    'Cash sale ' || v_sale.sale_no || coalesce(' — ' || v_sale.customer_name, ''),
    'cash_sales', p_id, v_lines);

  update cash_sales set status = 'completed' where id = p_id;
end; $$;
revoke execute on function complete_cash_sale(uuid) from anon;

-- ===================== 5. INTER-ACCOUNT TRANSFERS =======================
create table account_transfers (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  transfer_no     text,
  transfer_date   date not null default current_date,
  from_account_id uuid not null references cash_bank_accounts(id),
  to_account_id   uuid not null references cash_bank_accounts(id),
  amount          numeric not null check (amount > 0),
  note            text,
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  unique (company_id, transfer_no),
  check (from_account_id <> to_account_id)
);

create or replace function fill_transfer_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.transfer_no is null then
    new.transfer_no := next_document_number(new.company_id, 'account_transfer', 'TRF');
  end if;
  return new;
end; $$;
create trigger trg_transfer_no before insert on account_transfers
  for each row execute function fill_transfer_no();

create or replace function record_transfer_posting() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_from_code text; v_to_code text;
begin
  select code into v_from_code from accounts where id = (select gl_account_id from cash_bank_accounts where id = new.from_account_id);
  select code into v_to_code   from accounts where id = (select gl_account_id from cash_bank_accounts where id = new.to_account_id);
  perform post_journal(new.company_id, new.transfer_date,
    'Transfer ' || new.transfer_no || coalesce(' — ' || new.note, ''),
    'account_transfers', new.id,
    jsonb_build_array(
      jsonb_build_object('account', v_to_code, 'debit', new.amount),
      jsonb_build_object('account', v_from_code, 'credit', new.amount)));
  return new;
end; $$;
create trigger trg_transfer_posting after insert on account_transfers
  for each row execute function record_transfer_posting();

-- ================= 6. BANK CHARGES / FEES / AIT / LEGAL =================
create type bank_charge_category as enum (
  'lc_fee', 'swift_fee', 'service_charge', 'legal_fee', 'ait_deducted', 'other'
);

create table bank_charge_entries (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  entry_no       text,
  entry_date     date not null default current_date,
  cash_bank_account_id uuid not null references cash_bank_accounts(id),
  category       bank_charge_category not null default 'service_charge',
  description    text,
  amount         numeric not null check (amount > 0),
  vat_amount     numeric not null default 0,   -- only if separately creditable — verify with accountant
  reference_no   text,
  created_by     uuid references auth.users(id),
  created_at     timestamptz not null default now(),
  unique (company_id, entry_no)
);

create or replace function fill_charge_entry_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.entry_no is null then
    new.entry_no := next_document_number(new.company_id, 'bank_charge_entry', 'BCE');
  end if;
  return new;
end; $$;
create trigger trg_charge_entry_no before insert on bank_charge_entries
  for each row execute function fill_charge_entry_no();

create or replace function record_bank_charge_posting() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_bank_code text;
  v_debit_acc text;
  v_lines jsonb;
begin
  select code into v_bank_code from accounts where id = (select gl_account_id from cash_bank_accounts where id = new.cash_bank_account_id);
  v_debit_acc := case new.category
    when 'legal_fee' then '5430'
    when 'ait_deducted' then '1250'
    else '5400' end;

  v_lines := jsonb_build_array(
    jsonb_build_object('account', v_debit_acc, 'debit', round(new.amount, 2), 'note', new.description));
  if new.vat_amount > 0 then
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('account','1260','debit', round(new.vat_amount, 2)));
  end if;
  v_lines := v_lines || jsonb_build_array(
    jsonb_build_object('account', v_bank_code, 'credit', round(new.amount + new.vat_amount, 2)));

  perform post_journal(new.company_id, new.entry_date,
    initcap(replace(new.category::text, '_', ' ')) || ' — ' || new.entry_no ||
      coalesce(' (' || new.reference_no || ')', ''),
    'bank_charge_entries', new.id, v_lines);
  return new;
end; $$;
create trigger trg_bank_charge_posting after insert on bank_charge_entries
  for each row execute function record_bank_charge_posting();

-- =================== 7. BANK STATEMENT RECONCILIATION ====================
create table bank_statement_lines (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  cash_bank_account_id  uuid not null references cash_bank_accounts(id),
  txn_date              date not null,
  description           text,
  debit                 numeric not null default 0,
  credit                numeric not null default 0,
  matched_journal_line_id uuid references journal_lines(id),
  created_by            uuid references auth.users(id),
  created_at            timestamptz not null default now(),
  check (debit = 0 or credit = 0)
);
create index idx_stmt_lines_account on bank_statement_lines(cash_bank_account_id, txn_date);

create or replace function match_statement_line(p_line_id uuid, p_journal_line_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_company uuid;
begin
  select company_id into v_company from bank_statement_lines where id = p_line_id;
  if auth.uid() is not null and not coalesce(can_write_company(v_company), false) then
    raise exception 'Not permitted for this company';
  end if;
  update bank_statement_lines set matched_journal_line_id = p_journal_line_id where id = p_line_id;
end; $$;
revoke execute on function match_statement_line(uuid, uuid) from anon;

-- ========================= 8. REPORTING VIEWS ===========================
-- Proper P&L statement (not just a trial balance): revenue, COGS, gross
-- profit, opex, financial expenses, net profit.
create view v_profit_and_loss with (security_invoker = true) as
  select company_id, code, name,
         case
           when code like '41%' or code like '42%' or code like '43%' or code = '4900' then 'revenue'
           when code = '5100' then 'cogs'
           when code in ('5400','5410','5420','5430') then 'financial_expense'
           when code like '5%' then 'operating_expense'
           else 'other'
         end as pnl_section,
         -balance as amount   -- income/expense sign flipped so both read positive when "normal"
    from account_balances
   where account_type in ('income', 'expense');

-- VAT (Mushak 9.1 basis): every GRN's input credit and every domestic /
-- cash-sale's output VAT, dated, for date-range filtering in the UI.
create view v_vat_transactions with (security_invoker = true) as
  select g.company_id, g.grn_date as txn_date, 'input' as vat_side,
         g.grn_no as doc_no, jl.debit as vat_amount
    from journal_lines jl
    join journals j on j.id = jl.journal_id
    join grns g on g.id = j.ref_id and j.ref_table = 'grns'
   where jl.account_id = (select id from accounts where code = '1260' and company_id = g.company_id)
  union all
  select cs.company_id, cs.sale_date as txn_date, 'output' as vat_side,
         cs.sale_no as doc_no, jl.credit as vat_amount
    from journal_lines jl
    join journals j on j.id = jl.journal_id
    join cash_sales cs on cs.id = j.ref_id and j.ref_table = 'cash_sales'
   where jl.account_id = (select id from accounts where code = '2510' and company_id = cs.company_id);

-- AIT: advance tax we've paid (asset, adjustable against final liability)
-- vs. tax we've withheld from others (liability, owed to NBR).
create view v_ait_summary with (security_invoker = true) as
  select company_id,
         sum(case when code = '1250' then balance else 0 end) as advance_tax_paid,
         sum(case when code = '2500' then -balance else 0 end) as tds_withheld_payable
    from account_balances
   where code in ('1250', '2500')
   group by company_id;

-- ==================== 9. CORPORATE TAX COMPUTATION ========================
-- A working paper, not a filing: net profit per accounts, adjusted by
-- addbacks/deductions to taxable income, less advance tax/TDS credits.
create table company_tax_computations (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  assessment_year    text not null,
  net_profit_per_accounts numeric not null default 0,
  tax_rate_pct       numeric not null default 27.5,
  advance_tax_paid   numeric not null default 0,
  tds_credit         numeric not null default 0,
  notes              text,
  created_by         uuid references auth.users(id),
  created_at         timestamptz not null default now(),
  unique (company_id, assessment_year)
);

create type tax_adjustment_type as enum ('addback', 'deduction');

create table company_tax_adjustment_lines (
  id             uuid primary key default gen_random_uuid(),
  computation_id uuid not null references company_tax_computations(id) on delete cascade,
  adj_type       tax_adjustment_type not null,
  description    text not null,
  amount         numeric not null default 0
);

create view v_tax_computation_totals with (security_invoker = true) as
  select c.id as computation_id,
         c.net_profit_per_accounts,
         coalesce(sum(l.amount) filter (where l.adj_type = 'addback'), 0) as total_addbacks,
         coalesce(sum(l.amount) filter (where l.adj_type = 'deduction'), 0) as total_deductions,
         c.net_profit_per_accounts
           + coalesce(sum(l.amount) filter (where l.adj_type = 'addback'), 0)
           - coalesce(sum(l.amount) filter (where l.adj_type = 'deduction'), 0) as taxable_income
    from company_tax_computations c
    left join company_tax_adjustment_lines l on l.computation_id = c.id
   group by c.id, c.net_profit_per_accounts;

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array[
    'cash_bank_accounts', 'cash_sales', 'account_transfers', 'bank_charge_entries',
    'bank_statement_lines', 'company_tax_computations'
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

-- cash_sale_lines / company_tax_adjustment_lines have no company_id of
-- their own — scoped via their parent document.
alter table cash_sale_lines enable row level security;
create policy cash_sale_lines_read on cash_sale_lines for select to authenticated
  using (exists (select 1 from cash_sales s where s.id = cash_sale_lines.cash_sale_id and is_member(s.company_id)));
create policy cash_sale_lines_write on cash_sale_lines for all to authenticated
  using (exists (select 1 from cash_sales s where s.id = cash_sale_lines.cash_sale_id and can_write_company(s.company_id)))
  with check (exists (select 1 from cash_sales s where s.id = cash_sale_lines.cash_sale_id and can_write_company(s.company_id)));
create trigger trg_audit_cash_sale_lines after insert or update or delete on cash_sale_lines
  for each row execute function audit_row_change();

alter table company_tax_adjustment_lines enable row level security;
create policy company_tax_adjustment_lines_read on company_tax_adjustment_lines for select to authenticated
  using (exists (select 1 from company_tax_computations c where c.id = company_tax_adjustment_lines.computation_id and is_member(c.company_id)));
create policy company_tax_adjustment_lines_write on company_tax_adjustment_lines for all to authenticated
  using (exists (select 1 from company_tax_computations c where c.id = company_tax_adjustment_lines.computation_id and can_write_company(c.company_id)))
  with check (exists (select 1 from company_tax_computations c where c.id = company_tax_adjustment_lines.computation_id and can_write_company(c.company_id)));
create trigger trg_audit_company_tax_adjustment_lines after insert or update or delete on company_tax_adjustment_lines
  for each row execute function audit_row_change();
