-- Lekkside Connect — the feed.
--
-- One base view resolving a post to its author's handle, plus three functions
-- selecting from it. Deliberately NOT `security_invoker`: an invoker view would
-- inherit `social_profiles`' owner-only policy and return nothing at all, so
-- each does its own filtering and simply has no `profile_id` column to leak.
--
-- `security_barrier` stops the planner pushing a caller-supplied predicate
-- underneath that filtering, which is the classic way such a view leaks.

create view feed_posts
with (security_barrier = true)
as
select
  p.id,
  p.kind,
  p.body,
  p.link_url,
  p.reply_policy,
  p.like_count,
  p.comment_count,
  p.repost_count,
  p.pinned_at,
  p.created_at,
  p.edited_at,

  -- The author, by handle. No account id anywhere in this view.
  coalesce(inst_sp.handle, sp.handle)                 as author_handle,
  coalesce(i.name, sp.display_name)                   as author_name,
  coalesce(i.logo_url, sp.avatar_url)                 as author_avatar,
  case when p.institution_id is not null
       then (case when i.kind = 'embassy' then 'embassy' else 'institution' end)
       else sp.kind::text end                         as author_kind,
  case
    when p.institution_id is not null then i.verification_status = 'verified'
    else coalesce(
      (select pass.verification_status = 'verified'
         from student_passports pass where pass.profile_id = p.author_id),
      false)
  end                                                 as author_verified,
  i.country                                           as author_country,

  -- The reshared post, flattened into the row so the card needs one query.
  p.repost_of,
  case when p.repost_of is not null then
    (select jsonb_build_object(
       'id', o.id,
       'body', o.body,
       'kind', o.kind,
       'created_at', o.created_at,
       'like_count', o.like_count,
       'comment_count', o.comment_count,
       'repost_count', o.repost_count,
       'author_handle', coalesce(osp_inst.handle, osp.handle),
       'author_name', coalesce(oi.name, osp.display_name),
       'author_avatar', coalesce(oi.logo_url, osp.avatar_url),
       'author_verified', case
         when o.institution_id is not null
           then oi.verification_status = 'verified'
         else false end,
       'media', (select coalesce(jsonb_agg(jsonb_build_object(
                    'storage_path', m.storage_path, 'alt_text', m.alt_text)
                    order by m.ord), '[]'::jsonb)
                   from post_media m where m.post_id = o.id))
       from posts o
       left join social_profiles osp on osp.profile_id = o.author_id
       left join institutions oi on oi.id = o.institution_id
       left join social_profiles osp_inst
              on osp_inst.institution_id = o.institution_id
      where o.id = p.repost_of and o.deleted_at is null)
  end                                                 as reposted,

  (select coalesce(jsonb_agg(jsonb_build_object(
            'storage_path', m.storage_path,
            'alt_text', m.alt_text,
            'width', m.width,
            'height', m.height) order by m.ord), '[]'::jsonb)
     from post_media m where m.post_id = p.id)        as media,

  (select coalesce(jsonb_agg(jsonb_build_object('kind', t.kind, 'value', t.value)),
          '[]'::jsonb)
     from post_topics t where t.post_id = p.id)       as topics,

  -- What this reader has done with it, so the card renders in the right state.
  exists (select 1 from post_likes l
           where l.post_id = p.id and l.profile_id = auth.uid())    as liked,
  exists (select 1 from post_bookmarks b
           where b.post_id = p.id and b.profile_id = auth.uid())    as bookmarked,
  exists (select 1 from posts r
           where r.repost_of = coalesce(p.repost_of, p.id)
             and r.author_id = auth.uid()
             and r.body is null and r.deleted_at is null)           as reposted_by_me,
  p.author_id = auth.uid()                                          as is_mine,

  -- Private to the row; the API never selects it, and the functions below
  -- filter on it. Dropping it would mean re-joining posts to apply mutes.
  p.author_id                                        as _author_id,
  p.institution_id                                   as _institution_id

from posts p
left join social_profiles sp on sp.profile_id = p.author_id
left join institutions i on i.id = p.institution_id
left join social_profiles inst_sp on inst_sp.institution_id = p.institution_id
where p.deleted_at is null
  and auth.uid() is not null
  -- A block hides both parties from each other, everywhere.
  and not is_blocked_either_way(p.author_id)
  -- A reshare of something removed should vanish with it, not leave a hole.
  and (p.repost_of is null
       or exists (select 1 from posts o
                   where o.id = p.repost_of and o.deleted_at is null));

comment on view feed_posts is
  'Posts resolved to their author''s handle. Carries no public profile_id: the '
  'two underscore-prefixed columns exist for the feed functions to filter on '
  'and are never selected by a client.';

