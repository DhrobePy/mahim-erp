# Mahim Packaging ERP

A Nuxt 3 (SSR) + Supabase ERP for a packaging manufacturer selling mostly against
**Local LC**, partially cash, and using **LBPD** (Local Bill Purchase / Discount)
facilities across multiple banks.

**Modules live:**

- **Inventory + Production** — items, batches (FSC/moisture), BOMs, production orders
- **Procurement** — gate entry → QA true-net-weight GRN (moisture/tare deductions) →
  auto debit notes; posts inventory + Mushak 6.1 VAT input vs AP at accepted value only
- **Sales & Local LC** — sales orders, versioned LCs (master-child amendments),
  **dual delivery flows**: standard (LC in hand) and pre-LC originals with
  covering-document sets (marked, linked, official Mushak series, zero re-posting),
  invoices, sales returns with scrap downgrade
- **Banking / LBPD** — facilities with limits, bill submission → acceptance →
  discounting → maturity settlement, forced-PAD conversion with penalty interest
- **Accounting / GL** — chart of accounts (52-account template per company),
  immutable journals via the `post_journal` engine, trial balance, manual vouchers
- **HR & Payroll** — employees, attendance (OT ≤ 4h/day guard), employee loans
  (6×basic cap, payroll-amortised), monthly payroll (OT = basic/208×2, BLA 2006),
  tenure-prorated festival bonuses
- **LC lifecycle** — PDF intake with automatic field extraction (SWIFT MT700
  tags 20/31D/32B/39A/42C and free-form), per-LC detail page with event
  timeline (auto-fed from amendments and bill status changes), discrepancy
  tracking, maturity/overdue alerts, in-app notifications, document store,
  per-contract P&L and close-out
- **Admin** — per-company role assignment UI (RLS-enforced) and a full audit
  trail (who/when/what-changed on every business table)

## Stack

- **Frontend:** Nuxt 3 (SSR), `@nuxt/ui` (Tailwind), Pinia
- **Backend:** Supabase (Postgres, Auth, Row Level Security, RPC)

## Getting started

### Option A — fully local (Docker + Supabase CLI, no cloud account)

```bash
npm install
cp .env.example .env          # local defaults already point at the local stack
# install Docker Desktop (or Colima on macOS) and the Supabase CLI, then:
supabase start                # boots Postgres/Auth/API/Studio in containers
supabase db reset             # applies migrations 0001–0008 + seed (fresh DB only!)
npm run dev                   # → http://localhost:3000
```

Local endpoints: app `:3000`, **Supabase Studio** (table browser / SQL editor —
the phpMyAdmin equivalent) `http://127.0.0.1:54323`, API `:54321`,
Postgres `127.0.0.1:54322` (`postgres`/`postgres`).

Create your first user via the login page's **Sign up**, then grant admin in
Studio's SQL editor (see Companies & roles below). Daily start order:
Docker/Colima → `supabase start` → `npm run dev`. Apply new migrations to an
existing local DB with `supabase migration up` — **never** `db reset`, which
wipes data.

### Option B — hosted database (cloud)

### 1. Install dependencies

```bash
npm install
```

### 2. Create a Supabase project

