-- =====================================================================
-- Mahim Packaging ERP — 0007_hr_payroll
-- Employee master, attendance (BLA 2006 OT cap enforced at the row),
-- employee loans amortised through payroll, monthly payroll and
-- festival-bonus runs (tenure-prorated) posting through the GL engine.
--
-- Statutory formulas:
--   OT rate            = (basic / 208) × 2         [BLA 2006]
--   Absence deduction  = gross / 30 per absent day
--   Festival bonus     = full basic at ≥ 12 months tenure,
--                        else basic × tenure_months / 12
-- =====================================================================

create type payroll_status as enum ('draft','posted','paid');

create table employees (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  emp_no               text,
  full_name            text not null,
  designation          text,
  department           text,
  joining_date         date not null default current_date,
  basic_salary         numeric not null default 0,
  gross_salary         numeric not null default 0,
  attendance_allowance numeric not null default 0,   -- monthly, forfeited by any absence
  biometric_id         text,
  phone                text,
  nid_no               text,
  is_active            boolean not null default true,
  created_at           timestamptz not null default now(),
  unique (company_id, emp_no)
);

create or replace function fill_emp_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.emp_no is null then
    new.emp_no := next_document_number(new.company_id, 'employee', 'EMP');
  end if;
  return new;
end; $$;
create trigger trg_emp_no before insert on employees
  for each row execute function fill_emp_no();

-- ========================= ATTENDANCE ===============================
-- One row per employee per day (biometric sync upserts here). The OT
-- check is the Sedex/BSCI guardrail: >4h/day cannot even be recorded.
create table attendance (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  employee_id uuid not null references employees(id) on delete cascade,
  att_date    date not null,
  status      text not null default 'present',  -- present|absent|leave|holiday|weekend
  in_time     time,
  out_time    time,
  ot_hours    numeric not null default 0,
  is_late     boolean not null default false,
  unique (employee_id, att_date),
  check (ot_hours >= 0 and ot_hours <= 4),
  check (status in ('present','absent','leave','holiday','weekend'))
);
create index idx_att_emp_date on attendance(employee_id, att_date);

-- ======================= EMPLOYEE LOANS =============================
create table employee_loans (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id),
  loan_no             text,
  employee_id         uuid not null references employees(id),
  principal           numeric not null,
  monthly_installment numeric not null,
  balance             numeric not null,
  disbursed_at        date not null default current_date,
  status              text not null default 'active',   -- active | closed
  note                text,
  created_at          timestamptz not null default now(),
  unique (company_id, loan_no)
);

-- Disbursement: Dr Employee Loans Outstanding / Cr Bank. The structural
-- cap from the spec: principal ≤ 6 × basic wage.
create or replace function disburse_employee_loan(
  p_employee_id uuid, p_principal numeric, p_installment numeric, p_note text default null
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
                              monthly_installment, balance, note)
  values (v_emp.company_id,
          next_document_number(v_emp.company_id, 'employee_loan', 'EL'),
          p_employee_id, p_principal, p_installment, p_principal, p_note)
  returning id into v_id;

  perform post_journal(v_emp.company_id, current_date,
    'Employee loan disbursement — ' || v_emp.emp_no || ' ' || v_emp.full_name,
    'employee_loans', v_id,
    jsonb_build_array(
      jsonb_build_object('account','1240','debit', p_principal),
      jsonb_build_object('account','1100','credit', p_principal)));

  return v_id;
end; $$;
revoke execute on function disburse_employee_loan(uuid, numeric, numeric, text) from anon;

-- ========================= PAYROLL RUNS =============================
create table payroll_runs (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id),
  run_no       text,
  run_type     text not null default 'monthly',   -- monthly | festival_bonus
  period_year  int not null,
  period_month int not null,
  label        text,
  status       payroll_status not null default 'draft',
  total_gross  numeric not null default 0,
  total_net    numeric not null default 0,
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now(),
  unique (company_id, run_no),
  unique (company_id, run_type, period_year, period_month)
);

