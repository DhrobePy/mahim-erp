-- Bug fix: soft_delete_record()/restore_record() flip a document's own
-- status column (e.g. sales_documents.status, of type sales_doc_status)
-- via `execute format(...) using <text value>`. A bound parameter keeps
-- its source type (text, since recycle_bin_config.cancelled_value and
-- pre_delete_status are both text columns) — Postgres only auto-coerces
-- an *unknown-type literal* to an enum target, not an already-typed text
-- parameter, so this raised "column status is of type X but expression
-- is of type text" on every has_status=true table: grns, production_orders,
-- sales_orders, delivery_challans, lcs, sales_documents. Fix: inline the
-- value as a properly-escaped literal (%L) into the executed SQL text
-- instead of binding it, so ordinary literal-to-enum coercion applies.
-- (%L is safe here — the values come from our own trusted config/audit
-- columns, never directly from client input.)
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

  if v_cfg.custom_cancel_fn is not null then
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

  if v_cfg.is_ledger_doc then
    perform reverse_ledger_effects(p_table, p_id, 'Restored from recycle bin');
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
