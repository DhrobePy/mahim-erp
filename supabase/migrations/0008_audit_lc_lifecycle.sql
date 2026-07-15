-- =====================================================================
-- Mahim Packaging ERP — 0008_audit_lc_lifecycle
--   1. audit_log — who did what, when, with old/new row images, on
--      every business table (including access grants).
--   2. LC lifecycle — lc_events timeline (auto-fed by triggers on LCs,
--      amendments and bills), discrepancy tracking, notifications,
--      document store (manual PDF upload + extracted fields),
--      time-based alerts (maturity soon / overdue), per-contract P&L,
--      and formal close-out.
-- Email ingestion is deliberately NOT here: it needs a server-side
-- mailbox listener (edge function / cron forwarder) — the lc_documents
-- table is the landing zone it will write into later.
-- =====================================================================

-- ========================= 1. AUDIT TRAIL ===========================
create table audit_log (
  id         bigint generated always as identity primary key,
  company_id uuid,
  table_name text not null,
  record_id  uuid,
  action     text not null,            -- INSERT | UPDATE | DELETE
  actor      uuid,                     -- auth.uid(); null = system/SQL
  old_data   jsonb,
  new_data   jsonb,
  created_at timestamptz not null default now()
);
create index idx_audit_company_time on audit_log(company_id, created_at desc);
create index idx_audit_table on audit_log(table_name, record_id);

create or replace function audit_row_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_new jsonb; v_old jsonb; v_company uuid; v_id uuid;
begin
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  v_company := coalesce((v_new->>'company_id')::uuid, (v_old->>'company_id')::uuid);
  v_id      := coalesce((v_new->>'id')::uuid, (v_old->>'id')::uuid);
  insert into audit_log (company_id, table_name, record_id, action, actor, old_data, new_data)
  values (v_company, tg_table_name, v_id, tg_op, auth.uid(), v_old, v_new);
  return coalesce(new, old);
end; $$;

