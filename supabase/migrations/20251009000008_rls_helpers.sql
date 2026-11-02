-- Lekkside Connect — RLS helper functions and role guards.
--
-- Supabase-first means Postgres row-level security *is* the authorization
-- layer: there is no server in front of it to catch a mistake. Everything here
-- exists to keep the policies in the next migration short enough to actually
-- read and audit.
--
-- All helpers are SECURITY DEFINER. That is not a shortcut — a policy on
-- `profiles` that itself queries `profiles` recurses infinitely, so the lookup
-- has to run outside RLS. Each one is therefore deliberately tiny, takes no
-- caller-supplied table name, and has a pinned search_path.

create or replace function current_user_role()
returns user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

-- Institutions the caller staffs. Used as `inst_id in (select my_institution_ids())`.
create or replace function my_institution_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select institution_id from institution_members where profile_id = auth.uid();
$$;

create or replace function is_member_of(p_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from institution_members
     where profile_id = auth.uid()
       and institution_id = p_institution_id);
$$;

create or replace function is_owner_of(p_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from institution_members
     where profile_id = auth.uid()
       and institution_id = p_institution_id
       and member_role = 'owner');
$$;

-- THE consent gate for all identifying student data.
--
-- There is exactly one condition: a live `passport_shares` row. Applying,
-- requesting a meeting and connecting at a booth all *write* such a row (see
-- 20251009000006_fairs.sql) rather than being extra cases here. One gate means
-- the student's "who can see me" screen is complete by construction, and every
-- grant can be revoked from one place.
create or replace function institution_can_see_student(
  p_institution_id uuid,
  p_student_id     uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from passport_shares
     where institution_id = p_institution_id
       and profile_id = p_student_id
       and revoked_at is null);
$$;

-- True when the caller's institution may see this student at all.
create or replace function my_institution_can_see_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from passport_shares s
      join institution_members m
        on m.institution_id = s.institution_id
     where m.profile_id = auth.uid()
       and s.profile_id = p_student_id
       and s.revoked_at is null);
$$;

-- Can the caller read this conversation? Either they are the student on it, or
-- they staff the institution on it.
create or replace function can_access_conversation(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from conversations c
     where c.id = p_conversation_id
       and (c.student_id = auth.uid() or is_member_of(c.institution_id)));
$$;

create or replace function can_access_application(p_application_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from applications a
     where a.id = p_application_id
       and (a.profile_id = auth.uid() or is_member_of(a.institution_id)));
$$;

-- -------------------------------------------------- privilege-escalation guards

-- `profiles` is self-updatable, so without this a student could simply set
-- their own role to 'admin' and acquire the run of the platform.
create or replace function guard_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null when there is no request context: a migration, the SQL
  -- editor, or an Edge Function on the service-role key. Those are already
  -- trusted, and blocking them would make an admin impossible to create.
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not is_admin() then
    raise exception 'role cannot be changed by its owner';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_role
  before update of role on profiles
  for each row execute function guard_profile_role_change();

-- Verification status is a trust claim; only the admin queue may move it.
-- Students and institutions can *request* verification (by inserting into
-- `verifications`) but never award it to themselves.
create or replace function guard_self_verification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- As above, a null auth.uid() means a trusted server-side write (migration,
  -- SQL editor, service-role Edge Function), which includes the write that
  -- apply_verification_decision() makes when admin resolves the queue.
  if new.verification_status is distinct from old.verification_status
     and auth.uid() is not null
     and not is_admin()
     and new.verification_status <> 'pending' then
    raise exception 'verification status is set by review, not by the subject';
  end if;
  return new;
end;
$$;

create trigger institutions_guard_verification
  before update of verification_status on institutions
  for each row execute function guard_self_verification();

create trigger passports_guard_verification
  before update of verification_status on student_passports
  for each row execute function guard_self_verification();

create trigger educators_guard_verification
  before update of verification_status on educators
  for each row execute function guard_self_verification();

