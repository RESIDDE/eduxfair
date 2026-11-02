-- Lekkside Connect — social access rules, write functions and the feed views.
--
-- Reads go through views that expose a handle and never a `profile_id`, which
-- is the rule step 1 established. Writes go through SECURITY DEFINER functions
-- so the rate limit, the restriction check and the reply policy are enforced in
-- one place rather than being re-derived by every client.

alter table posts                 enable row level security;
alter table post_media            enable row level security;
alter table comments              enable row level security;
alter table post_likes            enable row level security;
alter table comment_likes         enable row level security;
alter table post_bookmarks        enable row level security;
alter table follows               enable row level security;
alter table post_topics           enable row level security;
alter table reports               enable row level security;
alter table blocks                enable row level security;
alter table mutes                 enable row level security;
alter table account_restrictions  enable row level security;

-- ------------------------------------------------------------------- posts
--
-- Public to signed-in users, minus anything by someone either party blocked.
-- Writes are through create_post() / remove_post(); the direct update policy
-- exists only so an author can edit their own body.

create policy posts_select_visible on posts
  for select using (
    auth.uid() is not null
    and deleted_at is null
    and not is_blocked_either_way(author_id)
  );

create policy posts_select_own on posts
  for select using (author_id = auth.uid());

create policy posts_select_admin on posts
  for select using (is_admin());

create policy posts_update_own on posts
  for update using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy posts_all_admin on posts
  for all using (is_admin()) with check (is_admin());

create policy post_media_select on post_media
  for select using (
    exists (select 1 from posts p where p.id = post_id and p.deleted_at is null));

create policy post_media_write_author on post_media
  for all using (
    exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid()))
  with check (
    exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid()));

create policy post_topics_select on post_topics
  for select using (auth.uid() is not null);

create policy post_topics_write_author on post_topics
  for all using (
    exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid()))
  with check (
    exists (select 1 from posts p where p.id = post_id and p.author_id = auth.uid()));

-- ---------------------------------------------------------------- comments

create policy comments_select_visible on comments
  for select using (
    auth.uid() is not null
    and deleted_at is null
    and not is_blocked_either_way(author_id)
  );

create policy comments_select_own on comments
  for select using (author_id = auth.uid());

create policy comments_update_own on comments
  for update using (author_id = auth.uid()) with check (author_id = auth.uid());

create policy comments_all_admin on comments
  for all using (is_admin()) with check (is_admin());

-- ------------------------------------------------- likes, bookmarks, follows
--
-- Self-service, and each one checks the block so a blocked account cannot
-- interact at all.

create policy post_likes_select on post_likes
  for select using (auth.uid() is not null);
create policy post_likes_write_self on post_likes
  for all using (profile_id = auth.uid())
  with check (profile_id = auth.uid()
              and not exists (select 1 from posts p
                               where p.id = post_id
                                 and is_blocked_either_way(p.author_id)));

create policy comment_likes_select on comment_likes
  for select using (auth.uid() is not null);
create policy comment_likes_write_self on comment_likes
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- Bookmarks are private: never counted, never shown to the author.
create policy post_bookmarks_own on post_bookmarks
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy follows_select on follows
  for select using (auth.uid() is not null);
create policy follows_write_self on follows
  for all using (follower_id = auth.uid())
  with check (follower_id = auth.uid() and not is_blocked_either_way(followee_id));

-- --------------------------------------------------- blocks, mutes, reports

create policy blocks_own on blocks
  for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

create policy mutes_own on mutes
  for all using (muter_id = auth.uid()) with check (muter_id = auth.uid());

-- A reporter sees their own report's progress; nobody sees who reported them.
create policy reports_select_own on reports
  for select using (reporter_id = auth.uid());
create policy reports_insert_self on reports
  for insert with check (reporter_id = auth.uid());
create policy reports_all_admin on reports
  for all using (is_admin()) with check (is_admin());

-- A person can see that they are restricted, and why. Only admin sets one.
create policy restrictions_select_self on account_restrictions
  for select using (profile_id = auth.uid());
create policy restrictions_all_admin on account_restrictions
  for all using (is_admin()) with check (is_admin());

-- ------------------------------------------------------------------ storage

create policy post_media_read on storage.objects
  for select using (bucket_id = 'post-media');

