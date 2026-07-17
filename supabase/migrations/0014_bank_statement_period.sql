-- =====================================================================
-- Mahim Packaging ERP — 0014_bank_statement_period
-- Bank statement requests need an explicit date range, not the generic
-- tenor_or_period text meant for FDR/DPS. Dedicated columns so the
-- period is structured data (sortable, validatable), not buried in text.
-- =====================================================================

alter table bank_service_requests
  add column if not exists statement_period_from date,
  add column if not exists statement_period_to   date,
  add constraint bank_service_requests_period_chk
    check (statement_period_from is null or statement_period_to is null
           or statement_period_from <= statement_period_to);
