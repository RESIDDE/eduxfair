-- Drops the seven-argument create_post() that 20261027000044 left behind.
--
-- That migration added `p_tagged_handles` by writing a new CREATE OR REPLACE
-- with an eighth parameter. A different argument count is a different function
-- in Postgres, so the seven-argument version from 20251010000021 was not
-- replaced — it was shadowed, and both still exist.
--
-- Every parameter has a default, so a seven-argument call matches both and
-- Postgres refuses it:
--
--   function create_post(unknown, unknown, ..., text[], text[]) is not unique
--
-- The Flutter composer always sends all eight by name and so has never hit it,
-- which is exactly why this survived: the only caller that passes seven is
-- supabase/tests/rls_test.mjs, where it aborts the whole suite — including
-- every assertion written after it.

drop function if exists create_post(text, post_kind, uuid, text, reply_policy, text[], text[]);
