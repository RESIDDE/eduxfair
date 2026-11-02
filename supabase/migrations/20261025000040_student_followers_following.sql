-- Student followers and following lists and counts

create or replace function my_student_followers(p_limit int default 50)
returns table (
  handle text,
  display_name text,
  avatar_url text,
  kind text,
  bio text,
  is_verified boolean,
  followed_at timestamptz,
  is_following boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  return query
  select
    sp.handle::text,
    sp.display_name,
    sp.avatar_url,
    sp.kind::text,
    sp.bio,
    pp.is_verified,
    f.created_at as followed_at,
    exists (
      select 1 from follows back
       where back.follower_id = auth.uid()
         and back.followee_id = f.follower_id
    ) as is_following
  from follows f
  join social_profiles sp on sp.profile_id = f.follower_id
  left join public_profiles pp on pp.handle = sp.handle
  where f.followee_id = auth.uid()
  order by f.created_at desc
  limit coalesce(p_limit, 50);
end;
$$;

grant execute on function my_student_followers(int) to authenticated;

create or replace function my_student_following(p_limit int default 50)
returns table (
  id text,
  kind text, -- 'institution' or 'student'
  name text,
  handle text,
  avatar_url text,
  subtitle text,
  is_verified boolean,
  institution_id text,
  followed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  return query
  (
    -- Followed institutions
    select
      i.id::text as id,
      'institution'::text as kind,
      i.name as name,
      sp.handle::text as handle,
      i.logo_url as avatar_url,
      coalesce(i.city || ', ', '') || i.country as subtitle,
      (i.verification_status = 'verified') as is_verified,
      i.id::text as institution_id,
      ifl.created_at as followed_at
    from institution_follows ifl
    join institutions i on i.id = ifl.institution_id
    left join social_profiles sp on sp.institution_id = i.id
    where ifl.student_id = auth.uid()

    union all

    -- Followed students/profiles
    select
      sp.profile_id::text as id,
      sp.kind::text as kind,
      sp.display_name as name,
      sp.handle::text as handle,
      sp.avatar_url as avatar_url,
      coalesce(sp.bio, '@' || sp.handle::text) as subtitle,
      pp.is_verified as is_verified,
      null::text as institution_id,
      f.created_at as followed_at
    from follows f
    join social_profiles sp on sp.profile_id = f.followee_id
    left join public_profiles pp on pp.handle = sp.handle
    where f.follower_id = auth.uid()
  )
  order by followed_at desc
  limit coalesce(p_limit, 50);
end;
$$;

grant execute on function my_student_following(int) to authenticated;

create or replace function my_social_counts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_followers int := 0;
  v_following_users int := 0;
  v_following_institutions int := 0;
begin
  if auth.uid() is null then
    return jsonb_build_object('followers', 0, 'following', 0);
  end if;

  select count(*) into v_followers
    from follows where followee_id = auth.uid();

  select count(*) into v_following_users
    from follows where follower_id = auth.uid();

  select count(*) into v_following_institutions
    from institution_follows where student_id = auth.uid();

  return jsonb_build_object(
    'followers', v_followers,
    'following', v_following_users + v_following_institutions,
    'following_users', v_following_users,
    'following_institutions', v_following_institutions
  );
end;
$$;

grant execute on function my_social_counts() to authenticated;
