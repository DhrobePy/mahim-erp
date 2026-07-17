-- =====================================================================
-- Mahim Packaging ERP — 0012_company_admin
-- Company administration: profile + logo, group structure (subsidiary
-- creation), directors/partners (feeds RJSC Form XII / Schedule X
-- printable drafts), company document register with expiry tracking,
-- a generic legal-review log (attaches to any document/contract),
-- a forwarding-letter pad, and an IT-10B wealth-statement builder.
--
-- IT-10B and the RJSC prints generated from this data are DRAFT
-- PREPARATION AIDS, not certified filings — same posture as the LC
-- clause library: standard reference, verify with a tax practitioner /
-- company secretary before submission to NBR / RJSC.
-- =====================================================================

-- ===================== 1. COMPANY PROFILE FIELDS =====================
alter table companies
  add column if not exists logo_path text,
  add column if not exists phone     text,
  add column if not exists email     text,
  add column if not exists website   text;

insert into storage.buckets (id, name, public)
values ('company-assets', 'company-assets', true)
on conflict (id) do nothing;

create policy "company-assets read" on storage.objects for select to authenticated
  using (bucket_id = 'company-assets');
create policy "company-assets write" on storage.objects for insert to authenticated
  with check (bucket_id = 'company-assets');
create policy "company-assets update" on storage.objects for update to authenticated
  using (bucket_id = 'company-assets');

