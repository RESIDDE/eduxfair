-- Lekkside Connect — institution domain-verification tokens.
--
-- This backs the VERIFIED INSTITUTION badge: we email a token to an address on
-- the institution's own domain and only a party controlling that mailbox can
-- return it.
--
-- The token therefore must NOT be readable by institution staff. Putting it in
-- verifications.evidence would have been convenient, but that column is
-- readable by institution members (so they can watch their request's status) —
-- staff could simply read their own token and confirm without ever receiving
-- the email, which defeats the entire check. Hence a separate table with RLS
-- enabled and NO policies at all: unreachable by anon and authenticated alike,
-- and touched only by the Edge Function on the service-role key.

create table institution_domain_verifications (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  -- Where the token was sent. Kept for the audit trail behind the badge.
  email          text not null,
  domain         text not null,
  -- Only the hash is stored, so a database leak does not hand out verifications.
  token_hash     text not null,
  expires_at     timestamptz not null,
  consumed_at    timestamptz,
  attempts       int not null default 0,
  created_at     timestamptz not null default now()
);

create index institution_domain_verifications_lookup
  on institution_domain_verifications (institution_id, consumed_at);

alter table institution_domain_verifications enable row level security;

-- SERVICE-ROLE ONLY: intentionally no policies. See the header above.
comment on table institution_domain_verifications is
  'SERVICE-ROLE ONLY. Holds hashed domain-verification tokens. RLS is enabled '
  'with no policies on purpose: if institution staff could read these, they '
  'could verify their own domain without receiving the email.';
