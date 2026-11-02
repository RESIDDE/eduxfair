-- Lekkside Connect — Live Spaces, and the appointment room they share.
--
-- 20251009000004 said this would be additive: `appointments` carries a
-- `channel` column so "swapping in LiveKit later is an additive change, not a
-- migration", and 20251010000015 names Spaces as one of the things an embassy
-- inherits for free. Both held. Nothing below changes an existing column's
-- meaning, and `appointments` gains exactly one.
--
-- Two rooms, one mechanism:
--
--   a Space        one institution, many students, scheduled, open to join
--   an appointment one student, one institution, already named to each other
--
-- The LiveKit room name is DERIVED, never stored: `space_<spaces.id>` and
-- `appt_<appointments.id>`. A column would be a second source of truth for
-- something computable from the row the token function has already authorized,
-- and the prefix is what stops a token minted for one kind addressing a room of
-- the other.
--
-- THE IDENTITY RULE, restated because this is the feature most likely to break
-- it: an institution running a Space must never be handed a `profiles.id`. So
-- `space_participants` has no institution policy at all — staff read
-- `space_roster`, which has no profile_id column to leak — chat rows are keyed
-- on the participant rather than the person, and the identity a client presents
-- to LiveKit is a `space_participants.id`. Never an account id, not even in a
-- 1:1 appointment where a share already exists: 20251010000015 says the private
-- account id never leaves the server, and a LiveKit identity leaves the server.
--
-- THE CONSENT RULE: listening is pseudonymous, participating identifies. A
-- listener can publish nothing. Speaking, raising a hand or posting in the chat
-- goes through identify_in_space(), which writes an ordinary `passport_shares`
-- row — the same single gate as applying, booking and a booth scan. There is
-- deliberately no new consent mechanism here, so the student's "who can see me"
-- screen stays complete without knowing Spaces exist, and one revocation still
-- covers everything.

-- --------------------------------------------------------------- vocabularies

-- What a session is for. Asked at scheduling time rather than guessed from the
-- title, because it decides the label, the icon and who is notified.
create type space_kind as enum (
  'admissions_hour',
  'scholarship_qa',
  'country_briefing',
  'open_day'
);

create type space_status as enum ('scheduled', 'live', 'ended', 'cancelled');

-- Inside a room. Deliberately NOT institution_member_role: the two answer
-- different questions, and an owner dropping into a colleague's session is a
-- cohost there, not its host.
create type space_role as enum ('host', 'cohost', 'speaker', 'listener');

-- The waiting room, and the one-way door out of it.
create type space_admission as enum ('pending', 'admitted', 'denied', 'removed');

create type space_moderation_action as enum (
  'started', 'ended',
  'admitted', 'denied', 'removed',
  'muted', 'promoted', 'demoted', 'hand_lowered', 'message_removed'
);

-- ------------------------------------------------------------------- spaces

create table spaces (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references institutions (id) on delete cascade,
  -- Whoever scheduled it. Any member may go live and moderate — an admissions
  -- team shares a shift — so this decides who holds `host`, not who may.
  host_profile_id uuid not null references profiles (id) on delete cascade,

  title           text not null,
  description     text,
  kind            space_kind   not null default 'admissions_hour',
  status          space_status not null default 'scheduled',

  scheduled_for   timestamptz not null,
  duration_min    int not null default 45,

  -- The waiting room. Off for a verified institution running an open
  -- admissions hour; forced on below for one that is not yet verified.
  requires_admission boolean not null default false,

  -- Passed to LiveKit's CreateRoom. A cap in the database as well as in the
  -- function, so whoever wonders what this costs can read the answer.
  max_participants int not null default 200,

  started_at      timestamptz,
  ended_at        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint space_title_present    check (length(trim(title)) > 0),
  constraint space_duration_sane    check (duration_min between 5 and 480),
  constraint space_capacity_sane    check (max_participants between 2 and 1000),
  constraint space_live_has_started check (status <> 'live'  or started_at is not null),
  constraint space_ended_has_ended  check (status <> 'ended' or ended_at   is not null)
);

