-- Search students by handle or tag with their follow status for the current user.

create or replace function search_students_with_follow(
  p_query text default '',
  p_limit int default 20
)
returns table (
  handle         text,
  display_name   text,
  avatar_url     text,
  bio            text,
  follower_count int,
  is_verified    boolean,
  is_following   boolean,
  is_self        boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  clean text;
begin
  if auth.uid() is null then
    return;
  end if;

  clean := lower(trim(replace(coalesce(p_query, ''), '@', '')));

  return query
  select
    sp.handle::text,
    sp.display_name::text,
    sp.avatar_url::text,
    sp.bio::text,
    sp.follower_count::int,
    exists (
      select 1 from student_passports p
       where p.profile_id = sp.profile_id
         and p.verification_status = 'verified'
    ) as is_verified,
    exists (
      select 1 from follows f
       where f.follower_id = auth.uid()
         and f.followee_id = sp.profile_id
    ) as is_following,
    (sp.profile_id = auth.uid()) as is_self
  from social_profiles sp
  where sp.is_public
    and sp.kind = 'student'
    and (
      clean = ''
      or lower(sp.handle) like '%' || clean || '%'
      or lower(sp.display_name) like '%' || clean || '%'
    )
    and not is_blocked_either_way(sp.profile_id)
  order by
    case when lower(sp.handle) = clean then 0
         when lower(sp.handle) like clean || '%' then 1
         else 2 end,
    sp.follower_count desc
  limit p_limit;
end;
$$;

revoke all on function search_students_with_follow(text, int) from public;
grant execute on function search_students_with_follow(text, int) to authenticated;
