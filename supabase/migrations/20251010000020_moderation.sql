-- Lekkside Connect — reporting, blocking, restrictions and rate limits.
--
-- In the same step as the first public content, not after students arrive. A
-- feed mixing adults and minors with no reporting path is a safety problem,
-- and the worst time to build moderation is after an incident.
--
-- Reposting makes amplification possible, which raises the stakes: removing a
-- post has to remove every repost of it, or a deletion leaves copies behind.

create type report_subject as enum ('post', 'comment', 'profile', 'space');

create type report_reason as enum (
  'spam',
  'harassment',
  'misinformation',   -- false admissions or visa claims, which do real damage
  'impersonation',
  'inappropriate',
  'child_safety',     -- routed ahead of everything else
  'other'
);

create table reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references profiles (id) on delete cascade,
  subject_type report_subject not null,
  subject_id   uuid not null,
  reason       report_reason not null,
  note         text,

  -- Reuses the shape of `verifications` so admin keeps one inbox rather than
  -- two review queues with separate habits.
  status       verification_status not null default 'pending',
  reviewer_id  uuid references profiles (id) on delete set null,
  review_note  text,
  decided_at   timestamptz,
  created_at   timestamptz not null default now(),

  -- One open report per person per thing; repeat reports update the first.
  unique (reporter_id, subject_type, subject_id)
);

create index reports_queue_idx on reports (status, created_at)
  where status = 'pending';
-- Child-safety reports jump the queue, and the index says so.
create index reports_urgent_idx on reports (created_at)
  where status = 'pending' and reason = 'child_safety';
create index reports_subject_idx on reports (subject_type, subject_id);

-- -------------------------------------------------------- blocks and mutes

-- Mutual invisibility: neither sees the other's posts, replies or profile.
create table blocks (
  blocker_id uuid not null references profiles (id) on delete cascade,
  blocked_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on blocks (blocked_id);

-- Feed-only: a muted account is absent from the feed but still reachable on
-- their own profile, which is the difference students expect.
create table mutes (
  muter_id   uuid not null references profiles (id) on delete cascade,
  muted_id   uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  constraint no_self_mute check (muter_id <> muted_id)
);

-- ------------------------------------------------------------ restrictions

create type restriction_kind as enum ('read_only', 'suspended');

create table account_restrictions (
  id         uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  kind       restriction_kind not null,
  reason     text not null,
  until      timestamptz,          -- null is indefinite
  created_by uuid references profiles (id) on delete set null,
  lifted_at  timestamptz,
  created_at timestamptz not null default now()
);

create unique index account_restrictions_one_live
  on account_restrictions (profile_id)
  where lifted_at is null;

-- ------------------------------------------------------------- the helpers

create or replace function is_restricted(p_profile_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from account_restrictions
     where profile_id = coalesce(p_profile_id, auth.uid())
       and lifted_at is null
       and (until is null or until > now()));
$$;

/** Either direction: a block hides both parties from each other. */
create or replace function is_blocked_either_way(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from blocks
     where (blocker_id = auth.uid() and blocked_id = p_other)
        or (blocker_id = p_other and blocked_id = auth.uid()));
$$;

create or replace function is_muted(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from mutes where muter_id = auth.uid() and muted_id = p_other);
$$;

-- Caps, kept as functions so they are reviewable in one place.
create or replace function post_rate_limit() returns int
  language sql immutable as $$ select 20 $$;
create or replace function comment_rate_limit() returns int
  language sql immutable as $$ select 60 $$;

/**
 * Gate on every authored write.
 *
 * Checks the restriction and the hourly cap together, because the two refusals
 * a person can hit when posting should come from one place.
 */
create or replace function assert_can_write(p_kind text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  recent int;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if is_restricted() then
    raise exception 'Your account is restricted and cannot post right now.';
  end if;

  if p_kind = 'post' then
    select count(*) into recent
      from posts
     where author_id = auth.uid() and created_at > now() - interval '1 hour';
    if recent >= post_rate_limit() then
      raise exception 'That is a lot of posting in an hour. Try again shortly.';
    end if;
  else
    select count(*) into recent
      from comments
     where author_id = auth.uid() and created_at > now() - interval '1 hour';
    if recent >= comment_rate_limit() then
      raise exception 'That is a lot of replying in an hour. Try again shortly.';
    end if;
  end if;
end;
$$;

-- ------------------------------------------------- minors and direct messages
--
-- `social_profiles.is_minor` is derived from the passport's date of birth by a
-- trigger, never self-declared, so this cannot be sidestepped by editing a
-- profile.

create or replace function is_minor(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select is_minor from social_profiles where profile_id = p_profile_id),
    false);
$$;

/**
 * Whether an organisation may open a conversation with this student.
 *
 * An adult organisation account cannot cold-message a minor. Once the student
 * follows them, applies, or asks for a meeting, they have chosen the contact
 * and the conversation is theirs to have.
 */
create or replace function institution_may_message(p_student_id uuid, p_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    not is_minor(p_student_id)
    or exists (select 1 from follows f
                join institution_members m on m.profile_id = f.followee_id
               where f.follower_id = p_student_id
                 and m.institution_id = p_institution_id)
    or exists (select 1 from applications
                where profile_id = p_student_id
                  and institution_id = p_institution_id)
    or exists (select 1 from appointments
                where student_id = p_student_id
                  and institution_id = p_institution_id)
    or exists (select 1 from passport_shares
                where profile_id = p_student_id
                  and institution_id = p_institution_id
                  and revoked_at is null);
$$;

create or replace function guard_conversation_with_minor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only institution-opened threads are gated: a student reaching out is the
  -- student's own decision.
  if new.student_id = auth.uid() then
    return new;
  end if;

  if not institution_may_message(new.student_id, new.institution_id) then
    raise exception
      'This student has not been in touch with you yet, so you cannot start a '
      'conversation. Invite them or wait for them to reach out.';
  end if;

  return new;
end;
$$;

create trigger conversations_guard_minor
  before insert on conversations
  for each row execute function guard_conversation_with_minor();

-- --------------------------------------------- removing content, and its copies

/**
 * Soft-deletes a post and every repost of it.
 *
 * Without the second part, removing something harmful would leave every
 * reshare standing — which is where it had actually spread.
 */
create or replace function remove_post(p_post_id uuid, p_reason text default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
  v_removed int;
begin
  select author_id into v_author from posts where id = p_post_id;
  if v_author is null then
    raise exception 'no such post';
  end if;

  if v_author <> auth.uid() and not is_admin() then
    raise exception 'not your post';
  end if;

  update posts set deleted_at = now()
   where (id = p_post_id or repost_of = p_post_id)
     and deleted_at is null;
  get diagnostics v_removed = row_count;

  if p_reason is not null then
    update reports
       set status = 'verified', review_note = p_reason,
           reviewer_id = auth.uid(), decided_at = now()
     where subject_type = 'post' and subject_id = p_post_id
       and status = 'pending';
  end if;

  return v_removed;
end;
$$;

revoke all on function remove_post(uuid, text) from public;
grant execute on function remove_post(uuid, text) to authenticated;
