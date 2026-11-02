-- Universal Feed & Designated Areas
-- Ensures that when students or universities post for "everyone", it shows on "For You",
-- and when options/topics (fields, countries, kinds) or tags are selected, they show in the designated areas.

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
  with my_inst as (
    select im.institution_id, i.country,
           coalesce(array_agg(distinct p.field_of_study) filter (where p.field_of_study is not null), '{}') as fields
      from institution_members im
      join institutions i on i.id = im.institution_id
      left join programs p on p.institution_id = im.institution_id and p.is_active = true
     where im.profile_id = auth.uid()
     group by im.institution_id, i.country
     limit 1
  ),
  my_student as (
    select coalesce(target_fields, '{}') as fields,
           coalesce(target_countries, '{}') as countries
      from student_passports
     where profile_id = auth.uid()
     limit 1
  ),
  me as (
    select
      (select institution_id from my_inst) as institution_id,
      coalesce(
        (select fields from my_student),
        (select fields from my_inst),
        '{}'::text[]
      ) as fields,
      coalesce(
        (select countries from my_student),
        case when (select country from my_inst) is not null then array[(select country from my_inst)] else '{}'::text[] end,
        '{}'::text[]
      ) as countries
  )
  select f.* from feed_posts f, me
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and (
       -- 1. Topics: fields or countries matching caller's interests or university's programs
       exists (
         select 1 from post_topics t
          where t.post_id = f.id
            and ((t.kind = 'field'   and (t.value = any (me.fields) or cardinality(me.fields) = 0))
              or (t.kind = 'country' and (t.value = any (me.countries) or cardinality(me.countries) = 0))))

       -- 2. Institutions in targeted country
       or exists (
         select 1 from institutions i
          where i.id = f._institution_id and i.country = any (me.countries))

       -- 3. Followed profiles
       or exists (
         select 1 from follows fl
          where fl.follower_id = auth.uid() and fl.followee_id = f._author_id)

       -- 4. Followed institutions (students following university)
       or exists (
         select 1 from institution_follows ifl
          where ifl.student_id = auth.uid() and ifl.institution_id = f._institution_id)

       -- 5. Student followers (university seeing posts by students who follow them)
       or (me.institution_id is not null and exists (
         select 1 from institution_follows ifl
          where ifl.institution_id = me.institution_id and ifl.student_id = f._author_id))

       -- 6. Tagged/mentioned: caller or caller's institution is tagged
       or exists (
         select 1 from post_tags pt
          where pt.post_id = f.id
            and (pt.profile_id = auth.uid()
                 or (me.institution_id is not null and pt.institution_id = me.institution_id)))

       -- 7. Own posts
       or f._author_id = auth.uid()
       or (me.institution_id is not null and f._institution_id = me.institution_id)

       -- 8. General posts for everyone / public feed
       or (f.reply_policy = 'everyone')
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
  with my_inst as (
    select institution_id from institution_members where profile_id = auth.uid() limit 1
  )
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and (
       exists (select 1 from follows fl
                where fl.follower_id = auth.uid()
                  and fl.followee_id = f._author_id)
       or exists (select 1 from institution_follows ifl
                   where ifl.student_id = auth.uid()
                     and ifl.institution_id = f._institution_id)
       or exists (select 1 from my_inst mi, institution_follows ifl
                   where ifl.institution_id = mi.institution_id
                     and ifl.student_id = f._author_id)
       or f._author_id = auth.uid()
       or exists (select 1 from my_inst mi where mi.institution_id = f._institution_id)
     )
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

-- Feed by post option kind ('update', 'question', 'announcement', 'requirement')
create or replace function feed_by_kind(
  p_kind   post_kind,
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
     and f.kind = p_kind
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

-- Feed of posts tagging a specific handle or the current user/institution
create or replace function feed_tagged(
  p_handle text default null,
  p_limit  int default 30,
  p_before timestamptz default null
)
returns setof feed_posts
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_clean text;
  v_target_profile_id uuid;
  v_target_inst_id uuid;
begin
  v_clean := lower(trim(both ' ' from coalesce(p_handle, '')));
  if starts_with(v_clean, '@') then
    v_clean := substring(v_clean from 2);
  end if;

  if v_clean = '' then
    v_target_profile_id := auth.uid();
    select institution_id into v_target_inst_id
      from institution_members
     where profile_id = auth.uid()
     limit 1;
  else
    select profile_id, institution_id into v_target_profile_id, v_target_inst_id
      from social_profiles
     where lower(handle) = v_clean
     limit 1;

    if v_target_inst_id is null then
      select id into v_target_inst_id
        from institutions
       where lower(slug) = v_clean
       limit 1;
    end if;
  end if;

  return query
  select f.* from feed_posts f
   where (p_before is null or f.created_at < p_before)
     and not is_muted(f._author_id)
     and exists (
       select 1 from post_tags pt
        where pt.post_id = f.id
          and (
            (v_clean <> '' and lower(pt.handle) = v_clean)
            or (v_target_profile_id is not null and pt.profile_id = v_target_profile_id)
            or (v_target_inst_id is not null and pt.institution_id = v_target_inst_id)
          )
     )
   order by f.created_at desc
   limit greatest(1, least(p_limit, 50));
end;
$$;

revoke all on function feed_for_you from public;
grant execute on function feed_for_you to authenticated;

revoke all on function feed_following from public;
grant execute on function feed_following to authenticated;

revoke all on function feed_by_kind from public;
grant execute on function feed_by_kind to authenticated;

revoke all on function feed_tagged from public;
grant execute on function feed_tagged to authenticated;
