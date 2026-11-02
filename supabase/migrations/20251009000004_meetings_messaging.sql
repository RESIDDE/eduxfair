-- Lekkside Connect — Meet Me appointments and messaging.
--
-- Phase 1 deliberately has no in-app video. An appointment carries a
-- `meeting_url` supplied by the institution (Meet/Zoom/Teams) or is held in
-- person at a fair. The `channel` column means swapping in LiveKit later is an
-- additive change, not a migration.

-- ------------------------------------------------------------- availability

create table availability_slots (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references institutions (id) on delete cascade,
  host_profile_id uuid not null references profiles (id) on delete cascade,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  is_booked       boolean not null default false,
  created_at      timestamptz not null default now(),

  constraint availability_slot_order check (starts_at < ends_at)
);

create index availability_open_idx
  on availability_slots (institution_id, starts_at)
  where not is_booked;

-- One host cannot hold two overlapping open slots. Needs btree_gist to mix the
-- uuid equality with the range overlap in one exclusion constraint.
create extension if not exists btree_gist;

alter table availability_slots
  add constraint availability_no_overlap
  exclude using gist (
    host_profile_id with =,
    tstzrange(starts_at, ends_at) with &&
  );

-- ------------------------------------------------------------- appointments

create type appointment_channel as enum ('video', 'phone', 'in_person', 'chat');

create type appointment_status as enum (
  'requested',
  'confirmed',
  'declined',
  'rescheduled',
  'completed',
  'no_show',
  'cancelled'
);

create table appointments (
  id              uuid primary key default gen_random_uuid(),
  student_id      uuid not null references profiles (id) on delete cascade,
  institution_id  uuid not null references institutions (id) on delete cascade,
  program_id      uuid references programs (id) on delete set null,
  host_profile_id uuid references profiles (id) on delete set null,
  slot_id         uuid references availability_slots (id) on delete set null,

  scheduled_for   timestamptz,
  duration_min    int not null default 30,
  channel         appointment_channel not null default 'video',
  status          appointment_status not null default 'requested',
  -- Populated when the institution confirms. Phase 1: an external link.
  meeting_url     text,
  student_message text,
  notes           text,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- A confirmed appointment with no time is not actionable by either side.
  constraint appointment_confirmed_needs_time
    check (status <> 'confirmed' or scheduled_for is not null)
);

create index appointments_student_idx on appointments (student_id, scheduled_for desc);
create index appointments_institution_idx
  on appointments (institution_id, status, scheduled_for);

create trigger appointments_set_updated_at
  before update on appointments
  for each row execute function set_updated_at();

-- Keep slot.is_booked honest, so two students cannot take the same slot.
create or replace function sync_slot_booking()
returns trigger
language plpgsql
as $$
begin
  if tg_op in ('INSERT', 'UPDATE') and new.slot_id is not null
     and new.status in ('requested', 'confirmed', 'rescheduled') then
    update availability_slots set is_booked = true where id = new.slot_id;
  end if;

  -- Freeing the slot on the way out, whether released or reassigned.
  if tg_op = 'UPDATE' and old.slot_id is not null
     and (new.slot_id is distinct from old.slot_id
          or new.status in ('declined', 'cancelled', 'no_show')) then
    update availability_slots s
       set is_booked = false
     where s.id = old.slot_id
       and not exists (
         select 1 from appointments a
          where a.slot_id = s.id
            and a.id <> coalesce(new.id, old.id)
            and a.status in ('requested', 'confirmed', 'rescheduled'));
  end if;

  return new;
end;
$$;

create trigger appointments_sync_slot
  after insert or update of slot_id, status on appointments
  for each row execute function sync_slot_booking();

-- ---------------------------------------------------------------- messaging

-- A conversation is always between one student and one institution. Group
-- threads and live educator rooms are Phase 2 and will need their own shape.
create table conversations (
  id              uuid primary key default gen_random_uuid(),
  student_id      uuid not null references profiles (id) on delete cascade,
  institution_id  uuid not null references institutions (id) on delete cascade,
  subject         text,
  last_message_at timestamptz,
  created_at      timestamptz not null default now(),

  unique (student_id, institution_id)
);

create index conversations_institution_idx
  on conversations (institution_id, last_message_at desc nulls last);
create index conversations_student_idx
  on conversations (student_id, last_message_at desc nulls last);

-- Read state per person. Institution side can have several officers reading
-- one thread, which is why this is a table and not a column.
create table conversation_participants (
  conversation_id uuid not null references conversations (id) on delete cascade,
  profile_id      uuid not null references profiles (id) on delete cascade,
  last_read_at    timestamptz,

  primary key (conversation_id, profile_id)
);

create table messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations (id) on delete cascade,
  sender_id       uuid not null references profiles (id) on delete cascade,
  body            text,
  -- Path in the private `message-attachments` bucket.
  attachment_path text,
  created_at      timestamptz not null default now(),

  constraint message_has_content
    check (coalesce(trim(body), '') <> '' or attachment_path is not null)
);

create index messages_conversation_idx on messages (conversation_id, created_at desc);

-- Realtime: the Flutter and React clients subscribe to inserts here.
alter publication supabase_realtime add table messages;

create or replace function touch_conversation()
returns trigger
language plpgsql
as $$
begin
  update conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;
  return new;
end;
$$;

create trigger messages_touch_conversation
  after insert on messages
  for each row execute function touch_conversation();
