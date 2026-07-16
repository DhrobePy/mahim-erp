-- =====================================================================
-- Mahim Packaging ERP — 0009_print_clauses
-- Lets a user pick which standard LC/trade clauses print on a document,
-- and remembers the choice per document. The clause library itself is
-- static client-side content (composables/useLcClauses.ts) — only the
-- selected keys are persisted here.
-- =====================================================================

alter table invoices
  add column if not exists print_clauses jsonb not null default '[]'::jsonb;

alter table delivery_challans
  add column if not exists print_clauses jsonb not null default '[]'::jsonb;
