-- The LC / LBPD Tracker dashboard needs to let a user log a bill entry
-- directly (bank paperwork tracked by hand, not necessarily originating
-- from a sales invoice in this system). bills.invoice_id was NOT NULL
-- because the only prior entry point was create_bill(p_invoice_id) off the
-- sales pipeline — relax it so a standalone bill row can exist with
-- invoice_id = null.
alter table bills alter column invoice_id drop not null;
