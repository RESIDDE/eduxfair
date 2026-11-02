-- A new student's feed is not empty.
--
-- Found on the live project: a student signed up, an institution posted, and
-- the student saw nothing at all.
--
-- Two causes, both in the CTE below.
--
-- 1. `from student_passports where profile_id = auth.uid()` returns **zero
--    rows** for someone who has not filled in a passport yet. Every branch of
--    the WHERE then cross-joins against an empty relation, so all of them are
--    false and the feed is empty by construction. The coalesce() was guarding
--    against a null column, which is the wrong worry — the problem is a
--    missing row.
--
-- 2. Even with that fixed, a student with nothing in their passport matches
--    nothing, which is correct and still leaves them staring at a blank
--    screen on the day they join. Reading the feed is how someone decides the
--    app is worth filling a passport in for, so it cannot be the reward for
--    having filled one in.
--
-- The fallback is deliberately narrow: only institution posts, and only for
-- someone who has given us nothing to match on and follows nobody. The moment
-- they say what they want, or follow anyone, it stops applying and the feed is
-- theirs again.

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
    -- Left-joined from a single-row source, so this always yields exactly one
    -- row: empty arrays for someone with no passport, rather than no row.
    select coalesce(sp.target_fields, '{}') as fields,
           coalesce(sp.target_countries, '{}') as countries
      from (select auth.uid() as id) u
      left join student_passports sp on sp.profile_id = u.id
  ),
  blank as (
    select cardinality(fields) = 0 and cardinality(countries) = 0 as nothing_said
      from me
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
       -- First run: nothing in the passport and nobody followed. Show what
       -- institutions are saying, which is what the app is for.
       or (
         f._institution_id is not null
         and (select nothing_said from blank)
         and not exists (
           select 1 from follows fl where fl.follower_id = auth.uid())
       )
     )
   order by f.pinned_at desc nulls last, f.created_at desc
   limit greatest(1, least(p_limit, 50));
$$;

revoke all on function feed_for_you(int, timestamptz) from public;
grant execute on function feed_for_you(int, timestamptz) to authenticated;
