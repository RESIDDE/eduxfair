-- Post tags and mentions for institutions and fellow students, with notifications.

create table if not exists post_tags (
  id             uuid primary key default gen_random_uuid(),
  post_id        uuid not null references posts (id) on delete cascade,
  profile_id     uuid references profiles (id) on delete cascade,
  institution_id uuid references institutions (id) on delete cascade,
  handle         text not null,
  display_name   text not null,
  created_at     timestamptz not null default now(),
  constraint post_tags_has_target check (profile_id is not null or institution_id is not null)
);

create index if not exists post_tags_post_idx on post_tags (post_id);
create index if not exists post_tags_profile_idx on post_tags (profile_id) where profile_id is not null;
create index if not exists post_tags_institution_idx on post_tags (institution_id) where institution_id is not null;

alter table post_tags enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'post_tags' and policyname = 'post_tags_select') then
    create policy post_tags_select on post_tags for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'post_tags' and policyname = 'post_tags_all_admin') then
    create policy post_tags_all_admin on post_tags for all to authenticated using (is_admin()) with check (is_admin());
  end if;
end $$;

create or replace function create_post(
  p_body           text default null,
  p_kind           post_kind default 'update',
  p_institution_id uuid default null,
  p_link_url       text default null,
  p_reply_policy   reply_policy default 'everyone',
  p_fields         text[] default '{}',
  p_countries      text[] default '{}',
  p_tagged_handles text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_post uuid;
  v_value text;
  v_author_handle text;
  v_author_name text;
  v_inst_poster_name text;
  v_body_mentions text[];
  v_all_tagged text[];
  v_handle text;
  v_target_profile_id uuid;
  v_target_inst_id uuid;
  v_target_handle text;
  v_target_name text;
  v_target_kind text;
  v_snippet text;
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

  -- Resolve author info for notifications
  select handle, display_name into v_author_handle, v_author_name
    from social_profiles where profile_id = auth.uid();
  if v_author_handle is null then
    select coalesce(first_name || ' ' || last_name, 'Someone') into v_author_name
      from profiles where id = auth.uid();
    v_author_handle := 'user';
  end if;

  if p_institution_id is not null then
    select name into v_inst_poster_name from institutions where id = p_institution_id;
    if v_inst_poster_name is not null then
      v_author_name := v_inst_poster_name;
    end if;
  end if;

  -- Extract any @handle mentions written in the body text
  select coalesce(array_agg(distinct lower(m[1])), '{}')
    into v_body_mentions
    from regexp_matches(coalesce(p_body, ''), '@([a-zA-Z0-9_]{2,30})', 'g') as m;

  select coalesce(array_agg(distinct lower(trim(h))), '{}')
    into v_all_tagged
    from unnest(coalesce(p_tagged_handles, '{}') || coalesce(v_body_mentions, '{}')) as h
   where h is not null and length(trim(h)) > 0;

  v_snippet := coalesce(substring(trim(p_body) from 1 for 80), 'a post');
  if length(coalesce(p_body, '')) > 80 then
    v_snippet := v_snippet || '...';
  end if;

  -- Process tags and dispatch notifications
  foreach v_handle in array v_all_tagged loop
    v_target_profile_id := null;
    v_target_inst_id := null;
    v_target_handle := null;
    v_target_name := null;
    v_target_kind := null;

    select profile_id, institution_id, handle, display_name, kind
      into v_target_profile_id, v_target_inst_id, v_target_handle, v_target_name, v_target_kind
      from social_profiles
     where lower(handle) = v_handle
     limit 1;

    if v_target_handle is null then
      select id, slug, name into v_target_inst_id, v_target_handle, v_target_name
        from institutions
       where lower(slug) = v_handle
       limit 1;
    end if;

    if v_target_handle is not null or v_target_profile_id is not null or v_target_inst_id is not null then
      insert into post_tags (post_id, profile_id, institution_id, handle, display_name)
      values (
        v_post,
        v_target_profile_id,
        v_target_inst_id,
        coalesce(v_target_handle, v_handle),
        coalesce(v_target_name, v_handle)
      );

      -- Notify institution staff if an institution was tagged
      if v_target_inst_id is not null then
        insert into notifications (profile_id, kind, title, body, payload)
        select
          im.profile_id,
          'post_tagged',
          v_author_name || ' tagged ' || coalesce(v_target_name, 'your institution'),
          v_author_name || ' (@' || v_author_handle || ') tagged ' || coalesce(v_target_name, 'your institution') || ' in a post: "' || v_snippet || '"',
          jsonb_build_object(
            'post_id', v_post,
            'author_handle', v_author_handle,
            'author_name', v_author_name,
            'tagged_handle', coalesce(v_target_handle, v_handle),
            'institution_id', v_target_inst_id
          )
        from institution_members im
        where im.institution_id = v_target_inst_id
          and im.profile_id <> auth.uid();
      end if;

      -- Notify fellow student if a user was tagged
      if v_target_profile_id is not null and v_target_profile_id <> auth.uid() then
        insert into notifications (profile_id, kind, title, body, payload)
        values (
          v_target_profile_id,
          'post_tagged',
          v_author_name || ' tagged you',
          v_author_name || ' (@' || v_author_handle || ') tagged you in a post: "' || v_snippet || '"',
          jsonb_build_object(
            'post_id', v_post,
            'author_handle', v_author_handle,
            'author_name', v_author_name,
            'tagged_handle', coalesce(v_target_handle, v_handle)
          )
        );
      end if;
    end if;
  end loop;

  return v_post;
end;
$$;

revoke all on function create_post(text, post_kind, uuid, text, reply_policy, text[], text[], text[]) from public;
grant execute on function create_post(text, post_kind, uuid, text, reply_policy, text[], text[], text[]) to authenticated;

create or replace view feed_posts
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

  exists (select 1 from post_likes l
           where l.post_id = p.id and l.profile_id = auth.uid())    as liked,
  exists (select 1 from post_bookmarks b
           where b.post_id = p.id and b.profile_id = auth.uid())    as bookmarked,
  exists (select 1 from posts r
           where r.repost_of = coalesce(p.repost_of, p.id)
             and r.author_id = auth.uid()
             and r.body is null and r.deleted_at is null)           as reposted_by_me,
  p.author_id = auth.uid()                                          as is_mine,

  p.author_id                                        as _author_id,
  p.institution_id                                   as _institution_id,

  (select coalesce(jsonb_agg(jsonb_build_object(
            'handle', pt.handle,
            'name', pt.display_name,
            'is_institution', pt.institution_id is not null
          )), '[]'::jsonb)
     from post_tags pt where pt.post_id = p.id)       as tags

from posts p
left join social_profiles sp on sp.profile_id = p.author_id
left join institutions i on i.id = p.institution_id
left join social_profiles inst_sp on inst_sp.institution_id = p.institution_id
where p.deleted_at is null
  and auth.uid() is not null
  and not is_blocked_either_way(p.author_id)
  and (p.repost_of is null
       or exists (select 1 from posts o
                   where o.id = p.repost_of and o.deleted_at is null));

revoke all on feed_posts from public;
grant select on feed_posts to authenticated;