do $$
declare t text;
begin
  foreach t in array array[
    'parties','items','warehouses','boms','bom_lines','production_orders',
    'gate_entries','grns','grn_lines','debit_notes',
    'sales_orders','sales_order_lines','lcs','lc_amendments',
    'delivery_challans','delivery_challan_lines','invoices','credit_notes',
    'bank_facilities','bills','lbpd_disbursements',
    'employees','attendance','employee_loans','payroll_runs',
    'company_members','accounts','cost_centers','document_series'
  ] loop
    execute format(
      'create trigger trg_audit_%s after insert or update or delete on %I
         for each row execute function audit_row_change();', t, t);
  end loop;
end $$;

alter table audit_log enable row level security;
create policy audit_log_read on audit_log for select to authenticated
  using (company_id is null and is_any_admin()
         or coalesce(member_role(company_id) = 'admin', false));
-- no insert/update/delete policies: writes happen only via the definer trigger

-- ====================== 2. LC EVENT TIMELINE ========================
create table lc_events (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id),
  lc_id      uuid not null references lcs(id) on delete cascade,
  event_type text not null check (event_type in (
    'opened','amendment','docs_submitted','discrepancy','discrepancy_resolved',
    'acceptance','discounted','matured','realized','overdue','forced_pad',
    'note','closed')),
  event_date date not null default current_date,
  detail     text,
  ref_table  text,
  ref_id     uuid,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index idx_lc_events_lc on lc_events(lc_id, created_at);

-- ======================= 3. NOTIFICATIONS ===========================
-- Company-wide feed (small team; per-user read tracking can come later).
create table notifications (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id),
  kind       text not null default 'lc',      -- lc | system
  title      text not null,
  body       text,
  ref_table  text,
  ref_id     uuid,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_notifications_company on notifications(company_id, is_read, created_at desc);

alter table lc_events     enable row level security;
alter table notifications enable row level security;
create policy lc_events_read on lc_events for select to authenticated
  using (is_member(company_id));
create policy lc_events_write on lc_events for insert to authenticated
  with check (can_write_company(company_id));
create policy notifications_read on notifications for select to authenticated
  using (is_member(company_id));
create policy notifications_mark on notifications for update to authenticated
  using (is_member(company_id)) with check (is_member(company_id));

-- Every LC event raises a notification.
create or replace function notify_lc_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_lc_no text;
begin
  select lc_no into v_lc_no from lcs where id = new.lc_id;
  insert into notifications (company_id, kind, title, body, ref_table, ref_id)
  values (new.company_id, 'lc',
          'LC ' || coalesce(v_lc_no, '?') || ' — ' || replace(new.event_type, '_', ' '),
          new.detail, 'lcs', new.lc_id);
  return new;
end; $$;
create trigger trg_notify_lc_event after insert on lc_events
  for each row execute function notify_lc_event();

-- Auto-events: LC registered / amended.
create or replace function lc_opened_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into lc_events (company_id, lc_id, event_type, detail, created_by)
  values (new.company_id, new.id, 'opened',
          'LC registered (' || new.lc_type || case when new.lc_type = 'usance'
            then ' ' || new.usance_days || 'd' else '' end || ')', auth.uid());
  return new;
end; $$;
create trigger trg_lc_opened after insert on lcs
  for each row execute function lc_opened_event();

create or replace function lc_amendment_event() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.version > 1 then
    insert into lc_events (company_id, lc_id, event_type, detail, ref_table, ref_id, created_by)
    values (new.company_id, new.lc_id, 'amendment',
            'v' || new.version || ': amount ' || new.amount ||
            coalesce(', qty ' || new.quantity, '') ||
            coalesce(', expiry ' || new.expiry_date, ''),
            'lc_amendments', new.id, auth.uid());
  end if;
  return new;
end; $$;
create trigger trg_lc_amendment_event after insert on lc_amendments
  for each row execute function lc_amendment_event();

-- Auto-events: bill status transitions map onto the LC timeline.
create or replace function bill_status_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if old.status is distinct from new.status then
    v_type := case new.status
      when 'accepted'   then 'acceptance'
      when 'discounted' then 'discounted'
      when 'realized'   then 'realized'
      when 'overdue'    then 'overdue'
      else null end;
    if v_type is not null then
      insert into lc_events (company_id, lc_id, event_type, event_date, detail, ref_table, ref_id, created_by)
      values (new.company_id, new.lc_id, v_type, current_date,
              'Bill ' || new.bill_no ||
              case when new.maturity_date is not null
                   then ' (maturity ' || new.maturity_date || ')' else '' end,
              'bills', new.id, auth.uid());
    end if;
  end if;
  return new;
end; $$;
create trigger trg_bill_status_event after update on bills
  for each row execute function bill_status_event();

-- ===================== 4. LC DOCUMENT STORE =========================
create table lc_documents (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  lc_id         uuid references lcs(id) on delete set null,
  doc_type      text not null default 'lc',   -- lc | amendment | bill | other
  original_name text not null,
  file_path     text not null,                -- storage object path
  extracted     jsonb not null default '{}'::jsonb,  -- fields pulled from the PDF
  source        text not null default 'upload',      -- upload | email (future)
  uploaded_by   uuid references auth.users(id),
  created_at    timestamptz not null default now()
);
alter table lc_documents enable row level security;
create policy lc_documents_read on lc_documents for select to authenticated
  using (is_member(company_id));
create policy lc_documents_write on lc_documents for all to authenticated
  using (can_write_company(company_id)) with check (can_write_company(company_id));

insert into storage.buckets (id, name, public)
values ('lc-docs', 'lc-docs', false)
on conflict (id) do nothing;

create policy "lc-docs read" on storage.objects for select to authenticated
  using (bucket_id = 'lc-docs');
create policy "lc-docs write" on storage.objects for insert to authenticated
  with check (bucket_id = 'lc-docs');

-- ================ 5. TIME-BASED ALERTS (computed live) ==============
create view v_lc_alerts with (security_invoker = true) as
  select b.company_id, b.lc_id, l.lc_no, b.id as bill_id, b.bill_no,
         'maturity_soon' as alert_type,
         b.maturity_date, (b.maturity_date - current_date) as days
    from bills b join lcs l on l.id = b.lc_id
   where b.status in ('accepted','discounted')
     and b.maturity_date between current_date and current_date + 7
  union all
  select b.company_id, b.lc_id, l.lc_no, b.id, b.bill_no,
         'overdue', b.maturity_date, (b.maturity_date - current_date)
    from bills b join lcs l on l.id = b.lc_id
   where b.status in ('accepted','discounted','overdue')
     and b.maturity_date < current_date
  union all
  select e.company_id, e.lc_id, l.lc_no, null, null,
         'discrepancy_open', e.event_date, null
    from lc_events e join lcs l on l.id = e.lc_id
   where e.event_type = 'discrepancy'
     and not exists (select 1 from lc_events r
                      where r.lc_id = e.lc_id
                        and r.event_type = 'discrepancy_resolved'
                        and r.created_at > e.created_at);

-- Flag bills past maturity as overdue (idempotent; call from the UI on
-- load — replace with pg_cron when hosted).
create or replace function flag_overdue_bills(p_company uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  if auth.uid() is not null and not coalesce(is_member(p_company), false) then
    raise exception 'Not a member of this company';
  end if;
  update bills set status = 'overdue'
   where company_id = p_company
     and status in ('accepted','discounted')
     and maturity_date < current_date;
  get diagnostics v_count = row_count;
  return v_count;
end; $$;
revoke execute on function flag_overdue_bills(uuid) from anon;

-- ================== 6. CONTRACT P&L + CLOSE-OUT =====================
create view lc_profitability with (security_invoker = true) as
  select
    l.id as lc_id, l.company_id, l.lc_no, l.status,
    coalesce(inv.revenue, 0)                                   as revenue,
    coalesce(cn.returns, 0)                                    as returns,
    coalesce(inv.cogs, 0) - coalesce(cn.scrap_recovery, 0)     as cogs_net,
    coalesce(fees.amend_fees, 0)                               as bank_fees,
    coalesce(fin.interest, 0)                                  as interest,
    coalesce(inv.revenue, 0) - coalesce(cn.returns, 0)
      - (coalesce(inv.cogs, 0) - coalesce(cn.scrap_recovery, 0))
      - coalesce(fees.amend_fees, 0) - coalesce(fin.interest, 0) as contract_profit
  from lcs l
  left join (select lc_id, sum(total) as revenue, sum(cogs_total) as cogs
               from invoices where lc_id is not null group by lc_id) inv
    on inv.lc_id = l.id
  left join (select i.lc_id,
                    sum(c.qty * c.unit_price)       as returns,
                    sum(c.qty * c.scrap_unit_value) as scrap_recovery
               from credit_notes c join invoices i on i.id = c.invoice_id
              where i.lc_id is not null group by i.lc_id) cn
    on cn.lc_id = l.id
  left join (select lc_id, sum(bank_fee) as amend_fees
               from lc_amendments group by lc_id) fees
    on fees.lc_id = l.id
  left join (select b.lc_id, sum(d.interest_paid) as interest
               from lbpd_disbursements d join bills b on b.id = d.bill_id
              group by b.lc_id) fin
    on fin.lc_id = l.id;

-- Close the contract: only when nothing is still outstanding.
create or replace function close_lc(p_lc_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_lc lcs;
  v_open int;
begin
  select * into v_lc from lcs where id = p_lc_id for update;
  if not found then raise exception 'LC not found'; end if;
  if v_lc.status <> 'active' then raise exception 'LC is not active'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_lc.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  select count(*) into v_open from bills
   where lc_id = p_lc_id and status not in ('realized');
  if v_open > 0 then
    raise exception '% bill(s) not yet realized — settle them before close-out', v_open;
  end if;
  if exists (select 1 from delivery_challans
              where lc_id = p_lc_id and status in ('draft','issued','delivered_unbilled')) then
    raise exception 'Open challans remain against this LC';
  end if;

  update lcs set status = 'closed' where id = p_lc_id;
  insert into lc_events (company_id, lc_id, event_type, detail, created_by)
  values (v_lc.company_id, p_lc_id, 'closed',
          (select 'Closed with contract profit ৳' || round(contract_profit, 2)
             from lc_profitability where lc_id = p_lc_id), auth.uid());
end; $$;
revoke execute on function close_lc(uuid) from anon;
