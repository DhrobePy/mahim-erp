-- =====================================================================
-- Mahim Packaging ERP — 0013_resolutions_banking
-- Expands the license register for a real manufacturing factory,
-- adds Board Resolutions (minutes with choosable-or-manual agenda
-- items, feeds RJSC-adjacent governance needs and bank mandates), and
-- a bank branch register + service-request correspondence system
-- (LC issue, document collection, discrepancy handling, statements,
-- LBPD, FDR, DPS, and a manual catch-all).
-- =====================================================================

-- ================ 1. EXPANDED LICENSE / CERTIFICATE TYPES =============
-- Each ADD VALUE is its own statement and none are consumed later in
-- this same migration, so the "can't use a new enum value in the same
-- transaction it was added" restriction never applies here.
alter type company_doc_type add value if not exists 'factory_license';
alter type company_doc_type add value if not exists 'boiler_certificate';
alter type company_doc_type add value if not exists 'bsci_sedex_audit';
alter type company_doc_type add value if not exists 'fsc_coc_certificate';
alter type company_doc_type add value if not exists 'import_registration_certificate';
alter type company_doc_type add value if not exists 'export_registration_certificate';
alter type company_doc_type add value if not exists 'effluent_treatment_certificate';
alter type company_doc_type add value if not exists 'electrical_installation_license';
alter type company_doc_type add value if not exists 'bsti_certification';
alter type company_doc_type add value if not exists 'trademark_design_registration';
alter type company_doc_type add value if not exists 'labour_welfare_registration';
alter type company_doc_type add value if not exists 'group_insurance_certificate';
alter type company_doc_type add value if not exists 'bank_charge_document';
alter type company_doc_type add value if not exists 'noc_certificate';

-- ========================= 2. BOARD RESOLUTIONS ========================
create type board_meeting_type as enum ('board_meeting', 'agm', 'egm', 'circular_resolution');
create type board_resolution_status as enum ('draft', 'passed', 'circulated');

create table board_resolutions (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  resolution_no text,
  meeting_type  board_meeting_type not null default 'board_meeting',
  meeting_no    text,            -- e.g. "15th Board Meeting"
  meeting_date  date not null default current_date,
  venue         text,
  chairperson   text,
  status        board_resolution_status not null default 'draft',
  notes         text,
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  unique (company_id, resolution_no)
);

create or replace function fill_resolution_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.resolution_no is null then
    new.resolution_no := next_document_number(new.company_id, 'board_resolution', 'BR');
  end if;
  return new;
end; $$;
create trigger trg_resolution_no before insert on board_resolutions
  for each row execute function fill_resolution_no();

create table board_resolution_agendas (
  id              uuid primary key default gen_random_uuid(),
  resolution_id   uuid not null references board_resolutions(id) on delete cascade,
  agenda_no       int not null,
  title           text not null,
  resolution_text text not null,
  is_standard     boolean not null default false,   -- true if picked from the template library
  unique (resolution_id, agenda_no)
);

create table board_resolution_attendees (
  resolution_id uuid not null references board_resolutions(id) on delete cascade,
  director_id   uuid not null references company_directors(id),
  primary key (resolution_id, director_id)
);

-- ========================= 3. BANK BRANCHES =============================
create table bank_branches (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  bank_party_id  uuid not null references parties(id),
  branch_name    text not null,
  branch_address text,
  routing_no     text,
  contact_person text,
  phone          text,
  email          text,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

-- ===================== 4. BANK SERVICE REQUESTS ==========================
create type bank_service_type as enum (
  'lc_issue', 'document_collection', 'discrepancy', 'bank_statement',
  'lbpd_issue', 'fdr', 'dps', 'manual'
);
create type bank_request_status as enum ('draft', 'submitted', 'acknowledged', 'completed');

create table bank_service_requests (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  request_no          text,
  branch_id           uuid not null references bank_branches(id),
  service_type        bank_service_type not null default 'manual',
  request_date        date not null default current_date,
  reference_no        text,      -- e.g. LC no. / bill no. / facility name being referenced
  subject             text not null,
  body                text,
  amount              numeric,
  tenor_or_period      text,
  board_resolution_id uuid references board_resolutions(id),
  status              bank_request_status not null default 'draft',
  created_by          uuid references auth.users(id),
  created_at          timestamptz not null default now(),
  unique (company_id, request_no)
);

create or replace function fill_bank_request_no() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.request_no is null then
    new.request_no := next_document_number(new.company_id, 'bank_service_request', 'BSR');
  end if;
  return new;
end; $$;
create trigger trg_bank_request_no before insert on bank_service_requests
  for each row execute function fill_bank_request_no();

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array[
    'board_resolutions', 'bank_branches', 'bank_service_requests'
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

-- board_resolution_agendas / _attendees have no company_id of their own
-- (scoped via their parent resolution) — join through instead.
alter table board_resolution_agendas enable row level security;
create policy board_resolution_agendas_read on board_resolution_agendas for select to authenticated
  using (exists (select 1 from board_resolutions r
                  where r.id = board_resolution_agendas.resolution_id and is_member(r.company_id)));
create policy board_resolution_agendas_write on board_resolution_agendas for all to authenticated
  using (exists (select 1 from board_resolutions r
                  where r.id = board_resolution_agendas.resolution_id and can_write_company(r.company_id)))
  with check (exists (select 1 from board_resolutions r
                        where r.id = board_resolution_agendas.resolution_id and can_write_company(r.company_id)));
create trigger trg_audit_board_resolution_agendas after insert or update or delete on board_resolution_agendas
  for each row execute function audit_row_change();

alter table board_resolution_attendees enable row level security;
create policy board_resolution_attendees_read on board_resolution_attendees for select to authenticated
  using (exists (select 1 from board_resolutions r
                  where r.id = board_resolution_attendees.resolution_id and is_member(r.company_id)));
create policy board_resolution_attendees_write on board_resolution_attendees for all to authenticated
  using (exists (select 1 from board_resolutions r
                  where r.id = board_resolution_attendees.resolution_id and can_write_company(r.company_id)))
  with check (exists (select 1 from board_resolutions r
                        where r.id = board_resolution_attendees.resolution_id and can_write_company(r.company_id)));