-- ===================== 2. CREATE A CHILD COMPANY ======================
-- Only an admin of the parent may spin up a subsidiary; the creator is
-- auto-granted admin on the new company so it isn't orphaned. The CoA
-- auto-seeds via the existing trg_company_coa trigger (migration 0003).
create or replace function create_child_company(
  p_name text, p_code text, p_legal_name text default null, p_parent_id uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is not null and p_parent_id is not null
     and not coalesce(member_role(p_parent_id) = 'admin', false) then
    raise exception 'Only an admin of the parent company can create a subsidiary';
  end if;
  if p_name is null or p_code is null then raise exception 'Name and code are required'; end if;

  insert into companies (parent_company_id, code, name, legal_name)
  values (p_parent_id, p_code, p_name, coalesce(p_legal_name, p_name))
  returning id into v_id;

  if auth.uid() is not null then
    insert into company_members (user_id, company_id, role) values (auth.uid(), v_id, 'admin');
  end if;
  return v_id;
end; $$;
revoke execute on function create_child_company(text, text, text, uuid) from anon;

-- ==================== 3. DIRECTORS & PARTNERS =========================
create type director_designation as enum (
  'chairman', 'managing_director', 'director', 'partner', 'company_secretary'
);

create table company_directors (
  id                     uuid primary key default gen_random_uuid(),
  company_id             uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  full_name              text not null,
  designation            director_designation not null default 'director',
  father_or_spouse_name  text,
  nid_no                 text,
  tin_no                 text,
  nationality            text not null default 'Bangladeshi',
  address                text,
  phone                  text,
  email                  text,
  shares_held            numeric not null default 0,
  share_face_value       numeric not null default 100,
  appointment_date       date not null default current_date,
  resignation_date       date,
  is_active              boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create trigger trg_directors_updated before update on company_directors
  for each row execute function set_updated_at();

-- =================== 4. COMPANY DOCUMENT REGISTER =====================
create type company_doc_type as enum (
  'trade_license', 'incorporation_certificate', 'moa_aoa', 'tin_certificate',
  'vat_bin_certificate', 'fire_license', 'environment_clearance',
  'bank_account_doc', 'membership_certificate', 'other'
);

create table company_documents (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  doc_type     company_doc_type not null default 'other',
  title        text not null,
  doc_no       text,
  issue_date   date,
  expiry_date  date,
  file_path    text,
  notes        text,
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now()
);

create view v_company_document_alerts with (security_invoker = true) as
  select company_id, id as document_id, title, expiry_date,
         case when expiry_date < current_date then 'expired' else 'expiring_soon' end as alert_type,
         (expiry_date - current_date) as days
    from company_documents
   where expiry_date is not null
     and expiry_date < current_date + 30;

-- ======================= 5. LEGAL REVIEW LOG ===========================
-- Polymorphic, like audit_log/notifications: attaches to any document
-- or contract (company_documents, sales_documents...). Every action is
-- a new row (history preserved); read the latest per ref for current
-- status.
create type legal_review_status as enum ('pending', 'approved', 'flagged', 'rejected');

create table legal_reviews (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  ref_table      text not null,
  ref_id         uuid not null,
  status         legal_review_status not null default 'pending',
  reviewer_notes text,
  reviewed_by    uuid references auth.users(id),
  reviewed_at    timestamptz not null default now(),
  created_at     timestamptz not null default now()
);
create index idx_legal_reviews_ref on legal_reviews(ref_table, ref_id, reviewed_at desc);

create view v_latest_legal_review with (security_invoker = true) as
  select distinct on (ref_table, ref_id)
    ref_table, ref_id, company_id, status, reviewer_notes, reviewed_by, reviewed_at
    from legal_reviews
   order by ref_table, ref_id, reviewed_at desc;

-- ======================== 6. FORWARDING PAD ============================
create table forwarding_letters (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  letter_no   text,
  letter_date date not null default current_date,
  to_name     text not null,
  to_address  text,
  subject     text not null,
  body        text,
  enclosures  text,
  cc          text,
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now(),
  unique (company_id, letter_no)
);

create or replace function fill_forwarding_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.letter_no is null then
    new.letter_no := next_document_number(new.company_id, 'forwarding_letter', 'FWD');
  end if;
  return new;
end; $$;
create trigger trg_forwarding_no before insert on forwarding_letters
  for each row execute function fill_forwarding_no();

-- ================ 7. IT-10B WEALTH STATEMENT BUILDER ===================
create table it10b_statements (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  director_id        uuid references company_directors(id),
  individual_name    text,          -- fallback if not linked to a director
  individual_tin     text,
  assessment_year    text not null,  -- e.g. '2025-2026'
  statement_date     date not null default current_date,
  opening_net_wealth numeric not null default 0,
  total_income       numeric not null default 0,
  total_expenditure  numeric not null default 0,
  created_by         uuid references auth.users(id),
  created_at         timestamptz not null default now(),
  check (director_id is not null or individual_name is not null)
);

create type it10b_category as enum (
  'business_capital', 'non_agri_property', 'agri_property', 'investments',
  'motor_vehicles', 'ornaments', 'furniture_electronics', 'cash_bank', 'other_assets',
  'mortgage_liability', 'bank_loan_liability', 'other_liability'
);

create table it10b_lines (
  id            uuid primary key default gen_random_uuid(),
  statement_id  uuid not null references it10b_statements(id) on delete cascade,
  category      it10b_category not null,
  description   text not null,
  amount        numeric not null default 0
);

create view v_it10b_totals with (security_invoker = true) as
  select
    statement_id,
    sum(amount) filter (where category not in ('mortgage_liability','bank_loan_liability','other_liability')) as total_assets,
    sum(amount) filter (where category in ('mortgage_liability','bank_loan_liability','other_liability')) as total_liabilities
  from it10b_lines
  group by statement_id;

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array[
    'company_directors', 'company_documents', 'legal_reviews',
    'forwarding_letters', 'it10b_statements'
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

-- it10b_lines has no company_id column of its own (scoped via its parent
-- statement) — its policies join through it10b_statements instead.
alter table it10b_lines enable row level security;
create policy it10b_lines_read on it10b_lines for select to authenticated
  using (exists (select 1 from it10b_statements s
                  where s.id = it10b_lines.statement_id and is_member(s.company_id)));
create policy it10b_lines_write on it10b_lines for all to authenticated
  using (exists (select 1 from it10b_statements s
                  where s.id = it10b_lines.statement_id and can_write_company(s.company_id)))
  with check (exists (select 1 from it10b_statements s
                        where s.id = it10b_lines.statement_id and can_write_company(s.company_id)));
create trigger trg_audit_it10b_lines after insert or update or delete on it10b_lines
  for each row execute function audit_row_change();