create table payroll_lines (
  id                   uuid primary key default gen_random_uuid(),
  run_id               uuid not null references payroll_runs(id) on delete cascade,
  company_id           uuid not null references companies(id),
  employee_id          uuid not null references employees(id),
  basic                numeric not null default 0,
  gross                numeric not null default 0,
  days_present         int not null default 0,
  days_absent          int not null default 0,
  ot_hours             numeric not null default 0,
  ot_rate              numeric not null default 0,
  ot_amount            numeric not null default 0,
  attendance_allowance numeric not null default 0,
  absence_deduction    numeric not null default 0,
  loan_recovery        numeric not null default 0,
  net_pay              numeric not null default 0
);

-- ================== GENERATE MONTHLY PAYROLL ========================
create or replace function generate_payroll(p_company uuid, p_year int, p_month int)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_run_id uuid;
  v_emp    record;
  v_pres   int; v_abs int; v_ot numeric;
  v_rate   numeric; v_ot_amt numeric; v_allow numeric;
  v_ded    numeric; v_loan numeric; v_net numeric;
  v_tg     numeric := 0; v_tn numeric := 0;
begin
  if auth.uid() is not null and not coalesce(can_write_company(p_company), false) then
    raise exception 'Not permitted for this company';
  end if;

  insert into payroll_runs (company_id, run_no, run_type, period_year, period_month,
                            label, created_by)
  values (p_company, next_document_number(p_company, 'payroll', 'PAY'),
          'monthly', p_year, p_month,
          to_char(make_date(p_year, p_month, 1), 'FMMonth YYYY'), auth.uid())
  returning id into v_run_id;

  for v_emp in
    select * from employees where company_id = p_company and is_active
  loop
    select count(*) filter (where status = 'present'),
           count(*) filter (where status = 'absent'),
           coalesce(sum(ot_hours), 0)
      into v_pres, v_abs, v_ot
      from attendance
     where employee_id = v_emp.id
       and att_date >= make_date(p_year, p_month, 1)
       and att_date <  make_date(p_year, p_month, 1) + interval '1 month';

    v_rate   := round(v_emp.basic_salary / 208 * 2, 2);       -- BLA 2006
    v_ot_amt := round(v_ot * v_rate, 2);
    v_allow  := case when v_abs = 0 then v_emp.attendance_allowance else 0 end;
    v_ded    := round(v_emp.gross_salary / 30 * v_abs, 2);
    select coalesce(min(least(monthly_installment, balance)), 0) into v_loan
      from employee_loans
     where employee_id = v_emp.id and status = 'active';
    v_net := round(v_emp.gross_salary - v_ded + v_ot_amt + v_allow - v_loan, 2);

    insert into payroll_lines (run_id, company_id, employee_id, basic, gross,
                               days_present, days_absent, ot_hours, ot_rate, ot_amount,
                               attendance_allowance, absence_deduction, loan_recovery, net_pay)
    values (v_run_id, p_company, v_emp.id, v_emp.basic_salary, v_emp.gross_salary,
            v_pres, v_abs, v_ot, v_rate, v_ot_amt, v_allow, v_ded, v_loan, v_net);

    v_tg := v_tg + v_emp.gross_salary - v_ded + v_ot_amt + v_allow;
    v_tn := v_tn + v_net;
  end loop;

  update payroll_runs set total_gross = round(v_tg,2), total_net = round(v_tn,2)
   where id = v_run_id;
  return v_run_id;
end; $$;
revoke execute on function generate_payroll(uuid, int, int) from anon;