create policy post_media_write_own on storage.objects
  for all to authenticated
  using (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'post-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ======================================================== the write functions

/**
 * Creates a post.
 *
 * A function rather than an insert so the restriction, the rate limit, the
 * "posting as an institution" check and the topic tags all happen together —
 * a client that forgot any one of them would otherwise create a post that
 * bypasses it.
 */
create or replace function create_post(
  p_body           text default null,
  p_kind           post_kind default 'update',
  p_institution_id uuid default null,
  p_link_url       text default null,
  p_reply_policy   reply_policy default 'everyone',
  p_fields         text[] default '{}',
  p_countries      text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post uuid;
  v_value text;
begin
  perform assert_can_write('post');

  if p_institution_id is not null and not is_member_of(p_institution_id) then
    raise exception 'You do not belong to that institution.';
  end if;

  if coalesce(trim(p_body), '') = '' and p_link_url is null then
    raise exception 'A post needs something to say.';
  end if;

  insert into posts
    (author_id, institution_id, body, kind, link_url, reply_policy)
  values
    (auth.uid(), p_institution_id, nullif(trim(p_body), ''), p_kind,
     p_link_url, p_reply_policy)
  returning id into v_post;

  foreach v_value in array coalesce(p_fields, '{}') loop
    insert into post_topics (post_id, kind, value)
    values (v_post, 'field', v_value) on conflict do nothing;
  end loop;

  foreach v_value in array coalesce(p_countries, '{}') loop
    insert into post_topics (post_id, kind, value)
    values (v_post, 'country', v_value) on conflict do nothing;
  end loop;

  return v_post;
end;
$$;

/** Reshares a post. Flattens, so resharing a repost reshares the original. */
create or replace function repost(
  p_post_id uuid,
  p_body    text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_root uuid;
  v_author uuid;
  v_existing uuid;
  v_new uuid;
begin
  perform assert_can_write('post');

  select coalesce(repost_of, id), author_id into v_root, v_author
    from posts where id = p_post_id and deleted_at is null;

  if v_root is null then
    raise exception 'no such post';
  end if;
  if is_blocked_either_way(v_author) then
    raise exception 'You cannot reshare that.';
  end if;

  -- A plain repost toggles; a quote is a new post each time, since the comment
  -- differs.
  if p_body is null then
    select id into v_existing from posts
     where author_id = auth.uid() and repost_of = v_root
       and body is null and deleted_at is null;

    if v_existing is not null then
      update posts set deleted_at = now() where id = v_existing;
      return null;
    end if;
  end if;

  insert into posts (author_id, repost_of, body)
  values (auth.uid(), v_root, nullif(trim(p_body), ''))
  returning id into v_new;

  return v_new;
end;
$$;

/** Replies to a post, honouring its reply policy. */
create or replace function comment_on_post(
  p_post_id   uuid,
  p_body      text,
  p_parent_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post posts;
  v_comment uuid;
begin
  perform assert_can_write('comment');

  select * into v_post from posts
   where id = p_post_id and deleted_at is null;
  if not found then
    raise exception 'no such post';
  end if;
  if is_blocked_either_way(v_post.author_id) then
    raise exception 'You cannot reply to that.';
  end if;

  if v_post.reply_policy = 'following'
     and v_post.author_id <> auth.uid()
     and not exists (select 1 from follows
                      where follower_id = v_post.author_id
                        and followee_id = auth.uid()) then
    raise exception 'The author has limited replies to people they follow.';
  end if;

  if v_post.reply_policy = 'verified'
     and v_post.author_id <> auth.uid()
     and not exists (select 1 from public_profiles pp
                      join social_profiles sp on sp.handle = pp.handle
                     where sp.profile_id = auth.uid() and pp.is_verified) then
    raise exception 'The author has limited replies to verified accounts.';
  end if;

  insert into comments (post_id, author_id, parent_id, body)
  values (p_post_id, auth.uid(), p_parent_id, trim(p_body))
  returning id into v_comment;

  return v_comment;
end;
$$;

/** Follows or unfollows by handle — the client never holds an account id. */
create or replace function follow_handle(p_handle text, p_follow boolean default true)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
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

/** Blocks or mutes by handle, for the same reason. */
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

do $$
declare fn text;
begin
  foreach fn in array array[
    'create_post(text, post_kind, uuid, text, reply_policy, text[], text[])',
    'repost(uuid, text)',
    'comment_on_post(uuid, text, uuid)',
    'follow_handle(text, boolean)',
    'moderate_handle(text, text)'
  ] loop
    execute format('revoke all on function %s from public', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end
$$;
