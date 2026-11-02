-- Declares account_otps as the closed table it already is.
--
-- 20261025000042 enabled RLS on it and wrote no policies, which is correct —
-- every read and write goes through generate_account_otp() and
-- verify_account_otp(), both SECURITY DEFINER, and a client that could select
-- from this table could read the token hashes it is being rate-limited against.
--
-- What was missing is the declaration. supabase/tests/run.mjs treats "RLS on,
-- zero policies" as a bug unless the table's COMMENT says it is deliberate,
-- because the deliberate case and the forgotten case look identical in the
-- catalog. Without this line that check fails, and it fails BEFORE the RLS
-- assertions run — so the whole suite has been unable to report on anything
-- since that migration landed.

comment on table public.account_otps is
  'SERVICE-ROLE ONLY. One-time codes, stored as SHA-256 hashes. No policies by '
  'design: generate_account_otp() and verify_account_otp() are SECURITY '
  'DEFINER and are the only paths in. A client able to select here could read '
  'the hashes and the attempt counter it is being rate-limited by.';
