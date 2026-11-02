-- Lekkside Connect — physical fairs and the Fair Passport.
--
-- This is the bridge between the Lagos events and the year-round platform. A
-- student registers once, gets a QR pass, and taps CONNECT at each booth. The
-- institution gets a qualified lead instead of a business card; the student
-- gets an event report instead of a tote bag of brochures.
--
-- CONSENT MODEL: walking to a booth and tapping CONNECT is a real act of
-- consent, so a scan grants the institution access to the student's passport.
-- Crucially it does so by writing a normal `passport_shares` row rather than by
-- being a special case in the RLS helper. That keeps one single gate for
-- identifying data, which means the student's "who can see me" screen is
-- automatically complete and every grant is revocable in one place.

-- ------------------------------------------------------------------- fairs

create table fairs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       text not null unique,
  city       text,
  country    text,
  venue      text,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),

  constraint fairs_date_order check (starts_at < ends_at)
);

-- --------------------------------------------------------------- pass codes

-- Short, human-readable, unambiguous: no I/O/0/1, so a code read aloud at a
-- busy registration desk cannot be mistyped. 8 chars of a 32-char alphabet is
-- ~40 bits, which is ample for a single event and still fits a printed badge.
create or replace function generate_pass_code(len int default 8)
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  out text := '';
  i int;
begin
  for i in 1 .. len loop
    out := out || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
  end loop;
  return out;
end;
$$;

-- ------------------------------------------------------------ registrations

create table fair_registrations (
  id           uuid primary key default gen_random_uuid(),
  fair_id      uuid not null references fairs (id) on delete cascade,
  profile_id   uuid not null references profiles (id) on delete cascade,
  -- The QR payload. Scoped per fair so a leaked code expires with the event.
  pass_code    text not null,
  checked_in_at timestamptz,
  created_at   timestamptz not null default now(),

  unique (fair_id, profile_id),
  unique (fair_id, pass_code)
);

create index fair_registrations_profile_idx on fair_registrations (profile_id);

-- Assign a pass code on registration, retrying on the (rare) collision.
create or replace function assign_pass_code()
returns trigger
language plpgsql
as $$
declare
  candidate text;
  tries int := 0;
begin
  if new.pass_code is not null and new.pass_code <> '' then
    return new;
  end if;

  loop
    candidate := generate_pass_code();
    exit when not exists (
      select 1 from fair_registrations
       where fair_id = new.fair_id and pass_code = candidate);
    tries := tries + 1;
    if tries > 20 then
      raise exception 'could not allocate a unique pass code for fair %', new.fair_id;
    end if;
  end loop;

  new.pass_code := candidate;
  return new;
end;
$$;

create trigger fair_registrations_assign_pass_code
  before insert on fair_registrations
  for each row execute function assign_pass_code();

-- --------------------------------------------------------------- exhibitors

create type exhibitor_package as enum ('booth_only', 'booth_plus_platform', 'sponsor');

create table fair_exhibitors (
  id             uuid primary key default gen_random_uuid(),
  fair_id        uuid not null references fairs (id) on delete cascade,
  institution_id uuid not null references institutions (id) on delete cascade,
  -- Identifies the booth to the scanner. Not a secret: the authorization for a
  -- scan is the signed-in staff member's membership, not knowledge of this.
  booth_code     text not null,
  booth_label    text,
  package        exhibitor_package not null default 'booth_only',
  created_at     timestamptz not null default now(),

  unique (fair_id, institution_id),
  unique (fair_id, booth_code)
);

create index fair_exhibitors_institution_idx on fair_exhibitors (institution_id);

-- ------------------------------------------------------------- booth visits

create type interest_level as enum ('low', 'medium', 'high');