revoke all on feed_posts from public;
grant select on feed_posts to authenticated;

-- ------------------------------------------------------------- the three feeds

/**
 * For you.
 *
 * Built from the passport the student already filled in — their target fields
 * and destinations — so someone who follows nobody still opens a feed that is
 * about them. That is the whole reason `post_topics` reuses
 * `fields_of_study` rather than inventing a tag vocabulary.
 */
create or replace function feed_for_you(
  p_limit  int default 30,
  p_before timestamptz default null
)
returns setof feed_posts
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select coalesce(target_fields, '{}') as fields,
           coalesce(target_countries, '{}') as countries
      from student_passports where profile_id = auth.uid()
  )
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and (
       -- Anything tagged with something they said they want.
       exists (
         select 1 from post_topics t, me
          where t.post_id = f.id
            and ((t.kind = 'field'   and t.value = any (me.fields))
              or (t.kind = 'country' and t.value = any (me.countries))))
       -- Institutions in a country they are targeting, so a new institution
       -- is discoverable before anyone has tagged anything.
       or exists (
         select 1 from institutions i, me
          where i.id = f._institution_id and i.country = any (me.countries))
       -- And anyone they follow, so the tab is never emptier than Following.
       or exists (
         select 1 from follows fl
          where fl.follower_id = auth.uid() and fl.followee_id = f._author_id)
     )
   order by f.pinned_at desc nulls last, f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

create or replace function feed_following(
  p_limit  int default 30,
  p_before timestamptz default null
)
returns setof feed_posts
language sql
stable
security definer
set search_path = public
as $$
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and (
       exists (select 1 from follows fl
                where fl.follower_id = auth.uid()
                  and fl.followee_id = f._author_id)
       or f._author_id = auth.uid()
     )
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

/** One topic tab: a field of study, or a destination country. */
create or replace function feed_by_topic(
  p_kind   topic_kind,
  p_value  text,
  p_limit  int default 30,
  p_before timestamptz default null
)
returns setof feed_posts
language sql
stable
security definer
set search_path = public
as $$
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and (
       exists (select 1 from post_topics t
                where t.post_id = f.id and t.kind = p_kind and t.value = p_value)
       or (p_kind = 'country'
           and exists (select 1 from institutions i
                        where i.id = f._institution_id and i.country = p_value))
     )
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

/** One account's posts, for a profile page. Mutes do not apply here. */
create or replace function feed_by_handle(
  p_handle text,
  p_limit  int default 30,
  p_before timestamptz default null
)
returns setof feed_posts
language sql
stable
security definer
set search_path = public
as $$
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and f._author_id = (select profile_id from social_profiles
                          where handle = lower(trim(p_handle)))
   order by f.pinned_at desc nulls last, f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

/** A single post, for the detail screen. */
create or replace function post_by_id(p_post_id uuid)
returns setof feed_posts
language sql
stable
security definer
set search_path = public
as $$
  select * from feed_posts where id = p_post_id;
$$;

/** Replies, oldest first, resolved to handles the same way. */
create or replace function post_comments(p_post_id uuid, p_limit int default 100)
returns table (
  id              uuid,
  parent_id       uuid,
  body            text,
  like_count      int,
  created_at      timestamptz,
  author_handle   citext,
  author_name     text,
  author_avatar   text,
  author_verified boolean,
  liked           boolean,
  is_mine         boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.parent_id,
    c.body,
    c.like_count,
    c.created_at,
    sp.handle,
    sp.display_name,
    sp.avatar_url,
    coalesce((select pass.verification_status = 'verified'
                from student_passports pass
               where pass.profile_id = c.author_id), false),
    exists (select 1 from comment_likes cl
             where cl.comment_id = c.id and cl.profile_id = auth.uid()),
    c.author_id = auth.uid()
  from comments c
  join social_profiles sp on sp.profile_id = c.author_id
 where c.post_id = p_post_id
   and c.deleted_at is null
   and auth.uid() is not null
   and not is_blocked_either_way(c.author_id)
   and not is_muted(c.author_id)
 order by c.created_at
 limit greatest(1, least(p_limit, 200));
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'feed_for_you(int, timestamptz)',
    'feed_following(int, timestamptz)',
    'feed_by_topic(topic_kind, text, int, timestamptz)',
    'feed_by_handle(text, int, timestamptz)',
    'post_by_id(uuid)',
    'post_comments(uuid, int)'
  ] loop
    execute format('revoke all on function %s from public', fn);
    execute format('grant execute on function %s to authenticated', fn);
  end loop;
end
$$;