At [supabase.com](https://supabase.com) → new project. Then in the SQL editor,
run the migrations and seed **in order**:

1. `supabase/migrations/0001_init.sql` … `0008_audit_lc_lifecycle.sql` (in numeric order)
2. `supabase/seed.sql`

### 3. Configure environment

```bash
cp .env.example .env
```

Fill in `SUPABASE_URL` and `SUPABASE_KEY` (Project Settings → API → Project URL and
anon public key).

> **Tip for development:** In Supabase → Authentication → Providers → Email, turn
> **off** "Confirm email" so sign-up works without an inbox round-trip.

### 4. Run

```bash
npm run dev
```

Open http://localhost:3000 — you'll be redirected to `/login`. Sign up, then
grant yourself a company membership (new users have **no** membership and see
no data until one is granted). In the Supabase SQL editor:

```sql
insert into company_members (user_id, company_id, role)
select id, '00000000-0000-0000-0000-000000000001', 'admin'
from auth.users where email = 'you@company.com';
```

Sign out and back in to pick up the new role.

## Companies & roles

The schema supports **multiple companies under one mother company**
(`companies.parent_company_id`). Roles are **per company** via
`company_members` — a user can be `admin` in one company and `viewer` in
another. The mother company is seeded with the fixed id
`00000000-0000-0000-0000-000000000001`; `company_id` columns currently
default to it until the UI company switcher ships.

`admin`, `manager`, `store`, `production` can write. `sales`, `accounts`,
`viewer` are read-only in the current modules. Membership and role are
enforced by Postgres RLS, not just the UI — non-members of a company see
none of its rows.

## Data model highlights

- **`stock_movements`** is the single source of truth for stock. Quantity is signed
  (+ in / − out); `current_stock` is a view that sums it per item per warehouse.
- **Completing a production order** calls the `complete_production_order` RPC, which
  posts the finished-good IN and BOM-scaled component OUT movements in one
  transaction.
- **`parties`** is the unified counterparty master (customer / supplier /
  transporter / bank flags on one record) — it replaced the earlier
  `customers`/`suppliers` stubs.
- **`document_series`** issues per-company gapless document numbers via the
  `next_document_number` RPC. Statutory series (Mushak challans/invoices) and
  internal series (pre-LC originals, production orders) are separate
  `doc_type`s so official sequences never gap.
- **`batches`** gives rolls/lots identity (`stock_movements.batch_id`,
  nullable) for FSC and moisture traceability; `cost_centers` dimension
  future COGM work.

## Project structure

```
supabase/migrations/0001_init.sql          Inventory + production schema, RPCs
supabase/migrations/0002_multi_company.sql Companies, memberships, parties,
                                           document series, cost centers, batches
supabase/migrations/0003_gl_core.sql       CoA template, journals, post_journal engine
supabase/migrations/0004_procurement.sql   Gate entry, true-net-weight GRN, debit notes
supabase/migrations/0005_sales_lc.sql      SOs, versioned LCs, dual challan flows,
                                           covering sets, invoices, sales returns
supabase/migrations/0006_banking_lbpd.sql  Facilities, bills, LBPD, forced PAD
supabase/migrations/0007_hr_payroll.sql    Employees, attendance, loans, payroll, bonus
supabase/migrations/0008_audit_lc_lifecycle.sql  Audit trail, LC events/notifications/
                                           documents/alerts, contract P&L, close-out
supabase/seed.sql                          UOMs, categories, warehouses, sample
                                           items, cost centers, series
pages/                                     One folder per module (see sidebar)
layouts/default.vue                        App shell (sidebar + header)
composables/useProfile.ts                  Memberships, active company, role
```

## Posting model

Money enters the GL only through `post_journal` (journals have no client
insert policy), called by the module RPCs: `complete_grn`, `issue_challan`,
`create_covering_set` (documentation only — posts nothing),
`create_invoice_from_challan`, `process_sales_return`, `create_bill`,
`accept_bill`, `disburse_lbpd`, `settle_lbpd`, `convert_to_forced_pad`,
`disburse_employee_loan`, `generate_payroll` → `post_payroll` → `pay_payroll`,
`generate_festival_bonus`. Stock moves only through `stock_movements`.
The pre-LC double-track guarantee: per delivery, stock moves exactly once
(original challan) and revenue posts exactly once (covering invoice, clearing
Goods-Delivered-Not-Invoiced).

## Email LC ingestion (future hook)

Reading LCs straight from a mailbox needs a server-side listener the static
frontend can't provide. The landing zone is ready: `lc_documents` with
`source = 'email'`. When wanted, add either a Supabase Edge Function fed by
an inbound-mail webhook (Mailgun/Postmark route), or — on cPanel — a cron PHP
script that polls the mailbox via IMAP and POSTs attachments to Supabase
storage + `lc_documents`. The extraction and review flow is the same one the
manual "Register from PDF" button already uses.

## Deployment (cPanel)

Production hosting target is **cPanel**. Supabase itself cannot run there —
the database stays on hosted Supabase (supabase.com); only the Nuxt app
deploys to cPanel. Two options:

1. **Static SPA (recommended):** set `ssr: false` in `nuxt.config.ts`, run
   `npx nuxi generate`, upload `.output/public/` to `public_html/`. The
   browser talks to Supabase directly; RLS is the security boundary. Add an
   `.htaccess` SPA fallback rewriting unknown paths to `index.html`.
2. **Node SSR via Passenger:** if the host offers "Setup Node.js App", point
   it at a small CommonJS launcher that imports `.output/server/index.mjs`
   (built with `npm run build`). More moving parts; only worth it if SSR is
   actually needed — for a login-gated ERP it usually isn't.
