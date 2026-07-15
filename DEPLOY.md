# Deploying Mahim ERP to cPanel

The app ships as a **static SPA** — the `cpanel-deploy/` folder in this repo
is the complete, ready-to-serve build (3 MB). cPanel never runs Node, npm,
or any install step. `node_modules` (326 MB) is only needed on the machine
that *builds* the app, never on the server — that is why it is not in git.

## One-time setup

### 1. Hosted database (Supabase)

cPanel cannot run the database. Create a free project at
[supabase.com](https://supabase.com), then in its SQL editor run, in order:

1. `supabase/migrations/0001_init.sql` … `0008_audit_lc_lifecycle.sql`
2. `supabase/seed.sql`

Then create your admin user (Authentication → Add user) and grant the
membership (SQL editor):

```sql
insert into company_members (user_id, company_id, role)
select id, '00000000-0000-0000-0000-000000000001', 'admin'
from auth.users where email = 'you@company.com';
```

### 2. Production build (on your computer, not cPanel)

The Supabase URL/key are baked in at build time. The build currently in
`cpanel-deploy/` points at LOCAL Supabase — rebuild it once with your
hosted project's credentials:

```bash
# .env → your hosted project (Project Settings → API)
SUPABASE_URL=https://YOUR-PROJECT.supabase.co
SUPABASE_KEY=YOUR-ANON-PUBLIC-KEY

npx nuxi generate
rm -rf cpanel-deploy && cp -R .output/public cpanel-deploy
git add cpanel-deploy && git commit -m "Production build" && git push
```

### 3. cPanel

Either of:

- **Git Version Control** (cPanel → Git™ Version Control): clone
  `https://github.com/DhrobePy/mahim-erp.git`, then set the domain's
  document root to the repo's `cpanel-deploy/` folder
  (Domains → Manage → Document Root), or add a `.cpanel.yml` copy task.
- **Manual**: zip `cpanel-deploy/`, upload via File Manager into
  `public_html/`, extract there.

The included `.htaccess` handles SPA routing (deep links like `/ceo`
resolve to the app) and long-caches hashed assets.

## Every later release

```bash
npx nuxi generate
rm -rf cpanel-deploy && cp -R .output/public cpanel-deploy
git add -A && git commit -m "release" && git push
```

then **pull** in cPanel's Git Version Control (or re-upload the zip).
Nothing to install on the server — ever.

## Notes

- Database changes ship as new files in `supabase/migrations/` — run them
  in the hosted SQL editor before pulling the matching frontend build.
- Fonts load from Google Fonts (needs internet at the factory). To
  self-host later, download Inter + JetBrains Mono woff2 files into
  `public/fonts/` and swap the link in `nuxt.config.ts` for `@font-face`
  rules in `assets/css/main.css`.
- Email-based LC ingestion (future): a small PHP cron on cPanel can watch
  a mailbox and POST PDF attachments into the `lc-docs` storage bucket via
  the Supabase API — the `lc_documents` table is already the landing zone.