create index spaces_institution_idx on spaces (institution_id, scheduled_for desc);
-- The students' Spaces tab: what is on, and what is next.
create index spaces_upcoming_idx on spaces (scheduled_for)
  where status in ('scheduled', 'live');

create trigger spaces_set_updated_at
  before update on spaces
  for each row execute function set_updated_at();

comment on table spaces is
  'A scheduled live session run by one institution. Embassies host these '
  'unchanged, which is what institution_kind exists for.';

-- An unverified institution does not get to run an open-door room.
--
-- In the schema rather than in the scheduling form, because there are two
-- scheduling forms (the React console and the Flutter staff shell) and a rule
-- enforced in both is a rule enforced in neither.
create or replace function guard_space_admission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select verification_status from institutions where id = new.institution_id)
     is distinct from 'verified' then
    new.requires_admission := true;
  end if;
  return new;
end;
$$;

create trigger spaces_guard_admission
  before insert or update of requires_admission, institution_id on spaces
  for each row execute function guard_space_admission();

-- Realtime: a student sitting on the Spaces tab sees LIVE appear without
-- pulling to refresh. That is the whole "drop in" promise in the tab's copy.
alter publication supabase_realtime add table spaces;

-- --------------------------------------------------------------- the window
--
-- ONE definition of "open", shared by the join function, the grant function and
-- both clients, so the join button and the server cannot disagree. Ten minutes
-- early for the same reason an appointment opens ten minutes early: nobody
-- joins a call at exactly the appointed second.
create or replace function space_is_open(p_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from spaces s
     where s.id = p_space_id
       and s.status in ('scheduled', 'live')
       and now() >= s.scheduled_for - interval '10 minutes'
       and now() <  s.scheduled_for + make_interval(mins => s.duration_min + 30));
$$;

revoke all on function space_is_open(uuid) from public;
grant execute on function space_is_open(uuid) to authenticated;

-- ------------------------------------------------------------- participants

create table space_participants (
  id           uuid primary key default gen_random_uuid(),
  space_id     uuid not null references spaces (id) on delete cascade,
  profile_id   uuid not null references profiles (id) on delete cascade,

  role         space_role      not null default 'listener',
  admission    space_admission not null default 'admitted',

  -- The public handle, snapshotted at join rather than joined to
  -- social_profiles. Two reasons: the host's roster must keep making sense
  -- after a student renames themselves mid-session, and space_roster must not
  -- have to read an owner-only table to render a name.
  handle       citext,

  -- Set by identify_in_space(). The passport_shares row is the authority; this
  -- is the in-room consequence, and what decides the VideoGrant.
  identified_at  timestamptz,
  hand_raised_at timestamptz,

  joined_at    timestamptz,
  left_at      timestamptz,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  unique (space_id, profile_id),

  -- A listener who has identified is a contradiction: identifying is what
  -- promotes them. A constraint rather than a convention, because every grant
  -- the token function issues reads these two columns together.
  constraint space_speaker_identified
    check (role <> 'speaker' or identified_at is not null)
);

create index space_participants_space_idx   on space_participants (space_id, role);
create index space_participants_waiting_idx on space_participants (space_id)
  where admission = 'pending';
create index space_participants_profile_idx on space_participants (profile_id);

create trigger space_participants_set_updated_at
  before update on space_participants
  for each row execute function set_updated_at();

-- Realtime: the host's waiting list gets a row the moment someone arrives.
alter publication supabase_realtime add table space_participants;

comment on table space_participants is
  'Who is in a room, and as what. Institution staff have NO select policy here '
  'on purpose: the row carries a profiles.id, and handing one to an institution '
  'for a student it cannot name is exactly what 20251010000015 exists to '
  'prevent. Staff read space_roster and act through space_moderate().';