-- Subscription tier is the paid feature gate, and institution staff can update
-- their own institution row — so without this they could simply set
-- tier = 'enterprise' and unlock student matching, the CRM and seats for free.
-- Tier may only arrive via institution_subscriptions, whose writes are
-- admin-only; sync_institution_tier() therefore always runs as admin and passes.
create or replace function guard_institution_tier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tier is distinct from old.tier
     and auth.uid() is not null
     and not is_admin() then
    raise exception 'tier is set by subscription, not by the institution';
  end if;
  return new;
end;
$$;

create trigger institutions_guard_tier
  before update of tier on institutions
  for each row execute function guard_institution_tier();

-- --------------------------------------- application stage transition guard
--
-- Who may move an application where. Without this, RLS would let a student who
-- can update their own application simply set stage = 'offer'.
create or replace function guard_application_stage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  student_allowed application_stage[] := array[
    'draft', 'submitted', 'accepted', 'withdrawn'
  ]::application_stage[];
  institution_allowed application_stage[] := array[
    'under_review', 'documents_requested', 'conditional_offer', 'offer',
    'rejected', 'deposit_paid', 'visa', 'enrolled'
  ]::application_stage[];
begin
  if new.stage is not distinct from old.stage or is_admin() then
    return new;
  end if;

  -- No request context: a trusted server-side write, same reasoning as above.
  if auth.uid() is null then
    return new;
  end if;

  if new.profile_id = auth.uid() then
    if not (new.stage = any (student_allowed)) then
      raise exception 'a student cannot move an application to %', new.stage;
    end if;
    -- Accepting is only meaningful against an actual offer.
    if new.stage = 'accepted'
       and old.stage not in ('offer', 'conditional_offer') then
      raise exception 'cannot accept before an offer is made';
    end if;
    return new;
  end if;

  if is_member_of(new.institution_id) then
    if not (new.stage = any (institution_allowed)) then
      raise exception 'an institution cannot move an application to %', new.stage;
    end if;
    return new;
  end if;

  raise exception 'not authorized to change this application';
end;
$$;

create trigger applications_guard_stage
  before update of stage on applications
  for each row execute function guard_application_stage();

-- ------------------------------------------------- institution bootstrapping
--
-- An institution_member signing up has no institution yet, and RLS cannot let
-- them insert a membership row for an institution they are not a member of.
-- This closes that loop in one transaction.
create or replace function create_institution(
  p_name         text,
  p_country      text,
  p_website      text default null,
  p_email_domain text default null,
  p_city         text default null,
  p_description  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id   uuid;
  v_slug text;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if current_user_role() not in ('institution_member', 'admin') then
    raise exception 'only institution accounts can create an institution';
  end if;

  v_slug := regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  -- Collisions are real ("University of London" vs a second listing), so
  -- suffix rather than fail the signup.
  if exists (select 1 from institutions where slug = v_slug) then
    v_slug := v_slug || '-' || substr(gen_random_uuid()::text, 1, 6);
  end if;

  insert into institutions (name, slug, country, city, website, email_domain, description)
  values (
    trim(p_name), v_slug, p_country, p_city, p_website,
    lower(nullif(regexp_replace(coalesce(p_email_domain, ''), '^https?://|/.*$', '', 'g'), '')),
    p_description
  )
  returning id into v_id;

  insert into institution_members (institution_id, profile_id, member_role)
  values (v_id, auth.uid(), 'owner');

  insert into institution_subscriptions (institution_id, tier)
  values (v_id, 'basic');

  -- Queue it for the domain check that backs the VERIFIED INSTITUTION badge.
  insert into verifications (subject_type, subject_id, status, evidence)
  values ('institution', v_id, 'pending',
          jsonb_build_object('method', 'domain_email', 'domain', p_email_domain))
  on conflict do nothing;

  return v_id;
end;
$$;

revoke all on function create_institution(text, text, text, text, text, text) from public;
grant execute on function create_institution(text, text, text, text, text, text) to authenticated;
