-- "Bills Received Date" on the local-LC/LBPD tracker dashboard: the date the
-- issuing/negotiating bank confirms final receipt and settles the remaining
-- balance into our bank account. This is distinct from
-- lbpd_disbursements.settled_at (which only exists when the bill was
-- discounted via LBPD) — bills with no LBPD still mature and get paid
-- directly. Kept as a plain manually-entered date, not derived from any
-- existing status transition, per how the user actually tracks it today.
alter table bills add column if not exists received_at date;
