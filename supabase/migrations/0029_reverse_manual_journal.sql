-- Manual journal entries (posted via post_journal with ref_table/ref_id = null)
-- have no draft window and, until now, no delete/reverse path at all — they
-- are not registered in recycle_bin_config, and reverse_ledger_effects can't
-- find them since it matches on ref_table/ref_id, which manual journals never
-- set. This adds a dedicated reversal function keyed directly by journals.id,
-- walking the existing reversal_of chain (added generically in
-- 0022_recycle_bin_reversal.sql), and wires it into the recycle bin so a
-- mistaken manual entry can at least be deleted (auto-reversed) and restored
-- (un-reversed) — not in-place edit, but a real correction path where none
-- existed before.

create or replace function reverse_manual_journal(p_journal_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_root   journals;
  v_tip    journals;
  v_line   record;
  v_new_id uuid;
begin
  select * into v_root from journals where id = p_journal_id;
  if not found then raise exception 'Journal % not found', p_journal_id; end if;
  if v_root.ref_table is not null then
    raise exception 'Journal % was posted by % — delete/restore that document instead', p_journal_id, v_root.ref_table;
  end if;

  -- walk to the current active tip of the reversal chain rooted at p_journal_id
  v_tip := v_root;
  loop
    select * into v_root from journals where reversal_of = v_tip.id;
    exit when not found;
    v_tip := v_root;
  end loop;

  insert into journals (company_id, journal_no, journal_date, memo, ref_table, ref_id, created_by, reversal_of)
  values (v_tip.company_id, next_document_number(v_tip.company_id, 'journal', 'JV'),
          current_date, coalesce(v_tip.memo, '') || ' — reversal', null, null, auth.uid(), v_tip.id)
  returning id into v_new_id;

  for v_line in select * from journal_lines where journal_id = v_tip.id loop
    insert into journal_lines (journal_id, company_id, account_id, debit, credit, party_id, cost_center_id, note)
    values (v_new_id, v_tip.company_id, v_line.account_id, v_line.credit, v_line.debit,
            v_line.party_id, v_line.cost_center_id, v_line.note);
  end loop;
end; $$;
revoke execute on function reverse_manual_journal(uuid) from anon;

-- soft_delete_record/restore_record (0026) only ever call custom_cancel_fn
-- from soft_delete_record (fine for a status flip) or is_ledger_doc's
-- hardcoded reverse_ledger_effects (ref-table based, symmetric but can't
-- find a self-keyed manual journal). Neither fits: add a new dispatch column
-- that's called symmetrically from both delete and restore.
alter table recycle_bin_config add column if not exists custom_reverse_fn text;

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

  if v_cfg.has_status then
    execute format('select %I from %I where id = $1', v_cfg.status_column, p_table) into v_status using p_id;
    execute format('update %I set pre_delete_status = $1 where id = $2', p_table) using v_status, p_id;
  end if;

  if v_cfg.custom_reverse_fn is not null then
    execute format('select %I($1)', v_cfg.custom_reverse_fn) using p_id;
  elsif v_cfg.custom_cancel_fn is not null then
    execute format('select %I($1)', v_cfg.custom_cancel_fn) using p_id;
  else
    if v_cfg.is_ledger_doc then
      perform reverse_ledger_effects(p_table, p_id, 'Deleted via recycle bin');
    end if;
    if v_cfg.has_status then
      execute format('update %I set %I = %L where id = $1', p_table, v_cfg.status_column, v_cfg.cancelled_value)
        using p_id;
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

  if v_cfg.custom_reverse_fn is not null then
    execute format('select %I($1)', v_cfg.custom_reverse_fn) using p_id;
  else
    if v_cfg.is_ledger_doc then
      perform reverse_ledger_effects(p_table, p_id, 'Restored from recycle bin');
    end if;
  end if;
  if v_cfg.has_status then
    execute format('select pre_delete_status from %I where id = $1', p_table) into v_prev using p_id;
    if v_prev is not null then
      execute format('update %I set %I = %L where id = $1', p_table, v_cfg.status_column, v_prev) using p_id;
    end if;
  end if;

  execute format('update %I set deleted_at = null, deleted_by = null, pre_delete_status = null where id = $1', p_table)
    using p_id;
end; $$;
revoke execute on function restore_record(text, uuid) from anon;

-- Give journals the standard soft-delete columns + audit trail, then register it.
alter table journals add column if not exists deleted_at timestamptz;
alter table journals add column if not exists deleted_by uuid references auth.users(id);
alter table journals add column if not exists pre_delete_status text;
create index if not exists idx_journals_deleted_at on journals(deleted_at) where deleted_at is not null;

drop trigger if exists trg_audit_journals on journals;
create trigger trg_audit_journals after insert or update or delete on journals
  for each row execute function audit_row_change();

insert into recycle_bin_config (table_name, display_column, module_key, is_ledger_doc, has_status, custom_reverse_fn, sort_order)
values ('journals', 'journal_no', 'accounting', false, false, 'reverse_manual_journal', 69)
on conflict (table_name) do nothing;