create table booth_visits (
  id                  uuid primary key default gen_random_uuid(),
  fair_id             uuid not null references fairs (id) on delete cascade,
  exhibitor_id        uuid not null references fair_exhibitors (id) on delete cascade,
  profile_id          uuid not null references profiles (id) on delete cascade,
  program_id          uuid references programs (id) on delete set null,
  -- Free text for when the conversation was about something not yet listed.
  program_interest    text,
  interest_level      interest_level not null default 'medium',
  follow_up_requested boolean not null default false,
  scholarship_discussed boolean not null default false,
  note                text,
  scanned_by          uuid references profiles (id) on delete set null,
  created_at          timestamptz not null default now(),

  -- One visit row per student per booth; a second tap updates the first.
  unique (exhibitor_id, profile_id)
);

create index booth_visits_profile_idx on booth_visits (profile_id);
create index booth_visits_exhibitor_idx on booth_visits (exhibitor_id, created_at desc);

-- ------------------------------------------------------- the consent helper

-- Used by the booth scan and by the application/appointment triggers below, so
-- that every path which implies consent produces an identical, revocable row.
create or replace function grant_passport_share(
  p_profile_id     uuid,
  p_institution_id uuid,
  p_reason         text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing uuid;
begin
  select id into existing
    from passport_shares
   where profile_id = p_profile_id
     and institution_id = p_institution_id
     and revoked_at is null;

  if existing is not null then
    return existing;
  end if;

  insert into passport_shares (profile_id, institution_id, reason)
  values (p_profile_id, p_institution_id, p_reason)
  returning id into existing;

  return existing;
end;
$$;

-- Submitting an application to an institution, or asking it for a meeting, is
-- an unambiguous request to be identified by it. Both create a visible share
-- rather than relying on a hidden exception in the access rules.
create or replace function share_on_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.stage <> 'draft' then
    perform grant_passport_share(
      new.profile_id, new.institution_id, 'You applied to this institution');
  end if;
  return new;
end;
$$;

create trigger applications_grant_share
  after insert or update of stage on applications
  for each row execute function share_on_application();

create or replace function share_on_appointment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform grant_passport_share(
    new.student_id, new.institution_id, 'You requested a meeting');
  return new;
end;
$$;

create trigger appointments_grant_share
  after insert on appointments
  for each row execute function share_on_appointment();

-- --------------------------------------------------------- the booth scan
--
-- Must be a function, not a client insert: it resolves a pass code, checks the
-- scanner really works for that booth, writes the visit and grants the share
-- in one transaction. The anon/authenticated role has no direct insert on
-- booth_visits at all (see the RLS migration).

create or replace function record_booth_visit(
  p_pass_code             text,
  p_booth_code            text,
  p_program_id            uuid    default null,
  p_program_interest      text    default null,
  p_interest_level        interest_level default 'medium',
  p_follow_up_requested   boolean default false,
  p_scholarship_discussed boolean default false,
  p_note                  text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exhibitor fair_exhibitors;
  v_student   uuid;
  v_fair      fairs;
  v_visit_id  uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  -- Resolve the booth, then confirm the caller actually staffs it. Admin may
  -- scan on an exhibitor's behalf at the registration desk.
  select e.* into v_exhibitor
    from fair_exhibitors e
   where upper(e.booth_code) = upper(trim(p_booth_code));

  if not found then
    raise exception 'unknown booth code';
  end if;

  if not exists (
    select 1 from institution_members m
     where m.institution_id = v_exhibitor.institution_id
       and m.profile_id = auth.uid()
  ) and not exists (
    select 1 from profiles where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'you are not registered to this booth';
  end if;

  select * into v_fair from fairs where id = v_exhibitor.fair_id;

  -- Resolve the student's pass within the same fair.
  select r.profile_id into v_student
    from fair_registrations r
   where r.fair_id = v_exhibitor.fair_id
     and upper(r.pass_code) = upper(trim(p_pass_code));

  if v_student is null then
    raise exception 'pass code not registered for this fair';
  end if;

  insert into booth_visits (
    fair_id, exhibitor_id, profile_id, program_id, program_interest,
    interest_level, follow_up_requested, scholarship_discussed, note, scanned_by
  )
  values (
    v_exhibitor.fair_id, v_exhibitor.id, v_student, p_program_id, p_program_interest,
    p_interest_level, p_follow_up_requested, p_scholarship_discussed, p_note, auth.uid()
  )
  on conflict (exhibitor_id, profile_id) do update
    set program_id            = coalesce(excluded.program_id, booth_visits.program_id),
        program_interest      = coalesce(excluded.program_interest, booth_visits.program_interest),
        interest_level        = excluded.interest_level,
        follow_up_requested   = booth_visits.follow_up_requested or excluded.follow_up_requested,
        scholarship_discussed = booth_visits.scholarship_discussed or excluded.scholarship_discussed,
        note                  = coalesce(excluded.note, booth_visits.note)
  returning id into v_visit_id;

  -- The student chose to walk up and connect: grant the (revocable) share.
  perform grant_passport_share(
    v_student, v_exhibitor.institution_id,
    'You connected at ' || coalesce(v_fair.name, 'a Lekkside fair'));

  -- Mark them checked in if the desk had not already.
  update fair_registrations
     set checked_in_at = coalesce(checked_in_at, now())
   where fair_id = v_exhibitor.fair_id and profile_id = v_student;

  return jsonb_build_object(
    'visit_id', v_visit_id,
    'student_id', v_student,
    'institution_id', v_exhibitor.institution_id,
    'fair_name', v_fair.name
  );
end;
$$;

revoke all on function record_booth_visit(
  text, text, uuid, text, interest_level, boolean, boolean, text) from public;
grant execute on function record_booth_visit(
  text, text, uuid, text, interest_level, boolean, boolean, text) to authenticated;

-- --------------------------------------------------------- the event report
--
-- "You met 7 institutions · 4 programs matched your profile · 3 requested
-- follow-up" — assembled server-side so the student app makes one call.

create or replace function fair_report(p_fair_id uuid, p_profile_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid := coalesce(p_profile_id, auth.uid());
  v_result  jsonb;
begin
  -- A student may only ever pull their own report; admin may pull anyone's.
  if v_student <> auth.uid()
     and not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized to read that report';
  end if;

  select jsonb_build_object(
    'fair', (select jsonb_build_object('id', f.id, 'name', f.name, 'city', f.city,
                                       'starts_at', f.starts_at, 'ends_at', f.ends_at)
               from fairs f where f.id = p_fair_id),
    'institutions_met', (
      select count(distinct e.institution_id)
        from booth_visits v
        join fair_exhibitors e on e.id = v.exhibitor_id
       where v.fair_id = p_fair_id and v.profile_id = v_student),
    'follow_ups_requested', (
      select count(*) from booth_visits v
       where v.fair_id = p_fair_id and v.profile_id = v_student
         and v.follow_up_requested),
    'scholarship_discussions', (
      select count(*) from booth_visits v
       where v.fair_id = p_fair_id and v.profile_id = v_student
         and v.scholarship_discussed),
    'programs_matched', (
      select count(*)
        from match_scores ms
        join programs g on g.id = ms.program_id
        join fair_exhibitors e
          on e.institution_id = g.institution_id and e.fair_id = p_fair_id
       where ms.student_id = v_student),
    'applications_started', (
      select count(*)
        from applications a
        join fair_exhibitors e
          on e.institution_id = a.institution_id and e.fair_id = p_fair_id
       where a.profile_id = v_student),
    'visits', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'institution', i.name,
               'institution_id', i.id,
               'logo_url', i.logo_url,
               'booth_label', e.booth_label,
               'program_interest', coalesce(g.name, v.program_interest),
               'interest_level', v.interest_level,
               'follow_up_requested', v.follow_up_requested,
               'scholarship_discussed', v.scholarship_discussed,
               'met_at', v.created_at
             ) order by v.created_at), '[]'::jsonb)
        from booth_visits v
        join fair_exhibitors e on e.id = v.exhibitor_id
        join institutions i on i.id = e.institution_id
        left join programs g on g.id = v.program_id
       where v.fair_id = p_fair_id and v.profile_id = v_student)
  ) into v_result;

  return v_result;
end;
$$;
