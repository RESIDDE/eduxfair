-- Lekkside Connect — splitting public identity from the private account id.
--
-- Phase 1's privacy model rests on one guarantee: an institution browsing
-- `matched_student_cards` sees an anonymous student until that student grants a
-- `passport_shares` row. That held only because nothing could turn the exposed
-- `student_id` into a person.
--
-- A public social profile keyed on the same `profiles.id` destroys it, and not
-- subtly. Against the REST API directly:
--
--     GET /matched_student_cards             -> student_id of an anonymous minor
--     GET /social_profiles?profile_id=eq.…   -> name, photo, posts
--
-- So the social layer cannot be built on `profiles.id`. Three identities,
-- deliberately not derivable from one another:
--
--     profiles.id    private account id    never leaves the server
--     @handle        public identity       posts, comments, follows, likes
--     match token    per-institution       shortlist, invite, request access
--
-- A student's handle is not reachable from their match token, and vice versa.
-- If a student wants an institution to know who they are, that is what the
-- passport share already does — the mechanism stays exactly one thing.

create extension if not exists citext;

-- ------------------------------------------------------- organisation kind
--
-- Added here, ahead of the embassy work, because claim_handle() below needs to
-- know whether an organisation handle belongs to a university or an embassy.
--
-- A kind column rather than a parallel `embassies` table: embassies then
-- inherit members, domain verification, social profiles and Spaces unchanged,
-- and simply have no programs.

create type institution_kind as enum ('university', 'college', 'embassy', 'agency');

alter table institutions
  add column if not exists kind institution_kind not null default 'university';

create index institutions_kind_idx on institutions (kind);

-- ------------------------------------------------------------ social profiles

create type social_profile_kind as enum (
  'student',
  'institution',
  'embassy',
  'educator'
);

create table social_profiles (
  -- The column this whole migration exists to protect. It is never exposed by
  -- any public view, and this table has no public select policy at all.
  profile_id     uuid primary key references profiles (id) on delete cascade,

  handle         citext not null unique,
  display_name   text not null,
  bio            text,
  avatar_url     text,
  kind           social_profile_kind not null default 'student',

  -- Set when posting on behalf of an organisation.
  institution_id uuid references institutions (id) on delete set null,

  -- A student may hold a handle without being listed in discovery.
  is_public      boolean not null default true,

  -- Drives the protections in the moderation migration. Derived from the
  -- passport's date of birth, never self-declared.
  is_minor       boolean not null default false,

  follower_count int not null default 0,
  following_count int not null default 0,
  post_count     int not null default 0,

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- Lowercase, no leading digit-only handles that could be mistaken for ids.
  constraint social_handle_shape
    check (handle ~ '^[a-z][a-z0-9_]{2,19}$'),
  constraint social_display_name_present
    check (length(trim(display_name)) > 0)
);

create index social_profiles_kind_idx on social_profiles (kind) where is_public;
create index social_profiles_institution_idx on social_profiles (institution_id);

create trigger social_profiles_set_updated_at
  before update on social_profiles
  for each row execute function set_updated_at();

comment on table social_profiles is
  'Public identity, keyed by handle. `profile_id` is the private account id and '
  'is never exposed by a public view — that linkage is what keeps an anonymous '
  'match card anonymous.';

-- Keeps `is_minor` honest: derived from the passport, not from the account.
create or replace function sync_social_is_minor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  dob date;
begin
  select date_of_birth into dob
    from student_passports
   where profile_id = new.profile_id;

  new.is_minor := dob is not null and age_band(dob) = 'under 18';
  return new;
end;
$$;

create trigger social_profiles_sync_minor
  before insert or update of profile_id on social_profiles
  for each row execute function sync_social_is_minor();

-- A birthday, or a passport filled in later, has to update the flag too.
create or replace function sync_social_is_minor_from_passport()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update social_profiles
     set is_minor = new.date_of_birth is not null
                    and age_band(new.date_of_birth) = 'under 18'
   where profile_id = new.profile_id;
  return new;
end;
$$;

create trigger passports_sync_social_minor
  after insert or update of date_of_birth on student_passports
  for each row execute function sync_social_is_minor_from_passport();

-- ---------------------------------------------------------------- match tokens
--
-- The handle an institution uses to act on a student it cannot identify.
-- Per (student, institution), so two institutions looking at the same student
-- see unrelated tokens and cannot compare notes to correlate them.

create table match_tokens (
  token          text primary key,
  student_id     uuid not null references profiles (id) on delete cascade,
  institution_id uuid not null references institutions (id) on delete cascade,
  created_at     timestamptz not null default now(),

  unique (student_id, institution_id)
);

create index match_tokens_lookup on match_tokens (institution_id, student_id);

alter table match_tokens enable row level security;

-- SERVICE-ROLE ONLY: intentionally no policies. The token is only useful if it
-- cannot be resolved back to a student by the party holding it, so even the
-- institution that was issued one has no read access to this mapping. Resolution
-- happens inside the SECURITY DEFINER functions below.
comment on table match_tokens is
  'SERVICE-ROLE ONLY. Maps an opaque per-institution token to a student. RLS is '
  'enabled with no policies on purpose: an institution holding a token must not '
  'be able to resolve it, or the pseudonymity it provides is worthless.';

/**
 * Issues (or returns) the token for one student/institution pair.
 *
 * Random rather than a hash of the ids: a hash is only as strong as the secret
 * beside it, and a secret stored in the same database it protects is not one.
 *
 * Built from gen_random_uuid() rather than gen_random_bytes() because the
 * latter is pgcrypto, which this schema deliberately does not require.
 */
create or replace function match_token_for(
  p_student_id     uuid,
  p_institution_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  select token into v_token
    from match_tokens
   where student_id = p_student_id
     and institution_id = p_institution_id;

  if v_token is not null then
    return v_token;
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '');

  insert into match_tokens (token, student_id, institution_id)
  values (v_token, p_student_id, p_institution_id)
  on conflict (student_id, institution_id)
    do update set token = match_tokens.token
  returning token into v_token;

  return v_token;
end;
$$;

/** Resolves a token, but only for a caller who staffs the issuing institution. */
create or replace function student_for_match_token(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row match_tokens;
begin
  select * into v_row from match_tokens where token = p_token;

  if not found then
    raise exception 'unknown match token';
  end if;

  if not is_member_of(v_row.institution_id) and not is_admin() then
    raise exception 'that token was not issued to your institution';
  end if;

  return v_row.student_id;
end;
$$;
