import { useEffect, useRef, useState } from 'react';
import { SendHorizonal, Trash2 } from 'lucide-react';
import { supabase, describeError } from '../../lib/supabase';
import { Alert, Button, Input } from '../ui';

/**
 * In-room chat, over Postgres rather than LiveKit.
 *
 * LiveKit text streams are not persisted and reach only the clients that are
 * connected when the stream opens, so a student arriving ten minutes into an
 * admissions hour would find an empty panel. Keeping chat in a table means
 * ordering, history and persistence are one mechanism instead of three — and
 * both clients already have the postgres_changes code.
 *
 * A Space uses `space_messages`, keyed on the participant rather than the
 * person. An appointment uses the `messages` thread the two of them already
 * have, so what was typed during a call is in the inbox where they will look
 * for it afterwards, and the 1:1 case needs no new schema at all.
 */
export function ChatPanel({
  isSpace, chatId, myParticipantId, myProfileId, roster, canModerate, canPost, onNeedsConsent,
}) {
  const [messages, setMessages] = useState([]);
  const [body, setBody] = useState('');
  const [error, setError] = useState(null);
  const [sending, setSending] = useState(false);
  const bottomRef = useRef(null);

  const table = isSpace ? 'space_messages' : 'messages';
  const key = isSpace ? 'space_id' : 'conversation_id';

  useEffect(() => {
    if (!chatId) return undefined;
    let active = true;

    (async () => {
      const query = supabase.from(table).select('*').eq(key, chatId)
        .order('created_at', { ascending: true }).limit(400);
      const { data, error: queryError } = isSpace
        ? await query.is('deleted_at', null)
        : await query;
      if (!active) return;
      if (queryError) setError(describeError(queryError));
      else setMessages(data ?? []);
    })();

    const channel = supabase
      .channel(`${table}:${chatId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table, filter: `${key}=eq.${chatId}` },
        (payload) => {
          if (!active) return;
          // De-duplicate: the sender already appended this optimistically.
          setMessages((prev) => (
            prev.some((m) => m.id === payload.new.id) ? prev : [...prev, payload.new]
          ));
        },
      )
      .subscribe();

    return () => {
      active = false;
      supabase.removeChannel(channel);
    };
  }, [table, key, chatId, isSpace]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ block: 'end' });
  }, [messages]);

  // Names are resolved from the roster by participant id, which is why the
  // chat row itself does not carry one.
  const nameFor = (message) => {
    if (!isSpace) return message.sender_id === myProfileId ? 'You' : 'Them';
    if (message.participant_id === myParticipantId) return 'You';
    const row = (roster ?? []).find((r) => r.participant_id === message.participant_id);
    if (!row) return 'Someone';
    return row.shared_name ?? (row.handle ? `@${row.handle}` : 'A student');
  };

  async function send(event) {
    event.preventDefault();
    const text = body.trim();
    if (!text) return;

    // Posting in the chat identifies a student, so the consent sheet comes
    // first. The insert policy refuses a listener anyway — this is so they are
    // asked rather than rejected.
    if (!canPost) return onNeedsConsent?.();

    setSending(true);
    setError(null);
    const row = isSpace
      ? { space_id: chatId, participant_id: myParticipantId, body: text }
      : { conversation_id: chatId, sender_id: myProfileId, body: text };

    const { data, error: insertError } = await supabase
      .from(table).insert(row).select().single();

    if (insertError) setError(describeError(insertError));
    else {
      setBody('');
      setMessages((prev) => (prev.some((m) => m.id === data.id) ? prev : [...prev, data]));
    }
    setSending(false);
  }

  async function remove(id) {
    const { error: rpcError } = await supabase.rpc('remove_space_message', { p_message_id: id });
    if (rpcError) setError(describeError(rpcError));
    else setMessages((prev) => prev.filter((m) => m.id !== id));
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="min-h-0 flex-1 space-y-3 overflow-y-auto scrollbar-thin p-4">
        {messages.length === 0 && (
          <p className="pt-6 text-center text-[13px] text-subtle">
            No messages yet.
          </p>
        )}
        {messages.map((m) => (
          <div key={m.id} className="group">
            <div className="flex items-baseline gap-2">
              <span className="text-[12px] font-bold text-accent-light">{nameFor(m)}</span>
              <span className="text-[10px] text-subtle">
                {new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
              {isSpace && canModerate && (
                <button
                  type="button"
                  aria-label="Remove this message"
                  onClick={() => remove(m.id)}
                  className="ml-auto cursor-pointer text-error opacity-0 transition-opacity group-hover:opacity-100"
                >
                  <Trash2 size={13} />
                </button>
              )}
            </div>
            <p className="text-[13px] leading-relaxed break-words text-white/90">{m.body}</p>
          </div>
        ))}
        <div ref={bottomRef} />
      </div>

      {error && <div className="px-4 pb-2"><Alert tone="error">{error}</Alert></div>}

      <form onSubmit={send} className="flex items-center gap-2 border-t border-line p-3">
        <Input
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder={canPost ? 'Write a message' : 'Share your passport to join in'}
          maxLength={1000}
        />
        <Button type="submit" size="sm" icon={SendHorizonal} loading={sending} aria-label="Send" />
      </form>
    </div>
  );
}
