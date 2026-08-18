-- ============================================================
-- 08_signup_identity.sql
-- Adds full_name + mobile to user_profiles, and a trigger so the
-- client's auth signup raw_user_meta_data gets mirrored into the
-- public profile row automatically.
--
-- Run this AFTER 01_schema.sql. Safe to re-run.
-- ============================================================

-- 1. New columns on user_profiles -------------------------------------------------
alter table public.user_profiles
  add column if not exists full_name text,
  add column if not exists mobile text;

-- 2. Auto-create a profile row when a new auth user signs up ---------------------
-- The Flutter client passes full_name + mobile in user_metadata; we copy them
-- straight into the public profile so the rest of the app can read them like
-- any other profile field.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (
    user_id, full_name, mobile, age, weight_kg, height_cm
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'mobile', ''),
    -- The clinical fields are required NOT NULL, so seed with sensible defaults
    -- that the user will replace during onboarding.
    30,
    60.0,
    160.0
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- Drop + recreate the trigger so we can re-run this file idempotently.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
