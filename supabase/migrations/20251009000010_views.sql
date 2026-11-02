-- Lekkside Connect — controlled-disclosure views.
--
-- These two views are the only way an institution learns anything about a
-- student it has no share from, and they are therefore the most security-
-- sensitive objects in the schema.
--
-- They are intentionally NOT `security_invoker` views. An invoker view would
-- run under the caller's RLS, which blocks `student_passports` outright and
-- would leave the institution seeing nothing at all — there would be no
-- reverse admission. Instead each view does its own authorization in the WHERE
-- clause and exposes only non-identifying columns. `security_barrier` stops the
-- planner pushing a caller-supplied predicate underneath that filter, which is
-- the classic way such a view leaks.

-- ------------------------------------------------------------- banding helpers
--
-- Exact values are identifying in combination; bands are not. A 3.87 GPA plus
-- a birth date plus a country narrows to very few people. "80-89%" does not.

create or replace function grade_band(normalized numeric)
returns text
language sql
immutable
as $$
  select case
    when normalized is null then null
    when normalized >= 90 then '90-100%'
    when normalized >= 80 then '80-89%'
    when normalized >= 70 then '70-79%'
    when normalized >= 60 then '60-69%'
    when normalized >= 50 then '50-59%'
    else 'below 50%'
  end;
$$;

create or replace function age_band(dob date)
returns text
language sql
stable
as $$
  select case
    when dob is null then null
    when extract(year from age(dob)) < 18 then 'under 18'
    when extract(year from age(dob)) < 21 then '18-20'
    when extract(year from age(dob)) < 25 then '21-24'
    when extract(year from age(dob)) < 30 then '25-29'
    else '30+'
  end;
$$;

create or replace function budget_band(amount numeric, currency text)
returns text
language sql
immutable
as $$
  select case
    when amount is null then null
    when amount < 10000  then 'under 10k ' || currency
    when amount < 20000  then '10-20k ' || currency
    when amount < 35000  then '20-35k ' || currency
    when amount < 50000  then '35-50k ' || currency
    else '50k+ ' || currency
  end;
$$;

-- ------------------------------------------------------ matched_student_cards
--
-- What an institution browses BEFORE consent. Enough to decide whether to
-- invite someone; not enough to identify or contact them. The student_id is a
-- pseudonym: it is the handle used to shortlist and invite, and it resolves to
-- a real person only once that student grants a share.

create view matched_student_cards
with (security_barrier = true)
as
select
  ms.student_id,
  ms.program_id,
  g.institution_id,
  g.name              as program_name,
  ms.score,
  ms.reasons,
  ms.computed_at,

  -- Non-identifying attributes only.
  p.current_country,
  p.nationality,
  p.target_levels,
  p.target_fields,
  p.intended_intake,
  grade_band(p.normalized_grade)              as grade_band,
  age_band(p.date_of_birth)                   as age_band,
  p.english_band,
  budget_band(p.budget_max, p.budget_currency) as budget_band,
  p.completeness,
  p.verification_status                        as passport_verification,

  -- Has this student already let us see them? Drives the UI's "request access"
  -- versus "open full passport" branch.
  institution_can_see_student(g.institution_id, ms.student_id) as is_shared,

  -- So staff do not re-invite the same person twice.
  exists (
    select 1 from institution_interests ii
     where ii.institution_id = g.institution_id
       and ii.profile_id = ms.student_id
       and ii.program_id = ms.program_id
  ) as already_actioned

from match_scores ms
join programs g on g.id = ms.program_id
join student_passports p on p.profile_id = ms.student_id
where g.is_active
  -- Authorization, done here because the view is not security_invoker.
  and (
    is_member_of(g.institution_id)
    or ms.student_id = auth.uid()
    or is_admin()
  );

comment on view matched_student_cards is
  'Pseudonymous match cards. Deliberately excludes name, contact details, exact '
  'grades, date of birth, bio and documents. Identity requires a passport_share.';

revoke all on matched_student_cards from public;
grant select on matched_student_cards to authenticated;

-- ------------------------------------------------------- student_demand_stats
--
-- The institution-facing pitch: "1,284 students in Nigeria are seeking
-- Canadian institutions; 31% want Computer Science." Aggregates only.
--
-- K-ANONYMITY: cells smaller than the floor are dropped entirely rather than
-- shown. Without that, "1 student in Country X wants Program Y" combined with
-- a booth conversation identifies someone.

create or replace function demand_cell_floor() returns int
  language sql immutable as $$ select 5 $$;

create view student_demand_stats
with (security_barrier = true)
as
with exploded as (
  select
    p.profile_id,
    p.current_country,
    target_country,
    level,
    field
  from student_passports p
  cross join unnest(
    case when array_length(p.target_countries, 1) is null
         then array[null]::text[] else p.target_countries end
  ) as target_country
  cross join unnest(
    case when array_length(p.target_levels, 1) is null
         then array[null]::study_level[] else p.target_levels end
  ) as level
  cross join unnest(
    case when array_length(p.target_fields, 1) is null
         then array[null]::text[] else p.target_fields end
  ) as field
  where p.completeness >= min_completeness_to_match()
)
select
  current_country   as student_country,
  target_country,
  level             as target_level,
  field             as target_field,
  count(distinct profile_id) as student_count
from exploded
where
  -- Only institution staff and admin see demand data; a student has no reason
  -- to and it is the paid product.
  (current_user_role() in ('institution_member', 'admin'))
group by 1, 2, 3, 4
having count(distinct profile_id) >= demand_cell_floor();

comment on view student_demand_stats is
  'Aggregate demand for the institution dashboard. Cells below '
  'demand_cell_floor() are suppressed so a single student cannot be '
  're-identified by combining a small cell with a booth conversation.';

revoke all on student_demand_stats from public;
grant select on student_demand_stats to authenticated;

-- ------------------------------------------------- institution-facing summary
--
-- "84 students are looking for institutions offering your programs" — the one
-- number that makes the pitch concrete. Pseudonymous count, no floor needed
-- since it reveals nothing about any individual.

create or replace function my_institution_demand(p_institution_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_member_of(p_institution_id) and not is_admin() then
    raise exception 'not authorized';
  end if;

  return jsonb_build_object(
    'matched_students', (
      select count(distinct ms.student_id)
        from match_scores ms
        join programs g on g.id = ms.program_id
       where g.institution_id = p_institution_id and g.is_active),
    'shared_passports', (
      select count(*) from passport_shares
       where institution_id = p_institution_id and revoked_at is null),
    'open_applications', (
      select count(*) from applications
       where institution_id = p_institution_id
         and stage not in ('rejected', 'withdrawn', 'enrolled')),
    'pending_appointments', (
      select count(*) from appointments
       where institution_id = p_institution_id and status = 'requested'),
    'unread_conversations', (
      select count(*)
        from conversations c
       where c.institution_id = p_institution_id
         and c.last_message_at is not null
         and not exists (
           select 1 from conversation_participants cp
            where cp.conversation_id = c.id
              and cp.profile_id = auth.uid()
              and cp.last_read_at >= c.last_message_at)),
    'top_fields', (
      select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select g.field_of_study as field, count(distinct ms.student_id) as students
          from match_scores ms
          join programs g on g.id = ms.program_id
         where g.institution_id = p_institution_id and g.is_active
         group by g.field_of_study
         order by 2 desc
         limit 6
      ) t)
  );
end;
$$;

revoke all on function my_institution_demand(uuid) from public;
grant execute on function my_institution_demand(uuid) to authenticated;
