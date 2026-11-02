-- Deleting a message, two ways. And pinning an institution's threads.
--
-- A NOTE ON WHAT THIS CHANGES. 20251009000009 gave `messages` no UPDATE and no
-- DELETE policy, with a reason written into the file: "a message log that can
-- be rewritten is useless when a student disputes what an institution told
-- them." Delete-for-everyone is, straightforwardly, that. It is being added
-- because it was asked for, and the guarantee is kept where it can be:
--
--   * There is still no UPDATE or DELETE policy. The only path is the
--     SECURITY DEFINER function below, so every deletion is deliberate and
--     the rules live in one place.
--   * Only the sender may delete their own message for everyone. Nobody can
--     reach into the other party's side of a thread.
--   * The original is COPIED to `message_redactions` before it is cleared.
--     Normal users cannot read that table at all; an admin resolving a dispute
--     still can. So the record survives even though the conversation no
--     longer shows it.
--
-- Delete-for-me is a different thing entirely and carries none of that: it is
-- one row saying one person does not want to see one message, and the message
-- itself is untouched.

-- ------------------------------------------------------------ delete for me

create table message_hides (
  message_id uuid not null references messages (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  hidden_at  timestamptz not null default now(),

  primary key (message_id, profile_id)
);

create index message_hides_profile_idx on message_hides (profile_id);

alter table message_hides enable row level security;

comment on table message_hides is
  'One row per person per message they have hidden from their own view. The '
  'message is not altered and the other party never learns of it — this is a '
  'reading preference, not a deletion.';

-- Yours and only yours, and only on a thread you are on.
create policy message_hides_own on message_hides
  for all
  using (profile_id = auth.uid())
  with check (
    profile_id = auth.uid()
    and exists (
      select 1 from messages m
       where m.id = message_id
         and can_access_conversation(m.conversation_id)));

-- ------------------------------------------------------ delete for everyone

alter table messages
  add column deleted_at timestamptz,
  add column deleted_by uuid references profiles (id) on delete set null;

-- A deleted message has no body and no attachment, which the original
-- constraint forbade outright.
alter table messages drop constraint message_has_content;

alter table messages add constraint message_has_content
  check (deleted_at is not null
         or coalesce(trim(body), '') <> ''
         or attachment_path is not null);

create table message_redactions (
  message_id      uuid primary key references messages (id) on delete cascade,
  conversation_id uuid not null references conversations (id) on delete cascade,
  sender_id       uuid references profiles (id) on delete set null,
  body            text,
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  kind            message_kind not null,
  duration_ms     int,
  redacted_at     timestamptz not null default now(),
  redacted_by     uuid references profiles (id) on delete set null
);

alter table message_redactions enable row level security;

comment on table message_redactions is
  'What a deleted message said, kept for dispute resolution. Readable by '
  'admins only and written only by delete_message() — the parties to the '
  'conversation cannot read it, which is what makes the deletion real to '
  'them while the record survives.';

create policy message_redactions_select_admin on message_redactions
  for select using (is_admin());

-- No insert, update or delete policy for any role, admin included: the same
-- rule space_moderation_events has, for the same reason.

/**
 * Deletes one message, for the caller or for everyone.
 *
 * `scope = 'me'` hides it from the caller alone and leaves the row untouched.
 * `scope = 'everyone'` is the sender's own, copies the original into
 * message_redactions and clears it — so both clients render a tombstone and
 * neither can read what it said.
 */
create or replace function delete_message(
  p_message_id uuid,
  p_scope      text default 'me'
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_row messages;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_scope not in ('me', 'everyone') then
    raise exception 'scope must be ''me'' or ''everyone''';
  end if;

  select * into v_row from messages where id = p_message_id;
  if not found then raise exception 'no such message'; end if;

  if not can_access_conversation(v_row.conversation_id) then
    raise exception 'that conversation is not yours';
  end if;

  if p_scope = 'me' then
    insert into message_hides (message_id, profile_id)
    values (p_message_id, auth.uid())
    on conflict do nothing;
    return;
  end if;

  if v_row.sender_id <> auth.uid() then
    raise exception
      'You can only delete your own messages for everyone. Deleting this one '
      'for yourself removes it from your view.';
  end if;

  -- Already gone: idempotent rather than an error, because two taps on a slow
  -- connection is not a mistake worth a red banner.
  if v_row.deleted_at is not null then return; end if;

  insert into message_redactions
    (message_id, conversation_id, sender_id, body, attachment_path,
     attachment_name, attachment_mime, kind, duration_ms, redacted_by)
  values
    (v_row.id, v_row.conversation_id, v_row.sender_id, v_row.body,
     v_row.attachment_path, v_row.attachment_name, v_row.attachment_mime,
     v_row.kind, v_row.duration_ms, auth.uid());

  update messages
     set body = null,
         attachment_path = null,
         attachment_name = null,
         attachment_mime = null,
         duration_ms = null,
         -- Back to 'text': a client must not be handed a voice kind with no
         -- audio behind it and try to draw a player.
         kind = 'text',
         deleted_at = now(),
         deleted_by = auth.uid()
   where id = p_message_id;
end;
$$;

revoke all on function delete_message(uuid, text) from public;
grant execute on function delete_message(uuid, text) to authenticated;

-- ------------------------------------------- previews and search skip them

-- A deleted message must not go on matching the words it no longer contains.
create or replace function search_conversations(
  p_query text,
  p_limit int default 50
)
returns table (
  conversation_id uuid,
  snippet         text,
  matched_at      timestamptz
)
language sql
stable
set search_path = public
as $$
  select hits.conversation_id, hits.snippet, hits.matched_at
    from (
      select distinct on (m.conversation_id)
             m.conversation_id,
             coalesce(
               nullif(m.body, ''),
               m.attachment_name,
               case m.kind when 'voice' then 'Voice note' else 'Attachment' end
             ) as snippet,
             m.created_at as matched_at
        from messages m
       where coalesce(trim(p_query), '') <> ''
         and m.deleted_at is null
         and not exists (
               select 1 from message_hides h
                where h.message_id = m.id and h.profile_id = auth.uid())
         and (m.body ilike '%' || trim(p_query) || '%'
              or m.attachment_name ilike '%' || trim(p_query) || '%')
       order by m.conversation_id, m.created_at desc
    ) hits
   order by hits.matched_at desc
   limit greatest(1, least(p_limit, 100));
$$;

revoke all on function search_conversations(text, int) from public;
grant execute on function search_conversations(text, int) to authenticated;

-- ------------------------------------------- the institution's inbox state
--
-- Adds the caller's own pin and archive, so the institution's list can have
-- the two tabs the student's has. Per officer, like last_read_at beside it.

create or replace view institution_inbox
with (security_barrier = true)
as
select
  c.id            as conversation_id,
  c.institution_id,
  c.subject,
  c.last_message_at,
  c.created_at,

  match_token_for(c.student_id, c.institution_id) as token,
  institution_can_see_student(c.institution_id, c.student_id) as is_shared,
  case when institution_can_see_student(c.institution_id, c.student_id)
       then (select pr.full_name from profiles pr where pr.id = c.student_id)
  end as shared_name,

  (select case when m.deleted_at is not null then 'Message deleted' else m.body end
     from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1)            as last_message_body,
  (select m.sender_id = c.student_id from messages m
    where m.conversation_id = c.id
    order by m.created_at desc limit 1)            as last_message_from_student,
  (select count(*) from messages m
    where m.conversation_id = c.id
      and m.sender_id = c.student_id
      and m.created_at > coalesce(
            (select cp.last_read_at from conversation_participants cp
              where cp.conversation_id = c.id and cp.profile_id = auth.uid()),
            '-infinity'::timestamptz))::int        as unread_count,

  (select cp.pinned_at from conversation_participants cp
    where cp.conversation_id = c.id and cp.profile_id = auth.uid())
                                                   as pinned_at,
  (select cp.archived_at from conversation_participants cp
    where cp.conversation_id = c.id and cp.profile_id = auth.uid())
                                                   as archived_at

from conversations c
where is_member_of(c.institution_id) or is_admin();

comment on view institution_inbox is
  'An institution''s conversations, keyed by match token rather than account '
  'id. `shared_name` is null until the student shares their passport, so the '
  'inbox works for anonymous students without leaking who they are. '
  '`pinned_at` and `archived_at` are the CALLER''s, not the institution''s — '
  'one officer filing a thread away must not take it off a colleague''s list.';

revoke all on institution_inbox from public;
grant select on institution_inbox to authenticated;
