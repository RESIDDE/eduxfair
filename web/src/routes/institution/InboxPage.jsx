import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Archive, ArchiveRestore, Ban, EyeOff, Forward, Inbox, Lock, Mic, Paperclip,
  Pin, PinOff, Reply, Send, SmilePlus, Trash2, X,
} from 'lucide-react';
import {
  Alert,
  Avatar,
  Button,
  EmptyState,
  Input,
  Loading,
  SearchField,
  SegmentedControl,
  SurfaceCard,
} from '../../components/ui';
import {
  AttachmentChip,
  BUCKET,
  InlineImage,
  VoiceNote,
  VoiceRecorder,
  uploadAttachment,
} from '../../components/messages/Attachment';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { relativeTime } from '../../lib/format';

/**
 * The six, in agreement with the CHECK on `message_reactions`. Validated there
 * too, because the client is not the place to decide what may be written to a
 * table.
 */
const REACTIONS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/**
 * What to call the other side of a thread.
 *
 * A shortened match token rather than "Student": several anonymous threads
 * need to be told apart, and the same token is on their match card, so the two
 * line up. Mirrors InboxThread.displayName in the Flutter app.
 */
function threadName(conversation) {
  if (conversation.shared_name) return conversation.shared_name;
  const token = conversation.token ?? '';
  return token ? `Student ${token.slice(0, 6).toUpperCase()}` : 'Student';
}

/**
 * Conversations with students, delivered live over Supabase Realtime.
 *
 * The subscription is scoped to the open thread: subscribing to the whole table
 * would deliver nothing extra (RLS filters it) but would wake the client on
 * every message on the platform.
 *
 * Pinning and archiving are per officer, not per institution. They live on
 * `conversation_participants` for the same reason `last_read_at` does — a
 * thread several people are working must not vanish from a colleague's list
 * because one of them filed it away.
 */
