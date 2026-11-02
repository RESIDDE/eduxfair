-- Reading a match token must not write one.
--
-- `match_token_for()` mints a token when none exists, by INSERTing into
-- `match_tokens`. Three views call it on the read path — `matched_student_cards`
-- since the identity split, and `institution_inbox` and `institution_pipeline`
-- since the desk was built — so selecting from any of them tries to write.
--
-- PostgREST runs GET requests inside a READ ONLY transaction, so on a real
-- Supabase project every one of those reads fails outright:
--
--   25006: cannot execute INSERT in a read-only transaction
--
-- The dev server does not impose read-only transactions, which is exactly why
-- this passed every test and failed the moment it met production. It is the
-- same shape as the missing GRANTs: a shim faithful enough to be useful is
-- faithful enough to hide what only the real thing enforces.
--
-- The fix is to mint the token when the *relationship* starts — a match, a
-- conversation, an application — which is always a write anyway, and to make
-- the read path a plain lookup.

-- ------------------------------------------------------------ minting (write)

/**
 * Mints the token for a pair if it does not exist, and returns it.
 *
 * Only ever called from a write: the triggers below, or a caller that is
 * already inserting. Never from a view.
 */
create or replace function ensure_match_token(
  p_student_id     uuid,
  p_institution_id uuid
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_token text;
begin
  if p_student_id is null or p_institution_id is null then
    return null;
  end if;

  select token into v_token
    from match_tokens
   where student_id = p_student_id and institution_id = p_institution_id;
  if v_token is not null then
    return v_token;
  end if;

  v_token := replace(gen_random_uuid()::text, '-', '');

  insert into match_tokens (token, student_id, institution_id)
  values (v_token, p_student_id, p_institution_id)
  on conflict (student_id, institution_id)
    do update set token = match_tokens.token
  returning token into v_token;

  return v_token;
end;
$$;

revoke all on function ensure_match_token(uuid, uuid) from public;

-- -------------------------------------------------------------- reading (pure)

/**
 * The token for a pair, or null.
 *
 * `stable`, and it does not write — so a view may call it and PostgREST may
 * read that view. Null means no relationship has started yet, which for the
 * three views that use it cannot happen: each row *is* a relationship, and the
 * triggers below mint the token as it is created.
 */
create or replace function match_token_for(
  p_student_id     uuid,
  p_institution_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select token from match_tokens
   where student_id = p_student_id
     and institution_id = p_institution_id;
$$;

revoke all on function match_token_for(uuid, uuid) from public;
grant execute on function match_token_for(uuid, uuid) to authenticated;

-- ----------------------------------------------- mint as the relationship starts

create or replace function mint_match_token_for_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `applications` and `conversations` name the student differently; match
  -- scores carry both. tg_argv tells this trigger which column to read.
  perform ensure_match_token(
    (to_jsonb(new) ->> tg_argv[0])::uuid,
    (to_jsonb(new) ->> tg_argv[1])::uuid
  );
  return new;
end;
$$;

drop trigger if exists conversations_mint_token on conversations;
create trigger conversations_mint_token
  after insert on conversations
  for each row execute function mint_match_token_for_row('student_id', 'institution_id');

drop trigger if exists applications_mint_token on applications;
create trigger applications_mint_token
  after insert on applications
  for each row execute function mint_match_token_for_row('profile_id', 'institution_id');

-- Match scores are keyed on a program, so the institution comes from it.
create or replace function mint_match_token_for_score()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution uuid;
begin
  select institution_id into v_institution from programs where id = new.program_id;
  perform ensure_match_token(new.student_id, v_institution);
  return new;
end;
$$;

drop trigger if exists match_scores_mint_token on match_scores;
create trigger match_scores_mint_token
  after insert on match_scores
  for each row execute function mint_match_token_for_score();

-- ------------------------------------------------------------------- backfill

-- Everything that already exists. Without this, every row created before this
-- migration reads back with a null token — which is the same blank screen,
-- arrived at from the other direction.
insert into match_tokens (token, student_id, institution_id)
select replace(gen_random_uuid()::text, '-', ''), s.student_id, s.institution_id
  from (
    select c.student_id, c.institution_id from conversations c
    union
    select a.profile_id, a.institution_id from applications a
    union
    select ms.student_id, g.institution_id
      from match_scores ms join programs g on g.id = ms.program_id
  ) s
 where s.student_id is not null
   and s.institution_id is not null
on conflict (student_id, institution_id) do nothing;
