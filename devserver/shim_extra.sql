-- Devserver-only additions on top of supabase/tests/00_supabase_shim.sql.
--
-- The test shim gives us auth.users, auth.uid(), storage.objects and the API
-- roles. A server that real clients sign in to needs a little more: passwords,
-- and somewhere to keep uploaded bytes.
--
-- None of this ships. Hosted Supabase provides all of it.

alter table auth.users
  add column if not exists encrypted_password text,
  add column if not exists email_confirmed_at timestamptz,
  add column if not exists last_sign_in_at timestamptz;

create table if not exists auth.identities (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  provider      text not null default 'email',
  provider_id   text,
  identity_data jsonb default '{}'::jsonb,
  created_at    timestamptz default now()
);

-- Object bytes. Hosted Supabase keeps these in S3; here they live in the
-- database so a restart of the dev server does not lose an upload while the
-- row describing it survives.
create table if not exists storage.object_bytes (
  bucket_id text not null,
  name      text not null,
  mime      text,
  bytes     bytea not null,
  primary key (bucket_id, name)
);

-- Signed URLs. Real Storage signs a JWT; here a random token in a table is
-- equivalent and far less code.
create table if not exists storage.signed_urls (
  token      text primary key,
  bucket_id  text not null,
  name       text not null,
  expires_at timestamptz not null
);
