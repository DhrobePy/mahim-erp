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
deploys to cPanel as a **static SPA**. The repo already keeps a built copy at
`cpanel-deploy/` committed to git, so most of the time deploying is just
"pull the repo, point the domain at `cpanel-deploy/`" — see the update
workflow at the bottom. The steps below are the **first-time setup**.

> **Before you do anything else:** whatever is currently committed in
> `cpanel-deploy/` was built against the **local dev** Supabase instance
> (`http://127.0.0.1:54321`) — that URL and anon key are baked directly into
> every prerendered HTML page (Nuxt inlines `runtimeConfig.public` at build
> time; there is no server to read `.env` from at request time). Uploading
> it as-is means every visitor's browser tries to reach `127.0.0.1` and the
> site will look "logged out" / show zero data everywhere, with no obvious
> error. You **must** rebuild against a production Supabase project (step 4)
> before the first real deploy.

### 1. Create the production Supabase project

At [supabase.com](https://supabase.com) → New project. Pick a region close
to Bangladesh (Singapore is usually lowest latency). Save the generated DB
password somewhere safe — you won't need it day-to-day, but you will if you
ever connect a SQL client directly.

This is a **separate, empty database** from your local dev stack — none of
your local data/companies/users carry over automatically.

### 2. Apply the schema

In the Supabase dashboard → **SQL Editor**, run every file in
`supabase/migrations/` **in exact numeric order** (0001 → 0016 as of this
writing — check `ls supabase/migrations` for the current last number, this
list grows over time), then `supabase/seed.sql` last. Paste one file at a
time and run it — don't concatenate them, some migrations reference
functions/types created in the previous one and Postgres needs them to
already exist.

Prefer the CLI over copy-paste? `supabase link --project-ref <ref>` then
`supabase db push` applies every migration file in order automatically —
equivalent result, less clicking.

`seed.sql` inserts real reference data you'll want in production (UOMs,
warehouses, cost centers, the `production_order` numbering series) plus a
handful of **illustrative** items (`RM-BOARD-250`, `FG-CARTON-A`, etc.) —
rename or delete those once you've entered your actual item catalog; they're
placeholders, not required data.

Confirm it worked: **Table Editor** should show `companies` with one row
(the mother company, fixed id `00000000-0000-0000-0000-000000000001`), and
**Storage** should show two buckets already created by the migrations —
`company-assets` (public, for logos) and `lc-docs` (private, for LC PDFs).

### 3. Configure Auth

**Authentication → URL Configuration**: set **Site URL** to your real
production domain (e.g. `https://erp.mahimpackaging.com`) and add it to
**Redirect URLs** too — Supabase rejects auth callbacks to unlisted URLs.

**Authentication → Providers → Email**: decide on "Confirm email". Local
dev usually turns this **off** for convenience; for production, leaving it
**on** is the safer default so account creation requires a real inbox. Since
this ERP doesn't have public sign-up flows in practice (you'll create
accounts for known staff), either setting is defensible — just make the
choice deliberately rather than by accident.

### 4. Point the build at production and regenerate

```bash
cp .env .env.local.bak          # keep your local dev credentials safe
```

Edit `.env` (or make a fresh copy from `.env.example`) with the
**production** project's values from Project Settings → API:

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_KEY=<production anon public key>
```

Then rebuild:

```bash
rm -rf .nuxt .output
npx nuxi generate
rm -rf cpanel-deploy
cp -R .output/public cpanel-deploy
```

**Sanity-check before deploying** — this should print nothing:

```bash
grep -r "127.0.0.1" cpanel-deploy/index.html
```

If it prints the local URL, the build picked up the wrong `.env` — fix that
before continuing, don't deploy it.

Once confirmed, restore your local dev `.env` for day-to-day development:

```bash
cp .env.local.bak .env
```

### 5. Ship it to cPanel

Two ways to get `cpanel-deploy/` onto the server — pick one:

**A. Git Version Control (recommended)** — cPanel → *Git Version Control* →
*Create* → paste `https://github.com/DhrobePy/mahim-erp.git`, set the
repository path to something outside `public_html` (e.g.
`~/repos/mahim-erp`), branch `main`. After cloning, use cPanel's *File
Manager* (or a symlink) to point your domain's document root at
`~/repos/mahim-erp/cpanel-deploy` — or set the Git repo's deployment path
directly to your `public_html`/subdomain folder if the host's Git feature
supports it. Future updates are then `git pull` (via the Git UI's "Manage"
→ "Pull" or SSH if available), no re-upload needed.

