-- Local export LCs can be opened in a foreign currency (e.g. USD), but
-- LBPD principal and the final settlement are always actual BDT cash
-- figures from the bank's own advice — not something this app computes
-- via an exchange rate. Add:
--   - bills.fx_rate: reference rate for displaying the LC/bill face value's
--     BDT-equivalent (estimate only, never used for LBPD/settlement math)
--   - bills.received_amount_bdt: the real BDT amount credited at final
--     settlement, alongside the existing received_at date
alter table bills add column if not exists fx_rate numeric;
alter table bills add column if not exists received_amount_bdt numeric;
