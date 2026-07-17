-- =====================================================================
-- Mahim Packaging ERP — 0011_sales_documents
-- Pre-order paper trail: Quotation -> Proforma Invoice (PI) -> Sales
-- Contract, each convertible into the next (manual path), plus a
-- reverse auto-generation of a PI from an existing Sales Order (the
-- pre-LC reality: goods already move on a verbal deal, and the buyer
-- needs a paper PI afterward to open the LC against). Any of the three
-- can also convert straight into a real Sales Order once accepted.
-- =====================================================================

create type sales_doc_type   as enum ('quotation', 'pi', 'contract');
create type sales_doc_status as enum ('draft', 'sent', 'accepted', 'expired', 'converted', 'cancelled');

create table sales_documents (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  doc_type          sales_doc_type not null,
  doc_no            text,
  doc_date          date not null default current_date,
  valid_until       date,
  customer_party_id uuid not null references parties(id),
  so_id             uuid references sales_orders(id),        -- linked once converted to/from an order
  parent_doc_id     uuid references sales_documents(id),      -- e.g. the Quotation a PI was generated from
  status            sales_doc_status not null default 'draft',
  is_deemed_export  boolean not null default true,
  currency          text not null default 'BDT',
  payment_terms     text,
  delivery_terms    text,
  notes             text,
  print_clauses     jsonb not null default '[]'::jsonb,
  created_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (company_id, doc_no)
);
create trigger trg_sales_documents_updated before update on sales_documents
  for each row execute function set_updated_at();

-- Per-type numbering: QT-, PI-, SC-. Trigger-based like every other
-- document series in this schema (grns, challans, invoices...).
create or replace function fill_sales_doc_no() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_prefix text;
begin
  if new.doc_no is null then
    v_prefix := case new.doc_type when 'quotation' then 'QT' when 'pi' then 'PI' else 'SC' end;
    new.doc_no := next_document_number(new.company_id, 'sales_doc_' || new.doc_type::text, v_prefix);
  end if;
  return new;
end; $$;
create trigger trg_sales_doc_no before insert on sales_documents
  for each row execute function fill_sales_doc_no();

create table sales_document_lines (
  id               uuid primary key default gen_random_uuid(),
  sales_document_id uuid not null references sales_documents(id) on delete cascade,
  company_id       uuid not null
    default '00000000-0000-0000-0000-000000000001' references companies(id),
  item_id          uuid not null references items(id),
  qty              numeric not null,
  unit_price       numeric not null default 0,
  note             text
);

-- ===================== FORWARD CONVERSION ============================
-- Quotation -> PI, Quotation -> Contract, PI -> Contract. Copies header
-- + lines into a fresh document, retires the source (status=converted),
-- links parent_doc_id so the chain is traceable both ways.
create or replace function convert_sales_document(p_id uuid, p_to_type sales_doc_type)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_src  sales_documents;
  v_new_id uuid;
begin
  select * into v_src from sales_documents where id = p_id for update;
  if not found then raise exception 'Document not found'; end if;
  if v_src.status not in ('draft', 'sent', 'accepted') then
    raise exception 'Document is % — only draft/sent/accepted documents can convert', v_src.status;
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_src.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if p_to_type = v_src.doc_type then raise exception 'Already a %', p_to_type; end if;

  insert into sales_documents (company_id, doc_type, valid_until, customer_party_id, so_id,
                               parent_doc_id, is_deemed_export, currency, payment_terms,
                               delivery_terms, notes, created_by)
  values (v_src.company_id, p_to_type, current_date + 30, v_src.customer_party_id, v_src.so_id,
          v_src.id, v_src.is_deemed_export, v_src.currency, v_src.payment_terms,
          v_src.delivery_terms, v_src.notes, auth.uid())
  returning id into v_new_id;

  insert into sales_document_lines (sales_document_id, company_id, item_id, qty, unit_price, note)
  select v_new_id, company_id, item_id, qty, unit_price, note
    from sales_document_lines where sales_document_id = v_src.id;

  update sales_documents set status = 'converted' where id = v_src.id;
  return v_new_id;
end; $$;
revoke execute on function convert_sales_document(uuid, sales_doc_type) from anon;

-- =============== MANUAL PATH: DOCUMENT -> SALES ORDER =================
create or replace function sales_document_to_order(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_doc sales_documents;
  v_so_id uuid;
begin
  select * into v_doc from sales_documents where id = p_id for update;
  if not found then raise exception 'Document not found'; end if;
  if v_doc.status not in ('draft', 'sent', 'accepted') then
    raise exception 'Document is % — cannot create an order from it', v_doc.status;
  end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_doc.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;
  if v_doc.so_id is not null then raise exception 'Already linked to a sales order'; end if;
  if not exists (select 1 from sales_document_lines where sales_document_id = p_id) then
    raise exception 'Document has no lines';
  end if;

  insert into sales_orders (company_id, customer_party_id, is_deemed_export, created_by)
  values (v_doc.company_id, v_doc.customer_party_id, v_doc.is_deemed_export, auth.uid())
  returning id into v_so_id;

  insert into sales_order_lines (so_id, company_id, item_id, qty, unit_price)
  select v_so_id, company_id, item_id, qty, unit_price
    from sales_document_lines where sales_document_id = p_id;

  update sales_documents set so_id = v_so_id, status = 'converted' where id = p_id;
  return v_so_id;
end; $$;
revoke execute on function sales_document_to_order(uuid) from anon;

-- =============== AUTO PATH: SALES ORDER -> PI (reverse) ===============
-- The deal already exists (verbal / pre-LC delivery already underway);
-- the buyer needs a paper Proforma Invoice to open the LC against.
create or replace function generate_pi_from_order(p_so_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_so sales_orders;
  v_new_id uuid;
begin
  select * into v_so from sales_orders where id = p_so_id;
  if not found then raise exception 'Sales order not found'; end if;
  if auth.uid() is not null and not coalesce(can_write_company(v_so.company_id), false) then
    raise exception 'Not permitted for this company';
  end if;

  insert into sales_documents (company_id, doc_type, valid_until, customer_party_id, so_id,
                               is_deemed_export, created_by, status)
  values (v_so.company_id, 'pi', current_date + 30, v_so.customer_party_id, v_so.id,
          v_so.is_deemed_export, auth.uid(), 'sent')
  returning id into v_new_id;

  insert into sales_document_lines (sales_document_id, company_id, item_id, qty, unit_price)
  select v_new_id, company_id, item_id, qty, unit_price
    from sales_order_lines where so_id = p_so_id;

  return v_new_id;
end; $$;
revoke execute on function generate_pi_from_order(uuid) from anon;

-- ============================ RLS ===================================
do $$
declare t text;
begin
  foreach t in array array['sales_documents', 'sales_document_lines'] loop
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
