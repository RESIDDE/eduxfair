-- The two screens an admissions officer lives in: the inbox and the pipeline.
--
-- Both were built in the React console and never ported, and the console's
-- inbox has a bug worth not carrying over: it reads
-- `student:profiles!student_id(full_name)` directly, and
-- `profiles_select_shared_student` only lets an institution read a student's
-- profile *after* a passport share. So every conversation with a student who
-- has not shared renders with a null name. The console has been showing
-- nameless rows and calling it a list.
--
-- These views do what `matched_student_cards` does instead: identify the
-- student by their per-institution match token, expose `is_shared`, and carry
-- a real name only once consent exists. An institution can therefore run its
-- whole inbox and pipeline — reply, review, make an offer — without ever being
-- handed an account id or an unshared name.

-- ------------------------------------------------------------------- inbox

create or replace view institution_inbox
with (security_barrier = true)
as
select
  c.id            as conversation_id,
  c.institution_id,
  c.subject,
  c.last_message_at,
  c.created_at,

  -- The same opaque key the match cards use, so a conversation and a match
  -- card for one student line up without either exposing who they are.
  match_token_for(c.student_id, c.institution_id) as token,
  institution_can_see_student(c.institution_id, c.student_id) as is_shared,
  case when institution_can_see_student(c.institution_id, c.student_id)
       then (select pr.full_name from profiles pr where pr.id = c.student_id)
  end as shared_name,

  -- Enough to render a list row without a second query per conversation.
  (select m.body from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1)              as last_message_body,
  (select m.sender_id = c.student_id from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1)              as last_message_from_student,
  (select count(*) from messages m
    where m.conversation_id = c.id
      and m.sender_id = c.student_id
      and m.created_at > coalesce(
            (select cp.last_read_at from conversation_participants cp
              where cp.conversation_id = c.id and cp.profile_id = auth.uid()),
            '-infinity'::timestamptz))::int          as unread_count

from conversations c
where is_member_of(c.institution_id) or is_admin();

comment on view institution_inbox is
  'An institution''s conversations, keyed by match token rather than account '
  'id. `shared_name` is null until the student shares their passport, so the '
  'inbox works for anonymous students without leaking who they are.';

revoke all on institution_inbox from public;
grant select on institution_inbox to authenticated;

-- ---------------------------------------------------------------- pipeline

create or replace view institution_pipeline
with (security_barrier = true)
as
select
  a.id            as application_id,
  a.institution_id,
  a.program_id,
  g.name          as program_name,
  g.level         as program_level,
  a.intake,
  a.stage,
  a.student_note,
  a.submitted_at,
  a.decision_at,
  a.updated_at,
  a.created_at,

  match_token_for(a.profile_id, a.institution_id) as token,
  institution_can_see_student(a.institution_id, a.profile_id) as is_shared,
  case when institution_can_see_student(a.institution_id, a.profile_id)
       then (select pr.full_name from profiles pr where pr.id = a.profile_id)
  end as shared_name,

  -- What the row needs to show without opening it.
  (select count(*) from application_documents ad
    where ad.application_id = a.id)::int            as document_count,
  (select count(*) from application_document_requests r
    where r.application_id = a.id and r.fulfilled_at is null)::int
                                                    as outstanding_requests,

  -- The passport's own standing, in bands rather than figures — the same
  -- non-identifying attributes a match card carries.
  p.completeness,
  p.verification_status                             as passport_verification,
  grade_band(p.normalized_grade)                    as grade_band,
  p.english_band,
  p.current_country,
  p.nationality

from applications a
join programs g on g.id = a.program_id
left join student_passports p on p.profile_id = a.profile_id
where is_member_of(a.institution_id) or is_admin();

comment on view institution_pipeline is
  'Applications to an institution, grouped by stage in the client. Identity is '
  'the match token until the student shares a passport; grades arrive as bands '
  'rather than figures, as on a match card.';

revoke all on institution_pipeline from public;
grant select on institution_pipeline to authenticated;

-- ------------------------------------- the event trail carries a human reason

create or replace function log_application_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_note text := nullif(current_setting('lekkside.stage_note', true), '');
begin
  if tg_op = 'INSERT' then
    insert into application_events (application_id, from_stage, to_stage, actor_id, note)
    values (new.id, null, new.stage, auth.uid(), v_note);
  elsif new.stage is distinct from old.stage then
    insert into application_events (application_id, from_stage, to_stage, actor_id, note)
    values (new.id, old.stage, new.stage, auth.uid(), v_note);
  end if;

  -- Cleared so a later change in the same transaction does not inherit it.
  perform set_config('lekkside.stage_note', '', true);
  return new;
end;
$$;

-- -------------------------------------------------- moving an application on

/**
 * Advances an application and records why.
 *
 * A direct UPDATE would work — `applications_update_institution` allows it —
 * but then the note lives nowhere. The trigger writes an `application_events`
 * row on every stage change; this is how a human reason gets attached to it,
 * which is the difference between a history and a list of timestamps.
 */
create or replace function set_application_stage(
  p_application_id uuid,
  p_stage          application_stage,
  p_note           text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution uuid;
  v_current     application_stage;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select institution_id, stage into v_institution, v_current
    from applications where id = p_application_id;

  if v_institution is null then
    raise exception 'no such application';
  end if;

  if not is_member_of(v_institution) and not is_admin() then
    raise exception 'that application was not made to your institution';
  end if;

  -- `draft` belongs to the student: it means they have not sent it yet, and an
  -- institution pulling one back there would be rewriting their intent.
  if p_stage = 'draft' then
    raise exception 'only a student can return an application to draft';
  end if;

  if v_current = p_stage then
    return;                              -- nothing happened; do not log a move
  end if;

  -- Handed to the trigger rather than patched afterwards.
  --
  -- The first attempt updated "the most recent event" after the UPDATE, which
  -- looked right and was not: `now()` is fixed for a whole transaction, so
  -- every event created in one ties on `created_at`, and the tiebreak fell
  -- through to a random uuid. It attached the note to an arbitrary event.
  -- A transaction-local setting is read by the trigger at the moment it
  -- writes the row, so there is nothing to find afterwards.
  perform set_config('lekkside.stage_note', coalesce(trim(p_note), ''), true);

  update applications
     set stage = p_stage,
         decision_at = case
           when p_stage in ('conditional_offer', 'offer', 'rejected')
           then now() else decision_at end,
         updated_at = now()
   where id = p_application_id;

end;
$$;

revoke all on function set_application_stage(uuid, application_stage, text) from public;
grant execute on function set_application_stage(uuid, application_stage, text) to authenticated;

/** Asks a student for a document, which shows on their side as an action. */
create or replace function request_application_document(
  p_application_id uuid,
  p_kind           document_kind,
  p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution uuid;
  v_id          uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select institution_id into v_institution
    from applications where id = p_application_id;

  if v_institution is null then
    raise exception 'no such application';
  end if;
  if not is_member_of(v_institution) and not is_admin() then
    raise exception 'that application was not made to your institution';
  end if;

  insert into application_document_requests
    (application_id, kind, note, requested_by)
  values (p_application_id, p_kind, nullif(trim(p_note), ''), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function request_application_document(uuid, document_kind, text) from public;
grant execute on function request_application_document(uuid, document_kind, text) to authenticated;