-- ================== FESTIVAL BONUS RUN ==============================
-- Dual-festival statutory bonus, prorated on tenure at generation date.
create or replace function generate_festival_bonus(
  p_company uuid, p_year int, p_month int, p_label text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_run_id uuid;
  v_emp    record;
  v_months numeric;
  v_amt    numeric;
  v_tot    numeric := 0;
begin
  if auth.uid() is not null and not coalesce(can_write_company(p_company), false) then
    raise exception 'Not permitted for this company';
  end if;

  insert into payroll_runs (company_id, run_no, run_type, period_year, period_month,
                            label, created_by)
  values (p_company, next_document_number(p_company, 'payroll', 'PAY'),
          'festival_bonus', p_year, p_month, p_label, auth.uid())
  returning id into v_run_id;

  for v_emp in
    select * from employees where company_id = p_company and is_active
  loop
    v_months := extract(year from age(current_date, v_emp.joining_date)) * 12
              + extract(month from age(current_date, v_emp.joining_date));
    v_amt := case when v_months >= 12 then v_emp.basic_salary
                  else round(v_emp.basic_salary * v_months / 12.0, 2) end;
    if v_amt > 0 then
      insert into payroll_lines (run_id, company_id, employee_id, basic, gross, net_pay)
      values (v_run_id, p_company, v_emp.id, v_emp.basic_salary, v_amt, v_amt);
      v_tot := v_tot + v_amt;
    end if;
  end loop;

  update payroll_runs set total_gross = round(v_tot,2), total_net = round(v_tot,2)
   where id = v_run_id;
  return v_run_id;
end; $$;
revoke execute on function generate_festival_bonus(uuid, int, int, text) from anon;

-- ====================== POST / PAY A RUN ============================
-- post: expense recognised, net owed to workers, loan recoveries
--       amortised (Dr Salary-Payable-side against Cr Employee Loans).
--   monthly:  Dr 5200 (gross±) + Dr 5210 (OT) / Cr 2200 (net) + Cr 1240 (loans)
--   bonus:    Dr 5220 / Cr 2200
-- pay:  Dr 2200 / Cr 1100.
create or replace function post_payroll(p_run_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_run   payroll_runs;
  v_ot    numeric;
  v_loan  numeric;
  v_base  numeric;
  v_lines jsonb;
  v_l     record;
begin
  select * into v_run from payroll_runs where id = p_run_id for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if v_run.status <> 'draft' then raise exception 'Run is not draft'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_run.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  select coalesce(sum(ot_amount),0), coalesce(sum(loan_recovery),0)
    into v_ot, v_loan
    from payroll_lines where run_id = p_run_id;
  v_base := v_run.total_gross - v_ot;
  if v_run.total_gross <= 0 then raise exception 'Run has no value'; end if;

  if v_run.run_type = 'festival_bonus' then
    v_lines := jsonb_build_array(
      jsonb_build_object('account','5220','debit', v_run.total_gross),
      jsonb_build_object('account','2200','credit', v_run.total_net));
  else
    v_lines := jsonb_build_array(
      jsonb_build_object('account','5200','debit', round(v_base,2)),
      jsonb_build_object('account','5210','debit', round(v_ot,2)),
      jsonb_build_object('account','2200','credit', v_run.total_net),
      jsonb_build_object('account','1240','credit', round(v_loan,2)));
  end if;

  perform post_journal(v_run.company_id, current_date,
    'Payroll ' || v_run.label || ' (' || v_run.run_no || ')',
    'payroll_runs', v_run.id, v_lines);

  -- amortise loan balances
  for v_l in
    select employee_id, loan_recovery from payroll_lines
     where run_id = p_run_id and loan_recovery > 0
  loop
    update employee_loans
       set balance = balance - v_l.loan_recovery,
           status  = case when balance - v_l.loan_recovery <= 0 then 'closed' else 'active' end
     where employee_id = v_l.employee_id and status = 'active';
  end loop;

  update payroll_runs set status = 'posted' where id = p_run_id;
end; $$;
revoke execute on function post_payroll(uuid) from anon;

create or replace function pay_payroll(p_run_id uuid) returns void
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
      jsonb_build_object('account','1100','credit', v_run.total_net)));

  update payroll_runs set status = 'paid' where id = p_run_id;
end; $$;
revoke execute on function pay_payroll(uuid) from anon;

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array[
    'employees','attendance','employee_loans','payroll_runs','payroll_lines'
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
