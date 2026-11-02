-- Lekkside Connect — the Education Passport.
--
-- One student, one profile, built once and reused at every institution. This is
-- the core asset of the product: the thing that means a student never has to
-- re-explain their qualifications at a seventh booth.
--
-- PRIVACY: nothing in this file is readable by an institution by default.
-- `passport_shares` is the consent gate and the RLS policies in
-- 20251009000009_rls_policies.sql depend on it entirely.

-- ------------------------------------------- cross-border grade normalization
--
-- A Nigerian WAEC grade, a UK 2:1 and a 3.4/4.0 GPA have to become comparable
-- numbers or matching cannot reason about entry requirements at all. We map
-- everything onto a 0-100 scale. These are deliberately coarse: they are good
-- enough to rank and to filter out clear mismatches, and they are NOT a
-- credential evaluation. An institution always makes the real decision.

create type grading_scheme as enum (
  'percentage',   -- 0-100 as given
  'gpa_4',        -- US-style 0.0-4.0
  'gpa_5',        -- Nigerian university 0.0-5.0
  'waec',         -- WAEC/NECO subject grade, 1 (A1) to 9 (F9)
  'uk_class',     -- 1, 2.1, 2.2, 3
  'ib',           -- IB diploma total, 0-45
  'a_level'       -- points per grade, E=1 to A*=6
);

create or replace function normalize_grade(
  value  numeric,
  scheme grading_scheme
)
returns numeric
language sql
immutable
as $$
  select case
    when value is null then null
    when scheme = 'percentage' then least(100, greatest(0, value))
    when scheme = 'gpa_4'      then least(100, greatest(0, value / 4.0 * 100))
    when scheme = 'gpa_5'      then least(100, greatest(0, value / 5.0 * 100))
    when scheme = 'ib'         then least(100, greatest(0, value / 45.0 * 100))
    when scheme = 'a_level'    then least(100, greatest(0, value / 6.0 * 100))
    -- WAEC runs backwards: 1 (A1) is the best grade, 9 (F9) is a fail.
    when scheme = 'waec' then case
      when value <= 1 then 95   -- A1
      when value <= 2 then 85   -- B2
      when value <= 3 then 78   -- B3
      when value <= 4 then 70   -- C4
      when value <= 5 then 65   -- C5
      when value <= 6 then 60   -- C6 — the usual credit floor
      when value <= 7 then 50   -- D7
      when value <= 8 then 45   -- E8
      else 0                    -- F9
    end
    -- UK classifications, also backwards: 1 is a First.
    when scheme = 'uk_class' then case
      when value <= 1.0 then 78  -- First
      when value <= 2.1 then 66  -- Upper second
      when value <= 2.2 then 56  -- Lower second
      else 45                    -- Third
    end
  end;
$$;

comment on function normalize_grade is
  'Maps a grade in any supported scheme onto 0-100 so entry requirements are '
  'comparable. Coarse by design: a ranking aid, not a credential evaluation.';

-- --------------------------------------- English proficiency normalization
--
-- Normalized to an IELTS-equivalent band (0-9) because that is what program
-- entry requirements are overwhelmingly quoted in.

create type english_test as enum (
  'none',
  'ielts',
  'toefl',
  'duolingo',
  'pte',
  'waec_english'  -- common in-region: WAEC English at credit level
);

create or replace function normalize_english_band(
  test  english_test,
  score numeric
)
returns numeric
language sql
immutable
as $$
  select case
    when test is null or test = 'none' or score is null then null
    when test = 'ielts' then least(9, greatest(0, score))
    when test = 'toefl' then case          -- iBT, 0-120
      when score >= 110 then 8.0 when score >= 102 then 7.5
      when score >= 94  then 7.0 when score >= 79  then 6.5
      when score >= 60  then 6.0 when score >= 46  then 5.5
      when score >= 35  then 5.0 else 4.0 end
    when test = 'duolingo' then case       -- 10-160
      when score >= 145 then 8.0 when score >= 135 then 7.5
      when score >= 125 then 7.0 when score >= 115 then 6.5
      when score >= 105 then 6.0 when score >= 95  then 5.5
      when score >= 85  then 5.0 else 4.0 end
    when test = 'pte' then case            -- 10-90
      when score >= 85 then 8.0 when score >= 76 then 7.5
      when score >= 65 then 7.0 when score >= 58 then 6.5
      when score >= 50 then 6.0 when score >= 42 then 5.5
      when score >= 36 then 5.0 else 4.0 end
    -- WAEC English subject grade (1=A1 .. 9=F9). Many institutions accept a
    -- credit pass in lieu of a test; treated conservatively.
    when test = 'waec_english' then case
      when score <= 2 then 6.5 when score <= 4 then 6.0
      when score <= 6 then 5.5 else 4.0 end
  end;
$$;

-- ------------------------------------------------------------ the passport

