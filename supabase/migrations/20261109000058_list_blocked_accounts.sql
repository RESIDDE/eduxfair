-- The rest of the safety surface: seeing who you have blocked, undoing it,
-- and reporting a person rather than only a post.
--
-- `moderate_handle` has supported 'unblock' and 'unmute' since the moderation
-- migration, but nothing could list them, so a block was a one-way door: you
-- could stop seeing someone and never take it back.
--
-- App Review guideline 1.2 requires "the ability to block abusive users". A
-- block you cannot review or reverse meets the letter of that and fails the
-- person who mis-tapped it, so this is the other half.

create or replace function my_blocked_accounts()
returns table (
  handle       citext,
  display_name text,
  avatar_url   text,
  kind         text,         -- 'block' | 'mute'
  created_at   timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  -- Blocks and mutes are separate tables because they mean different things:
  -- a block is mutual invisibility, a mute only hides someone from your feed.
  -- They are listed together because from the student's side it is one
  -- question — "who have I silenced?" — and two screens would hide the
  -- lighter option from anyone who only knew about the heavier one.
  select sp.handle, sp.display_name, sp.avatar_url, 'block'::text, b.created_at
    from blocks b
    join social_profiles sp on sp.profile_id = b.blocked_id
   where b.blocker_id = auth.uid()

  union all

  select sp.handle, sp.display_name, sp.avatar_url, 'mute'::text, m.created_at
    from mutes m
    join social_profiles sp on sp.profile_id = m.muted_id
   where m.muter_id = auth.uid()

   order by created_at desc;
$$;

comment on function my_blocked_accounts() is
  'Accounts the caller has blocked or muted. SECURITY DEFINER so it can read '
  'social_profiles, which has no public select policy; the auth.uid() filter '
  'is what keeps it to the caller''s own list.';

-- Signed out there is no list, and auth.uid() would be null — which would
-- return nothing rather than everything, but there is no reason to allow the
-- call at all.
revoke all on function my_blocked_accounts() from public, anon;
grant execute on function my_blocked_accounts() to authenticated;


-- ───────────────────────────────────────────────────── reporting a person

-- `reports` already accepts a 'profile' subject, but nothing could file one,
-- because the client has no profile id to name: social_profiles.profile_id is
-- never exposed by any public view, which is the point of the identity split.
-- Resolving the handle in here keeps that intact — the caller names a handle,
-- the id never leaves the database.
create or replace function report_handle(
  p_handle text,
  p_reason report_reason,
  p_note   text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in to report';
  end if;

  select profile_id into v_target
    from social_profiles
   where handle = lower(trim(p_handle));

  if v_target is null then
    raise exception 'no such account';
  end if;

  if v_target = auth.uid() then
    raise exception 'you cannot report yourself';
  end if;

  -- One open report per person per subject, as everywhere else. A second
  -- report updates the first rather than stacking duplicates in the queue —
  -- which also means someone cannot bury a moderator in noise.
  insert into reports (reporter_id, subject_type, subject_id, reason, note)
  values (auth.uid(), 'profile', v_target, p_reason, p_note)
  on conflict (reporter_id, subject_type, subject_id)
  do update set reason = excluded.reason,
                note   = excluded.note,
                status = 'pending',
                created_at = now();
end;
$$;

comment on function report_handle(text, report_reason, text) is
  'Files a report against an account by handle. SECURITY DEFINER so the '
  'handle can be resolved to a profile id without that id ever reaching the '
  'client.';

revoke all on function report_handle(text, report_reason, text) from public, anon;
grant execute on function report_handle(text, report_reason, text) to authenticated;
