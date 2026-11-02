-- 20261025000042_custom_account_otps.sql
-- Custom OTP generation, storage, rate-limiting, and verification logic
-- completely independent of Supabase's built-in confirmation emails.

create table if not exists public.account_otps (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  token_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_account_otps_email_consumed
  on public.account_otps(email, consumed_at);

alter table public.account_otps enable row level security;

-- Drop existing functions to replace cleanly
drop function if exists public.generate_account_otp(text);
drop function if exists public.verify_account_otp(text, text);

-- Generates a 6-digit OTP, stores its SHA-256 hash, and returns the raw code
-- ONLY callable by service_role (invoked via Edge Function or backend).
create or replace function public.generate_account_otp(p_email text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_norm_email text := lower(trim(p_email));
  v_code text;
  v_hash text;
  v_num int;
begin
  if coalesce(v_norm_email, '') = '' then
    raise exception 'Email is required';
  end if;

  -- 30-second cooldown protection against rapid repeat calls
  if exists (
    select 1 from public.account_otps
     where email = v_norm_email
       and consumed_at is null
       and created_at > (now() - interval '30 seconds')
  ) then
    raise exception 'Please wait 30 seconds before requesting another code.';
  end if;

  -- Generate 6-digit integer in range 100000..999999
  v_num := floor(random() * (999999 - 100000 + 1) + 100000)::int;
  v_code := v_num::text;
  v_hash := encode(sha256(convert_to(v_code, 'UTF8')), 'hex');

  -- Invalidate any pending unconsumed OTPs for this email
  update public.account_otps
     set consumed_at = now()
   where email = v_norm_email
     and consumed_at is null;

  -- Store new OTP expiring in 15 minutes
  insert into public.account_otps (email, token_hash, expires_at)
  values (v_norm_email, v_hash, now() + interval '15 minutes');

  return v_code;
end;
$$;

-- Revoke public access so clients cannot generate or inspect codes directly
revoke all on function public.generate_account_otp(text) from public, anon, authenticated;
grant execute on function public.generate_account_otp(text) to service_role;


-- Verifies an entered 6-digit OTP code against the SHA-256 hash.
-- Accessible to anon and authenticated callers.
create or replace function public.verify_account_otp(p_email text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_norm_email text := lower(trim(p_email));
  v_code text := trim(p_code);
  v_hash text;
  v_otp public.account_otps;
  v_user_id uuid;
begin
  if coalesce(v_code, '') = '' then
    return jsonb_build_object('ok', false, 'error', 'Please enter the 6-digit verification code.');
  end if;

  -- Find the most recent active OTP for this email
  select * into v_otp
    from public.account_otps
   where email = v_norm_email
     and consumed_at is null
   order by created_at desc
   limit 1;

  if v_otp is null then
    return jsonb_build_object('ok', false, 'error', 'No active verification code found. Please request a new code.');
  end if;

  if v_otp.expires_at < now() then
    return jsonb_build_object('ok', false, 'error', 'This verification code has expired. Please request a new code.');
  end if;

  if v_otp.attempts >= 5 then
    return jsonb_build_object('ok', false, 'error', 'Too many failed attempts. Please request a new verification code.');
  end if;

  -- Hash provided code and compare
  v_hash := encode(sha256(convert_to(v_code, 'UTF8')), 'hex');

  if v_otp.token_hash <> v_hash then
    update public.account_otps
       set attempts = attempts + 1
     where id = v_otp.id;
    return jsonb_build_object(
      'ok', false,
      'error', 'Incorrect verification code. Please check and try again.'
    );
  end if;

  -- Consume OTP
  update public.account_otps
     set consumed_at = now()
   where id = v_otp.id;

  -- Mark profile as verified
  select id into v_user_id from auth.users where lower(trim(email)) = v_norm_email;
  if v_user_id is not null then
    update public.profiles
       set email_verified = true,
           email_verified_at = now()
     where id = v_user_id;

    update auth.users
       set email_confirmed_at = coalesce(email_confirmed_at, now())
     where id = v_user_id;
  end if;

  if auth.uid() is not null then
    update public.profiles
       set email_verified = true,
           email_verified_at = now()
     where id = auth.uid();
  end if;

  return jsonb_build_object('ok', true, 'verified', true);
end;
$$;

grant execute on function public.verify_account_otp(text, text) to anon, authenticated, service_role;
