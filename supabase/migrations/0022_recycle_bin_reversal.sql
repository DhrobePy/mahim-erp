-- =====================================================================
-- Mahim Packaging ERP — 0022_recycle_bin_reversal
-- System-wide "delete": for master/reference data this is a real soft
-- delete (deleted_at/deleted_by, hidden from pickers, restorable). For
-- anything that has already posted to the GL (journals) or stock ledger
-- (stock_movements) — both of which are deliberately append-only, see
-- 0003_gl_core.sql — a "delete" can never be a row mutation. It has to
-- be a reversing entry, exactly like voiding a posted transaction in
-- any real accounting system. Restoring un-reverses it the same way.
--
-- The reversal mechanism is fully generic: every posting function
-- already tags its journal/stock rows with (ref_table, ref_id) pointing
-- back to the source document. So reversing "whatever GL/stock effects
-- this document caused" needs no per-document bespoke logic — it just
-- walks journals/stock_movements by ref and mirrors them (debit<->credit,
-- quantity negated), chained via a self-referencing reversal_of column.
-- Toggling delete/restore is the same operation both times: reverse
-- whatever in the chain is currently the active (unreversed) tip.
--
-- recycle_bin_config is a data-driven catalog (same pattern as
-- permission_modules) — enabling a new table means adding a config row,
-- not writing new code.
-- =====================================================================

-- ==================== REVERSAL CHAIN COLUMNS ==========================
alter table journals        add column if not exists reversal_of uuid references journals(id);
alter table stock_movements add column if not exists reversal_of uuid references stock_movements(id);
create index if not exists idx_journals_reversal_of on journals(reversal_of);
create index if not exists idx_sm_reversal_of on stock_movements(reversal_of);

-- ==================== RECYCLE BIN CONFIG ===============================
create table recycle_bin_config (
  table_name       text primary key,
  display_column   text not null default 'name',
  module_key       text not null references permission_modules(key),
  is_ledger_doc    boolean not null default false,  -- reverse journals/stock on delete
  has_status       boolean not null default false,  -- flip a status column
  status_column    text not null default 'status',
  cancelled_value  text not null default 'cancelled',
  custom_cancel_fn text,                             -- e.g. 'cancel_purchase_order' — reuse existing guarded RPC instead of a blind status flip
  sort_order       int not null default 100
);
alter table recycle_bin_config enable row level security;
create policy recycle_bin_config_read on recycle_bin_config for select to authenticated using (true);

insert into recycle_bin_config (table_name, display_column, module_key, is_ledger_doc, has_status, custom_cancel_fn, sort_order) values
  -- master / reference data — simple soft delete, no ledger effect
  ('parties',                'name',        'parties',       false, false, null, 10),
  ('items',                  'name',        'items',         false, false, null, 11),
  ('warehouses',             'name',        'items',         false, false, null, 12),
  ('uoms',                   'name',        'items',         false, false, null, 13),
  ('item_categories',        'name',        'items',         false, false, null, 14),
  ('accounts',               'name',        'accounting',    false, false, null, 15),
  ('cost_centers',           'name',        'accounting',    false, false, null, 16),
  ('boms',                   'name',        'boms',          false, false, null, 17),
  ('carton_specs',           'id',          'boms',          false, false, null, 18),
  ('carton_recipe_templates','name',        'boms',          false, false, null, 19),
  ('employees',              'full_name',   'hr',            false, false, null, 20),
  ('attendance',             'id',          'attendance',    false, false, null, 21),
  ('employee_assistance',    'request_no',  'hr',            false, false, null, 22),
  ('bank_facilities',        'name',        'banking',       false, false, null, 23),
  ('cash_bank_accounts',     'name',        'bank_accounts', true,  false, null, 24),
  ('credit_notes',           'cn_no',       'invoices',      false, false, null, 25),
  ('debit_notes',            'dn_no',       'procurement',   false, false, null, 26),
  ('gate_entries',           'gate_no',     'procurement',   false, false, null, 27),
  ('board_resolutions',      'resolution_no','resolutions',  false, false, null, 28),
  ('bank_branches',          'branch_name', 'bank_requests', false, false, null, 29),
  ('bank_service_requests',  'request_no',  'bank_requests', false, false, null, 30),
  ('company_directors',      'full_name',   'directors',     false, false, null, 31),
  ('company_documents',      'title',       'documents',     false, false, null, 32),
  ('legal_reviews',          'id',          'documents',     false, false, null, 33),
  ('forwarding_letters',     'subject',     'forwarding',    false, false, null, 34),
  ('company_tax_computations','id',         'tax_corporate', false, false, null, 35),
  ('lc_documents',           'doc_type',    'lcs',           false, false, null, 36),
  -- ledger-touching documents — reverse GL/stock effects on delete
  ('grns',                   'grn_no',      'procurement',   true,  true,  null, 50),
  ('purchase_orders',        'po_no',       'purchase_orders', false, true, 'cancel_purchase_order', 51),
  ('production_orders',      'order_no',    'production',    true,  true,  null, 52),
  ('sales_orders',           'so_no',       'sales_orders',  false, true,  null, 53),
  ('delivery_challans',      'challan_no',  'challans',      true,  true,  null, 54),
  ('invoices',               'invoice_no',  'invoices',      true,  false, null, 55),
  ('lcs',                    'lc_no',       'lcs',           false, true,  null, 56),
  ('lc_amendments',          'id',          'lcs',           true,  false, null, 57),
  ('sales_documents',        'doc_no',      'quotations',    false, true,  null, 58),
  ('bills',                  'bill_no',     'banking',       true,  false, null, 59),
  ('lbpd_disbursements',     'id',          'banking',       true,  false, null, 60),
  ('employee_loans',         'loan_no',     'hr',            true,  false, null, 61),
  ('employee_acr',           'id',          'hr',            true,  false, null, 62),
  ('stationery_receipts',    'receipt_no',  'stationery',    true,  false, null, 63),
  ('stationery_issues',      'issue_no',    'stationery',    true,  false, null, 64),
  ('payroll_runs',           'run_no',      'payroll',       true,  false, null, 65),
  ('cash_sales',             'sale_no',     'cash_sales',    true,  false, null, 66),
  ('account_transfers',      'transfer_no', 'transfers',     true,  false, null, 67),
  ('bank_charge_entries',    'entry_no',    'bank_charges',  true,  false, null, 68)