-- ---------------------------------------------------------------- the roster
--
-- Same shape as institution_inbox: identify the person by a key the institution
-- may hold, carry a real name only once consent exists, and have no profile_id
-- column at all so there is nothing to leak. Not security_invoker — an invoker
-- view would inherit space_participants' self-only policy and return the
-- caller's own row, which is not a roster.

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
where is_member_of(s.institution_id) or is_admin();

comment on view space_roster is
  'An institution''s view of who is in its room. Has no profile_id column by '
  'design — that absence is what lets a host admit, mute and remove a listener '
  'they still cannot name.';

revoke all on space_roster from public;
grant select on space_roster to authenticated;

-- ------------------------------------------------------------- in-room chat
--
-- Its own table, NOT `conversations`/`messages`. Four reasons, in order of how
-- much they cost to get wrong:
--
--   1. `conversations` is unique (student_id, institution_id) and
--      can_access_conversation() is written for exactly two parties. A group
--      thread cannot live there without destroying the 1:1 invariant the
--      inbox, institution_inbox, the unread counts and the consent gate all
--      rest on. 20251009000004 said as much: "Group threads and live educator
--      rooms are Phase 2 and will need their own shape." This is that shape.
--   2. LiveKit text streams are not persisted and late joiners see nothing. An
--      admissions hour where a student arrives ten minutes late to an empty
--      chat is a worse product than one query.
--   3. `reports` is keyed on (subject_type, subject_id), and report_subject
--      already contains 'space'. A message nobody stored cannot be reported —
--      and these rooms have minors in them.
--   4. It is the only durable record of what an institution told a student in
--      public. The same argument `messages` makes for having no update policy.
--
-- Keyed on the PARTICIPANT, not the person. So the row carries no account id,
-- and an institution can read its whole chat log without learning who anyone
-- is. The display name comes from the roster, client-side, by participant id.

create table space_messages (
  id             uuid primary key default gen_random_uuid(),
  space_id       uuid not null references spaces (id) on delete cascade,
  participant_id uuid not null references space_participants (id) on delete cascade,
  body           text not null,
  -- A host retracting a message, which is a different act from editing one.
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),

  constraint space_message_has_body check (coalesce(trim(body), '') <> ''),
  constraint space_message_length   check (length(body) <= 1000)
);

create index space_messages_space_idx on space_messages (space_id, created_at)
  where deleted_at is null;

-- Realtime is the transport AS WELL AS the store. LiveKit data packets are
-- reserved for the genuinely transient (reactions); chat goes over
-- postgres_changes, because then ordering, history and persistence are one
-- mechanism instead of three, and both clients already have the subscribe code.
alter publication supabase_realtime add table space_messages;

-- ----------------------------------------------------------- the audit trail

create table space_moderation_events (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references spaces (id) on delete cascade,
  -- Staff, so naming them is right: a removal with no author is not a record.
  actor_id uuid references profiles (id) on delete set null,
  -- Who it was done to, by their in-room key. NOT their profile id.
  subject_participant_id uuid references space_participants (id) on delete set null,
  action space_moderation_action not null,
  reason text,
  created_at timestamptz not null default now()
);

create index space_moderation_events_space_idx
  on space_moderation_events (space_id, created_at desc);

comment on table space_moderation_events is
  'Who did what to whom in a room. Written only by the SECURITY DEFINER '
  'functions below, and with no insert, update or delete policy for any role, '
  'admin included — the same rule application_events has, for the same reason: '
  'a record of a removal that the remover can edit is not a record.';

-- =========================================================== appointments
--
-- The one additive change. A client cannot tell from today's columns whether a
-- confirmed video appointment is a Lekkside room or an unsupplied Meet link —
-- a null meeting_url means both — so the distinction gets a column of its own
-- rather than being inferred from an absence.

create type meeting_mode as enum ('lekkside_room', 'external_link');

alter table appointments
  add column meeting_mode meeting_mode not null default 'lekkside_room';

