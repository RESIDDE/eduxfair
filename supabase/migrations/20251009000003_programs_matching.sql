-- Lekkside Connect — programs, matching and reverse admission.
--
-- Reverse admission is the distinctive mechanic: institutions discover students
-- who already match their programs, rather than students cold-applying. That
-- requires a score both sides can see and understand, so every score carries a
-- `reasons` payload explaining itself. No black box, no ML — a student should be
-- able to read exactly why a program was suggested.
--
-- The scoring runs in SQL rather than in the Edge Function: it is set-based
-- work over data already in Postgres, so doing it here is atomic, needs no
-- network hop, and cannot drift from the schema. The `compute-matches` Edge
-- Function is a thin HTTP wrapper over refresh_matches_for_* below.

-- -------------------------------------------------------------------- programs

create table programs (
  id                  uuid primary key default gen_random_uuid(),
  institution_id      uuid not null references institutions (id) on delete cascade,
  name                text not null,
  level               study_level not null,
  field_of_study      text not null references fields_of_study (slug),

  tuition_min         numeric(12, 2),
  tuition_max         numeric(12, 2),
  tuition_currency    text not null default 'USD',
  duration_months     int,

  -- Free-text intake labels, e.g. {'Fall 2026','Winter 2027'}.
  intakes             text[] not null default '{}',

  -- Entry requirements, expressed so they can be compared against a passport.
  min_grade_value     numeric(6, 3),
  min_grade_scheme    grading_scheme,
  min_english_band    numeric(3, 1),   -- IELTS-equivalent; see normalize_english_band

  scholarship_available boolean not null default false,
  -- Anything that does not fit the structured fields above, for display only.
  requirements        jsonb not null default '{}'::jsonb,

  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint programs_tuition_order
    check (tuition_min is null or tuition_max is null or tuition_min <= tuition_max),
  constraint programs_min_grade_needs_scheme
    check ((min_grade_value is null) = (min_grade_scheme is null))
);

alter table programs
  add column normalized_min_grade numeric(6, 3)
    generated always as (normalize_grade(min_grade_value, min_grade_scheme)) stored;

create index programs_institution_idx on programs (institution_id);
create index programs_discovery_idx on programs (level, field_of_study) where is_active;

create trigger programs_set_updated_at
  before update on programs
  for each row execute function set_updated_at();

-- ------------------------------------------------------------ the scoring

-- Weights sum to 100. Kept as a function rather than a table so the breakdown
-- is reviewable in one place and version-controlled with the migration.
create or replace function score_passport_against_program(
  p student_passports,
  g programs
)
returns jsonb
language plpgsql
-- STABLE, not IMMUTABLE: this reads institutions.country, so the planner must
-- not treat it as cacheable across statements.
stable
as $$
declare
  score    int := 0;
  reasons  jsonb := '[]'::jsonb;
  inst_country text;
begin
  -- Country of study (25) — the strongest signal of intent.
  select country into inst_country from institutions where id = g.institution_id;
  if inst_country is not null and inst_country = any (p.target_countries) then
    score := score + 25;
    reasons := reasons || jsonb_build_object(
      'code', 'country_match', 'weight', 25,
      'detail', 'You are looking to study in ' || inst_country);
  end if;

  -- Level (20).
  if g.level = any (p.target_levels) then
    score := score + 20;
    reasons := reasons || jsonb_build_object(
      'code', 'level_match', 'weight', 20,
      'detail', 'Matches the ' || g.level::text || ' level you are seeking');
  end if;

  -- Field of study (20).
  if g.field_of_study = any (p.target_fields) then
    score := score + 20;
    reasons := reasons || jsonb_build_object(
      'code', 'field_match', 'weight', 20,
      'detail', 'In your field of interest');
  end if;

  -- Entry grade (15). Unknown requirement is not held against the student:
  -- a program that states no minimum gets partial credit, not zero.
  if g.normalized_min_grade is null then
    score := score + 8;
    reasons := reasons || jsonb_build_object(
      'code', 'grade_unstated', 'weight', 8,
      'detail', 'No published minimum grade');
  elsif p.normalized_grade is not null
        and p.normalized_grade >= g.normalized_min_grade then
    score := score + 15;
    reasons := reasons || jsonb_build_object(
      'code', 'grade_met', 'weight', 15,
      'detail', 'Your grades meet the stated entry requirement');
  end if;

  -- Affordability (10). Compared only when both sides use the same currency —
  -- there is no FX table in phase 1 and a wrong conversion is worse than no
  -- conversion, so a mismatch scores as "unknown" rather than "unaffordable".
  if g.tuition_min is null then
    score := score + 5;
    reasons := reasons || jsonb_build_object(
      'code', 'tuition_unstated', 'weight', 5,
      'detail', 'Tuition not published');
  elsif p.budget_max is not null and p.budget_currency = g.tuition_currency then
    if g.tuition_min <= p.budget_max then
      score := score + 10;
      reasons := reasons || jsonb_build_object(
        'code', 'within_budget', 'weight', 10,
        'detail', 'Tuition is within your stated budget');
    end if;
  else
    score := score + 5;
    reasons := reasons || jsonb_build_object(
      'code', 'budget_not_comparable', 'weight', 5,
      'detail', 'Budget stated in a different currency — not compared');
  end if;

  -- Intake (5).
  if p.intended_intake is not null and p.intended_intake = any (g.intakes) then
    score := score + 5;
    reasons := reasons || jsonb_build_object(
      'code', 'intake_match', 'weight', 5,
      'detail', g.intakes[array_position(g.intakes, p.intended_intake)] || ' intake is open');
  end if;

  -- English (5), same "unstated is not a penalty" rule as grades.
  if g.min_english_band is null then
    score := score + 3;
  elsif p.english_band is not null and p.english_band >= g.min_english_band then
    score := score + 5;
    reasons := reasons || jsonb_build_object(
      'code', 'english_met', 'weight', 5,
      'detail', 'Your English score meets the requirement');
  end if;

  -- Scholarships are not scored — they do not make a program a better fit —
  -- but they are surfaced, because they change whether a student can go.
  if g.scholarship_available then
    reasons := reasons || jsonb_build_object(
      'code', 'scholarship_available', 'weight', 0,
      'detail', 'Scholarships are available for this program');
  end if;

  return jsonb_build_object('score', least(100, score), 'reasons', reasons);
