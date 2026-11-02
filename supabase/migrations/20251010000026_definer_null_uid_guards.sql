-- Anonymous callers cannot reach the write paths.
--
-- `remove_post()` could be called with the anon key and would delete any post
-- on the platform, along with every repost of it. The anon key ships inside
-- the app, so this was reachable by anyone who had installed it.
--
-- The cause is SQL's three-valued logic, not a missing policy:
--
--     if v_author <> auth.uid() and not is_admin() then
--       raise exception 'not your post';
--     end if;
--
-- With no session, `auth.uid()` is null, so `v_author <> null` is **null** —
-- not true. `null and true` is null, `if null then` does not fire, and
-- execution falls straight through to the delete. The guard reads as though it
-- denies anonymous callers and does the opposite.
--
-- `revoke all on function remove_post from public` did not help: `anon` is a
-- named role holding its own privilege, granted by the `alter default
-- privileges ... grant execute on functions to anon` that both hosted Supabase
-- and the test shim set up. Revoking from PUBLIC leaves that grant untouched.
--
-- Every other write path was checked by calling it as `anon` with valid
-- arguments. `create_post`, `comment_on_post`, `repost`, `claim_handle` and
-- `create_institution` all raise 'authentication required' through their own
-- guards or through `assert_can_write()`; the three `institution_*` functions
-- raise 'that token was not issued to your institution'; inserting a report
-- fails RLS; direct UPDATE and DELETE on `posts` affect zero rows.
--
-- `follow_handle` and `moderate_handle` were also refused, but only because
-- `follows.follower_id` and `blocks.blocker_id` are NOT NULL — an accident of
-- the schema rather than a decision, and one that would evaporate the moment a
-- column became nullable. They get explicit guards too.

create or replace function remove_post(p_post_id uuid, p_reason text default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author  uuid;
  v_removed int;
begin
  -- First, and before anything is compared against it: every check below is an
  -- expression involving auth.uid(), and all of them evaluate to null rather
  -- than to true when there is no session.
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select author_id into v_author from posts where id = p_post_id;
  if v_author is null then
    raise exception 'no such post';
  end if;

  if v_author <> auth.uid() and not is_admin() then
    raise exception 'not your post';
  end if;

  -- A removal has to take the reposts with it, or the content stays standing
  -- exactly where it spread.
  update posts set deleted_at = now()
   where (id = p_post_id or repost_of = p_post_id)
     and deleted_at is null;
  get diagnostics v_removed = row_count;

  if p_reason is not null then
    update reports
       set status = 'verified', review_note = p_reason,
           reviewer_id = auth.uid(), decided_at = now()
     where subject_type = 'post' and subject_id = p_post_id
       and status = 'pending';
  end if;

  return v_removed;
end;
$$;

revoke all on function remove_post(uuid, text) from public;
grant execute on function remove_post(uuid, text) to authenticated;

create or replace function follow_handle(p_handle text, p_follow boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select profile_id into v_target
    from social_profiles where handle = lower(trim(p_handle));

  if v_target is null then
    raise exception 'no such handle';
  end if;
  if v_target = auth.uid() then
    raise exception 'You cannot follow yourself.';
  end if;

  if p_follow then
    insert into follows (follower_id, followee_id)
    values (auth.uid(), v_target) on conflict do nothing;
  else
    delete from follows
     where follower_id = auth.uid() and followee_id = v_target;
  end if;
end;
$$;

revoke all on function follow_handle(text, boolean) from public;
grant execute on function follow_handle(text, boolean) to authenticated;

create or replace function moderate_handle(
  p_handle text,
  p_action text  -- 'block' | 'unblock' | 'mute' | 'unmute'
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
    raise exception 'authentication required';
  end if;

  select profile_id into v_target
    from social_profiles where handle = lower(trim(p_handle));
  if v_target is null then
    raise exception 'no such handle';
  end if;
  if v_target = auth.uid() then
    raise exception 'That is you.';
  end if;

  if p_action = 'block' then
    insert into blocks (blocker_id, blocked_id)
    values (auth.uid(), v_target) on conflict do nothing;
    -- Blocking severs the follow in both directions, as it must.
    delete from follows
     where (follower_id = auth.uid() and followee_id = v_target)
        or (follower_id = v_target and followee_id = auth.uid());

  elsif p_action = 'unblock' then
    delete from blocks where blocker_id = auth.uid() and blocked_id = v_target;

  elsif p_action = 'mute' then
    insert into mutes (muter_id, muted_id)
    values (auth.uid(), v_target) on conflict do nothing;

  elsif p_action = 'unmute' then
    delete from mutes where muter_id = auth.uid() and muted_id = v_target;

  else
    raise exception 'unknown action %', p_action;
  end if;
end;
$$;

revoke all on function moderate_handle(text, text) from public;
grant execute on function moderate_handle(text, text) to authenticated;
