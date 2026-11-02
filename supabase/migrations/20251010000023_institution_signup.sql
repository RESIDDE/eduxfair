-- Institution self-signup.
--
-- Until now the only way to get an `institution_member` account was the React
-- console or the seed script, so the app could not onboard an institution at
-- all. Sign-up now forks — student or organisation — and the organisation path
-- has to be able to say *what kind* of organisation it is.
--
-- `institutions.kind` has existed since …015_identity_split, but
-- create_institution() never set it, so every self-signed-up embassy would
-- have been stored as a university. The enum is the product distinction that
-- decides whether a listing shows programs or visa routes, so getting it wrong
-- at signup is not cosmetic.

-- The parameter list changes, so this is a drop rather than a replace: adding a
-- defaulted 7th argument alongside the 6-argument version would make every
-- existing 6-argument call ambiguous.
drop function if exists create_institution(text, text, text, text, text, text);

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
  v_id   uuid;
  v_slug text;
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

  v_slug := regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g');
  v_slug := trim(both '-' from v_slug);
  -- Collisions are real ("University of London" vs a second listing), so
  -- suffix rather than fail the signup.
  if exists (select 1 from institutions where slug = v_slug) then
    v_slug := v_slug || '-' || substr(gen_random_uuid()::text, 1, 6);
  end if;

  insert into institutions
    (name, slug, country, city, website, email_domain, description, kind)
  values (
    trim(p_name), v_slug, p_country, p_city, p_website,
    lower(nullif(regexp_replace(coalesce(p_email_domain, ''), '^https?://|/.*$', '', 'g'), '')),
    p_description,
    p_kind
  )
  returning id into v_id;

  insert into institution_members (institution_id, profile_id, member_role)
  values (v_id, auth.uid(), 'owner');

  insert into institution_subscriptions (institution_id, tier)
  values (v_id, 'basic');

  return v_id;
end;
$$;

revoke all on function
  create_institution(text, text, text, text, text, text, institution_kind)
  from public;
grant execute on function
  create_institution(text, text, text, text, text, text, institution_kind)
  to authenticated;
