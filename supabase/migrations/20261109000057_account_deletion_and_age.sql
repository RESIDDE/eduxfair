-- Account deletion, and the age floor that App Review asks for.
--
-- Guideline 5.1.1(v) requires that an app which lets people create an account
-- also lets them delete it, from inside the app, including the content they
-- posted. Almost all of that already works by construction: profiles.id
-- references auth.users on delete cascade, and thirty-eight tables cascade
-- from profiles, so removing the auth user removes the passport, the
-- documents, the posts, the comments, the messages and the follows with it.
--
-- Two things that cascade do not get right, and this migration fixes both.

-- ─────────────────────────────────────────── reports outlive their reporter

-- A report is evidence about the person reported, not about the person who
-- filed it. Cascading it away meant that if A reported B for child safety and
-- A later deleted their account, the report against B disappeared with them —
-- so the fastest way to bury a report was to delete the account that made it.
--
-- The reporter becomes null instead. The unique constraint that stopped one
-- person filing the same report twice has to be rebuilt to match: in Postgres
-- nulls are distinct, so the original index would stop constraining anything
-- once the reporter was cleared, which is the behaviour we want — an
-- anonymised report should never collide with a live one.
alter table reports
  drop constraint reports_reporter_id_fkey,
  alter column reporter_id drop not null,
  add constraint reports_reporter_id_fkey
    foreign key (reporter_id) references profiles (id) on delete set null;

comment on column reports.reporter_id is
  'Null once the reporter deletes their account. The report survives: it is '
  'evidence about the subject, and letting it vanish made account deletion a '
  'way to retract a child-safety report.';

-- ──────────────────────────────────────────────────────── date of birth

-- Collected for one purpose — confirming the account holder meets the
-- minimum age — which is the only basis guideline 5.1.4(a) allows for asking
-- a minor for a birthdate. It is never shown to anyone else, and the RLS
-- policies on profiles already restrict who can read a row.
alter table profiles
  add column if not exists date_of_birth date;

comment on column profiles.date_of_birth is
  'Age verification only. Not displayed, not used for matching, not shared '
  'with institutions. See guideline 5.1.4(a).';

-- Sixteen. Keeping the floor here puts COPPA''s under-13 regime out of scope
-- and matches the GDPR Article 8 ceiling, so one rule holds everywhere the
-- fair recruits. Rows predating this column are left alone rather than
-- assumed compliant or assumed not.
alter table profiles
  add constraint profiles_minimum_age
  check (
    date_of_birth is null
    or date_of_birth <= (current_date - interval '16 years')
  );

-- ───────────────────────────────────────────────────────── purge_account

-- One call, so the edge function is not orchestrating a dozen deletes over a
-- connection that might drop halfway. Deleting the profile row is what
-- triggers the cascade; the function exists to make that explicit, to be the
-- place any future non-cascading cleanup goes, and to be greppable when
-- someone asks "what actually happens when a student deletes their account?".
create or replace function purge_account(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id is null then
    raise exception 'purge_account requires a profile id';
  end if;

  -- Reports this person filed are detached rather than removed, per above.
  -- Explicit, because relying on the FK rule alone would make this silently
  -- wrong if someone later changed it back.
  update reports set reporter_id = null where reporter_id = p_profile_id;

  -- Everything else goes with the profile.
  delete from profiles where id = p_profile_id;
end;
$$;

comment on function purge_account(uuid) is
  'Removes a profile and, by cascade, everything it owns. Service role only: '
  'it takes the id it is given and does not check the caller, so the edge '
  'function''s JWT check is what decides whose account goes.';

-- Nobody signed in may call this. The delete-account edge function runs as
-- the service role, which bypasses these grants; a student''s own token does
-- not, so the id argument cannot be turned into a way to delete someone else.
revoke all on function purge_account(uuid) from public, anon, authenticated;