-- Every appointment that already has a link was agreed as an external call.
-- Without this, ADD COLUMN ... DEFAULT would silently reclassify every
-- existing confirmed Zoom meeting as a room nobody is in.
update appointments set meeting_mode = 'external_link' where meeting_url is not null;

alter table appointments
  add constraint appointment_external_needs_url
  check (meeting_mode <> 'external_link'
         or status <> 'confirmed'
         or meeting_url is not null);

comment on column appointments.meeting_mode is
  'Where a video meeting is held. Defaults to lekkside_room now that there is '
  'one; external_link keeps Meet/Zoom/Teams available for an institution whose '
  'process depends on it.';

-- A student may reschedule or cancel. They may not decide where the meeting is
-- held. appointments_update_student is a whole-row policy, so without this a
-- student can set meeting_url to anything and the institution's console renders
-- it as a link to click. Found while adding meeting_mode: the new column made
-- the existing latitude worth closing rather than widening.
create or replace function guard_appointment_venue()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- No request context: a migration, the SQL editor, or a service-role Edge
  -- Function. Same reasoning as every other guard in 20251009000008.
  if auth.uid() is null or is_admin() then return new; end if;
  if is_member_of(new.institution_id) then return new; end if;

  if new.meeting_mode is distinct from old.meeting_mode
     or new.meeting_url is distinct from old.meeting_url then
    raise exception 'the institution decides where a meeting is held';
  end if;
  return new;
end;
$$;

create trigger appointments_guard_venue
  before update of meeting_mode, meeting_url on appointments
  for each row execute function guard_appointment_venue();

-- =============================================================== write paths
--
-- Every volatile function below opens with the null-uid guard from
-- 20251010000026. That migration exists because `v_author <> auth.uid()` is
-- null, not true, when there is no session — so a guard that reads as denying
-- anonymous callers did the opposite. The stable helpers carry an explicit
-- `auth.uid() is not null` predicate instead, which is belt and braces rather
-- than redundancy for the same reason.

-- ---------------------------------------------------------- joining a space

/**
 * Joins the caller, or returns the row they already have.
 *
 * Idempotent, because every token mint goes through it: a reconnect after a
 * tunnel, an app restart, and the second token a listener gets on becoming a
 * speaker must all land on the SAME participant row. That row's id is the
 * identity LiveKit knows them by, so a new one would read as a new person
 * arriving and would orphan every moderation event pointing at the old one.
 */
