-- Students get a handle automatically.
--
-- Until now a student had to choose one before they could reply or reshare,
-- and the app only asked at the moment they first tried — so the first thing
-- anyone attempted was the thing that stopped. Institutions have had a derived
-- handle since …024; this does the same for students.
--
-- Derived from the FIRST name only, plus four random characters.
--
-- That is a privacy decision, not an aesthetic one. The handle is the single
-- public part of a student's identity, and the rest of this schema works hard
-- to keep their name away from institutions until they choose to share it —
-- `matched_student_cards` hands out an opaque token precisely so an
-- institution cannot work out who they are. Deriving `samuel_ebhomien` from
-- "Samuel Ebhomien" would publish their full legal name on every post and quietly
-- undo that. A first name is friendly; a first name plus noise is not a search
-- key.
--
-- Renaming stays available through claim_handle(), so this is a starting
-- point rather than an assignment.

create or replace function derive_student_handle(p_name text)
returns citext
language plpgsql
volatile                       -- random suffix; never inline or cache this
set search_path = public
as $$
declare
  v_first   text;
  v_handle  citext;
  v_attempt int := 0;
begin
  -- First word only, lowercased, letters and digits kept.
  v_first := lower(split_part(trim(coalesce(p_name, '')), ' ', 1));
  v_first := regexp_replace(v_first, '[^a-z0-9]', '', 'g');

  -- Must start with a letter, and leave room for '_' plus four characters.
  if v_first !~ '^[a-z]' or length(v_first) < 2 then
    v_first := 'student';
  end if;
  v_first := left(v_first, 15);

  loop
    v_attempt := v_attempt + 1;
    v_handle := (v_first || '_' ||
                 substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))::citext;

    exit when not exists (
      select 1 from social_profiles where handle = v_handle
    );

    -- 65,536 suffixes per first name, so this is practically unreachable;
    -- widening the suffix rather than looping forever is the safe way out.
    if v_attempt > 20 then
      v_handle := ('student_' ||
                   substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))::citext;
      exit;
    end if;
  end loop;

  return v_handle;
end;
$$;

revoke all on function derive_student_handle(text) from public;

-- ------------------------------------------------- issued at account creation

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  requested text := new.raw_user_meta_data ->> 'role';
  resolved  user_role;
  full_name text := coalesce(new.raw_user_meta_data ->> 'full_name', '');
begin
  resolved := case requested
                when 'institution_member' then 'institution_member'::user_role
                when 'educator'           then 'educator'::user_role
                else                           'student'::user_role
              end;

  insert into public.profiles (id, role, full_name)
  values (new.id, resolved, full_name)
  on conflict (id) do nothing;

  -- Students get a handle here. Institution staff do not: at signup they have
  -- no institution yet, and create_institution() derives theirs from the
  -- organisation's name, which is the public thing in that case.
  --
  -- `is_minor` is left to the triggers that own it: this row is created before
  -- any passport exists, so it starts false and is corrected by
  -- passports_sync_social_minor the moment a date of birth is saved.
  if resolved = 'student' then
    insert into public.social_profiles
      (profile_id, handle, display_name, kind)
    values (
      new.id,
      derive_student_handle(full_name),
      coalesce(nullif(full_name, ''), 'Student'),
      'student'
    )
    on conflict (profile_id) do nothing;
  end if;

  return new;
end;
$$;

-- ------------------------------------------------------------------ backfill

-- Students who signed up before this. Without it they stay unable to reply or
-- reshare, which is the bug this migration exists to remove.
do $$
declare
  r record;
begin
  for r in
    select p.id, p.full_name
      from profiles p
     where p.role = 'student'
       and not exists (
         select 1 from social_profiles sp where sp.profile_id = p.id
       )
  loop
    insert into social_profiles (profile_id, handle, display_name, kind)
    values (
      r.id,
      derive_student_handle(r.full_name),
      coalesce(nullif(r.full_name, ''), 'Student'),
      'student'
    )
    on conflict (profile_id) do nothing;
  end loop;
end;
$$;
