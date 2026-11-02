-- Lekkside Connect — the public read path, and match cards keyed on tokens.
--
-- Every public social read goes through a view that exposes `handle` and never
-- `profile_id`. That is the whole mechanism: there is no query a client can
-- write that returns both, so an institution holding a match token has nothing
-- to join it against.

-- ------------------------------------------------- social_profiles policies
--
-- Owner and admin only. No public select — discovery reads `public_profiles`.

alter table social_profiles enable row level security;

create policy social_profiles_select_self on social_profiles
  for select using (profile_id = auth.uid());

create policy social_profiles_all_admin on social_profiles
  for all using (is_admin()) with check (is_admin());

create policy social_profiles_insert_self on social_profiles
  for insert with check (profile_id = auth.uid());

create policy social_profiles_update_self on social_profiles
  for update using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- Institution staff manage their organisation's handle.
create policy social_profiles_write_institution on social_profiles
  for all using (institution_id is not null and is_member_of(institution_id))
  with check (institution_id is not null and is_member_of(institution_id));

-- --------------------------------------------------------- public_profiles
--
-- Deliberately NOT security_invoker: an invoker view would inherit the policies
-- above and return only the caller's own row, so there would be no directory at
-- all. Instead this does its own filtering and simply has no `profile_id`
-- column to leak. `security_barrier` stops the planner pushing a
-- caller-supplied predicate underneath that filter.

create view public_profiles
with (security_barrier = true)
as
select
  sp.handle,
  sp.display_name,
  sp.bio,
  sp.avatar_url,
  sp.kind,
  sp.follower_count,
  sp.following_count,
  sp.post_count,
  sp.created_at,

  -- Organisation context, which is public anyway via the institution directory.
  i.name    as institution_name,
  i.country as institution_country,
  i.verification_status = 'verified' as institution_verified,

  -- What the badge beside the handle attests to. A student's badge means their
  -- documents were checked; an organisation's means its domain was.
  case
    when sp.kind in ('institution', 'embassy')
      then i.verification_status = 'verified'
    when sp.kind = 'educator'
      then exists (select 1 from educators e
                    where e.profile_id = sp.profile_id
                      and e.verification_status = 'verified')
    else exists (select 1 from student_passports p
                  where p.profile_id = sp.profile_id
                    and p.verification_status = 'verified')
  end as is_verified

from social_profiles sp
left join institutions i on i.id = sp.institution_id
where sp.is_public
  and auth.uid() is not null;

comment on view public_profiles is
  'The public directory, keyed by handle. Has no profile_id column by design — '
  'that absence is what prevents an institution resolving an anonymous match '
  'card to a person.';

revoke all on public_profiles from public;
grant select on public_profiles to authenticated;

-- --------------------------------------- the caller's own handle, for the UI
--
-- A client needs to know whether it has a handle yet, and which one, without
-- being able to ask that question about anybody else.

create or replace function my_handle()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select handle::text from social_profiles where profile_id = auth.uid();
$$;

/**
 * Claims a handle for the caller.
 *
 * A function rather than a direct insert so the handle shape, uniqueness and
 * the organisation check are enforced in one place with messages worth showing
 * someone — `social_handle_shape` is not a sentence.
 */
