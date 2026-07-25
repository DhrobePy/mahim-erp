-- Bug fix: handle_new_user() (redefined in 0020_profile_email.sql to add
-- the `email` column) still listed `role` in its insert column list, but
-- profiles.role was dropped back in 0002_multi_company.sql when roles
-- moved to company_members. Every new auth.users insert has been firing
-- this trigger and failing with "column role of relation profiles does
-- not exist" — rolling back the whole insert. This silently broke every
-- new-user creation path (including the admin-create-user Edge Function)
-- since 0020 was applied.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email), new.email)
  on conflict (id) do nothing;
  return new;
end; $$;
