-- =====================================================================
-- Mahim Packaging ERP — 0003_gl_core
-- General ledger core: chart of accounts (template-seeded per company),
-- immutable journals, and the post_journal engine every operational
-- module calls. Journals can ONLY be created through post_journal
-- (no client insert policy), which guarantees every entry balances.
-- =====================================================================

-- Enum values used by later migrations (added here so the same-transaction
-- restriction on new enum values never bites).
alter type stock_movement_type add value if not exists 'sales_return_in';
alter type stock_movement_type add value if not exists 'scrap_in';
alter type stock_movement_type add value if not exists 'scrap_out';

create type account_type as enum ('asset','liability','equity','income','expense');

-- ==================== CHART OF ACCOUNTS =============================
create table accounts (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  code         text not null,
  name         text not null,
  account_type account_type not null,
  parent_id    uuid references accounts(id),
  is_postable  boolean not null default true,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (company_id, code)
);

create or replace function account_id(p_company uuid, p_code text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from accounts
   where company_id = p_company and code = p_code and is_postable and is_active;
$$;

-- Standard CoA template. Codes follow the trade-finance framework:
-- the specialised accounts (GDNI, Bills Receivable under LC, LBPD, Forced
-- PAD, margins, AIT/TDS) exist from day one so posting rules never miss.
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
    (p_company,'5500','Freight & Transit Expenses','expense',true),
    (p_company,'5600','Scrap Valuation Loss','expense',true),
    (p_company,'5700','Depreciation','expense',true),
    (p_company,'5900','Miscellaneous Expense','expense',true)
  on conflict (company_id, code) do nothing;
end; $$;

select seed_default_coa('00000000-0000-0000-0000-000000000001');

-- Every new company automatically gets the CoA template.
create or replace function handle_new_company() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform seed_default_coa(new.id);
  return new;
end; $$;
create trigger trg_company_coa after insert on companies
  for each row execute function handle_new_company();

-- ========================= JOURNALS =================================
create table journals (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id),
  journal_no   text not null,
  journal_date date not null default current_date,
  memo         text,
  ref_table    text,
  ref_id       uuid,
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  unique (company_id, journal_no)
);
create index idx_journals_ref on journals(ref_table, ref_id);

create table journal_lines (
  id             uuid primary key default gen_random_uuid(),
  journal_id     uuid not null references journals(id) on delete cascade,
  company_id     uuid not null references companies(id),
  account_id     uuid not null references accounts(id),
  debit          numeric not null default 0,
  credit         numeric not null default 0,
  party_id       uuid references parties(id),
  cost_center_id uuid references cost_centers(id),
  currency       text not null default 'BDT',
  fx_rate        numeric not null default 1,
  note           text,
  check (debit >= 0 and credit >= 0 and (debit = 0 or credit = 0))
);
create index idx_jl_journal on journal_lines(journal_id);
create index idx_jl_account on journal_lines(account_id);

-- ===================== POSTING ENGINE ===============================
-- The single entry point for money. p_lines is a jsonb array:
--   [{"account":"1100","debit":5000,"credit":0,"party_id":null,
--     "cost_center_id":null,"note":"..."}, ...]
-- Accounts are referenced by CODE so posting rules read like the
-- accounting framework spec. Raises unless debits = credits.
create or replace function post_journal(
  p_company   uuid,
  p_date      date,
  p_memo      text,
  p_ref_table text,
  p_ref_id    uuid,
  p_lines     jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_journal_id uuid;
  v_line       jsonb;
  v_account    uuid;
  v_debits     numeric := 0;
  v_credits    numeric := 0;
  v_n          int := 0;
begin
  if auth.uid() is not null and not coalesce(can_write_company(p_company), false) then
    raise exception 'Not permitted to post journals for this company';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_debits  := v_debits  + coalesce((v_line->>'debit')::numeric, 0);
    v_credits := v_credits + coalesce((v_line->>'credit')::numeric, 0);
    v_n := v_n + 1;
  end loop;
  if v_n < 2 then raise exception 'A journal needs at least two lines'; end if;
  if abs(v_debits - v_credits) > 0.005 then
    raise exception 'Journal does not balance: debits % vs credits %', v_debits, v_credits;
  end if;
  if v_debits = 0 then raise exception 'Journal has zero value'; end if;

  insert into journals (company_id, journal_no, journal_date, memo, ref_table, ref_id, created_by)
  values (p_company, next_document_number(p_company, 'journal', 'JV'),
          coalesce(p_date, current_date), p_memo, p_ref_table, p_ref_id, auth.uid())
  returning id into v_journal_id;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_account := account_id(p_company, v_line->>'account');
    if v_account is null then
      raise exception 'Unknown or non-postable account code "%"', v_line->>'account';
    end if;
    if coalesce((v_line->>'debit')::numeric, 0) = 0
       and coalesce((v_line->>'credit')::numeric, 0) = 0 then
      continue;
    end if;
    insert into journal_lines (journal_id, company_id, account_id, debit, credit,
                               party_id, cost_center_id, note)
    values (v_journal_id, p_company, v_account,
            coalesce((v_line->>'debit')::numeric, 0),
            coalesce((v_line->>'credit')::numeric, 0),
            nullif(v_line->>'party_id','')::uuid,
            nullif(v_line->>'cost_center_id','')::uuid,
            v_line->>'note');
  end loop;

  return v_journal_id;
end; $$;
revoke execute on function post_journal(uuid, date, text, text, uuid, jsonb) from anon;

-- ========================== VIEWS ===================================
create view account_balances with (security_invoker = true) as
  select
    jl.company_id,
    jl.account_id,
    a.code,
    a.name,
    a.account_type,
    sum(jl.debit)             as total_debit,
    sum(jl.credit)            as total_credit,
    sum(jl.debit - jl.credit) as balance
  from journal_lines jl
  join accounts a on a.id = jl.account_id
  group by jl.company_id, jl.account_id, a.code, a.name, a.account_type;

create view trial_balance with (security_invoker = true) as
  select
    company_id, code, name, account_type,
    total_debit, total_credit,
    case when balance > 0 then balance else 0 end  as debit_balance,
    case when balance < 0 then -balance else 0 end as credit_balance
  from account_balances
  order by code;

-- ============================ RLS ===================================
alter table accounts      enable row level security;
alter table journals      enable row level security;
alter table journal_lines enable row level security;

create policy accounts_read on accounts for select to authenticated
  using (is_member(company_id));
create policy accounts_write on accounts for all to authenticated
  using (can_write_company(company_id)) with check (can_write_company(company_id));

-- Journals are read-only from the client: creation goes through
-- post_journal (SECURITY DEFINER); there is deliberately no insert,
-- update or delete policy.
create policy journals_read on journals for select to authenticated
  using (is_member(company_id));
create policy journal_lines_read on journal_lines for select to authenticated
  using (is_member(company_id));
