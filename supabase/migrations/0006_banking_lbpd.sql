-- =====================================================================
-- Mahim Packaging ERP — 0006_banking_lbpd
-- Bank facilities with limits, bills under LC (submission → acceptance
-- → maturity), LBPD discounting and the forced-PAD conversion when the
-- issuing bank fails to remit at maturity.
--
-- Accounting (accounting-correct variant of the framework spec):
--   disburse:  Dr Bank(principal) / Cr LBPD Loan(principal); the bill
--              receivable stays on the books — LBPD is a loan against it.
--   settle:    Dr LBPD Loan(principal) + Dr Interest + Dr Bank(margin
--              net of interest) / Cr Bills Receivable(full bill).
--   forced:    Dr LBPD Loan / Cr Forced PAD Loan; penalty interest
--              account (5420) applies at eventual settlement.
-- =====================================================================

create type bill_status as enum ('submitted','accepted','discounted','realized','overdue');
create type lbpd_status as enum ('open','settled','forced_pad');

create table bank_facilities (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  bank_party_id  uuid not null references parties(id),
  facility_type  text not null default 'lbpd',   -- lbpd | od | cc | term
  name           text not null,
  limit_amount   numeric not null default 0,
  interest_rate  numeric not null default 0,     -- annual %
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

create table bills (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id),
  bill_no       text,
  lc_id         uuid not null references lcs(id),
  invoice_id    uuid not null references invoices(id),
  amount        numeric not null,
  submitted_at  date not null default current_date,
  accepted_at   date,
  maturity_date date,
  status        bill_status not null default 'submitted',
  note          text,
  created_at    timestamptz not null default now(),
  unique (company_id, bill_no)
);

create table lbpd_disbursements (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id),
  bill_id       uuid not null references bills(id),
  facility_id   uuid not null references bank_facilities(id),
  advance_pct   numeric not null default 85,
  principal     numeric not null,
  interest_rate numeric not null default 0,
  disbursed_at  date not null default current_date,
  status        lbpd_status not null default 'open',
  settled_at    date,
  interest_paid numeric not null default 0,
  created_at    timestamptz not null default now()
);

-- =============== SUBMIT A BILL AGAINST AN INVOICE ===================
create or replace function create_bill(p_invoice_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_inv  invoices;
  v_id   uuid;
begin
  select * into v_inv from invoices where id = p_invoice_id;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv.lc_id is null then raise exception 'Invoice has no LC — bills need one'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_inv.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if exists (select 1 from bills where invoice_id = p_invoice_id) then
    raise exception 'A bill already exists for this invoice';
  end if;

  insert into bills (company_id, bill_no, lc_id, invoice_id, amount)
  values (v_inv.company_id,
          next_document_number(v_inv.company_id, 'bill', 'BILL'),
          v_inv.lc_id, p_invoice_id, v_inv.total)
  returning id into v_id;

  update invoices set status = 'billed' where id = p_invoice_id;
  return v_id;
end; $$;
revoke execute on function create_bill(uuid) from anon;

-- ====================== BANK ACCEPTANCE =============================
-- Maturity = acceptance date + the LC's usance days.
create or replace function accept_bill(p_bill_id uuid, p_accepted_at date default current_date)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_bill bills;
  v_days int;
begin
  select * into v_bill from bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found'; end if;
  if v_bill.status <> 'submitted' then raise exception 'Bill is not awaiting acceptance'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_bill.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  select usance_days into v_days from lcs where id = v_bill.lc_id;
  update bills
     set status = 'accepted',
         accepted_at = coalesce(p_accepted_at, current_date),
         maturity_date = coalesce(p_accepted_at, current_date) + coalesce(v_days, 0)
   where id = p_bill_id;
end; $$;
revoke execute on function accept_bill(uuid, date) from anon;

-- ===================== LBPD DISBURSEMENT ============================
create or replace function disburse_lbpd(
  p_bill_id uuid, p_facility_id uuid, p_advance_pct numeric default 85
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
                                  principal, interest_rate)
  values (v_bill.company_id, p_bill_id, p_facility_id, p_advance_pct,
          v_principal, v_fac.interest_rate)
  returning id into v_id;

  perform post_journal(v_bill.company_id, current_date,
    'LBPD disbursement ' || round(p_advance_pct) || '% against bill ' || v_bill.bill_no,
    'lbpd_disbursements', v_id,
    jsonb_build_array(
      jsonb_build_object('account','1100','debit', v_principal),
      jsonb_build_object('account','2300','credit', v_principal,
                         'party_id', v_fac.bank_party_id::text)));

  update bills set status = 'discounted' where id = p_bill_id;
  return v_id;
end; $$;
revoke execute on function disburse_lbpd(uuid, uuid, numeric) from anon;

-- ================== SETTLEMENT AT MATURITY ==========================
-- The issuing bank remits the full bill; loan closes, interest is
-- charged, the net margin lands in the bank account. Works for both
-- normal LBPD (interest → 5410) and forced PAD (penalty → 5420).
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
      jsonb_build_object('account','1100','debit', v_net),
      jsonb_build_object('account','1210','credit', v_bill.amount)));

  update lbpd_disbursements
     set status = 'settled', settled_at = current_date,
         interest_paid = coalesce(p_interest, 0)
   where id = p_disbursement_id;
  update bills set status = 'realized' where id = v_d.bill_id;
  update invoices set status = 'settled' where id = v_bill.invoice_id;
end; $$;
revoke execute on function settle_lbpd(uuid, numeric) from anon;

-- ================= FORCED PAD CONVERSION ============================
-- Issuing bank failed to remit at maturity: the clean LBPD profile
-- closes and reopens as a penalty-rate forced loan.
create or replace function convert_to_forced_pad(p_disbursement_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_d lbpd_disbursements;
begin
  select * into v_d from lbpd_disbursements where id = p_disbursement_id for update;
  if not found then raise exception 'Disbursement not found'; end if;
  if v_d.status <> 'open' then raise exception 'Only open LBPD can convert'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_d.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  perform post_journal(v_d.company_id, current_date,
    'LBPD → forced PAD conversion (issuing bank default at maturity)',
    'lbpd_disbursements', v_d.id,
    jsonb_build_array(
      jsonb_build_object('account','2300','debit', v_d.principal),
      jsonb_build_object('account','2310','credit', v_d.principal)));

  update lbpd_disbursements set status = 'forced_pad' where id = p_disbursement_id;
  update bills set status = 'overdue' where id = v_d.bill_id;
end; $$;
revoke execute on function convert_to_forced_pad(uuid) from anon;

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array['bank_facilities','bills','lbpd_disbursements'] loop
    execute format('alter table %I enable row level security;', t);
    execute format(
      'create policy %I on %I for select to authenticated using (is_member(company_id));',
      t || '_read', t);
    execute format(
      'create policy %I on %I for all to authenticated using (can_write_company(company_id)) with check (can_write_company(company_id));',
      t || '_write', t);
  end loop;
end $$;
