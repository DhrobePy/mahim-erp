-- ============================================================================
-- Migration 0017 — generalize the LC register to cover all three trade
-- scenarios Mahim can be party to, not just the back-to-back local export
-- flow it was originally built around:
--   export_local  — back-to-back / deemed export (existing flow, unchanged)
--   export_direct — Mahim as beneficiary on a genuine foreign export LC
--   import        — Mahim as applicant on a foreign import LC
-- Additive/renaming only — no existing row's meaning changes. Money
-- movement for export_direct/import still goes through the manual journal
-- screen for now; this migration is register + document + clause scope.
-- ============================================================================

create type lc_role as enum ('export_local', 'export_direct', 'import');

alter table lcs add column if not exists lc_role lc_role not null default 'export_local';

-- buyer_party_id was always "the other party" in spirit — just named for
-- the one direction that existed. Rename, keep the FK/index/data intact.
alter table lcs rename column buyer_party_id to counterparty_party_id;

-- Foreign-trade fields that export_local never needed (ports, shipment
-- terms) — LC-level, not versioned like amount/expiry, matching how
-- lc_type/usance_days already sit directly on lcs rather than lc_amendments.
alter table lcs add column if not exists incoterm text;                 -- e.g. CFR, FOB, CIF, EXW
alter table lcs add column if not exists port_of_loading text;
alter table lcs add column if not exists port_of_discharge text;
alter table lcs add column if not exists latest_shipment_date date;
alter table lcs add column if not exists presentation_period_days int;  -- field 48
alter table lcs add column if not exists available_with_by text;       -- field 41D, reference text

-- Foreign-counterparty awareness on parties — needed to tell a domestic
-- buyer/supplier apart from a foreign one (currency defaulting, foreign
-- clause set, country-of-origin certificates etc.). Informational, not a
-- hard gate: the counterparty picker still filters on is_customer/
-- is_supplier as before, this just adds context.
alter table parties add column if not exists is_foreign boolean not null default false;
alter table parties add column if not exists country text;

comment on column lcs.lc_role is
  'export_local = back-to-back/deemed export (original flow); export_direct = genuine foreign export, Mahim beneficiary; import = foreign import LC, Mahim applicant';
comment on column lcs.counterparty_party_id is
  'Buyer for export_local/export_direct roles, supplier for import role';
