-- Reactions, replies and forwarding.
--
-- Three small additions that change what a thread can say without changing
-- who may read it: every one of them is still fenced by
-- `can_access_conversation`, and none of them adds a way to write into
-- somebody else's conversation.

-- ------------------------------------------------------------- reactions

/**
 * The six, fixed.
 *
 * The same argument RoomProtocol makes for a live room: an open emoji field is
 * an open text field, and these threads can have minors in them. A CHECK
 * rather than a client-side list, because the client is not the place to
 * decide what may be written to a table.
 */
create table message_reactions (
  message_id uuid not null references messages (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  emoji      text not null,
  created_at timestamptz not null default now(),

  -- One per person per message. Changing your mind is an UPDATE, not a second
  -- row, so a bubble can never show the same person twice.
  primary key (message_id, profile_id),

  constraint message_reaction_emoji
    check (emoji in ('👍', '❤️', '😂', '😮', '😢', '🙏'))
);

create index message_reactions_message_idx on message_reactions (message_id);

alter table message_reactions enable row level security;

comment on table message_reactions is
  'One reaction per person per message, from a fixed set. Readable by anyone '
  'on the thread; writable only as yourself.';

create policy message_reactions_select_party on message_reactions
  for select using (
    exists (select 1 from messages m
             where m.id = message_id
               and can_access_conversation(m.conversation_id)));

create policy message_reactions_write_self on message_reactions
  for all
  using (profile_id = auth.uid())
  with check (
    profile_id = auth.uid()
    and exists (select 1 from messages m
                 where m.id = message_id
                   and can_access_conversation(m.conversation_id)));

-- Realtime, so a reaction lands on the other screen without a reload.
alter publication supabase_realtime add table message_reactions;

-- --------------------------------------------------- replies and forwards

alter table messages
  -- What this is a reply to. `on delete set null` rather than cascade: a reply
  -- is its own message and does not stop existing because the thing it
  -- answered was deleted — it just stops quoting it.
  add column reply_to_id uuid references messages (id) on delete set null,
  add column is_forwarded boolean not null default false;

create index messages_reply_to_idx on messages (reply_to_id)
  where reply_to_id is not null;

comment on column messages.is_forwarded is
  'Shown as a "Forwarded" label. Deliberately carries no pointer to where it '
  'came from: that would name a conversation the reader is not on.';

/**
 * A reply must answer something in the same conversation.
 *
 * A trigger because a CHECK cannot subquery. Without it, `reply_to_id` would
 * be a way to quote a message out of a thread the reader is not on — the
 * quoted snippet is rendered from the row the id points at, so a client would
 * happily display it.
 */
create or replace function guard_reply_same_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_id is null then return new; end if;

  if not exists (
    select 1 from messages m
     where m.id = new.reply_to_id
       and m.conversation_id = new.conversation_id)
  then
    raise exception 'a reply must answer a message in the same conversation';
  end if;

  return new;
end;
$$;

create trigger messages_reply_same_conversation
  before insert or update of reply_to_id on messages
  for each row execute function guard_reply_same_conversation();

-- A deleted message keeps its tombstone but stops quoting and stops claiming
-- to be forwarded — there is nothing left for either label to describe.
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
         kind = 'text',
         reply_to_id = null,
         is_forwarded = false,
         deleted_at = now(),
         deleted_by = auth.uid()
   where id = p_message_id;

  -- Reactions are deliberately left where they are. Clearing them here would
  -- be tidier, and both clients already refuse to render reactions on a
  -- tombstone, so the rows are never shown. They go for real when the message
  -- row does, by cascade.
end;
$$;

revoke all on function delete_message(uuid, text) from public;
grant execute on function delete_message(uuid, text) to authenticated;