export default function InboxPage() {
  const { institutionId, user } = useAuth();
  const [activeId, setActiveId] = useState(null);
  const [tab, setTab] = useState('inbox');
  const [query, setQuery] = useState('');
  const [matches, setMatches] = useState({});

  // `institution_inbox`, not `conversations` joined to `profiles`. The view
  // is where the consent rules already live: it hands back a match token for
  // every thread and withholds the name and the avatar until the student has
  // shared. Reading profiles directly worked — RLS still hid the names — but
  // it made every anonymous student render as the same word "Student", with
  // no way to tell two of them apart. It also duplicates, in JavaScript, the
  // unread and pinned arithmetic the view already does.
  const { data: conversations, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('institution_inbox')
        .select('*')
        .eq('institution_id', institutionId)
        .order('last_message_at', { ascending: false, nullsFirst: false }),
    [institutionId],
  );

  // Typing is not a search. The name half filters what is already in memory on
  // every keystroke; only the message-body half waits, so the server sees one
  // query per pause rather than one per letter.
  useEffect(() => {
    const term = query.trim();
    if (!term) {
      setMatches({});
      return undefined;
    }
    const timer = setTimeout(async () => {
      const { data } = await supabase.rpc('search_conversations', { p_query: term });
      setMatches(
        Object.fromEntries((data ?? []).map((row) => [row.conversation_id, row.snippet])),
      );
    }, 280);
    return () => clearTimeout(timer);
  }, [query]);

  const rows = useMemo(() => {
    const all = conversations ?? [];
    const term = query.trim().toLowerCase();

    return all
      .filter((c) => {
        if (Boolean(c.archived_at) !== (tab === 'archived')) return false;
        if (!term) return true;
        return (
          threadName(c).toLowerCase().includes(term)
          || (c.subject ?? '').toLowerCase().includes(term)
          || c.conversation_id in matches
        );
      })
      .sort((a, b) => {
        const ap = Boolean(a.pinned_at);
        const bp = Boolean(b.pinned_at);
        if (ap !== bp) return ap ? -1 : 1;
        return new Date(b.last_message_at ?? 0) - new Date(a.last_message_at ?? 0);
      });
  }, [conversations, query, matches, tab]);

  const archivedCount = (conversations ?? []).filter((c) => c.archived_at).length;

  async function setState(conversationId, next) {
    await supabase.rpc('set_conversation_state', {
      p_conversation_id: conversationId,
      p_pinned: next.pinned ?? null,
      p_archived: next.archived ?? null,
    });
    reload();
  }

  if (loading) return <Loading label="Loading your inbox" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  if ((conversations ?? []).length === 0) {
    return (
      <EmptyState
        icon={Inbox}
        title="No conversations yet"
        subtitle="Students can message you from your institution page or any of your program pages."
      />
    );
  }

  const active = rows.find((c) => c.id === activeId) ?? rows[0] ?? null;

  return (
    <div className="flex h-full min-h-0 gap-4">
      <div className="flex w-[320px] shrink-0 flex-col gap-3 min-h-0">
        <SearchField
          value={query}
          onChange={setQuery}
          placeholder="Search students and messages"
        />
        <SegmentedControl
          value={tab}
          onChange={setTab}
          options={[
            { value: 'inbox', label: 'Inbox' },
            { value: 'archived', label: 'Archived', count: archivedCount || undefined },
          ]}
        />

        <div className="flex flex-1 flex-col gap-2 overflow-y-auto scrollbar-thin">
          {rows.length === 0 && (
            <div className="px-2 py-8 text-center text-[12.5px] leading-relaxed text-subtle">
              {query.trim()
                ? 'Nothing matched. Search looks at the student’s name and at what has been said in the thread.'
                : tab === 'archived'
                  ? 'Nothing archived. Archiving moves a thread off your inbox without deleting anything, and only you see the change.'
                  : 'Nothing here.'}
            </div>
          )}

          {rows.map((conversation) => {
            const pinned = Boolean(conversation.pinned_at);
            const archived = Boolean(conversation.archived_at);
            const unread = conversation.unread_count > 0;

            return (
              <SurfaceCard
                key={conversation.conversation_id}
                radius="rounded-tile"
                onClick={() => setActiveId(conversation.conversation_id)}
                className={`group p-3.5 transition-colors ${
                  active?.conversation_id === conversation.conversation_id
                    ? 'bg-accent/10'
                    : 'hover:bg-white/[0.03]'
                }`}
              >
                <div className="flex items-start gap-3">
                  {/* A face once there is one to show, and a padlock until
                      then: the same image is on the student's public handle
                      profile, so one on an anonymous row would match the
                      thread to a handle. */}
                  {conversation.is_shared ? (
                    <Avatar
                      size={32}
                      src={conversation.shared_avatar_url || undefined}
                      name={conversation.shared_name}
                    />
                  ) : (
                    <span
                      title="Identity hidden until they share their passport"
                      className="grid size-8 shrink-0 place-items-center rounded-full bg-surface-variant text-subtle"
                    >
                      <Lock size={13} />
                    </span>
                  )}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      {pinned && <Pin size={11} className="shrink-0 text-subtle" />}
                      <span
                        className={`truncate text-[13.5px] ${
                          unread ? 'font-bold' : 'font-medium'
                        }`}
                      >
                        {threadName(conversation)}
                      </span>
                      {unread && <span className="size-2 shrink-0 rounded-full bg-accent" />}
                    </div>
                    <div className="truncate text-[12px] text-subtle">
                      {/* The matching line beats the latest one while a search
                          is running: a result with no visible reason is what
                          makes search feel arbitrary. */}
                      {(query.trim() && matches[conversation.conversation_id])
                        || conversation.last_message_body
                        || conversation.subject
                        || 'Conversation'}
                    </div>
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-1">
                    <span className="text-[11px] text-subtle">
                      {relativeTime(conversation.last_message_at)}
                    </span>
                    <div className="flex gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
                      <RowAction
                        label={pinned ? 'Unpin' : 'Pin to the top'}
                        icon={pinned ? PinOff : Pin}
                        onClick={() => setState(conversation.conversation_id, { pinned: !pinned })}
                      />
                      <RowAction
                        label={archived ? 'Unarchive' : 'Archive'}
                        icon={archived ? ArchiveRestore : Archive}
                        onClick={() => setState(conversation.conversation_id, { archived: !archived })}
                      />
                    </div>
                  </div>
                </div>
              </SurfaceCard>
            );
          })}
        </div>
      </div>

      {active && (
        <Thread
          key={active.conversation_id}
          conversation={active}
          conversations={conversations ?? []}
          myId={user?.id}
          onSent={reload}
        />
      )}
    </div>
  );
}

