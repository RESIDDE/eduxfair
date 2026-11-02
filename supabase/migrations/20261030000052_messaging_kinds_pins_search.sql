-- Voice notes, pictures that look like pictures, pinning, archiving, search.
--
-- `messages` already carried an `attachment_path`, so files and images were
-- being SENT before this — they just arrived as an anonymous chip, because
-- nothing recorded what a row actually was. A client cannot tell a voice note
-- from a PDF by looking at a storage path, and guessing from the extension is
-- how a .m4a someone attached deliberately ends up rendered as a player.
--
-- So the kind is written down. Everything else here follows from that, plus
-- two pieces of per-person state the inbox needed and did not have.

-- ------------------------------------------------------------- what a row is

create type message_kind as enum ('text', 'file', 'image', 'voice');

alter table messages
  -- The name as the sender had it. `attachment_path` is prefixed with a
  -- timestamp for uniqueness, and both clients were reconstructing the
  -- original by splitting on the first dash — which quietly mangled every
  -- filename that already contained one.
  add column attachment_name text,
  add column attachment_mime text,
  -- Voice notes only. Stored rather than read from the file so a waveform can
  -- be drawn before the audio has been fetched.
  add column duration_ms int,
  add column kind message_kind not null default 'text';

-- Existing rows predate the column: anything with a path was a file.
update messages set kind = 'file' where attachment_path is not null;

alter table messages add constraint message_kind_has_attachment
  check (kind = 'text' or attachment_path is not null);

alter table messages add constraint message_voice_has_duration
  check (kind <> 'voice' or (duration_ms is not null and duration_ms > 0));

comment on column messages.kind is
  'What this row is, decided by the sender and not inferred from the file '
  'extension. Drives whether a client renders a bubble, an image, a download '
  'or a player.';

-- Audio was not in the bucket's allowlist, so a voice note would have been
-- refused by Storage before any of this mattered. webm/ogg is what a browser's
-- MediaRecorder produces; mp4/aac is what the phones record.
update storage.buckets
   set allowed_mime_types = array[
         'application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'audio/mp4', 'audio/aac', 'audio/mpeg', 'audio/webm', 'audio/ogg',
         'audio/wav']
 where id = 'message-attachments';

-- ------------------------------------------------------- pinned and archived
--
-- On conversation_participants, NOT on conversations. An institution thread
-- can have several officers reading it, and one of them archiving a thread
-- must not take it off a colleague's list — the same reason last_read_at
-- lives here rather than being a column on the conversation.

alter table conversation_participants
  add column pinned_at   timestamptz,
  add column archived_at timestamptz;

create index conversation_participants_pinned_idx
  on conversation_participants (profile_id, pinned_at desc)
  where pinned_at is not null;

create index conversation_participants_archived_idx
  on conversation_participants (profile_id)
  where archived_at is not null;

/**
 * Pins or archives a thread for the caller alone.
 *
 * Null leaves a flag as it was, so a client can set one without knowing the
 * other. Upserts, because a participant row is created lazily on first read
 * and somebody may pin a thread they have not opened yet.
 *
 * Pinning clears `archived_at`: the two states are a contradiction, and
 * resolving it here means no client has to remember the rule.
 */
create or replace function set_conversation_state(
  p_conversation_id uuid,
  p_pinned          boolean default null,
  p_archived        boolean default null
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not can_access_conversation(p_conversation_id) then
    raise exception 'that conversation is not yours';
  end if;

  insert into conversation_participants (conversation_id, profile_id)
  values (p_conversation_id, auth.uid())
  on conflict (conversation_id, profile_id) do nothing;

  update conversation_participants
     set pinned_at = case
           when p_pinned is null then pinned_at
           when p_pinned then coalesce(pinned_at, now())
           else null end,
         archived_at = case
           -- Pinning un-archives, whatever p_archived says.
           when p_pinned then null
           when p_archived is null then archived_at
           when p_archived then coalesce(archived_at, now())
           else null end
   where conversation_id = p_conversation_id
     and profile_id = auth.uid();
end;
$$;

revoke all on function set_conversation_state(uuid, boolean, boolean) from public;
grant execute on function set_conversation_state(uuid, boolean, boolean) to authenticated;

-- ---------------------------------------------------------------- searching
--
-- `ilike`, not full-text, for the reason search_posts gives in 20251010000029:
-- tsvector needs an index, a language configuration and a decision about
-- stemming across the languages these students write in, and none of that is
-- worth committing to yet. The signature here does not change when it is.
--
-- Deliberately NOT security definer. Invoker rights mean messages_select_party
-- decides what is searchable, so this function cannot become a way to read a
-- thread the caller is not on — which is exactly the mistake a definer
-- function over a message table would be.

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
             -- A voice note has no body to quote, so say what it was.
             coalesce(
               nullif(m.body, ''),
               m.attachment_name,
               case m.kind when 'voice' then 'Voice note' else 'Attachment' end
             ) as snippet,
             m.created_at as matched_at
        from messages m
       where coalesce(trim(p_query), '') <> ''
         and (m.body ilike '%' || trim(p_query) || '%'
              or m.attachment_name ilike '%' || trim(p_query) || '%')
       order by m.conversation_id, m.created_at desc
    ) hits
   order by hits.matched_at desc
   limit greatest(1, least(p_limit, 100));
$$;

comment on function search_conversations(text, int) is
  'Threads whose MESSAGES match. Matching a thread by the other party''s name '
  'is left to the clients, which already hold that list and can filter it '
  'without a round trip.';

revoke all on function search_conversations(text, int) from public;
grant execute on function search_conversations(text, int) to authenticated;
