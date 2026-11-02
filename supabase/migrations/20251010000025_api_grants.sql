-- API role privileges.
--
-- Found by applying the schema to a real Supabase project: every table came
-- back `42501 permission denied for table institutions`. The tables were all
-- there, RLS was on, 163 policies were in place — and nothing could reach any
-- of it, because no GRANT had ever been issued.
--
-- It worked locally for a reason worth spelling out. The test shim runs
-- `alter default privileges in schema public grant select, insert, update,
-- delete on tables to anon, authenticated, service_role` *before* the
-- migrations, so every table created afterwards picked privileges up silently.
-- The migrations never had to say anything, so they never did — and the
-- omission could not show up anywhere except against hosted Supabase.
--
-- This is the same shape of bug as the missing handles: a shim that is
-- faithful enough to be useful is also faithful enough to hide what the
-- migrations forgot.
--
-- What is granted here is deliberately broad, because that is the model the
-- whole schema is designed around and the one the RLS suite was validated
-- against: the API roles hold table-level privileges and **RLS is the thing
-- that constrains them**. Every public table has RLS enabled — asserted by
-- devserver/bundle-migrations.mjs, which refuses to bless a bundle where one
-- does not — so a broad grant exposes nothing a policy does not allow. `anon`
-- in particular holds privileges and still sees nothing, which is itself an
-- explicit assertion in the RLS suite.

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public
  to anon, authenticated, service_role;

grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;

-- Execute goes to the signed-in roles only, and deliberately NOT to `anon`.
--
-- The first draft of this granted execute to anon too, reasoning that it
-- matched hosted Supabase's defaults. Measuring the actual project showed it
-- does not: `anon` there held no execute privilege on anything, so granting it
-- would have been this migration *introducing* the access rather than
-- reproducing it.
--
-- The worry about withholding it was that RLS policies call helpers such as
-- `current_user_role()` and `is_admin()`, which are evaluated as the querying
-- role — so an anon read might fail on policy evaluation instead of returning
-- no rows. Tested rather than assumed: with execute revoked from anon, every
-- anon read still returns cleanly (0 rows, or the 25 intentionally-public
-- `fields_of_study` rows), and authenticated access is untouched.
--
-- It works because the two cases are separated by what the migrations already
-- say. A function gets EXECUTE to PUBLIC when it is created, and the policy
-- helpers leave that alone — so they stay callable during policy evaluation.
-- Every privileged write path does `revoke all on function ... from public`,
-- which closes it to anon once anon has no explicit grant of its own.
--
-- So this is defence in depth under the null-uid guards in
-- …026_definer_null_uid_guards: an anonymous caller cannot reach
-- `remove_post` at all, and would be refused by its first statement if it did.
-- Revoked explicitly, not merely withheld. The test shim sets
-- `alter default privileges ... grant execute on functions to anon` *before*
-- the migrations run, so every function picks up an explicit anon grant at
-- creation — and `revoke ... from public` does not touch a named role's own
-- privilege. Declining to grant here would therefore leave anon with execute
-- locally and without it on the hosted project: the two environments would
-- disagree about who can call `remove_post`, which is precisely the kind of
-- divergence that hid today's bugs. Revoking makes them agree.
revoke execute on all functions in schema public from anon;

grant execute on all functions in schema public
  to authenticated, service_role;

-- And for anything added later, so a future migration cannot reintroduce the
-- unreachable-schema problem by simply not thinking about it.
alter default privileges in schema public
  grant select, insert, update, delete on tables
  to anon, authenticated, service_role;
alter default privileges in schema public
  grant usage, select on sequences
  to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions
  to authenticated, service_role;