function RowAction({ label, icon: Icon, onClick }) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={(event) => {
        // The row behind this opens the thread; pinning it should not.
        event.stopPropagation();
        onClick();
      }}
      className="grid size-6 cursor-pointer place-items-center rounded-full text-subtle transition-colors hover:bg-white/10 hover:text-white"
    >
      <Icon size={13} />
    </button>
  );
}

/**
 * Delete controls, revealed on hover.
 *
 * "For me" is a reading preference — the row is untouched and the other side
 * never learns of it, so there is nothing to mark. "For everyone" withdraws
 * what was said, is the sender's own only, and leaves the tombstone that makes
 * the gap honest.
 */
function BubbleActions({ message, isMine, onRemove, onReact, onReply, onForward }) {
  const [picking, setPicking] = useState(false);

  // A tombstone has nothing left to react to, reply to or forward.
  if (message.deleted_at) {
    return (
      <div className="flex shrink-0 flex-col gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
        <IconAction label="Delete for me" icon={EyeOff} onClick={() => onRemove(message, 'me')} />
      </div>
    );
  }

  return (
    <div className="relative flex shrink-0 flex-col gap-0.5 opacity-0 transition-opacity group-hover:opacity-100">
      {picking && (
        <div className="glass absolute bottom-full z-10 mb-1 flex gap-0.5 rounded-full p-1">
          {REACTIONS.map((emoji) => (
            <button
              key={emoji}
              type="button"
              onClick={() => { setPicking(false); onReact(message, emoji); }}
              className="cursor-pointer rounded-full px-1.5 py-0.5 text-[16px] hover:bg-white/15"
            >
              {emoji}
            </button>
          ))}
        </div>
      )}
      <IconAction label="React" icon={SmilePlus} onClick={() => setPicking((p) => !p)} />
      <IconAction label="Reply" icon={Reply} onClick={() => onReply(message)} />
      <IconAction label="Forward" icon={Forward} onClick={() => onForward(message)} />
      <IconAction label="Delete for me" icon={EyeOff} onClick={() => onRemove(message, 'me')} />
      {isMine && (
        <IconAction
          label="Delete for everyone"
          icon={Trash2}
          danger
          onClick={() => onRemove(message, 'everyone')}
        />
      )}
    </div>
  );
}

