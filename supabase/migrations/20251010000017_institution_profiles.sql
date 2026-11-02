-- Lekkside Connect — the institution prospectus.
--
-- An `institutions` row holds eleven columns, so the student-facing page can
-- render a logo, a location, one paragraph and three buttons. None of that
-- answers what a student is actually deciding on: what it costs to live there,
-- whether their WASSCE grades qualify, when applications close, whether there
-- is funding.
--
-- A separate table rather than twenty more columns on `institutions`, which a
-- dozen queries already join and which should stay lean — the prospectus is
-- read on one screen and written on one screen.

-- --------------------------------------------------------------- the profile

create table institution_profiles (
  institution_id uuid primary key references institutions (id) on delete cascade,

  tagline        text,
  about          text,
  campus_life    text,
  accommodation  text,

  founded_year                int,
  student_count               int,
  international_student_count int,

  -- Living costs, kept apart from tuition: tuition belongs to a program, and
  -- a student comparing two countries needs both numbers separately.
  cost_of_living_min numeric(12, 2),
  cost_of_living_max numeric(12, 2),
  cost_currency      text not null default 'USD',

  application_fee numeric(12, 2),
  deposit         numeric(12, 2),
  fee_currency    text not null default 'USD',

  accreditation text[] not null default '{}',

  -- [{ "body": "QS World", "rank": 301, "year": 2026 }]
  rankings jsonb not null default '[]'::jsonb,

  -- { "x": "...", "instagram": "...", "linkedin": "...", "youtube": "..." }
  socials jsonb not null default '{}'::jsonb,

  -- [{ "title": "Submit your transcript", "detail": "..." }] — short, ordered,
  -- and always edited as a block, so a table would only add joins.
  application_steps jsonb not null default '[]'::jsonb,

  -- Trigger-maintained, 0-100. Same idea as the student passport's
  -- completeness: a nudge toward a page worth reading, and later the gate for
  -- featured placement in discovery.
  completeness int not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint institution_cost_order
    check (cost_of_living_min is null or cost_of_living_max is null
           or cost_of_living_min <= cost_of_living_max),
  constraint institution_founded_plausible
    check (founded_year is null
           or founded_year between 800 and extract(year from now())::int)
);

create trigger institution_profiles_set_updated_at
  before update on institution_profiles
  for each row execute function set_updated_at();

-- Every institution gets an empty profile, so the console always has a row to
-- edit and the student page never has to branch on its absence.
create or replace function create_institution_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into institution_profiles (institution_id)
  values (new.id)
  on conflict (institution_id) do nothing;
  return new;
end;
$$;

create trigger institutions_create_profile
  after insert on institutions
  for each row execute function create_institution_profile();

insert into institution_profiles (institution_id)
select id from institutions
on conflict (institution_id) do nothing;

-- ----------------------------------------------------------------- the media

create type institution_media_kind as enum ('photo', 'brochure', 'video_link');

create table institution_media (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  kind           institution_media_kind not null default 'photo',

  -- Path within the public `institution-media` bucket, prefixed with the
  -- institution's uuid so the storage policy can authorize on prefix alone.
  storage_path   text,
  -- For 'video_link': a YouTube or Vimeo URL. Embedding beats hosting video.
  external_url   text,

  caption        text,
  ord            int not null default 0,
  created_at     timestamptz not null default now(),

  constraint institution_media_has_a_source
    check ((kind = 'video_link') = (external_url is not null)
           and (kind = 'video_link') = (storage_path is null)),
  constraint institution_media_path_is_prefixed
    check (storage_path is null
           or storage_path like (institution_id::text || '/%'))
);

create index institution_media_order on institution_media (institution_id, ord);

-- --------------------------------------------------------------- the intakes

create table institution_intakes (
  id                 uuid primary key default gen_random_uuid(),
  institution_id     uuid not null references institutions (id) on delete cascade,
  label              text not null,
  applications_open  date,
  applications_close date,
  term_starts        date,
  ord                int not null default 0,
  created_at         timestamptz not null default now(),

  unique (institution_id, label),
  constraint intake_window_order
    check (applications_open is null or applications_close is null
           or applications_open <= applications_close)
);

create index institution_intakes_order on institution_intakes (institution_id, ord);

-- ---------------------------------------------------------- the scholarships

create table institution_scholarships (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  name           text not null,
  amount         numeric(12, 2),
  currency       text not null default 'USD',
  -- "Full tuition", "50% of tuition", "One-off" — not every award is a number.
  coverage       text,
  criteria       text,
  deadline       date,
  url            text,
  ord            int not null default 0,
  created_at     timestamptz not null default now()
);

create index institution_scholarships_order
  on institution_scholarships (institution_id, ord);