on conflict (table_name) do nothing;

-- ==================== deleted_at / deleted_by / pre_delete_status ======
do $$
declare t record;
begin
  for t in select table_name from recycle_bin_config loop
    execute format('alter table %I add column if not exists deleted_at timestamptz', t.table_name);
    execute format('alter table %I add column if not exists deleted_by uuid references auth.users(id)', t.table_name);
    execute format('alter table %I add column if not exists pre_delete_status text', t.table_name);
    execute format('create index if not exists idx_%s_deleted_at on %I(deleted_at) where deleted_at is not null', t.table_name, t.table_name);
  end loop;
end $$;

-- ==================== GENERIC LEDGER REVERSAL ==========================
-- Finds the current "active tip" of the reversal chain for this document
-- (a journal/stock row with this ref that nothing has reversed yet) and
-- posts a mirror-image entry against it. Calling this twice on the same
-- document reverses, then un-reverses (restores), by construction.
create or replace function reverse_ledger_effects(p_ref_table text, p_ref_id uuid, p_memo text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_journal   journals;
  v_line      record;
  v_new_lines jsonb;
  v_sm        record;
begin
  for v_journal in
    select j.* from journals j
     where j.ref_table = p_ref_table and j.ref_id = p_ref_id
       and not exists (select 1 from journals r where r.reversal_of = j.id)
  loop
    v_new_lines := '[]'::jsonb;
    for v_line in select * from journal_lines where journal_id = v_journal.id loop
      v_new_lines := v_new_lines || jsonb_build_array(jsonb_build_object(
        'account', (select code from accounts where id = v_line.account_id),
        'debit', v_line.credit, 'credit', v_line.debit,
        'party_id', v_line.party_id, 'cost_center_id', v_line.cost_center_id,
        'note', coalesce(v_line.note, '') || ' (' || p_memo || ')'
      ));
    end loop;
    insert into journals (company_id, journal_no, journal_date, memo, ref_table, ref_id, created_by, reversal_of)
    values (v_journal.company_id, next_document_number(v_journal.company_id, 'journal', 'JV'),
            current_date, p_memo || ' — reversal of ' || v_journal.journal_no, p_ref_table, p_ref_id, auth.uid(), v_journal.id)
    returning id into v_journal.id; -- reuse var; new journal's id
    -- insert lines directly (mirrors post_journal's own logic, but must
    -- set reversal linkage on the journals row above, which post_journal
    -- itself does not support, so we can't call it here as-is)
    for v_line in select * from jsonb_array_elements(v_new_lines) loop
      insert into journal_lines (journal_id, company_id, account_id, debit, credit, party_id, cost_center_id, note)
      values (v_journal.id, v_journal.company_id,
              account_id(v_journal.company_id, v_line.value->>'account'),
              coalesce((v_line.value->>'debit')::numeric, 0),
              coalesce((v_line.value->>'credit')::numeric, 0),
              nullif(v_line.value->>'party_id','')::uuid,
              nullif(v_line.value->>'cost_center_id','')::uuid,
              v_line.value->>'note');
    end loop;
  end loop;

  for v_sm in
    select sm.* from stock_movements sm
     where sm.ref_table = p_ref_table and sm.ref_id = p_ref_id
       and not exists (select 1 from stock_movements r where r.reversal_of = sm.id)
  loop
    insert into stock_movements (company_id, item_id, warehouse_id, movement_type, quantity, unit_cost,
                                 batch_id, ref_table, ref_id, ref_no, created_by, note, reversal_of)
    values (v_sm.company_id, v_sm.item_id, v_sm.warehouse_id, v_sm.movement_type, -v_sm.quantity, v_sm.unit_cost,
            v_sm.batch_id, p_ref_table, p_ref_id, coalesce(v_sm.ref_no,'') || '-REV', p_memo, v_sm.id);
  end loop;
end; $$;
revoke execute on function reverse_ledger_effects(text, uuid, text) from anon;

-- ==================== GENERIC SOFT DELETE / RESTORE ====================
create or replace function soft_delete_record(p_table text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cfg     recycle_bin_config;
  v_company uuid;
  v_status  text;
begin
  select * into v_cfg from recycle_bin_config where table_name = p_table;
  if not found then raise exception 'Table % is not recycle-bin enabled', p_table; end if;

  execute format('select company_id from %I where id = $1', p_table) into v_company using p_id;
  if v_company is null then raise exception 'Record not found in %', p_table; end if;
  if not coalesce(has_permission(v_company, v_cfg.module_key, 'write'), false) then
    raise exception 'Not permitted to delete records in %', p_table;
  end if;

  -- capture pre-delete status unconditionally (before any status change,
  -- whether that change comes from the generic path below or from a
  -- custom_cancel_fn), so restore_record always has something to revert to
  if v_cfg.has_status then
    execute format('select %I from %I where id = $1', v_cfg.status_column, p_table) into v_status using p_id;
    execute format('update %I set pre_delete_status = $1 where id = $2', p_table) using v_status, p_id;
  end if;

  if v_cfg.custom_cancel_fn is not null then
    execute format('select %I($1)', v_cfg.custom_cancel_fn) using p_id;
  else
    if v_cfg.is_ledger_doc then
      perform reverse_ledger_effects(p_table, p_id, 'Deleted via recycle bin');
    end if;
    if v_cfg.has_status then
      execute format('update %I set %I = $1 where id = $2', p_table, v_cfg.status_column)
        using v_cfg.cancelled_value, p_id;
    end if;
  end if;

  execute format('update %I set deleted_at = now(), deleted_by = $1 where id = $2', p_table)
    using auth.uid(), p_id;
end; $$;
revoke execute on function soft_delete_record(text, uuid) from anon;

create or replace function restore_record(p_table text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_cfg     recycle_bin_config;
  v_company uuid;
  v_prev    text;
begin
  select * into v_cfg from recycle_bin_config where table_name = p_table;
  if not found then raise exception 'Table % is not recycle-bin enabled', p_table; end if;

  execute format('select company_id from %I where id = $1', p_table) into v_company using p_id;
  if v_company is null then raise exception 'Record not found in %', p_table; end if;
  if not coalesce(has_permission(v_company, v_cfg.module_key, 'write'), false) then
    raise exception 'Not permitted to restore records in %', p_table;
  end if;

  if v_cfg.is_ledger_doc then
    perform reverse_ledger_effects(p_table, p_id, 'Restored from recycle bin');
  end if;
  if v_cfg.has_status then
    execute format('select pre_delete_status from %I where id = $1', p_table) into v_prev using p_id;
    if v_prev is not null then
      execute format('update %I set %I = $1 where id = $2', p_table, v_cfg.status_column) using v_prev, p_id;
    end if;
  end if;

  execute format('update %I set deleted_at = null, deleted_by = null, pre_delete_status = null where id = $1', p_table)
    using p_id;
end; $$;
revoke execute on function restore_record(text, uuid) from anon;

-- ==================== RECYCLE BIN LISTING ==============================
create or replace function list_deleted_records(p_company uuid) returns table (
  table_name text, record_id uuid, display_label text, module_key text,
  deleted_at timestamptz, deleted_by_name text
) language plpgsql security definer set search_path = public as $$
declare t recycle_bin_config;
begin
  for t in select * from recycle_bin_config order by sort_order loop
    if has_module_view(p_company, t.module_key) then
      return query execute format(
        'select %L::text, x.id, coalesce(x.%I::text, x.id::text), %L::text, x.deleted_at,
                coalesce(p.full_name, p.email, ''—'')
           from %I x left join profiles p on p.id = x.deleted_by
          where x.deleted_at is not null and x.company_id = $1',
        t.table_name, t.display_column, t.module_key, t.table_name
      ) using p_company;
    end if;
  end loop;
end; $$;
revoke execute on function list_deleted_records(uuid) from anon;

-- ==================== AUDIT TRIGGER — extend to all configured tables ==
do $$
declare t record;
begin
  for t in select table_name from recycle_bin_config loop
    execute format(
      'drop trigger if exists trg_audit_%s on %I;
       create trigger trg_audit_%s after insert or update or delete on %I
         for each row execute function audit_row_change();',
      t.table_name, t.table_name, t.table_name, t.table_name
    );
  end loop;
end $$;
