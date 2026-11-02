-- "Take back the floor" has to mean it.
--
-- Demoting set role = 'listener' and LiveKit revoked publishing, both
-- correctly. Then the student tapped unmute, the app did what it does for any
-- listener — offered the consent sheet — and accepting called
-- identify_in_space(), which promoted any listener to speaker without knowing
-- a host had just taken the floor away. Two taps, no host involved, and the
-- only trace was the `demoted` row in the audit log.
--
-- That is not a moderation action, it is a suggestion. So the promotion in
-- identify_in_space() now asks whether the floor is being withheld, and the
-- only way back is the host's own "Give them the floor".
--
-- Deliberately NOT a column on space_participants. The events table already
-- holds this history, is append-only for every role including admin, and is
-- the thing a student could later dispute. A boolean beside the role would be
-- a second source of truth that a future UPDATE could silently disagree with.

create or replace function space_floor_withheld(p_participant_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- Withheld when the newest 'demoted' is newer than anything that gave the
  -- floor back. Comparing the two rather than merely looking for a demotion
  -- is what lets a host demote, relent, and demote again.
  select exists (
    select 1
      from space_moderation_events e
     where e.subject_participant_id = p_participant_id
       and e.action = 'demoted'
       and e.created_at > coalesce((
             select max(g.created_at)
               from space_moderation_events g
              where g.subject_participant_id = p_participant_id
                and g.action in ('promoted', 'moderator_granted')),
           '-infinity'::timestamptz));
$$;

comment on function space_floor_withheld(uuid) is
  'True when a host has taken this participant''s floor and not given it back. '
  'Read by identify_in_space(), so that consenting again cannot undo a '
  'demotion the host has not reversed.';

revoke all on function space_floor_withheld(uuid) from public;
grant execute on function space_floor_withheld(uuid) to authenticated;

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

  -- Checked BEFORE grant_passport_share(), so a refused promotion does not
  -- leave a new share behind for something that did not happen.
  if v_row.role = 'listener' and space_floor_withheld(v_row.id) then
    raise exception
      'A host took back the floor in this session, so speaking in it is up to '
      'them now.';
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
