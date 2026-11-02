-- Local-only shim: the objects Supabase manages for us in a hosted project.
--
-- Applied ONLY by supabase/tests/run.mjs so the migrations can be executed and
-- the RLS assertions run on a throwaway Postgres, without Docker or a hosted
-- project. It is never part of a migration and never reaches production.
--
-- Everything here mirrors how Supabase actually behaves, in particular that
-- auth.uid() reads the `request.jwt.claims` GUC — which is what lets a test
-- impersonate a user with `set local request.jwt.claims`.

create schema if not exists auth;
create schema if not exists storage;

-- Supabase's three API roles. `authenticated` is the one tests assume.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    -- Mirrors the hosted key that intentionally bypasses RLS.
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text unique,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at         timestamptz default now(),

  -- Hosted Supabase has these, and `admin_people` reads them, so the shim has
  -- to as well. They lived in devserver/shim_extra.sql while only the dev
  -- server's auth emulation touched them — which meant 20251024000035 applied
  -- against the hosted project and against the bundler, and failed only in the
  -- schema suite. A column a MIGRATION depends on belongs in the base shim;
  -- `encrypted_password` stays devserver-only because nothing but the fake
  -- sign-in needs it.
  email_confirmed_at timestamptz,
  last_sign_in_at    timestamptz
);

-- The real implementation: the user id comes from the verified JWT claims that
-- the API gateway sets per request.
-- Mirrors hosted Supabase exactly, including the detail that matters: nullif
-- is applied to the raw setting BEFORE the cast. current_setting() returns ''
-- (not NULL) once the GUC has been RESET, and ''::jsonb is a hard error — so
-- casting first would make auth.uid() throw in every non-request context.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
    ''
  )::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    'anon');
$$;

-- ------------------------------------------------------------------- storage

create table if not exists storage.buckets (
  id                 text primary key,
  name               text not null,
  public             boolean default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz default now()
);

create table if not exists storage.objects (
  id         uuid primary key default gen_random_uuid(),
  bucket_id  text references storage.buckets (id),
  name       text,
  owner      uuid,
  metadata   jsonb,
  created_at timestamptz default now()
);

alter table storage.objects enable row level security;

-- Supabase's own definition: every path segment except the filename.
create or replace function storage.foldername(name text)
returns text[]
language plpgsql
immutable
as $$
declare
  parts text[];
begin
  parts := string_to_array(name, '/');
  return parts[1 : array_length(parts, 1) - 1];
end;
$$;

-- --------------------------------------------------------------- realtime

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

-- ----------------------------------------------------------------- grants
--
-- Hosted Supabase grants the API roles broad table privileges and relies on RLS
-- to constrain them. Reproducing that is essential: without these grants a test
-- would "pass" because of a missing GRANT rather than because a policy worked.

grant usage on schema public, auth, storage to anon, authenticated, service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema storage
  to anon, authenticated, service_role;
grant select on all tables in schema auth to authenticated, service_role;
