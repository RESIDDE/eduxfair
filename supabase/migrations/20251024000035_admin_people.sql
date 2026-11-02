-- Everything an admin needs to act on a person, in one row.
--
-- The super-admin console has to answer "who is this" before it can answer
-- "what may they do", and `profiles` cannot: the address someone signs in with
-- lives on `auth.users`, which PostgREST does not expose. Two people called
-- Samuel are indistinguishable without it, and changing the wrong one's role is
-- not a mistake you notice quickly.
--
-- So this view reaches across into auth.users — and because it does, the gate
-- is the first thing in it. `where is_admin()` is the whole access rule, in the
-- same shape institution_inbox and space_roster use: a security_barrier view
-- that returns nothing at all to anyone else. Not security_invoker, because an
-- invoker view would hit profiles_select_self and hand every caller their own
-- row, which is not a people list.
--
-- Deliberately read-only. Acting on a person still goes through the ordinary
-- policies — `profiles_update_admin` for a role change, which
-- guard_profile_role_change() already exempts is_admin() from, and
-- `restrictions_all_admin` for a suspension. This view decides nothing; it only
-- gathers what is already readable into one place so the console does not make
-- six round trips per row.

create or replace view admin_people
with (security_barrier = true)
as
select
  p.id,
  p.role,
  p.full_name,
  p.avatar_url,
  p.country,
  p.phone,
  p.created_at,

  -- The reason this view exists.
  u.email,
  u.last_sign_in_at,
  u.email_confirmed_at is not null as email_confirmed,

  sp.handle::text as handle,
  sp.is_minor,

  -- Current restriction, if one is in force. `until` in the past is expired
  -- rather than lifted, so it is filtered here and not left to the caller —
  -- is_restricted() already makes the same judgement and the two must agree.
  r.kind   as restriction_kind,
  r.reason as restriction_reason,
  r.until  as restriction_until,
  r.id is not null as is_restricted,

  -- Staff only. A student has no membership and these stay null.
  im.institution_id,
  im.member_role,
  i.name               as institution_name,
  i.verification_status as institution_verification_status

from profiles p
join auth.users u on u.id = p.id
left join social_profiles sp on sp.profile_id = p.id
left join lateral (
  select ar.id, ar.kind, ar.reason, ar.until
    from account_restrictions ar
   where ar.profile_id = p.id
     and ar.lifted_at is null
     and (ar.until is null or ar.until > now())
   order by ar.created_at desc
   limit 1
) r on true
left join lateral (
  select im2.institution_id, im2.member_role
    from institution_members im2
   where im2.profile_id = p.id
   order by im2.created_at
   limit 1
) im on true
left join institutions i on i.id = im.institution_id
where is_admin();

comment on view admin_people is
  'Every account, with the sign-in address, for the super-admin console. '
  'Reaches into auth.users, so `where is_admin()` is the whole access rule — '
  'it returns nothing to anyone else. Read-only: acting on a person still goes '
  'through profiles_update_admin and restrictions_all_admin.';

revoke all on admin_people from public;
grant select on admin_people to authenticated;
