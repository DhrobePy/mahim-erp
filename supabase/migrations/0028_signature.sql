-- Authorized-signatory support for print letterheads: an uploaded e-signature
-- image plus the name/designation printed beneath it, reusing the existing
-- public "company-assets" storage bucket (same one logo_path already uses —
-- see 0012_company_admin.sql) so no new bucket/policy is needed.
alter table companies
  add column if not exists signature_path text,
  add column if not exists signatory_name text,
  add column if not exists signatory_designation text;
