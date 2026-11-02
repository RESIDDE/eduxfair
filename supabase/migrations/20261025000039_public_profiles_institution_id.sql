-- Expose institution_id on public_profiles view so client routing to handles
-- can resolve institution profiles seamlessly.

create or replace view public_profiles
with (security_barrier = true)
as
select
  sp.handle,
  sp.display_name,
  sp.bio,
  sp.avatar_url,
  sp.kind,
  sp.follower_count,
  sp.following_count,
  sp.post_count,
  sp.created_at,
  i.name    as institution_name,
  i.country as institution_country,
  i.verification_status = 'verified' as institution_verified,
  case
    when sp.kind in ('institution', 'embassy')
      then i.verification_status = 'verified'
    when sp.kind = 'educator'
      then exists (select 1 from educators e
                    where e.profile_id = sp.profile_id
                      and e.verification_status = 'verified')
    else exists (select 1 from student_passports p
                  where p.profile_id = sp.profile_id
                    and p.verification_status = 'verified')
  end as is_verified,
  sp.institution_id as institution_id
from social_profiles sp
left join institutions i on i.id = sp.institution_id
where sp.is_public
  and auth.uid() is not null;

revoke all on public_profiles from public;
grant select on public_profiles to authenticated;

create or replace function is_following_handle(p_handle text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  if auth.uid() is null then
    return false;
  end if;
  select profile_id into v_target
    from social_profiles where handle = lower(trim(p_handle));
  if v_target is null then
    return false;
  end if;
  return exists (
    select 1 from follows
     where follower_id = auth.uid() and followee_id = v_target
  );
end;
$$;

grant execute on function is_following_handle(text) to authenticated;