-- ------------------------------------------------- entry requirements, by country
--
-- The question students actually ask is not "what are the entry requirements"
-- but "what do I need, from Nigeria, for an undergraduate place". A null
-- country or level means "applies to everyone", so an institution can state a
-- general rule once and override it per country.

create table institution_entry_requirements (
  id               uuid primary key default gen_random_uuid(),
  institution_id   uuid not null references institutions (id) on delete cascade,

  from_country     text,              -- ISO 3166-1 alpha-2; null = any
  level            study_level,       -- null = any

  qualification    text,              -- 'WASSCE with 5 credits', 'A-Levels', …
  min_grade_value  numeric(6, 3),
  min_grade_scheme grading_scheme,
  min_english_band numeric(3, 1),     -- IELTS-equivalent, as elsewhere
  additional       text[] not null default '{}',
  note             text,

  ord              int not null default 0,
  created_at       timestamptz not null default now(),

  unique (institution_id, from_country, level),
  constraint entry_grade_needs_scheme
    check ((min_grade_value is null) = (min_grade_scheme is null))
);

create index institution_entry_requirements_lookup
  on institution_entry_requirements (institution_id, from_country, level);

-- -------------------------------------------------------------- the contacts

create table institution_contacts (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  role           text not null,       -- 'International admissions', …
  name           text,
  email          text,
  phone          text,
  ord            int not null default 0,
  created_at     timestamptz not null default now()
);

create index institution_contacts_order on institution_contacts (institution_id, ord);

-- ------------------------------------------------------------------ the FAQs

create table institution_faqs (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  question       text not null,
  answer         text not null,
  ord            int not null default 0,
  created_at     timestamptz not null default now()
);

create index institution_faqs_order on institution_faqs (institution_id, ord);

-- ------------------------------------------------------------- completeness
--
-- Mirrors recompute_passport_completeness() in …002_passport.sql: a trigger
-- scoring filled fields, so an organisation gets the same nudge a student does.

create or replace function recompute_institution_completeness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.institution_id, old.institution_id);
  p      institution_profiles;
  score  int := 0;
begin
  select * into p from institution_profiles where institution_id = target;
  if not found then
    return coalesce(new, old);
  end if;

  -- Who you are: 25
  if coalesce(trim(p.tagline), '') <> ''     then score := score + 5;  end if;
  if coalesce(trim(p.about), '') <> ''       then score := score + 12; end if;
  if p.founded_year is not null              then score := score + 4;  end if;
  if p.student_count is not null             then score := score + 4;  end if;

  -- What it is like: 20
  if coalesce(trim(p.campus_life), '') <> ''    then score := score + 10; end if;
  if coalesce(trim(p.accommodation), '') <> '' then score := score + 10; end if;

  -- What it costs — the first thing anyone asks: 15
  if p.cost_of_living_max is not null then score := score + 10; end if;
  if p.application_fee is not null    then score := score + 5;  end if;

  -- Credibility: 10
  if array_length(p.accreditation, 1) > 0        then score := score + 5; end if;
  if jsonb_array_length(p.rankings) > 0          then score := score + 5; end if;

  -- How to act on it: 10
  if jsonb_array_length(p.application_steps) > 0 then score := score + 10; end if;

  -- The pieces that make the page worth reading: 20
  if exists (select 1 from institution_media where institution_id = target)
    then score := score + 6; end if;
  if exists (select 1 from institution_intakes where institution_id = target)
    then score := score + 4; end if;
  if exists (select 1 from institution_entry_requirements where institution_id = target)
    then score := score + 5; end if;
  if exists (select 1 from institution_contacts where institution_id = target)
    then score := score + 3; end if;
  if exists (select 1 from institution_faqs where institution_id = target)
    then score := score + 2; end if;

  update institution_profiles
     set completeness = least(100, score)
   where institution_id = target
     and completeness is distinct from least(100, score);

  return coalesce(new, old);
end;
$$;

-- `after update of <columns>` deliberately omits `completeness`, so the nested
-- update above cannot re-fire this trigger.
create trigger institution_profiles_recompute
  after insert or update of
    tagline, about, campus_life, accommodation, founded_year, student_count,
    cost_of_living_max, application_fee, accreditation, rankings,
    application_steps
  on institution_profiles
  for each row execute function recompute_institution_completeness();

do $$
declare
  t text;
begin
  foreach t in array array[
    'institution_media', 'institution_intakes', 'institution_entry_requirements',
    'institution_contacts', 'institution_faqs'
  ] loop
    execute format(
      'create trigger %I_recompute_completeness
         after insert or delete on %I
         for each row execute function recompute_institution_completeness()',
      t, t);
  end loop;
end
$$;
