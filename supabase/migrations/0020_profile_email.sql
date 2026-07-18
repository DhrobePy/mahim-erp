-- =====================================================================
-- Mahim Packaging ERP — 0020_profile_email
-- profiles never stored email (only full_name) — the admin user-edit UI
-- needs to display/prefill it. Backfill from auth.users, then keep it
-- in sync going forward via handle_new_user().
-- =====================================================================

alter table profiles add column if not exists email text;

update profiles p set email = u.email
from auth.users u
where u.id = p.id and p.email is null;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.email, 'viewer')
  on conflict (id) do nothing;
  return new;
end; $$;