create or replace function claim_handle(
  p_handle         text,
  p_display_name   text,
  p_bio            text default null,
  p_institution_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_handle citext := lower(trim(p_handle));
  v_kind   social_profile_kind;
  v_role   user_role;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if v_handle !~ '^[a-z][a-z0-9_]{2,19}$' then
    raise exception 'A handle is 3 to 20 characters: letters, numbers and '
                    'underscores, starting with a letter.';
  end if;

  if exists (select 1 from social_profiles
              where handle = v_handle and profile_id <> auth.uid()) then
    raise exception 'That handle is already taken.';
  end if;

  if p_institution_id is not null and not is_member_of(p_institution_id) then
    raise exception 'You do not belong to that institution.';
  end if;

  v_role := current_user_role();
  v_kind := case
    when p_institution_id is not null then
      case when (select kind from institutions where id = p_institution_id)
                = 'embassy'
           then 'embassy'::social_profile_kind
           else 'institution'::social_profile_kind end
    when v_role = 'educator' then 'educator'::social_profile_kind
    else 'student'::social_profile_kind
  end;

  insert into social_profiles
    (profile_id, handle, display_name, bio, kind, institution_id)
  values
    (auth.uid(), v_handle, trim(p_display_name), p_bio, v_kind, p_institution_id)
  on conflict (profile_id) do update
    set handle = excluded.handle,
        display_name = excluded.display_name,
        bio = coalesce(excluded.bio, social_profiles.bio),
        institution_id = coalesce(excluded.institution_id,
                                  social_profiles.institution_id);

  return v_handle::text;
end;
$$;

revoke all on function claim_handle(text, text, text, uuid) from public;
grant execute on function claim_handle(text, text, text, uuid) to authenticated;

-- ------------------------------------------- match cards, keyed on the token

drop view if exists matched_student_cards;

create view matched_student_cards
with (security_barrier = true)
as
select
  -- The token replaces student_id. An institution can shortlist, invite and
  -- request access with this, and can resolve it to a person only by the
  -- student granting a passport share.
  match_token_for(ms.student_id, g.institution_id) as token,

  ms.program_id,
  g.institution_id,
  g.name              as program_name,
  ms.score,
  ms.reasons,
  ms.computed_at,

  -- Non-identifying attributes only.
  p.current_country,
  p.nationality,
  p.target_levels,
  p.target_fields,
  p.intended_intake,
  grade_band(p.normalized_grade)               as grade_band,
  age_band(p.date_of_birth)                    as age_band,
  p.english_band,
  budget_band(p.budget_max, p.budget_currency) as budget_band,
  p.completeness,
  p.verification_status                        as passport_verification,

  institution_can_see_student(g.institution_id, ms.student_id) as is_shared,

  -- Only meaningful once shared; null keeps the card anonymous until then.
  case when institution_can_see_student(g.institution_id, ms.student_id)
       then (select pr.full_name from profiles pr where pr.id = ms.student_id)
  end as shared_name,

  exists (
    select 1 from institution_interests ii
     where ii.institution_id = g.institution_id
       and ii.profile_id = ms.student_id
       and ii.program_id = ms.program_id
  ) as already_actioned

from match_scores ms
join programs g on g.id = ms.program_id
join student_passports p on p.profile_id = ms.student_id
where g.is_active
  -- Institutions and admin only. A student reads their own matches from
  -- `match_scores`, which their own RLS policy already allows; without a
  -- student_id column there is nothing here for them to filter on anyway.
  and (is_member_of(g.institution_id) or is_admin());

comment on view matched_student_cards is
  'Pseudonymous match cards, keyed by a per-institution token rather than the '
  'account id. Excludes name, contact details, exact grades, date of birth, bio '
  'and documents. Identity requires a passport_share — and with the token there '
  'is no handle to correlate against either.';

revoke all on matched_student_cards from public;
grant select on matched_student_cards to authenticated;

-- --------------------------------- institution actions, resolved server-side

/** Shortlist, pass or invite — without ever handing over the student's id. */
create or replace function institution_record_interest(
  p_token      text,
  p_program_id uuid,
  p_kind       institution_interest_kind,
  p_note       text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := student_for_match_token(p_token);
  v_institution uuid;
begin
  select institution_id into v_institution from match_tokens where token = p_token;

  insert into institution_interests
    (institution_id, program_id, profile_id, kind, note, created_by)
  values (v_institution, p_program_id, v_student, p_kind, p_note, auth.uid())
  on conflict (institution_id, profile_id, program_id, kind) do update
    set note = coalesce(excluded.note, institution_interests.note);
end;
$$;

/**
 * Invites a student and notifies them, in one call.
 *
 * Together rather than separately because the notification is the only part
 * the student sees — an invite that silently fails to notify is an invite that
 * did not happen.
 */
create or replace function institution_invite_student(
  p_token      text,
  p_program_id uuid,
  p_note       text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := student_for_match_token(p_token);
  v_institution uuid;
  v_name text;
begin
  select institution_id into v_institution from match_tokens where token = p_token;
  select name into v_name from institutions where id = v_institution;

  perform institution_record_interest(p_token, p_program_id, 'invited', p_note);

  insert into notifications (profile_id, kind, title, body, payload)
  values (
    v_student,
    'institution_invited_you',
    v_name || ' would like to hear from you',
    p_note,
    jsonb_build_object('institution_id', v_institution, 'program_id', p_program_id)
  );
end;
$$;

/** Asks a student to share their passport. They decide; this only asks. */
create or replace function institution_request_access(
  p_token text,
  p_note  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := student_for_match_token(p_token);
  v_institution uuid;
  v_name text;
begin
  select institution_id into v_institution from match_tokens where token = p_token;
  select name into v_name from institutions where id = v_institution;

  insert into notifications (profile_id, kind, title, body, payload)
  values (
    v_student,
    'institution_requested_access',
    v_name || ' would like to see your passport',
    coalesce(p_note, 'They can only see your name, documents and contact '
                     'details if you choose to share.'),
    jsonb_build_object('institution_id', v_institution)
  );
end;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'institution_record_interest(text, uuid, institution_interest_kind, text)',
    'institution_invite_student(text, uuid, text)',
    'institution_request_access(text, text)'
  ] loop
    execute format('revoke all on function %s from public', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end
$$;

-- Institutions lose direct reads of institution_interests: the rows carry
-- profile_id, which is exactly what the token model withholds.
drop policy if exists interests_select_institution on institution_interests;
drop policy if exists interests_write_institution on institution_interests;

create view institution_interest_cards
with (security_barrier = true)
as
select
  match_token_for(ii.profile_id, ii.institution_id) as token,
  ii.id,
  ii.institution_id,
  ii.program_id,
  ii.kind,
  ii.note,
  ii.created_at,
  institution_can_see_student(ii.institution_id, ii.profile_id) as is_shared
from institution_interests ii
where is_member_of(ii.institution_id) or is_admin();

revoke all on institution_interest_cards from public;
grant select on institution_interest_cards to authenticated;