/** Which thread to forward into, from the ones this officer already has. */
function ForwardPicker({ conversations, onPick, onCancel }) {
  return (
    <div className="shrink-0 border-t border-white/6 bg-surface-variant px-5 py-3">
      <div className="mb-2 flex items-center justify-between">
        <span className="text-[12px] font-bold text-white">Forward to</span>
        <button
          type="button"
          aria-label="Cancel"
          onClick={onCancel}
          className="grid size-7 cursor-pointer place-items-center rounded-full text-subtle hover:bg-white/10 hover:text-white"
        >
          <X size={14} />
        </button>
      </div>
      {conversations.length === 0 ? (
        <p className="text-[12px] text-subtle">No other conversation to forward this to.</p>
      ) : (
        <div className="flex max-h-40 flex-col gap-1 overflow-y-auto scrollbar-thin">
          {conversations.map((c) => (
            <button
              key={c.conversation_id}
              type="button"
              onClick={() => onPick(c.conversation_id)}
              className="cursor-pointer truncate rounded-tile px-3 py-2 text-left text-[13px] hover:bg-white/8"
            >
              {threadName(c)}
              {c.subject && <span className="text-subtle"> · {c.subject}</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Rows of (emoji, profile_id) into emoji -> who. */
function groupReactions(rows) {
  const out = {};
  for (const row of rows ?? []) {
    (out[row.emoji] ??= []).push(row.profile_id);
  }
  return out;
}

/** A one-line stand-in for a quoted message, where the body is not the point. */
function quotedLabel(message) {
  if (!message) return 'Message';
  if (message.deleted_at) return 'This message was deleted';
  if (message.body?.trim()) return message.body;
  if (message.kind === 'voice') return 'Voice note';
  if (message.kind === 'image') return 'Photo';
  return message.attachment_name || 'Attachment';
}

function IconAction({ label, icon: Icon, danger, onClick }) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      className={`grid size-6 cursor-pointer place-items-center rounded-full transition-colors ${
        danger ? 'text-error hover:bg-error-bg' : 'text-subtle hover:bg-white/10 hover:text-white'
      }`}
    >
      <Icon size={12} />
    </button>
  );
}

function Thread({ conversation, conversations, myId, onSent }) {
  // The view calls it `conversation_id`; everything below wants one name.
  const conversationId = conversation.conversation_id;
  const [messages, setMessages] = useState([]);
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const [recording, setRecording] = useState(false);
  const [replyingTo, setReplyingTo] = useState(null);
  const [forwarding, setForwarding] = useState(null);
  const [error, setError] = useState(null);
  const bottomRef = useRef(null);
  const fileRef = useRef(null);

  useEffect(() => {
    let active = true;

    async function load() {
      // The embedded hides are filtered to OUR rows, so a non-empty list means
      // this person chose not to see this message. Delete-for-me is a reading
      // preference: the row is untouched and the other side never learns of it.
      const { data } = await supabase
        .from('messages')
        .select('*, message_hides(profile_id), message_reactions(profile_id, emoji)')
        .eq('conversation_id', conversationId)
        .eq('message_hides.profile_id', myId)
        .order('created_at')
        .limit(200);
      if (active) setMessages((data ?? []).filter((m) => !m.message_hides?.length));
    }

    load();

    // Mark read so the unread dot clears and the dashboard count is honest.
    supabase.from('conversation_participants').upsert(
      {
        conversation_id: conversationId,
        profile_id: myId,
        last_read_at: new Date().toISOString(),
      },
      { onConflict: 'conversation_id,profile_id' },
    );

    const channel = supabase
      .channel(`messages:${conversationId}`)
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'messages',
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          if (!active) return;
          setMessages((prev) =>
            // De-duplicate: the sender already appended this optimistically.
            prev.some((m) => m.id === payload.new.id) ? prev : [...prev, payload.new],
          );
        },
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'messages',
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          // A delete-for-everyone is an UPDATE, not an insert. Without this
          // the other party keeps reading a message its sender withdrew.
          if (!active) return;
          setMessages((prev) =>
            prev.map((m) => (m.id === payload.new.id ? { ...m, ...payload.new } : m)));
        },
      )
      .subscribe();

    return () => {
      active = false;
      supabase.removeChannel(channel);
    };
  }, [conversationId, myId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: 'end' });
  }, [messages]);

  // Quotes resolve from what is loaded; anything older falls back to a label.
  const byId = new Map(messages.map((m) => [m.id, m]));

  /**
   * One write path for every kind of message.
   *
   * `kind` is passed rather than inferred: the column exists precisely so a
   * client does not have to guess from a file extension, which is how an .m4a
   * somebody attached on purpose ends up rendered as a voice note.
   */
  async function insert({ text, path, name, mime, kind, durationMs, replyToId, forwarded }) {
    const { data, error: writeError } = await supabase
      .from('messages')
      .insert({
        conversation_id: conversationId,
        sender_id: myId,
        body: text || null,
        attachment_path: path ?? null,
        kind: path ? kind : 'text',
        attachment_name: path ? name : null,
        attachment_mime: path ? mime : null,
        duration_ms: durationMs ?? null,
        reply_to_id: replyToId ?? null,
        is_forwarded: forwarded ?? false,
      })
      .select()
      .single();

    if (writeError) throw writeError;
    setMessages((prev) => (prev.some((m) => m.id === data.id) ? prev : [...prev, data]));
    onSent();
  }

  /// The two deletions, which are genuinely different things.
  async function remove(message, scope) {
    try {
      await supabase.rpc('delete_message', {
        p_message_id: message.id,
        p_scope: scope,
      });
      if (scope === 'me') {
        setMessages((prev) => prev.filter((m) => m.id !== message.id));
      } else {
        // Reloaded through the realtime UPDATE above rather than patched
        // here: the tombstone's shape is the server's to decide.
        setMessages((prev) => prev.map((m) => (
          m.id === message.id
            ? { ...m, body: null, attachment_path: null, kind: 'text', deleted_at: new Date().toISOString() }
            : m)));
      }
      onSent();
    } catch (err) {
      setError(describeError(err));
    }
  }

  /**
   * Adds, changes or clears this person's reaction.
   *
   * One per person, so a different emoji is an UPSERT and the same one again
   * clears it — which is what clicking a reaction you already gave means.
   */
  async function react(message, emoji) {
    const mine = (message.message_reactions ?? [])
      .find((r) => r.profile_id === myId);
    try {
      if (mine?.emoji === emoji) {
        await supabase.from('message_reactions').delete()
          .eq('message_id', message.id).eq('profile_id', myId);
      } else {
        await supabase.from('message_reactions').upsert(
          { message_id: message.id, profile_id: myId, emoji },
          { onConflict: 'message_id,profile_id' },
        );
      }
      // Applied locally rather than refetching the thread: a reaction is one
      // cell changing, and two hundred rows to repaint it would make the
      // click feel like a round trip.
      setMessages((prev) => prev.map((m) => {
        if (m.id !== message.id) return m;
        const others = (m.message_reactions ?? []).filter((r) => r.profile_id !== myId);
        return {
          ...m,
          message_reactions: mine?.emoji === emoji
            ? others
            : [...others, { profile_id: myId, emoji }],
        };
      }));
    } catch (err) {
      setError(describeError(err));
    }
  }

  /**
   * Sends a copy of a message into another thread.
   *
   * The attachment is COPIED in storage, not referenced: object paths are
   * keyed on the conversation and the storage policy authorizes on that first
   * segment, so pointing the new row at the old path would produce a message
   * nobody on the receiving thread could open.
   */
  async function forward(message, toConversationId) {
    setSending(true);
    setError(null);
    try {
      let path = null;
      if (message.attachment_path) {
        const safe = (message.attachment_name ?? 'file').replace(/[^A-Za-z0-9._-]/g, '_');
        path = `${toConversationId}/${Date.now()}-${safe}`;
        const { error: copyError } = await supabase.storage
          .from(BUCKET).copy(message.attachment_path, path);
        if (copyError) throw copyError;
      }
      const { error: writeError } = await supabase.from('messages').insert({
        conversation_id: toConversationId,
        sender_id: myId,
        body: message.body,
        attachment_path: path,
        kind: path ? message.kind : 'text',
        attachment_name: path ? message.attachment_name : null,
        attachment_mime: path ? message.attachment_mime : null,
        duration_ms: message.duration_ms,
        is_forwarded: true,
      });
      if (writeError) throw writeError;
      onSent();
    } catch (err) {
      setError(describeError(err));
    } finally {
      setSending(false);
    }
  }

  async function send(event) {
    event.preventDefault();
    const text = body.trim();
    if (!text) return;

    const quoted = replyingTo;
    setSending(true);
    setError(null);
    setBody('');
    // Cleared before the round trip, so the strip does not sit there looking
    // like the next message will quote it too.
    setReplyingTo(null);
    try {
      await insert({ text, replyToId: quoted?.id });
    } catch (err) {
      setBody(text); // don't lose what they typed
      setReplyingTo(quoted);
      setError(describeError(err));
    } finally {
      setSending(false);
    }
  }

  async function sendFile(file) {
    if (!file) return;
    if (file.size > 20 * 1024 * 1024) {
      setError('That file is larger than 20 MB.');
      return;
    }
    setSending(true);
    setError(null);
    try {
      const path = await uploadAttachment(conversationId, file);
      await insert({
        path,
        name: file.name,
        mime: file.type,
        kind: file.type?.startsWith('image/') ? 'image' : 'file',
      });
    } catch (err) {
      setError(describeError(err));
    } finally {
      setSending(false);
    }
  }

  async function sendVoice(blob, durationMs) {
    setRecording(false);
    setSending(true);
    setError(null);
    try {
      // The container the browser actually produced — webm on Chrome, mp4 on
      // Safari — so the extension and the stored mime cannot disagree.
      const ext = blob.type.includes('mp4') ? 'm4a' : 'webm';
      const file = new File([blob], `voice-note.${ext}`, { type: blob.type.split(';')[0] });
      const path = await uploadAttachment(conversationId, file);
      await insert({
        path,
        name: file.name,
        mime: file.type,
        kind: 'voice',
        durationMs,
      });
    } catch (err) {
      setError(describeError(err));
    } finally {
      setSending(false);
    }
  }

  return (
    <SurfaceCard className="flex min-w-0 flex-1 flex-col overflow-hidden p-0">
      <div className="shrink-0 border-b border-white/6 px-5 py-4">
        <div className="font-semibold">
          {threadName(conversation)}
        </div>
        <div className="text-[12.5px] text-subtle">
          {conversation.subject ?? 'Conversation'}
        </div>
      </div>

      <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto scrollbar-thin px-5 py-4">
        {messages.length === 0 && (
          <div className="m-auto max-w-sm text-center text-[13px] leading-relaxed text-subtle">
            No messages yet. Anything you write here is part of the permanent
            record — it cannot be edited or deleted afterwards, by you or by us.
          </div>
        )}
        {messages.map((message, index) => {
          const isMine = message.sender_id === myId;
          const isFirstOfRun =
            index === 0 || messages[index - 1].sender_id !== message.sender_id;

          return (
            <div
              key={message.id}
              className={`flex ${isMine ? 'justify-end' : 'justify-start'} ${
                isFirstOfRun ? 'mt-2' : ''
              }`}
            >
              <div className="group flex max-w-[72%] items-center gap-1.5">
                {isMine && (
                  <BubbleActions
                    message={message} isMine onRemove={remove}
                    onReact={react} onReply={setReplyingTo} onForward={setForwarding}
                  />
                )}
                <div
                  className={`min-w-0 rounded-[16px] px-3.5 py-2.5 text-[13.5px] leading-relaxed ${
                    isMine ? 'gradient-accent text-on-accent' : 'bg-surface-variant text-white'
                  }`}
                >
                  {/* Like WhatsApp: a small italic label, and nothing about
                      where it came from — naming that would name a
                      conversation the reader is not on. */}
                  {message.is_forwarded && !message.deleted_at && (
                    <div className={`mb-1 flex items-center gap-1 text-[11px] italic ${isMine ? 'text-white/75' : 'text-subtle'}`}>
                      <Forward size={12} />
                      Forwarded
                    </div>
                  )}

                  {message.reply_to_id && !message.deleted_at && (
                    <div className={`mb-1.5 border-l-[3px] pl-2 text-[12px] leading-snug ${
                      isMine ? 'border-white/80 text-white/85' : 'border-accent text-subtle'
                    }`}
                    >
                      {/* Null when the original is outside the loaded window;
                          the label beats an empty strip. */}
                      {quotedLabel(byId.get(message.reply_to_id))}
                    </div>
                  )}

                  {message.deleted_at ? (
                    // A withdrawn message says so, and says nothing else.
                    <span className={`flex items-center gap-1.5 italic ${isMine ? 'text-white/80' : 'text-subtle'}`}>
                      <Ban size={13} className="shrink-0" />
                      This message was deleted
                    </span>
                  ) : (
                    <>
                      {/* Three attachments, three renderings. One grey chip for
                          all of them made a photo look exactly like a PDF. */}
                      {message.kind === 'voice' && (
                        <VoiceNote message={message} mine={isMine} />
                      )}
                      {message.kind === 'image' && <InlineImage message={message} />}
                      {message.kind === 'file' && <AttachmentChip message={message} />}

                      {message.body && (
                        <div className={message.attachment_path ? 'mt-2' : undefined}>
                          {message.body}
                        </div>
                      )}
                    </>
                  )}

                  {!message.deleted_at && (message.message_reactions ?? []).length > 0 && (
                    <div className="mt-1.5 flex flex-wrap gap-1">
                      {Object.entries(groupReactions(message.message_reactions)).map(
                        ([emoji, who]) => (
                          <button
                            key={emoji}
                            type="button"
                            onClick={() => react(message, emoji)}
                            className={`cursor-pointer rounded-full px-1.5 py-0.5 text-[12px] ${
                              isMine ? 'bg-white/20' : 'bg-surface'
                            } ${who.includes(myId) ? 'ring-1 ring-accent' : ''}`}
                          >
                            {who.length > 1 ? `${emoji} ${who.length}` : emoji}
                          </button>
                        ),
                      )}
                    </div>
                  )}

                  <div className={`mt-1 text-[10.5px] ${isMine ? 'text-white/70' : 'text-subtle'}`}>
                    {new Date(message.created_at).toLocaleTimeString('en-GB', {
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                  </div>
                </div>
                {!isMine && (
                  <BubbleActions
                    message={message} onRemove={remove}
                    onReact={react} onReply={setReplyingTo} onForward={setForwarding}
                  />
                )}
              </div>
            </div>
          );
        })}
        <div ref={bottomRef} />
      </div>

      {error && (
        <div className="px-5 pb-3">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      {replyingTo && (
        <div className="flex shrink-0 items-center gap-3 border-t border-white/6 bg-surface-variant px-5 py-2.5">
          <span className="h-8 w-[3px] shrink-0 rounded bg-accent" />
          <div className="min-w-0 flex-1">
            <div className="text-[11px] font-bold text-accent">Replying</div>
            <div className="truncate text-[12px] text-subtle">
              {quotedLabel(replyingTo)}
            </div>
          </div>
          <button
            type="button"
            aria-label="Stop replying"
            onClick={() => setReplyingTo(null)}
            className="grid size-7 cursor-pointer place-items-center rounded-full text-subtle hover:bg-white/10 hover:text-white"
          >
            <X size={14} />
          </button>
        </div>
      )}

      {forwarding && (
        <ForwardPicker
          conversations={conversations.filter(
            (c) => c.conversation_id !== conversationId,
          )}
          onPick={async (id) => { setForwarding(null); await forward(forwarding, id); }}
          onCancel={() => setForwarding(null)}
        />
      )}

      <div className="shrink-0 border-t border-white/6 px-5 py-4">
        {recording ? (
          <VoiceRecorder
            onComplete={sendVoice}
            onCancel={(message) => {
              setRecording(false);
              if (message) setError(message);
            }}
          />
        ) : (
          <form onSubmit={send} className="flex items-center gap-2.5">
            <input
              ref={fileRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/heic,application/pdf,.doc,.docx"
              className="hidden"
              onChange={(event) => {
                sendFile(event.target.files?.[0]);
                event.target.value = '';
              }}
            />
            <Button
              type="button"
              variant="ghost"
              icon={Paperclip}
              aria-label="Attach a photo or file"
              onClick={() => fileRef.current?.click()}
              disabled={sending}
            />
            <Input
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Write a reply"
              className="flex-1"
            />
            {/* Microphone until there is something to send, then send. Two
                buttons would mean one of them is disabled most of the time. */}
            {body.trim() ? (
              <Button type="submit" icon={Send} loading={sending}>Send</Button>
            ) : (
              <Button
                type="button"
                icon={Mic}
                disabled={sending}
                onClick={() => setRecording(true)}
              >
                Record
              </Button>
            )}
          </form>
        )}
      </div>
    </SurfaceCard>
  );
}
