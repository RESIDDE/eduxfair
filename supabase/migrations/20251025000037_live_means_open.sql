-- A live room is open, and its host is never locked out of it.
--
-- space_is_open() applied one window to everybody:
--
--     now() >= scheduled_for - 10 min  and  now() < scheduled_for + duration + 30
--
-- which is right for an audience and wrong for the two cases that matter most.
--
-- Found on the real project. A Space scheduled for the 28th was taken LIVE on
-- the 25th, and then refused every join — including its own host's:
--
--     HIIJKKJ   status = live   scheduled_for = 2026-10-28   space_is_open = false
--
-- The host saw "This room is not open yet" about a room they had just opened.
--
-- Two corrections:
--
--   1. `live` means open. The moment a host goes live the schedule stops being
--      the authority — they have said, with a button, that it is happening now.
--      A session that starts early, runs long, or was scheduled loosely should
--      not be shut by arithmetic nobody is looking at.
--
--   2. Staff of the hosting institution are never shut out of their own room,
--      whatever the clock says. They open it to set up before the hour and stay
--      after it to answer the last question. Needing authorisation to enter a
--      room you are hosting is not a safety property, it is a bug.
--
-- The audience keeps the window exactly as before, so a scheduled session is
-- still not joinable days ahead of time.

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
       and (
         -- A host has opened the doors.
         s.status = 'live'
         -- ...or this is their own room.
         or is_member_of(s.institution_id)
         or is_admin()
         -- Everyone else: ten minutes early, thirty past the end.
         or (now() >= s.scheduled_for - interval '10 minutes'
             and now() <  s.scheduled_for + make_interval(mins => s.duration_min + 30))
       ));
$$;

revoke all on function space_is_open(uuid) from public;
grant execute on function space_is_open(uuid) to authenticated;

-- ------------------------------------------------- telling people it started
--
-- A live session nobody knows about is a room with a host in it. Students who
-- follow an institution already asked to hear from it, so going live notifies
-- them — once, on the transition, and never again for the same session.
--
-- A trigger rather than a call inside livekit-room, for the reason the rest of
-- this schema prefers triggers: there are two clients that can start a session
-- and a third (the admin console) that can end one, and a notification that
-- depends on which button was pressed is a notification that goes missing.
--
-- `notifications` is already in the realtime publication, so the student app
-- receives this without polling.
create or replace function notify_followers_space_live()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution text;
begin
  -- Only the transition into 'live'. An update that leaves it live — a title
  -- edit mid-session — must not notify again.
  if new.status <> 'live' or old.status = 'live' then
    return new;
  end if;

  select name into v_institution from institutions where id = new.institution_id;

  -- Students follow an institution by following the profile that holds its
  -- handle, which is what social_profiles.institution_id marks.
  insert into notifications (profile_id, kind, title, body, payload)
  select
    f.follower_id,
    'space_live',
    coalesce(v_institution, 'An institution') || ' is live',
    new.title,
    jsonb_build_object(
      'space_id', new.id,
      'institution_id', new.institution_id,
      'kind', new.kind,
      'duration_min', new.duration_min)
  from follows f
  join social_profiles sp on sp.profile_id = f.followee_id
  join profiles p on p.id = f.follower_id
  where sp.institution_id = new.institution_id
    -- Staff of the institution are in the room already.
    and p.role = 'student'
    -- A restricted account cannot join, so telling it to is a dead end.
    and not is_restricted(f.follower_id);

  return new;
end;
$$;

create trigger spaces_notify_live
  after update of status on spaces
  for each row execute function notify_followers_space_live();

comment on function notify_followers_space_live is
  'Tells a student that an institution they follow has gone live. Fires only on '
  'the transition into `live`, so editing a session mid-flight does not notify '
  'twice.';