create table student_passports (
  profile_id             uuid primary key references profiles (id) on delete cascade,

  -- Who they are
  date_of_birth          date,
  nationality            text,                -- ISO 3166-1 alpha-2
  current_country        text,                -- ISO 3166-1 alpha-2

  -- What they have
  highest_qualification  text,
  grade_value            numeric(6, 3),
  grade_scheme           grading_scheme,
  english_test_name      english_test not null default 'none',
  english_score          numeric(6, 2),

  -- What they want. These drive matching.
  target_countries       text[] not null default '{}',
  target_levels          study_level[] not null default '{}',
  target_fields          text[] not null default '{}',
  budget_min             numeric(12, 2),
  budget_max             numeric(12, 2),
  budget_currency        text not null default 'USD',
  intended_intake        text,                -- e.g. 'Fall 2026'

  bio                    text,

  -- Trigger-maintained, 0-100. Drives the "complete your passport" nudge and
  -- the match threshold: an empty passport should not be matched to anything.
  completeness           int not null default 0,

  -- 'verified' attests that an admin checked the uploaded documents against
  -- the stated qualifications. It is not a claim about the documents' issuer.
  verification_status    verification_status not null default 'unverified',
  verified_at            timestamptz,
  verified_by            uuid references profiles (id) on delete set null,

  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  constraint passport_budget_order
    check (budget_min is null or budget_max is null or budget_min <= budget_max),
  -- A grade value is meaningless without knowing which scheme it is in.
  constraint passport_grade_needs_scheme
    check ((grade_value is null) = (grade_scheme is null))
);

-- Generated columns so matching never has to re-derive these.
alter table student_passports
  add column normalized_grade numeric(6, 3)
    generated always as (normalize_grade(grade_value, grade_scheme)) stored,
  add column english_band numeric(3, 1)
    generated always as (normalize_english_band(english_test_name, english_score)) stored;

create index passports_targets_idx
  on student_passports using gin (target_countries, target_fields);
create index passports_verification_idx
  on student_passports (verification_status);

create trigger passports_set_updated_at
  before update on student_passports
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------- documents

create type document_kind as enum (
  'transcript',
  'certificate',
  'passport_id',
  'english_test',
  'cv',
  'recommendation',
  'statement',
  'financial'
);

create table passport_documents (
  id                  uuid primary key default gen_random_uuid(),
  profile_id          uuid not null references profiles (id) on delete cascade,
  kind                document_kind not null,
  -- Path within the private `passport-docs` storage bucket. Always prefixed
  -- with the owner's uuid so the storage RLS policy can authorize on prefix.
  storage_path        text not null unique,
  file_name           text not null,
  mime                text,
  size_bytes          bigint,
  verification_status verification_status not null default 'pending',
  reviewed_by         uuid references profiles (id) on delete set null,
  review_note         text,
  reviewed_at         timestamptz,
  created_at          timestamptz not null default now(),

  constraint document_path_is_owner_prefixed
    check (storage_path like (profile_id::text || '/%'))
);

create index passport_documents_profile_idx on passport_documents (profile_id);
create index passport_documents_status_idx on passport_documents (verification_status);

-- ----------------------------------------------- the consent gate: shares
--
-- An institution sees a student's name, contact details and documents ONLY
-- while a row here is live (revoked_at is null). Reverse admission works
-- without one: the institution browses anonymous match cards and invites a
-- student it cannot yet identify. The student grants the share in response.

create table passport_shares (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references profiles (id) on delete cascade,
  institution_id uuid not null references institutions (id) on delete cascade,
  granted_at     timestamptz not null default now(),
  revoked_at     timestamptz,
  -- Why the student granted it, for their own audit view.
  reason         text
);

-- A student may re-grant after revoking, so only one LIVE share per pair.
create unique index passport_shares_one_live
  on passport_shares (profile_id, institution_id)
  where revoked_at is null;

create index passport_shares_institution_idx
  on passport_shares (institution_id) where revoked_at is null;

comment on table passport_shares is
  'Student consent for one institution to see identifying passport data. '
  'Revocation is a timestamp, not a delete, so the grant history survives.';

-- --------------------------------------------- completeness recomputation

create or replace function recompute_passport_completeness()
returns trigger
language plpgsql
as $$
declare
  target uuid;
  score  int := 0;
  docs   int;
  p      student_passports;
begin
  -- Fires from both student_passports and passport_documents.
  target := case tg_table_name
              when 'passport_documents' then coalesce(new.profile_id, old.profile_id)
              else coalesce(new.profile_id, old.profile_id)
            end;

  select * into p from student_passports where profile_id = target;
  if not found then
    return coalesce(new, old);
  end if;

  -- Identity: 25
  if p.date_of_birth is not null then score := score + 8; end if;
  if p.nationality   is not null then score := score + 9; end if;
  if p.current_country is not null then score := score + 8; end if;

  -- Academics: 30
  if p.highest_qualification is not null then score := score + 10; end if;
  if p.grade_value is not null then score := score + 12; end if;
  if p.english_band is not null then score := score + 8; end if;

  -- Intent — without these there is nothing to match on: 30
  if array_length(p.target_countries, 1) > 0 then score := score + 10; end if;
  if array_length(p.target_levels, 1)    > 0 then score := score + 8;  end if;
  if array_length(p.target_fields, 1)    > 0 then score := score + 12; end if;

  -- Evidence: 15
  select count(*) into docs from passport_documents where profile_id = target;
  score := score + least(15, docs * 5);

  update student_passports
     set completeness = least(100, score)
   where profile_id = target
     and completeness is distinct from least(100, score);

  return coalesce(new, old);
end;
$$;

-- `before` on the passport itself so the row being written is scored with its
-- new values; `after` on documents since they are a separate table.
create trigger passports_recompute_completeness
  after insert or update of
    date_of_birth, nationality, current_country, highest_qualification,
    grade_value, grade_scheme, english_test_name, english_score,
    target_countries, target_levels, target_fields
  on student_passports
  for each row execute function recompute_passport_completeness();

create trigger documents_recompute_completeness
  after insert or delete on passport_documents
  for each row execute function recompute_passport_completeness();