end;
$$;

-- ---------------------------------------------------------------- match store

create table match_scores (
  student_id  uuid not null references profiles (id) on delete cascade,
  program_id  uuid not null references programs (id) on delete cascade,
  score       int  not null,
  reasons     jsonb not null default '[]'::jsonb,
  computed_at timestamptz not null default now(),

  primary key (student_id, program_id),
  constraint match_score_range check (score between 0 and 100)
);

create index match_scores_program_idx on match_scores (program_id, score desc);
create index match_scores_student_idx on match_scores (student_id, score desc);

-- Below this, a "match" is noise and showing it damages trust on both sides.
create or replace function match_score_floor() returns int
  language sql immutable as $$ select 40 $$;

-- A passport too empty to reason about should not match anything, or
-- institutions would be shown ghosts.
create or replace function min_completeness_to_match() returns int
  language sql immutable as $$ select 50 $$;

create or replace function refresh_matches_for_student(target uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  p       student_passports;
  written int := 0;
begin
  select * into p from student_passports where profile_id = target;
  if not found or p.completeness < min_completeness_to_match() then
    delete from match_scores where student_id = target;
    return 0;
  end if;

  with scored as (
    select g.id as program_id,
           score_passport_against_program(p, g) as result
      from programs g
     where g.is_active
  ),
  kept as (
    select program_id,
           (result ->> 'score')::int as score,
           result -> 'reasons'       as reasons
      from scored
     where (result ->> 'score')::int >= match_score_floor()
  ),
  upserted as (
    insert into match_scores (student_id, program_id, score, reasons, computed_at)
    select target, program_id, score, reasons, now() from kept
    on conflict (student_id, program_id) do update
      set score = excluded.score,
          reasons = excluded.reasons,
          computed_at = excluded.computed_at
    returning program_id
  )
  select count(*) into written from upserted;

  -- Drop matches that no longer qualify, so a narrowed passport does not leave
  -- stale suggestions behind.
  delete from match_scores m
   where m.student_id = target
     and not exists (
       select 1 from programs g
        where g.id = m.program_id
          and g.is_active
          and (score_passport_against_program(p, g) ->> 'score')::int
              >= match_score_floor());

  return written;
end;
$$;

create or replace function refresh_matches_for_program(target uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  g       programs;
  written int := 0;
begin
  select * into g from programs where id = target;
  if not found or not g.is_active then
    delete from match_scores where program_id = target;
    return 0;
  end if;

  with scored as (
    select p.profile_id,
           score_passport_against_program(p, g) as result
      from student_passports p
     where p.completeness >= min_completeness_to_match()
  ),
  kept as (
    select profile_id,
           (result ->> 'score')::int as score,
           result -> 'reasons'       as reasons
      from scored
     where (result ->> 'score')::int >= match_score_floor()
  ),
  upserted as (
    insert into match_scores (student_id, program_id, score, reasons, computed_at)
    select profile_id, target, score, reasons, now() from kept
    on conflict (student_id, program_id) do update
      set score = excluded.score,
          reasons = excluded.reasons,
          computed_at = excluded.computed_at
    returning student_id
  )
  select count(*) into written from upserted;

  delete from match_scores m
   where m.program_id = target
     and not exists (
       select 1 from student_passports p
        where p.profile_id = m.student_id
          and (score_passport_against_program(p, g) ->> 'score')::int
              >= match_score_floor());

  return written;
end;
$$;

-- ------------------------------------------------- interest in both directions

-- Institution → student. This is reverse admission.
create type institution_interest_kind as enum (
  'invited',      -- "we want to talk to you"
  'shortlisted',  -- internal, student is not told
  'passed'        -- internal, so the student stops surfacing in their queue
);

create table institution_interests (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  program_id     uuid references programs (id) on delete set null,
  profile_id     uuid not null references profiles (id) on delete cascade,
  kind           institution_interest_kind not null,
  note           text,
  created_by     uuid references profiles (id) on delete set null,
  created_at     timestamptz not null default now(),

  unique (institution_id, profile_id, program_id, kind)
);

create index institution_interests_profile_idx
  on institution_interests (profile_id) where kind = 'invited';
create index institution_interests_institution_idx
  on institution_interests (institution_id, kind);

comment on column institution_interests.kind is
  'Only ''invited'' is visible to the student; shortlisted/passed are internal '
  'institution notes and the RLS policies must keep them that way.';

-- Student → program.
create type student_interest_kind as enum ('saved', 'requested_info');

create table student_interests (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  program_id uuid not null references programs (id) on delete cascade,
  kind       student_interest_kind not null default 'saved',
  created_at timestamptz not null default now(),

  unique (profile_id, program_id, kind)
);

create index student_interests_program_idx on student_interests (program_id);
