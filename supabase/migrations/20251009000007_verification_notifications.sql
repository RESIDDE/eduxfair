-- Lekkside Connect — the verification queue, notifications and subscriptions.
--
-- Verification is the trust product. One polymorphic queue gives admin a single
-- inbox across institutions, documents, passports and educators, instead of
-- four screens that each get half-checked.

create type verification_subject as enum (
  'institution',
  'passport',
  'document',
  'educator'
);

create table verifications (
  id           uuid primary key default gen_random_uuid(),
  subject_type verification_subject not null,
  subject_id   uuid not null,
  status       verification_status not null default 'pending',
  -- What we actually checked, so a badge can be justified after the fact:
  -- e.g. {"method":"domain_email","domain":"utoronto.ca","confirmed_at":"..."}
  evidence     jsonb not null default '{}'::jsonb,
  reviewer_id  uuid references profiles (id) on delete set null,
  review_note  text,
  decided_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- One open request per subject; history is kept once decided.
create unique index verifications_one_open
  on verifications (subject_type, subject_id)
  where status = 'pending';

create index verifications_queue_idx
  on verifications (status, created_at) where status = 'pending';
create index verifications_subject_idx on verifications (subject_type, subject_id);

create trigger verifications_set_updated_at
  before update on verifications
  for each row execute function set_updated_at();

comment on column verifications.evidence is
  'The basis for the badge. A VERIFIED INSTITUTION badge means exactly what is '
  'recorded here — domain-email confirmation — and nothing about accreditation.';

-- Applying a decision writes it back to the subject, so the badge shown in the
-- apps never disagrees with the queue.
create or replace function apply_verification_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  new.decided_at := case when new.status in ('verified', 'rejected')
                         then now() else null end;

  if new.subject_type = 'institution' then
    update institutions
       set verification_status = new.status,
           verified_at = case when new.status = 'verified' then now() else null end
     where id = new.subject_id;

  elsif new.subject_type = 'passport' then
    update student_passports
       set verification_status = new.status,
           verified_at = case when new.status = 'verified' then now() else null end,
           verified_by = new.reviewer_id
     where profile_id = new.subject_id;

  elsif new.subject_type = 'document' then
    update passport_documents
       set verification_status = new.status,
           reviewed_by = new.reviewer_id,
           review_note = new.review_note,
           reviewed_at = now()
     where id = new.subject_id;

  elsif new.subject_type = 'educator' then
    update educators
       set verification_status = new.status
     where profile_id = new.subject_id;
  end if;

  return new;
end;
$$;

create trigger verifications_apply_decision
  before update of status on verifications
  for each row execute function apply_verification_decision();

-- ------------------------------------------------------------ notifications

create table notifications (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  -- e.g. 'institution_invited_you', 'appointment_confirmed', 'stage_changed'
  kind       text not null,
  title      text not null,
  body       text,
  payload    jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_unread_idx
  on notifications (profile_id, created_at desc) where read_at is null;
create index notifications_profile_idx on notifications (profile_id, created_at desc);

alter publication supabase_realtime add table notifications;

-- ------------------------------------------------------------ subscriptions
--
-- Billing itself is Phase 2 (Paystack in-region, Stripe international). The
-- table exists now so tier gating has somewhere to read from and so we are not
-- migrating live institution records later.

create table institution_subscriptions (
  institution_id uuid primary key references institutions (id) on delete cascade,
  tier           institution_tier not null default 'basic',
  status         text not null default 'active',
  seats          int not null default 1,
  period_start   date,
  period_end     date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint subscription_seats_positive check (seats > 0)
);

create trigger institution_subscriptions_set_updated_at
  before update on institution_subscriptions
  for each row execute function set_updated_at();

-- Keep institutions.tier in step with the subscription, since every read path
-- in the apps looks at the institution row.
create or replace function sync_institution_tier()
returns trigger
language plpgsql
as $$
begin
  update institutions set tier = new.tier where id = new.institution_id;
  return new;
end;
$$;

create trigger institution_subscriptions_sync_tier
  after insert or update of tier on institution_subscriptions
  for each row execute function sync_institution_tier();
