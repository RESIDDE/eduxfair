-- Every author has a handle.
--
-- Found by running the app against an empty database for the first time: an
-- institution that signs itself up has no `social_profiles` row, because only
-- the seed script ever created them. It could still create a listing and post,
-- and the post reached the feed with an *empty* author handle — the card
-- rendering a bare "@" and the profile link going nowhere.
--
-- The seed hid this completely. Every institution it makes gets a handle by
-- hand, so the whole social layer has only ever been exercised by accounts
-- that happened to have one.
--
-- Two changes, because either alone leaves a hole:
--   1. create_institution() claims a handle, so organisations have one from
--      the moment they exist.
--   2. assert_can_write() refuses without one, so no future path can quietly
--      reintroduce a handle-less post, comment or repost.

-- ------------------------------------------------------- deriving from a name

-- Handles are stricter than slugs: 3-20 characters, letters, digits and
-- underscores, starting with a letter. A slug may contain hyphens and may
-- start with a digit, so it cannot be used as-is.
create or replace function derive_handle(p_seed text)
returns citext
language plpgsql
stable
set search_path = public
as $$
declare
  v_base    text;
  v_handle  citext;
  v_attempt int := 0;
  v_suffix  text;
begin
  v_base := lower(coalesce(p_seed, ''));
  v_base := regexp_replace(v_base, '[^a-z0-9]+', '_', 'g');
  v_base := trim(both '_' from v_base);

  -- Must start with a letter.
  if v_base !~ '^[a-z]' then
    v_base := 'o_' || v_base;
  end if;

  v_base := left(v_base, 20);
  -- And be at least three characters.
  while length(v_base) < 3 loop
    v_base := v_base || '0';
  end loop;

  v_handle := v_base;

  -- Collisions are expected ("University of London" twice), so suffix rather
  -- than fail the signup. The base is truncated to leave room for the suffix.
  while exists (select 1 from social_profiles where handle = v_handle) loop
    v_attempt := v_attempt + 1;
    if v_attempt > 50 then
      -- Practically unreachable, but better than looping forever.
      v_handle := 'o_' || replace(gen_random_uuid()::text, '-', '');
      return left(v_handle, 20)::citext;
    end if;
    v_suffix := v_attempt::text;
    v_handle := (left(v_base, 20 - length(v_suffix)) || v_suffix)::citext;
  end loop;

  return v_handle;
end;
$$;

-- Internal only. Its collision check reads social_profiles, which is behind
-- RLS: called directly by a user it would see no rows and happily return a
-- handle that is already taken.
revoke all on function derive_handle(text) from public;

-- ------------------------------------------- create_institution claims a handle

drop function if exists create_institution(text, text, text, text, text, text, institution_kind);

create or replace function create_institution(
  p_name         text,
  p_country      text,
  p_website      text default null,
  p_email_domain text default null,
  p_city         text default null,
  p_description  text default null,
  p_kind         institution_kind default 'university'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id     uuid;
  v_slug   text;
  v_handle citext;
  v_name   text := trim(p_name);
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if current_user_role() not in ('institution_member', 'admin') then
    raise exception 'only institution accounts can create an institution';
  end if;

  -- One listing per member. Without this, a staff account that double-taps
  -- "Create listing" owns two institutions and the shell picks one at random.
  if exists (
    select 1 from institution_members where profile_id = auth.uid()
  ) then
    raise exception 'this account already belongs to an institution';
  end if;

  v_slug := regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  -- Collisions are real ("University of London" vs a second listing), so
  -- suffix rather than fail the signup.
  if exists (select 1 from institutions where slug = v_slug) then
    v_slug := v_slug || '-' || substr(gen_random_uuid()::text, 1, 6);
  end if;

  insert into institutions
    (name, slug, country, city, website, email_domain, description, kind)
  values (
    v_name, v_slug, p_country, p_city, p_website,
    lower(nullif(regexp_replace(coalesce(p_email_domain, ''), '^https?://|/.*$', '', 'g'), '')),
    p_description,
    p_kind
  )
  returning id into v_id;

  insert into institution_members (institution_id, profile_id, member_role)
  values (v_id, auth.uid(), 'owner');

  insert into institution_subscriptions (institution_id, tier)
  values (v_id, 'basic');

  -- The public identity, derived from the name the organisation just gave.
  -- Unlike a student's handle this is not a privacy decision: the institution
  -- name is the public thing, and an organisation with no handle cannot be
  -- attributed on a post it makes.
  v_handle := derive_handle(v_name);

  insert into social_profiles
    (profile_id, handle, display_name, kind, institution_id)
  values (
    auth.uid(),
    v_handle,
    v_name,
    case when p_kind = 'embassy' then 'embassy'::social_profile_kind
         else 'institution'::social_profile_kind end,
    v_id
  )
  on conflict (profile_id) do update
    set institution_id = excluded.institution_id,
        display_name   = excluded.display_name,
        kind           = excluded.kind;

  return v_id;
end;
$$;

revoke all on function
  create_institution(text, text, text, text, text, text, institution_kind)
  from public;
grant execute on function
  create_institution(text, text, text, text, text, text, institution_kind)
  to authenticated;

-- ------------------------------------------------- nothing posts without one

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

  -- A post, comment or repost is attributed to a handle. Without one the feed
  -- shows a bare "@" and the author cannot be reached, so this is refused at
  -- the only place every write path goes through. The message is the one the
  -- app shows, so it has to be something a person can act on.
  if not exists (select 1 from social_profiles where profile_id = auth.uid()) then
    raise exception 'Choose a handle before posting — it is the name other '
                    'people see.'
      using errcode = 'P0002';
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

-- --------------------------------------------- backfill anything already live

-- An institution created before this migration has no handle. Derived the same
-- way, so a project that has been running keeps working rather than having
-- silently broken listings.
do $$
declare
  r record;
begin
  for r in
    select im.profile_id, i.name, i.id as institution_id, i.kind
      from institution_members im
      join institutions i on i.id = im.institution_id
     where im.member_role = 'owner'
       and not exists (
         select 1 from social_profiles sp where sp.profile_id = im.profile_id
       )
  loop
    insert into social_profiles
      (profile_id, handle, display_name, kind, institution_id)
    values (
      r.profile_id,
      derive_handle(r.name),
      r.name,
      case when r.kind = 'embassy' then 'embassy'::social_profile_kind
           else 'institution'::social_profile_kind end,
      r.institution_id
    )
    on conflict (profile_id) do nothing;
  end loop;
end;
$$;
