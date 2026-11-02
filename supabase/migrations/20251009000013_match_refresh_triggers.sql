-- Lekkside Connect — keep match_scores current automatically.
--
-- Matching runs synchronously on write. At phase-1 scale (hundreds of programs,
-- thousands of passports) scoring one student against every active program is a
-- few milliseconds, and the alternative — a job queue — is a lot of moving
-- parts to buy nothing yet. The `compute-matches` Edge Function remains for
-- bulk and scheduled recomputation, e.g. after changing the scoring weights.
--
-- When this starts to hurt, the fix is to move these two calls onto pg_cron or
-- a queue; nothing else has to change, because the clients only ever read
-- match_scores.

create or replace function trigger_refresh_matches_for_student()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform refresh_matches_for_student(new.profile_id);
  return new;
end;
$$;

-- Fires on the matching inputs *and* on completeness, because completeness is
-- itself the gate (min_completeness_to_match). Listing both means a change that
-- leaves completeness untouched — swapping one target country for another at an
-- already-complete passport — still triggers a refresh.
--
-- The completeness trigger's own nested UPDATE can cause a second, harmless
-- fire; refresh_matches_for_student is idempotent.
create trigger passports_refresh_matches
  after insert or update of
    nationality, current_country, grade_value, grade_scheme,
    english_test_name, english_score,
    target_countries, target_levels, target_fields,
    budget_max, budget_currency, intended_intake, completeness
  on student_passports
  for each row execute function trigger_refresh_matches_for_student();

create or replace function trigger_refresh_matches_for_program()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform refresh_matches_for_program(new.id);
  return new;
end;
$$;

create trigger programs_refresh_matches
  after insert or update of
    level, field_of_study, tuition_min, tuition_max, tuition_currency,
    intakes, min_grade_value, min_grade_scheme, min_english_band,
    scholarship_available, is_active
  on programs
  for each row execute function trigger_refresh_matches_for_program();

-- An institution moving country changes every one of its programs' scores.
create or replace function trigger_refresh_matches_for_institution()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p uuid;
begin
  if new.country is distinct from old.country then
    for p in select id from programs where institution_id = new.id and is_active loop
      perform refresh_matches_for_program(p);
    end loop;
  end if;
  return new;
end;
$$;

create trigger institutions_refresh_matches
  after update of country on institutions
  for each row execute function trigger_refresh_matches_for_institution();
