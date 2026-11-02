-- Lekkside Connect — comment threading and comment removal
--
-- Ensures replying to a comment or a reply correctly resolves to the thread root,
-- validating the parent comment belongs to the post and is not deleted.
-- Also provides remove_comment() for author or admin removal.

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
  v_effective_parent uuid := null;
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

  if p_parent_id is not null then
    -- Verify the parent comment exists and belongs to this post
    -- If replying to an existing reply, attach to the root comment so threading stays 1-level deep
    select coalesce(parent_id, id) into v_effective_parent
      from comments
     where id = p_parent_id and post_id = p_post_id and deleted_at is null;

    if v_effective_parent is null then
      raise exception 'The comment you are replying to no longer exists.';
    end if;
  end if;

  insert into comments (post_id, author_id, parent_id, body)
  values (p_post_id, auth.uid(), v_effective_parent, trim(p_body))
  returning id into v_comment;

  return v_comment;
end;
$$;

create or replace function remove_comment(p_comment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
begin
  select author_id into v_author from comments where id = p_comment_id and deleted_at is null;
  if v_author is null then
    raise exception 'no such comment';
  end if;

  if v_author <> auth.uid() and not is_admin() then
    raise exception 'not your comment';
  end if;

  update comments set deleted_at = now() where id = p_comment_id;
  return true;
end;
$$;

revoke all on function remove_comment(uuid) from public;
grant execute on function remove_comment(uuid) to authenticated;
