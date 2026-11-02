-- Moderators a host can appoint, and the two mutes that act on a whole room.
--
-- Three things were too small for a two-hundred-person admissions hour:
--
--   1. "May I moderate this room" meant "do I staff this institution". The
--      host is the person actually talking, and cannot also be watching a
--      waiting room — so the host needs to be able to hand that job to someone
--      in the room with them.
--   2. The only mute was one participant's microphone. A room that has to be
--      silenced has to be silenced in one action, not forty.
--   3. A camera could not be turned off at all, only a microphone.
--
-- The authorization stays where it already was: in SQL, under the caller's own
-- RLS, in the same transaction as the audit row. The Edge Function carries the
-- decision through to LiveKit afterwards and decides nothing.

-- ------------------------------------------------- a moderator is identified
--
-- The old constraint covered `speaker` only. A moderator holds the floor and a
-- mute button, so the same rule applies: it is a share they gave themselves
-- that puts them there, not a host's say-so alone.

alter table space_participants drop constraint space_speaker_identified;

alter table space_participants add constraint space_speaker_identified
  check (role not in ('speaker', 'moderator') or identified_at is not null);

-- ------------------------------------------------------------ who may do what
--
-- Two questions that used to be one:
--
--   space_is_staff       may appoint moderators, and may act on one
--   space_can_moderate   may admit, mute, lower a hand, remove
--
-- Staff can do both. An appointed moderator can do the second only, which is
-- what stops two moderators revoking each other in the middle of a session.

create or replace function space_is_staff(p_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from spaces s
     where s.id = p_space_id
       and (is_member_of(s.institution_id) or is_admin()));
$$;

comment on function space_is_staff(uuid) is
  'Staff of the hosting institution, or an admin. The authority that appoints '
  'moderators — deliberately NOT the authority that moderates, which '
  'space_can_moderate answers and an appointed attendee also holds.';

revoke all on function space_is_staff(uuid) from public;
grant execute on function space_is_staff(uuid) to authenticated;

create or replace function is_space_moderator(p_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from space_participants
     where space_id = p_space_id
       and profile_id = auth.uid()
       and admission = 'admitted'
       and role in ('host', 'cohost', 'moderator'));
$$;

revoke all on function is_space_moderator(uuid) from public;
grant execute on function is_space_moderator(uuid) to authenticated;

