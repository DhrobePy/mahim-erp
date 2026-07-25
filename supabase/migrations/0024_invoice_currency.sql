-- Invoices never carried their own currency — the print sheet hardcoded
-- ৳/Taka everywhere regardless of whether the invoice sits under a
-- foreign (USD/EUR) export LC. sales_documents already had a currency
-- column (0011); invoices didn't, so it silently fell back to BDT
-- symbols on genuinely foreign-currency trade documents.
alter table invoices add column if not exists currency text not null default 'BDT';

create or replace function create_invoice_from_challan(
  p_challan_id uuid, p_invoice_date date default current_date
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_ch      delivery_challans;
  v_so      sales_orders;
  v_line    record;
  v_inv_id  uuid;
  v_total   numeric := 0;
  v_cogs    numeric := 0;
  v_ar      text;
  v_rev     text;
  v_deemed  boolean := true;
  v_currency text := 'BDT';
begin
  select * into v_ch from delivery_challans where id = p_challan_id for update;
  if not found then raise exception 'Challan not found'; end if;
  if not (v_ch.challan_kind in ('standard','covering') and v_ch.status = 'issued') then
    raise exception 'Challan must be an issued standard or covering challan (got % / %)',
      v_ch.challan_kind, v_ch.status;
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_ch.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  if v_ch.so_id is not null then
    select * into v_so from sales_orders where id = v_ch.so_id;
    v_deemed := coalesce(v_so.is_deemed_export, true);
  end if;

  if v_ch.lc_id is not null then
    select currency into v_currency from lcs where id = v_ch.lc_id;
    v_currency := coalesce(v_currency, 'BDT');
  end if;

  insert into invoices (company_id, invoice_no, customer_party_id, challan_id, so_id,
                        lc_id, invoice_date, is_deemed_export, currency, created_by)
  values (v_ch.company_id,
          next_document_number(v_ch.company_id, 'invoice', 'INV'),
          v_ch.customer_party_id, v_ch.id, v_ch.so_id, v_ch.lc_id,
          coalesce(p_invoice_date, current_date), v_deemed, v_currency, auth.uid())
  returning id into v_inv_id;

  for v_line in
    select dcl.*, i.standard_cost from delivery_challan_lines dcl
    join items i on i.id = dcl.item_id where dcl.challan_id = p_challan_id
  loop
    insert into invoice_lines (invoice_id, company_id, item_id, qty, unit_price)
    values (v_inv_id, v_ch.company_id, v_line.item_id, v_line.qty, v_line.unit_price);
    v_total := v_total + v_line.qty * v_line.unit_price;
    v_cogs  := v_cogs  + v_line.qty * coalesce(v_line.standard_cost, 0);
  end loop;
  if v_total <= 0 then raise exception 'Invoice has no value'; end if;

  v_ar  := case when v_ch.lc_id is not null then '1210' else '1200' end;
  v_rev := case when v_deemed then '4100' else '4200' end;

  -- Note: GL posting still books v_total at face value regardless of
  -- currency (no FX conversion to BDT here) — unchanged from before this
  -- migration. Fixing that is a separate, larger multi-currency GL task;
  -- this migration only fixes the currency LABEL shown on documents.
  perform post_journal(v_ch.company_id, coalesce(p_invoice_date, current_date),
    'Invoice for challan ' || v_ch.challan_no ||
      case v_ch.challan_kind when 'covering' then ' (covering set, clears GDNI)' else '' end,
    'invoices', v_inv_id,
    jsonb_build_array(
      jsonb_build_object('account', v_ar, 'debit', round(v_total,2),
                         'party_id', v_ch.customer_party_id::text),
      jsonb_build_object('account', v_rev, 'credit', round(v_total,2)),
      jsonb_build_object('account','5100','debit', round(v_cogs,2)),
      jsonb_build_object('account',
        case v_ch.challan_kind when 'covering' then '1220' else '1310' end,
        'credit', round(v_cogs,2))));

  update invoices set total = round(v_total,2), cogs_total = round(v_cogs,2)
   where id = v_inv_id;
  update delivery_challans set status = 'invoiced' where id = p_challan_id;

  return v_inv_id;
end; $$;
revoke execute on function create_invoice_from_challan(uuid, date) from anon;