**B. File Manager / FTP upload** — zip the **contents** of `cpanel-deploy/`
(not the folder itself — you want `index.html` etc. at the top level of the
zip) and upload+extract into `public_html/` (or a subdomain's document
root) via File Manager's Upload + Extract, or any FTP client.

Either way: the domain's document root must point at the folder containing
`index.html`, not at the repo root — `cpanel-deploy/` is the deployable
artifact, the rest of the repo (source, migrations) has no business being
web-accessible.

### 6. SPA routing — add `.htaccess`

Most pages were prerendered as their own `index.html` (e.g. `/accounting/pnl/`
resolves naturally), but pages with a dynamic id in the URL — `/hr/<uuid>`,
`/print/payslip/<uuid>`, `/lcs/<uuid>`, etc. — have no matching file on disk
and need a fallback so a hard refresh or direct link doesn't 404. Add this
`.htaccess` next to `index.html` in the deployed folder:

```apache
DirectoryIndex index.html
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /
  RewriteCond %{REQUEST_FILENAME} !-f
  RewriteCond %{REQUEST_FILENAME} !-d
  RewriteRule ^ /200.html [L]
</IfModule>
```

`200.html` is the same app shell as `index.html` — Nuxt's convention for
"serve this with a 200 status and let the client-side router figure out
what page it is," which is what a dynamic id route needs.

### 7. Domain + SSL

If deploying to a subdomain (recommended, e.g. `erp.yourdomain.com`), create
it under cPanel → *Domains* first, pointing at the folder from step 5. Then
cPanel → *SSL/TLS Status* → run **AutoSSL** (or issue Let's Encrypt manually
if AutoSSL isn't enabled) so the site serves over HTTPS — Supabase's auth
cookies are set `secure`, so the app won't authenticate correctly over plain
HTTP.

### 8. Bootstrap your first admin user

Visit the deployed site → **Sign up** with your real email. Then in the
production Supabase **SQL Editor**:

```sql
insert into company_members (user_id, company_id, role)
select id, '00000000-0000-0000-0000-000000000001', 'admin'
from auth.users where email = 'you@company.com';
```

Sign out and back in to pick up the membership — new signups have **no**
company membership by default and see no data until one is granted, exactly
like local dev.

### 9. Post-deploy smoke test

- Log in, confirm the sidebar and dashboard load with real (empty) data, not
  a blank/frozen screen (that symptom means step 4's rebuild didn't happen
  or picked up the wrong `.env`).
- Create one real record in a couple of modules (an item, a party) to
  confirm writes work — this exercises RLS end-to-end, not just reads.
- Open a print page (e.g. any `/print/...` route) to confirm the company
  logo/letterhead renders — this confirms the `company-assets` storage
  bucket and its public URL are reachable from the internet, not just from
  your machine.
- Hard-refresh a dynamic-id page (e.g. an employee detail page) to confirm
  step 6's `.htaccess` fallback is actually working.

### Updating an existing deployment

For ordinary code changes (no new migration): repeat step 4 (rebuild with
production `.env`) and step 5 (redeploy — `git pull` if using Git Version
Control, or re-upload if using File Manager). For changes that include a new
migration file: apply the new migration in the production SQL Editor first
(same as step 2, just the one new file), *then* rebuild and redeploy — the
frontend and schema should never drift apart for more than the few minutes
it takes to do both.