create or replace function space_can_moderate(p_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select space_is_staff(p_space_id) or is_space_moderator(p_space_id);
$$;

revoke all on function space_can_moderate(uuid) from public;
grant execute on function space_can_moderate(uuid) to authenticated;

-- ------------------------------------------------------ a moderator may speak

create or replace function my_speaking_participant(p_space_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from space_participants
   where auth.uid() is not null
     and space_id = p_space_id
     and profile_id = auth.uid()
     and admission = 'admitted'
     and role in ('host', 'cohost', 'moderator', 'speaker');
$$;

revoke all on function my_speaking_participant(uuid) from public;
grant execute on function my_speaking_participant(uuid) to authenticated;

-- identify_in_space() promoted unconditionally, so a moderator who re-ran the
-- consent step demoted themselves to speaker and lost the mute button.
create or replace function identify_in_space(p_space_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_row   space_participants;
  v_space spaces;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select * into v_space from spaces where id = p_space_id;
  if not found then raise exception 'no such space'; end if;

  select * into v_row from space_participants
   where space_id = p_space_id and profile_id = auth.uid();
  if not found then raise exception 'join the session first'; end if;

  if v_row.admission <> 'admitted' then
    raise exception 'a host has not let you in yet';
  end if;

  if not institution_may_message(auth.uid(), v_space.institution_id) then
    raise exception
      'You can listen to this session, but speaking in it needs you to have '
      'been in touch with this institution first — follow them, apply, or ask '
      'for a meeting.';
  end if;

  perform grant_passport_share(
    auth.uid(), v_space.institution_id,
    'You spoke in a live session: ' || v_space.title);

  update space_participants
     set role = case when role = 'listener' then 'speaker' else role end,
         identified_at = coalesce(identified_at, now())
   where id = v_row.id;

  return v_row.id;
end;
$$;

revoke all on function identify_in_space(uuid) from public;
grant execute on function identify_in_space(uuid) to authenticated;

-- ---------------------------------------------------------------- the roster
--
-- Now readable by an appointed moderator, who needs the waiting room and the
-- hand queue to do the job at all. `shared_name` is gated on the VIEWER being
-- staff rather than on the subject having shared: a consent given to an
-- institution is not a consent given to whichever attendee it put a badge on.
-- So a moderator moderates people they cannot name, which is the same sentence
-- this view was already built around.

create or replace view space_roster
with (security_barrier = true)
as
select
  sp.id            as participant_id,
  sp.space_id,
  s.institution_id,
  sp.role,
  sp.admission,
  sp.handle::text  as handle,
  sp.hand_raised_at,
  sp.joined_at,
  sp.left_at,
  sp.identified_at is not null as is_identified,

  case
    -- An appointed moderator sees handles and nothing else, whoever the row is.
    when not space_is_staff(sp.space_id) then null

    -- Staff names are already visible to any signed-in user, so there is
    -- nothing here to gate.
    when sp.role in ('host', 'cohost')
      then (select pr.full_name from profiles pr where pr.id = sp.profile_id)
    when sp.identified_at is not null
         and institution_can_see_student(s.institution_id, sp.profile_id)
      then (select pr.full_name from profiles pr where pr.id = sp.profile_id)
  end as shared_name

from space_participants sp
join spaces s on s.id = sp.space_id
where is_member_of(s.institution_id) or is_admin() or is_space_moderator(sp.space_id);

comment on view space_roster is
  'An institution''s view of who is in its room, and an appointed moderator''s. '
  'Has no profile_id column by design — that absence is what lets a host admit, '
  'mute and remove a listener they still cannot name. A moderator who is not '
  'staff reads no shared_name either.';

revoke all on space_roster from public;
grant select on space_roster to authenticated;

-- ------------------------------------------------------------- one person
--
-- Replaces 20251024000032's space_moderate. Four new actions, one new
-- authorization rule, and the returned role so the Edge Function knows which
-- LiveKit permission set to apply.

create or replace function space_moderate(
  p_participant_id uuid,
  p_action         space_moderation_action,
  p_reason         text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_row   space_participants;
  v_space spaces;
  v_staff boolean;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select * into v_row from space_participants where id = p_participant_id;
  if not found then raise exception 'no such participant'; end if;

  select * into v_space from spaces where id = v_row.space_id;

  if not space_can_moderate(v_row.space_id) then
    raise exception 'that session is not yours to moderate';
  end if;

  v_staff := space_is_staff(v_row.space_id);

  -- An appointed moderator runs the room; they do not run the people who
  -- appointed them, or each other. Without this, the first thing two
  -- moderators can do is revoke one another.
  if v_row.role in ('host', 'cohost', 'moderator') and not v_staff then
    raise exception
      'only the institution running this session can act on its hosts and '
      'moderators';
  end if;

  if v_row.role = 'host' and p_action in ('removed', 'demoted') then
    raise exception 'the host of a session cannot be removed from it';
  end if;

  -- An if/elsif chain rather than a case statement, matching moderate_handle()
  -- in 20251010000026 and avoiding any enum-literal coercion question.
  if p_action = 'admitted' then
    update space_participants set admission = 'admitted' where id = v_row.id;

  elsif p_action = 'denied' then
    update space_participants set admission = 'denied' where id = v_row.id;

  elsif p_action = 'removed' then
    update space_participants
       set admission = 'removed', left_at = now(), hand_raised_at = null
     where id = v_row.id;

  elsif p_action in ('muted', 'camera_muted') then
    -- Nothing to write on the row: a mute is a LiveKit track operation and the
    -- participant may legitimately unmute again. The event row IS the record.
    null;

  elsif p_action = 'promoted' then
    -- The host literally cannot make an anonymous student speak. Promotion
    -- requires a share they gave themselves, which is the consent model paying
    -- for itself rather than a rule bolted on beside it.
    if v_row.identified_at is null then
      raise exception
        'that person has not shared their passport, so they cannot be given '
        'the floor';
    end if;
    if v_row.role = 'listener' then
      update space_participants set role = 'speaker' where id = v_row.id;
    end if;

  elsif p_action = 'demoted' then
    -- identified_at deliberately survives. Consent is a passport_shares row the
    -- student revokes from one place; losing the floor does not take it back.
    if v_row.role = 'moderator' then
      raise exception
        'take back their moderator role first, then the floor';
    end if;
    update space_participants
       set role = 'listener', hand_raised_at = null where id = v_row.id;

  elsif p_action = 'moderator_granted' then
    if not v_staff then
      raise exception 'only the institution running this session can appoint moderators';
    end if;
    if v_row.role in ('host', 'cohost') then
      raise exception 'they already run this session';
    end if;
    -- Same gate as promotion, for the same reason and one size up: a moderator
    -- can silence the room, and an anonymous participant cannot be handed that.
    if v_row.identified_at is null then
      raise exception
        'that person has not shared their passport, so they cannot be made a '
        'moderator';
    end if;
    update space_participants
       set role = 'moderator', hand_raised_at = null where id = v_row.id;

  elsif p_action = 'moderator_revoked' then
    if not v_staff then
      raise exception 'only the institution running this session can take back a moderator role';
    end if;
    if v_row.role <> 'moderator' then
      raise exception 'they are not a moderator of this session';
    end if;
    -- Back to speaker, not to listener. They were identified before they were
    -- appointed and that has not changed; dropping them to the back of the room
    -- would be a second, unasked-for demotion.
    update space_participants set role = 'speaker' where id = v_row.id;

  elsif p_action = 'hand_lowered' then
    update space_participants set hand_raised_at = null where id = v_row.id;

  else
    raise exception 'unknown moderation action %', p_action;
  end if;

  insert into space_moderation_events
    (space_id, actor_id, subject_participant_id, action, reason)
  values (v_row.space_id, auth.uid(), v_row.id, p_action, nullif(trim(p_reason), ''));

  return jsonb_build_object(
    'room',     'space_' || v_row.space_id::text,
    'identity', 'sp_'    || v_row.id::text,
    'action',   p_action,
    'role',     (select role from space_participants where id = v_row.id));
end;
$$;

revoke all on function space_moderate(uuid, space_moderation_action, text) from public;
grant execute on function space_moderate(uuid, space_moderation_action, text) to authenticated;

-- ------------------------------------------------------------ the whole room

/**
 * Silences everyone who is not running the session.
 *
 * Returns the identities to mute rather than muting them: the LiveKit call is
 * the Edge Function's job, and keeping it there means this function is still
 * the one thing supabase/tests/rls_test.mjs has to assert about.
 *
 * Hosts, cohosts and appointed moderators are skipped, and so is the caller —
 * "mute everyone" from the person holding the microphone has never once meant
 * "including me".
 */
create or replace function space_mute_all(
  p_space_id     uuid,
  p_include_video boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_identities text[];
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not space_can_moderate(p_space_id) then
    raise exception 'that session is not yours to moderate';
  end if;

  select coalesce(array_agg('sp_' || sp.id::text), '{}')
    into v_identities
    from space_participants sp
   where sp.space_id = p_space_id
     and sp.admission = 'admitted'
     and sp.left_at is null
     and sp.role not in ('host', 'cohost', 'moderator')
     and sp.profile_id <> auth.uid();

  insert into space_moderation_events (space_id, actor_id, action, reason)
  values (p_space_id, auth.uid(), 'muted_everyone',
          case when p_include_video
               then 'microphones and cameras' else 'microphones' end);

  return jsonb_build_object(
    'room',          'space_' || p_space_id::text,
    'identities',    to_jsonb(v_identities),
    'include_video', p_include_video,
    'count',         coalesce(array_length(v_identities, 1), 0));
end;
$$;

revoke all on function space_mute_all(uuid, boolean) from public;
grant execute on function space_mute_all(uuid, boolean) to authenticated;

-- -------------------------------------------------------------- the grant
--
-- A moderator speaks, and gets a mic and a camera. Not screen share: the
-- reason a speaker does not get it — a student screen-sharing into a
-- two-hundred-person admissions hour — does not stop being true when that
-- student is holding a mute button.
--
-- `display_name` and `is_host` are untouched and that is the point: a
-- moderator is not in ('host', 'cohost'), so they stay '@handle' on their own
-- video tile exactly as they were before they were appointed.

create or replace function space_room_grant(p_space_id uuid)
returns jsonb
language plpgsql
volatile                 -- joining is a write; see join_space()
security definer
set search_path = public
as $$
declare
  v_participant uuid;
  v_row    space_participants;
  v_space  spaces;
  v_speaks boolean;
begin
  v_participant := join_space(p_space_id);   -- guards, and raises on refusal

  select * into v_row   from space_participants where id = v_participant;
  select * into v_space from spaces             where id = p_space_id;

  if not space_is_open(p_space_id) then
    return jsonb_build_object(
      'admission',    'closed',
      'space_status', v_space.status,
      'opens_at',     v_space.scheduled_for - interval '10 minutes');
  end if;

  if v_row.admission <> 'admitted' then
    return jsonb_build_object(
      'admission',      v_row.admission,
      'participant_id', v_row.id,
      'space_status',   v_space.status);
  end if;

  v_speaks := v_row.role in ('host', 'cohost', 'moderator', 'speaker');

  return jsonb_build_object(
    'admission',      'admitted',
    'kind',           'space',
    'room',           'space_' || p_space_id::text,
    'identity',       'sp_'    || v_row.id::text,
    'participant_id', v_row.id,
    'handle',         v_row.handle::text,
    'role',           v_row.role,
    'is_host',        v_row.role = 'host',

    -- A student is their handle and nothing more — first name plus noise, by
    -- 20251010000028's design, which is why it is safe to show. Staff are the
    -- name a student already sees on their messages. An appointed moderator is
    -- a student, and stays one.
    'display_name', case
      when v_row.role in ('host', 'cohost')
        then (select pr.full_name from profiles pr where pr.id = v_row.profile_id)
      else '@' || coalesce(v_row.handle::text, 'student')
    end,

    'can_publish',      v_speaks,
    'can_publish_data', v_speaks,
    'can_subscribe',    true,
    'publish_sources', case
      when v_row.role in ('host', 'cohost')
        then jsonb_build_array('microphone', 'camera', 'screen_share', 'screen_share_audio')
      when v_row.role in ('moderator', 'speaker')
        then jsonb_build_array('microphone', 'camera')
      else jsonb_build_array() end,

    'space', jsonb_build_object(
      'id',                 v_space.id,
      'title',              v_space.title,
      'kind',               v_space.kind,
      'status',             v_space.status,
      'institution_id',     v_space.institution_id,
      'duration_min',       v_space.duration_min,
      'scheduled_for',      v_space.scheduled_for,
      'max_participants',   v_space.max_participants,
      'requires_admission', v_space.requires_admission,
      'institution', (select name from institutions where id = v_space.institution_id)),

    'ttl_seconds', greatest(7200, (v_space.duration_min + 60) * 60));
end;
$$;

revoke all on function space_room_grant(uuid) from public;
grant execute on function space_room_grant(uuid) to authenticated;
