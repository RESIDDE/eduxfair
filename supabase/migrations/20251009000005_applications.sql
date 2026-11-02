-- Lekkside Connect — the admission pipeline.
--
-- The pipeline is what makes this more than a directory: it carries a student
-- from "interested" to "enrolled" and gives the institution a CRM view of its
-- cohort. Every stage change is recorded in `application_events` — never
-- overwritten — because when an offer or rejection is disputed months later,
-- the audit trail is the only thing that settles it.

create type application_stage as enum (
  'draft',
  'submitted',
  'under_review',
  'documents_requested',
  'conditional_offer',
  'offer',
  'rejected',
  'accepted',          -- student accepted the offer
  'deposit_paid',
  'visa',
  'enrolled',
  'withdrawn'
);

create table applications (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references profiles (id) on delete cascade,
  institution_id uuid not null references institutions (id) on delete cascade,
  program_id     uuid not null references programs (id) on delete restrict,
  intake         text,
  stage          application_stage not null default 'draft',
  assigned_to    uuid references profiles (id) on delete set null,
  student_note   text,
  submitted_at   timestamptz,
  decision_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  -- One live application per student per program. A withdrawn or rejected one
  -- should not block re-applying for a later intake.
  constraint applications_stage_timing
    check (stage = 'draft' or submitted_at is not null)
);

create unique index applications_one_live
  on applications (profile_id, program_id)
  where stage not in ('rejected', 'withdrawn');

create index applications_institution_idx
  on applications (institution_id, stage, updated_at desc);
create index applications_profile_idx on applications (profile_id, updated_at desc);
create index applications_assignee_idx on applications (assigned_to) where assigned_to is not null;

create trigger applications_set_updated_at
  before update on applications
  for each row execute function set_updated_at();

-- Submitting stamps the time, so the constraint above is satisfied without the
-- client having to remember.
create or replace function stamp_application_timestamps()
returns trigger
language plpgsql
as $$
begin
  if new.stage <> 'draft' and new.submitted_at is null then
    new.submitted_at := now();
  end if;

  if new.stage in ('conditional_offer', 'offer', 'rejected')
     and (tg_op = 'INSERT' or new.stage is distinct from old.stage) then
    new.decision_at := now();
  end if;

  return new;
end;
$$;

create trigger applications_stamp_timestamps
  before insert or update of stage on applications
  for each row execute function stamp_application_timestamps();

-- ------------------------------------------------------- immutable audit trail

create table application_events (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications (id) on delete cascade,
  from_stage     application_stage,
  to_stage       application_stage not null,
  actor_id       uuid references profiles (id) on delete set null,
  note           text,
  created_at     timestamptz not null default now()
);

create index application_events_application_idx
  on application_events (application_id, created_at);

comment on table application_events is
  'Append-only. RLS grants no UPDATE or DELETE to anyone, including admin: a '
  'decision history that can be edited is not a decision history.';

create or replace function log_application_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into application_events (application_id, from_stage, to_stage, actor_id)
    values (new.id, null, new.stage, auth.uid());
  elsif new.stage is distinct from old.stage then
    insert into application_events (application_id, from_stage, to_stage, actor_id)
    values (new.id, old.stage, new.stage, auth.uid());
  end if;

  return new;
end;
$$;

create trigger applications_log_event
  after insert or update of stage on applications
  for each row execute function log_application_event();

-- ------------------------------------------------- documents on an application

-- Links an existing passport document to an application rather than copying it.
-- The student uploads a transcript once and attaches it to five applications.
create table application_documents (
  application_id uuid not null references applications (id) on delete cascade,
  document_id    uuid not null references passport_documents (id) on delete cascade,
  attached_at    timestamptz not null default now(),

  primary key (application_id, document_id)
);

-- What the institution asked for, when stage = 'documents_requested'.
create table application_document_requests (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications (id) on delete cascade,
  kind           document_kind not null,
  note           text,
  requested_by   uuid references profiles (id) on delete set null,
  fulfilled_at   timestamptz,
  created_at     timestamptz not null default now()
);

create index application_document_requests_app_idx
  on application_document_requests (application_id) where fulfilled_at is null;
