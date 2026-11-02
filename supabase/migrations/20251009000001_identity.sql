-- Lekkside Connect — identity, roles and institutions.
--
-- Four kinds of people share one `profiles` table keyed to auth.users:
-- students, institution members (admissions staff), educators and Lekkside admin.
-- Role is set once at signup and is NOT self-assignable to admin — see
-- handle_new_user() below.

-- gen_random_uuid() is core Postgres since 13, so no extension is required.

-- ---------------------------------------------------------------- shared enums

create type user_role as enum (
  'student',
  'institution_member',
  'educator',
  'admin'
);

-- Every "verified" badge in the product resolves to one of these. What each
-- badge actually attests to is documented per-table, because the claim is a
-- trust statement we have to be able to stand behind.
create type verification_status as enum (
  'unverified',
  'pending',
  'verified',
  'rejected'
);

create type institution_tier as enum (
  'basic',
  'professional',
  'enterprise'
);

create type study_level as enum (
  'foundation',
  'diploma',
  'undergraduate',
  'postgraduate',
  'phd'
);

-- ------------------------------------------------- shared trigger: updated_at

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ----------------------------------------------------- controlled vocabularies

-- Matching only works if both sides describe a subject the same way, so field
-- of study is a lookup rather than free text. The UI must pick from this table.
create table fields_of_study (
  slug        text primary key,
  label       text not null,
  sort_order  int  not null default 100
);

comment on table fields_of_study is
  'Controlled vocabulary for program subjects and student target fields. '
  'Free text here would silently break matching.';

-- ------------------------------------------------------------------- profiles

create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        user_role not null default 'student',
  full_name   text not null default '',
  avatar_url  text,
  phone       text,
  -- ISO 3166-1 alpha-2, the country the person is in now.
  country     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index profiles_role_idx on profiles (role);

create trigger profiles_set_updated_at
  before update on profiles
  for each row execute function set_updated_at();

-- Mirrors a new auth user into profiles. Role comes from signup metadata but is
-- clamped to the three self-serve roles: 'admin' can only ever be granted by an
-- existing admin via update, never by anything a signup request can say.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested text := new.raw_user_meta_data ->> 'role';
  resolved  user_role;
begin
  resolved := case requested
                when 'institution_member' then 'institution_member'::user_role
                when 'educator'           then 'educator'::user_role
                else                           'student'::user_role
              end;

  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    resolved,
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- --------------------------------------------------------------- institutions

create table institutions (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  slug                text not null unique,
  country             text not null,
  city                text,
  website             text,
  -- The domain we check institution staff email against. This is the whole
  -- basis of the VERIFIED INSTITUTION badge, so it is stored bare and lowercase
  -- (e.g. 'utoronto.ca', never 'https://utoronto.ca/').
  email_domain        text,
  logo_url            text,
  description         text,
  -- 'verified' attests ONLY that someone controlling an address on
  -- email_domain confirmed the listing. It is not a claim about accreditation.
  verification_status verification_status not null default 'unverified',
  verified_at         timestamptz,
  tier                institution_tier not null default 'basic',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint institutions_email_domain_is_bare
    check (email_domain is null or email_domain !~ '[/:]')
);

create index institutions_country_idx on institutions (country);
create index institutions_verification_idx on institutions (verification_status);

create trigger institutions_set_updated_at
  before update on institutions
  for each row execute function set_updated_at();

-- -------------------------------------------------------- institution members

create type institution_member_role as enum (
  'owner',
  'admissions_officer'
);

create table institution_members (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  profile_id     uuid not null references profiles (id) on delete cascade,
  member_role    institution_member_role not null default 'admissions_officer',
  created_at     timestamptz not null default now(),

  unique (institution_id, profile_id)
);

create index institution_members_profile_idx on institution_members (profile_id);

comment on table institution_members is
  'Admissions staff seats. Multiple officers per institution is the Enterprise '
  'tier feature; tier is not enforced here, it is enforced at invite time.';

-- ------------------------------------------------------------------ educators

create type educator_kind as enum (
  'admissions_officer',
  'professor',
  'student_ambassador'
);

create table educators (
  profile_id          uuid primary key references profiles (id) on delete cascade,
  institution_id      uuid references institutions (id) on delete set null,
  title               text,
  kind                educator_kind not null default 'admissions_officer',
  bio                 text,
  -- 'verified' attests that the institution affiliation was confirmed.
  verification_status verification_status not null default 'unverified',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index educators_institution_idx on educators (institution_id);

create trigger educators_set_updated_at
  before update on educators
  for each row execute function set_updated_at();