create or replace function join_space(p_space_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_space  spaces;
  v_row    space_participants;
  v_role   space_role;
  v_handle citext;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select * into v_space from spaces where id = p_space_id;
  if not found then raise exception 'no such space'; end if;

  if v_space.status = 'cancelled' then
    raise exception 'That session was cancelled.';
  end if;
  if v_space.status = 'ended' then
    raise exception 'That session has ended.';
  end if;

  -- The platform's existing gate. An account too restricted to post is too
  -- restricted for a microphone in a room with two hundred people in it.
  if is_restricted() then
    raise exception
      'Your account is restricted and cannot join a live session right now.';
  end if;

  select * into v_row from space_participants
   where space_id = p_space_id and profile_id = auth.uid();

  if found then
    if v_row.admission in ('removed', 'denied') then
      raise exception 'A host removed you from this session.';
    end if;
    update space_participants
       set joined_at = coalesce(joined_at, now()), left_at = null
     where id = v_row.id;
    return v_row.id;
  end if;

  -- Staff of the hosting institution are never listeners and never wait.
  v_role := case
    when v_space.host_profile_id = auth.uid() then 'host'
    when is_member_of(v_space.institution_id) or is_admin() then 'cohost'
    else 'listener'
  end::space_role;

  select handle into v_handle from social_profiles where profile_id = auth.uid();

  insert into space_participants
    (space_id, profile_id, role, admission, handle, joined_at, identified_at)
  values (
    p_space_id, auth.uid(), v_role,
    case when v_role = 'listener' and v_space.requires_admission
         then 'pending' else 'admitted' end::space_admission,
    v_handle,
    now(),
    -- Staff are identified by definition: their names are already visible to
    -- any signed-in user.
    case when v_role = 'listener' then null else now() end
  )
  returning * into v_row;

  -- A join is the start of a relationship, so the token is minted HERE, on a
  -- write. 20251010000031 is the migration about what happens when a read
  -- mints one; this is the other side of that lesson. It also means
  -- send-notification's existing match_tokens relationship check covers a
  -- student who has joined a Space, with no change to that function.
  perform ensure_match_token(auth.uid(), v_space.institution_id);

  return v_row.id;
end;
$$;

revoke all on function join_space(uuid) from public;
grant execute on function join_space(uuid) to authenticated;

-- ------------------------------------------ listening becomes participating

/**
 * The one consent step in the whole feature.
 *
 * Unmuting, enabling a camera, raising a hand and posting in the chat all come
 * through here, and all of them do the same thing: write an ordinary
 * passport_shares row. The same single gate as applying, booking and tapping
 * CONNECT at a booth — so the student's "who can see me" screen is complete by
 * construction and one revocation covers Spaces too.
 *
 * Idempotent: grant_passport_share() returns the live share when there is one,
 * and passport_shares_one_live would reject a second anyway.
 */
create or replace function identify_in_space(p_space_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_space spaces;
  v_row   space_participants;
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

  -- Already speaking, or staff: nothing left to consent to.
  if v_row.role <> 'listener' then return v_row.id; end if;

  -- The minor rule, reusing 20251010000020's own test rather than inventing a
  -- second one. A minor may listen to anyone; they may only put a camera and a
  -- microphone in front of an institution they have already chosen contact
  -- with, by following it, applying, or asking it for a meeting.
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
     set role = 'speaker', identified_at = coalesce(identified_at, now())
   where id = v_row.id;

  return v_row.id;
end;
$$;

revoke all on function identify_in_space(uuid) from public;
grant execute on function identify_in_space(uuid) to authenticated;

-- Raising a hand is asking to speak, and asking to speak identifies.
create or replace function raise_hand(p_space_id uuid, p_raised boolean default true)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_raised then perform identify_in_space(p_space_id); end if;
  update space_participants
     set hand_raised_at = case when p_raised then now() else null end
   where space_id = p_space_id and profile_id = auth.uid();
end;
$$;

revoke all on function raise_hand(uuid, boolean) from public;
grant execute on function raise_hand(uuid, boolean) to authenticated;

create or replace function leave_space(p_space_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  update space_participants
     set left_at = now(), hand_raised_at = null
   where space_id = p_space_id and profile_id = auth.uid();
end;
$$;

revoke all on function leave_space(uuid) from public;
grant execute on function leave_space(uuid) to authenticated;

-- ------------------------------------------------- going live, and moderating

create or replace function space_can_moderate(p_space_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from spaces s
     where s.id = p_space_id and (is_member_of(s.institution_id) or is_admin()));
$$;

revoke all on function space_can_moderate(uuid) from public;
grant execute on function space_can_moderate(uuid) to authenticated;

create or replace function space_set_status(p_space_id uuid, p_status space_status)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_institution uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select institution_id into v_institution from spaces where id = p_space_id;
  if v_institution is null then raise exception 'no such space'; end if;
  if not is_member_of(v_institution) and not is_admin() then
    raise exception 'that session is not yours to run';
  end if;
  if p_status = 'scheduled' then
    raise exception 'a session cannot be un-started';
  end if;

  update spaces
     set status     = p_status,
         started_at = case when p_status = 'live'
                           then coalesce(started_at, now()) else started_at end,
         ended_at   = case when p_status in ('ended', 'cancelled')
                           then coalesce(ended_at, now()) else ended_at end
   where id = p_space_id;

  insert into space_moderation_events (space_id, actor_id, action)
  values (p_space_id, auth.uid(),
          case when p_status = 'live' then 'started' else 'ended'
          end::space_moderation_action);
end;
$$;

revoke all on function space_set_status(uuid, space_status) from public;
grant execute on function space_set_status(uuid, space_status) to authenticated;

/**
 * A host acting on somebody in their room.
 *
 * Returns exactly what the Edge Function needs to carry the decision through to
 * LiveKit — the room name and the subject's identity — and nothing else. The
 * authorization is HERE rather than in TypeScript for two reasons: it is then
 * the same check supabase/tests/rls_test.mjs asserts, and the audit row lands
 * in the same transaction as the state change. A kick LiveKit performed and the
 * database did not record is a kick that did not happen.
 */
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
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select * into v_row from space_participants where id = p_participant_id;
  if not found then raise exception 'no such participant'; end if;

  select * into v_space from spaces where id = v_row.space_id;

  if not is_member_of(v_space.institution_id) and not is_admin() then
    raise exception 'that session is not yours to moderate';
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

  elsif p_action = 'muted' then
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
    update space_participants set role = 'speaker' where id = v_row.id;

  elsif p_action = 'demoted' then
    -- identified_at deliberately survives. Consent is a passport_shares row the
    -- student revokes from one place; losing the floor does not take it back.
    update space_participants
       set role = 'listener', hand_raised_at = null where id = v_row.id;

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
    'action',   p_action);
end;
$$;

revoke all on function space_moderate(uuid, space_moderation_action, text) from public;
grant execute on function space_moderate(uuid, space_moderation_action, text) to authenticated;

create or replace function remove_space_message(p_message_id uuid, p_reason text default null)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_space       uuid;
  v_participant uuid;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select space_id, participant_id into v_space, v_participant
    from space_messages where id = p_message_id;
  if v_space is null then raise exception 'no such message'; end if;
  if not space_can_moderate(v_space) then
    raise exception 'that session is not yours to moderate';
  end if;

  update space_messages set deleted_at = now()
   where id = p_message_id and deleted_at is null;

  insert into space_moderation_events
    (space_id, actor_id, subject_participant_id, action, reason)
  values (v_space, auth.uid(), v_participant, 'message_removed',
          nullif(trim(p_reason), ''));
end;
$$;

revoke all on function remove_space_message(uuid, text) from public;
grant execute on function remove_space_message(uuid, text) to authenticated;

-- ------------------------------------------ "am I in this room, and as what"
--
-- The explicit `auth.uid() is not null` is belt and braces: `profile_id =
-- auth.uid()` already returns no rows with a null uid. It is written anyway,
-- because 20251010000026 is the migration about a guard that read as though it
-- denied anonymous callers and did the opposite.

create or replace function my_space_participant(p_space_id uuid)
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
     and admission = 'admitted';
$$;

revoke all on function my_space_participant(uuid) from public;
grant execute on function my_space_participant(uuid) to authenticated;

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
     and role in ('host', 'cohost', 'speaker');
$$;

revoke all on function my_speaking_participant(uuid) from public;
grant execute on function my_speaking_participant(uuid) to authenticated;

create or replace function is_my_space_participant(p_participant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from space_participants
     where id = p_participant_id and profile_id = auth.uid());
$$;

revoke all on function is_my_space_participant(uuid) from public;
grant execute on function is_my_space_participant(uuid) to authenticated;

-- ================================================================ the grants
--
-- Everything the token function needs, decided here. The Edge Function makes NO
-- authorization decision of its own: it calls one of these as the caller, under
-- the caller's own RLS, and signs whatever comes back. The only thing it adds
-- is an HMAC — the one part Postgres cannot do here, because this schema
-- deliberately does not require pgcrypto.
--
-- `display_name` is decided server-side so that no client can put a name of
-- its choosing on its own video.

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

  v_speaks := v_row.role in ('host', 'cohost', 'speaker');

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
    -- name a student already sees on their messages.
    'display_name', case
      when v_row.role in ('host', 'cohost')
        then (select pr.full_name from profiles pr where pr.id = v_row.profile_id)
      else '@' || coalesce(v_row.handle::text, 'student')
    end,

    'can_publish',      v_speaks,
    'can_publish_data', v_speaks,
    'can_subscribe',    true,
    -- A speaker gets a mic and a camera and NOT screen share: a student
    -- screen-sharing into a two-hundred-person admissions hour is a moderation
    -- problem nobody asked for.
    'publish_sources', case
      when v_row.role in ('host', 'cohost')
        then jsonb_build_array('microphone', 'camera', 'screen_share', 'screen_share_audio')
      when v_row.role = 'speaker'
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

create or replace function appointment_room_grant(p_appointment_id uuid)
returns jsonb
language plpgsql
stable                   -- nothing to upsert: both parties already exist
security definer
set search_path = public
as $$
declare
  a            appointments;
  v_is_student boolean;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;

  select * into a from appointments where id = p_appointment_id;
  if not found then raise exception 'no such appointment'; end if;

  v_is_student := a.student_id = auth.uid();
  if not (v_is_student or is_member_of(a.institution_id) or is_admin()) then
    raise exception 'that meeting is not yours';
  end if;

  if a.channel <> 'video' or a.meeting_mode <> 'lekkside_room' then
    raise exception 'that meeting is not held in a Lekkside room';
  end if;
  if a.status <> 'confirmed' then
    raise exception 'that meeting has not been confirmed yet';
  end if;

  -- The same window the student app's join button has always used: ten minutes
  -- early, fifteen past the end (Appointment.canJoinNow).
  if a.scheduled_for is null
     or now() < a.scheduled_for - interval '10 minutes'
     or now() > a.scheduled_for + make_interval(mins => a.duration_min + 15) then
    return jsonb_build_object(
      'admission', 'closed',
      'opens_at',  a.scheduled_for - interval '10 minutes');
  end if;

  return jsonb_build_object(
    'admission', 'admitted',
    'kind',      'appointment',
    'room',      'appt_' || a.id::text,
    -- Not a profiles.id, even here. Requesting the meeting already wrote the
    -- passport share (share_on_appointment, 20251009000006), so both sides are
    -- named to each other — but the private account id still never leaves the
    -- server, and a LiveKit identity leaves the server.
    'identity',  'ap_' || a.id::text
                 || case when v_is_student then '_s' else '_h' end,
    'display_name', (select pr.full_name from profiles pr where pr.id = auth.uid()),
    'role',    case when v_is_student then 'speaker' else 'host' end,
    'is_host', not v_is_student,
    'can_publish', true, 'can_publish_data', true, 'can_subscribe', true,
    'publish_sources',
      jsonb_build_array('microphone', 'camera', 'screen_share', 'screen_share_audio'),
    'appointment', jsonb_build_object(
      'id',             a.id,
      'scheduled_for',  a.scheduled_for,
      'duration_min',   a.duration_min,
      'institution_id', a.institution_id,
      -- So the call screen knows where its chat lives without a second query.
      'conversation_id', (select c.id from conversations c
                           where c.student_id = a.student_id
                             and c.institution_id = a.institution_id),
      'institution', (select name from institutions where id = a.institution_id)),
    'ttl_seconds', greatest(3600, (a.duration_min + 45) * 60));
end;
$$;

revoke all on function appointment_room_grant(uuid) from public;
grant execute on function appointment_room_grant(uuid) to authenticated;

-- ------------------------------------------------- local/hosted agreement
--
-- The lesson of 20251010000025, which has to be repeated by every migration
-- that adds a function.
--
-- The test shim sets `alter default privileges ... grant execute on functions
-- to anon` *before* the migrations run, so every function above picked up an
-- explicit anon grant at creation — and `revoke all ... from public` does not
-- touch a named role's own privilege. Hosted Supabase grants anon nothing, so
-- without this the two environments would disagree about who can call
-- join_space(), and the null-uid guards would be the only thing between an
-- anonymous caller and a consent row. Defence in depth is the point; it is not
-- supposed to be the only defence.
revoke execute on all functions in schema public from anon;
