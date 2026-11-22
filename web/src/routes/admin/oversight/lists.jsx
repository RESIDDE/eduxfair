import { useState } from 'react';
import {
  BadgeCheck, CalendarClock, ChevronDown, ChevronRight, CornerDownRight,
  FileText, Flag, Forward, MessageSquare, Mic, Newspaper, Paperclip,
  ShieldX, Trash2,
} from 'lucide-react';
import {
  Alert, Badge, Button, Dialog, EmptyRow, Field, StatusBadge, SurfaceCard,
  TableCard, Td, Textarea, Th, Tr,
} from '../../../components/ui';
import { useAuth } from '../../../context/AuthContext';
import { useQuery } from '../../../lib/hooks';
import { describeError, supabase } from '../../../lib/supabase';
import { formatDate, formatDateTime, relativeTime } from '../../../lib/format';
import {
  APPLICATION_STAGES, DOCUMENT_KINDS, STUDY_LEVELS,
} from '../../../lib/vocab';
import {
  formatBytes, lookupPeople, openPrivateFile,
  publicFileUrl, withLookups,
} from '../../../lib/admin';
import { decideVerification } from '../../../lib/verification';
import { DataState, InstitutionChip, PersonChip, Prose } from './parts';

/**
 * Lists shared by the person page, the institution page and the platform-wide
 * pages. Each takes a `scope` — a function that narrows the query — and a
 * `scopeKey` that changes when the scope does, so one list can show "all
 * documents", "this student's documents" or "documents sent to this
 * institution" without three copies.
 */

const all = (q) => q;

export const REPORT_REASONS = {
  spam: 'Spam',
  harassment: 'Harassment',
  misinformation: 'Misinformation',
  impersonation: 'Impersonation',
  inappropriate: 'Inappropriate',
  child_safety: 'Child safety',
  other: 'Other',
};

const POST_KINDS = {
  update: 'Update',
  question: 'Question',
  announcement: 'Announcement',
  requirement: 'Requirements',
};

// ─────────────────────────────────────────────────────────── documents

export function DocumentsList({ scope = all, scopeKey = 'all', showOwner = true }) {
  const { profile } = useAuth();
  const [actionError, setActionError] = useState(null);
  const [busy, setBusy] = useState(null);

  const { data, loading, error, reload } = useQuery(
    (client) => withLookups(
      scope(client.from('passport_documents').select('*'))
        .order('created_at', { ascending: false })
        .limit(500),
      { people: ['profile_id', 'reviewed_by'] },
    ),
    [scopeKey],
  );

  async function open(doc) {
    setActionError(null);
    const err = await openPrivateFile('passport-docs', doc.storage_path);
    if (err) setActionError(describeError(err));
  }

  async function decide(doc, status) {
    setActionError(null);
    setBusy(doc.id + status);
    const err = await decideVerification({
      subjectType: 'document', subjectId: doc.id, status, reviewer: profile,
    });
    setBusy(null);
    if (err) setActionError(describeError(err));
    await reload();
  }

  const rows = data?.rows ?? [];
  return (
    <div className="flex flex-col gap-3">
      {actionError && <Alert tone="error">{actionError}</Alert>}
      <DataState
        loading={loading && !data}
        error={error}
        empty={rows.length === 0}
        emptyIcon={FileText}
        emptyTitle="No documents"
        emptySubtitle="Nothing has been uploaded here yet."
      >
        <TableCard minWidth={860}>
          <thead>
            <tr>
              <Th>Document</Th>
              {showOwner && <Th>Student</Th>}
              <Th>Uploaded</Th>
              <Th>Status</Th>
              <Th className="text-right">Actions</Th>
            </tr>
          </thead>
          <tbody>
            {rows.map((doc) => (
              <Tr key={doc.id}>
                <Td>
                  <div className="font-semibold">{DOCUMENT_KINDS[doc.kind] ?? doc.kind}</div>
                  <div className="text-[11.5px] text-subtle truncate max-w-[280px]">
                    {doc.file_name} · {formatBytes(doc.size_bytes)}
                  </div>
                </Td>
                {showOwner && (
                  <Td><PersonChip id={doc.profile_id} person={data.people[doc.profile_id]} /></Td>
                )}
                <Td className="text-muted whitespace-nowrap">{formatDateTime(doc.created_at)}</Td>
                <Td>
                  <StatusBadge status={doc.verification_status} compact />
                  {doc.review_note && (
                    <div className="mt-1 text-[11.5px] text-subtle max-w-[220px]">{doc.review_note}</div>
                  )}
                </Td>
                <Td>
                  <div className="flex justify-end gap-2">
                    <Button size="sm" variant="outline" icon={FileText} onClick={() => open(doc)}>
                      Open
                    </Button>
                    {doc.verification_status !== 'verified' && (
                      <Button
                        size="sm" variant="glass" icon={BadgeCheck}
                        loading={busy === doc.id + 'verified'}
                        onClick={() => decide(doc, 'verified')}
                      >
                        Verify
                      </Button>
                    )}
                    {doc.verification_status !== 'rejected' && (
                      <Button
                        size="sm" variant="dangerGhost" icon={ShieldX}
                        loading={busy === doc.id + 'rejected'}
                        onClick={() => decide(doc, 'rejected')}
                      >
                        Reject
                      </Button>
                    )}
                  </div>
                </Td>
              </Tr>
            ))}
          </tbody>
        </TableCard>
      </DataState>
    </div>
  );
}

// ──────────────────────────────────────────────────────── applications

export function ApplicationsList({ scope = all, scopeKey = 'all', hide = [] }) {
  const [openId, setOpenId] = useState(null);
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      scope(client.from('applications').select('*'))
        .order('updated_at', { ascending: false })
        .limit(500),
      { people: ['profile_id', 'assigned_to'], institutions: ['institution_id'], programs: ['program_id'] },
    ),
    [scopeKey],
  );

  const rows = data?.rows ?? [];
  const cols = 6 - hide.length;
  return (
    <DataState
      loading={loading && !data}
      error={error}
      empty={rows.length === 0}
      emptyIcon={FileText}
      emptyTitle="No applications"
    >
      <TableCard minWidth={900}>
        <thead>
          <tr>
            {!hide.includes('student') && <Th>Student</Th>}
            {!hide.includes('institution') && <Th>Institution</Th>}
            <Th>Programme</Th>
            <Th>Stage</Th>
            <Th>Submitted</Th>
            <Th>Updated</Th>
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 && <EmptyRow colSpan={cols}>No applications</EmptyRow>}
          {rows.map((app) => {
            const program = data.programs[app.program_id];
            const isOpen = openId === app.id;
            return [
              <Tr key={app.id} onClick={() => setOpenId(isOpen ? null : app.id)}>
                {!hide.includes('student') && (
                  <Td><PersonChip id={app.profile_id} person={data.people[app.profile_id]} /></Td>
                )}
                {!hide.includes('institution') && (
                  <Td>
                    <InstitutionChip id={app.institution_id} institution={data.institutions[app.institution_id]} />
                  </Td>
                )}
                <Td>
                  <div className="flex items-center gap-1.5">
                    {isOpen ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                    <span className="font-medium">{program?.name ?? 'General application'}</span>
                  </div>
                  <div className="pl-5 text-[11.5px] text-subtle">
                    {[STUDY_LEVELS[program?.level], app.intake].filter(Boolean).join(' · ')}
                  </div>
                </Td>
                <Td><StatusBadge status={app.stage} compact /></Td>
                <Td className="text-muted whitespace-nowrap">{formatDate(app.submitted_at)}</Td>
                <Td className="text-muted whitespace-nowrap">{relativeTime(app.updated_at)}</Td>
              </Tr>,
              isOpen && (
                <tr key={`${app.id}-detail`}>
                  <td colSpan={cols} className="bg-white/[0.02] px-6 py-5">
                    <ApplicationDetail application={app} people={data.people} />
                  </td>
                </tr>
              ),
            ];
          })}
        </tbody>
      </TableCard>
    </DataState>
  );
}

/** Everything behind one application: the student's note, its history, its documents. */
function ApplicationDetail({ application, people }) {
  const [actionError, setActionError] = useState(null);
  const { data, loading, error } = useQuery(async (client) => {
    const [events, attached, requests] = await Promise.all([
      client.from('application_events').select('*')
        .eq('application_id', application.id).order('created_at', { ascending: true }),
      client.from('application_documents').select('*')
        .eq('application_id', application.id),
      client.from('application_document_requests').select('*')
        .eq('application_id', application.id).order('created_at', { ascending: true }),
    ]);
    const failed = events.error || attached.error || requests.error;
    if (failed) return { data: null, error: failed };

    const docIds = (attached.data ?? []).map((a) => a.document_id);
    const docs = docIds.length
      ? await client.from('passport_documents').select('*').in('id', docIds)
      : { data: [] };
    const actors = await lookupPeople([
      ...(events.data ?? []).map((e) => e.actor_id),
      ...(requests.data ?? []).map((r) => r.requested_by),
    ]);
    return {
      data: { events: events.data ?? [], docs: docs.data ?? [], requests: requests.data ?? [], actors },
      error: null,
    };
  }, [application.id]);

  async function open(doc) {
    setActionError(null);
    const err = await openPrivateFile('passport-docs', doc.storage_path);
    if (err) setActionError(describeError(err));
  }

  if (loading && !data) return <div className="text-[13px] text-subtle">Loading…</div>;
  if (error) return <Alert tone="error">{error}</Alert>;

  return (
    <div className="grid gap-6 lg:grid-cols-3">
      <div>
        <h4 className="mb-2 text-[12px] font-bold uppercase tracking-[1px] text-subtle">Student’s note</h4>
        <Prose>{application.student_note}</Prose>
        {application.assigned_to && (
          <div className="mt-3 text-[12.5px] text-muted">
            Assigned to <PersonChip id={application.assigned_to} person={people[application.assigned_to]} size={20} sub={null} />
          </div>
        )}
      </div>
      <div>
        <h4 className="mb-2 text-[12px] font-bold uppercase tracking-[1px] text-subtle">History</h4>
        {data.events.length === 0 ? (
          <span className="text-[13px] text-subtle">No stage changes yet.</span>
        ) : (
          <ol className="flex flex-col gap-2">
            {data.events.map((e) => (
              <li key={e.id} className="text-[12.5px]">
                <span className="font-semibold">
                  {APPLICATION_STAGES[e.from_stage] ?? 'Created'} → {APPLICATION_STAGES[e.to_stage] ?? e.to_stage}
                </span>
                <span className="text-subtle">
                  {' '}· {formatDateTime(e.created_at)}
                  {e.actor_id && ` · ${data.actors[e.actor_id]?.full_name ?? 'someone'}`}
                </span>
                {e.note && <div className="text-muted">{e.note}</div>}
              </li>
            ))}
          </ol>
        )}
      </div>
      <div>
        <h4 className="mb-2 text-[12px] font-bold uppercase tracking-[1px] text-subtle">Documents</h4>
        {actionError && <Alert tone="error">{actionError}</Alert>}
        {data.docs.length === 0 && data.requests.length === 0 && (
          <span className="text-[13px] text-subtle">None attached or requested.</span>
        )}
        <div className="flex flex-col gap-1.5">
          {data.docs.map((d) => (
            <button
              key={d.id}
              type="button"
              onClick={() => open(d)}
              className="flex items-center gap-2 text-left text-[12.5px] hover:text-accent cursor-pointer"
            >
              <Paperclip size={13} /> {DOCUMENT_KINDS[d.kind] ?? d.kind}
              <span className="text-subtle truncate">· {d.file_name}</span>
            </button>
          ))}
          {data.requests.map((r) => (
            <div key={r.id} className="text-[12.5px] text-muted">
              Requested: {DOCUMENT_KINDS[r.kind] ?? r.kind}
              {r.fulfilled_at ? ' · provided' : ' · outstanding'}
              {r.note && <span className="text-subtle"> — {r.note}</span>}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────── conversations

export function ConversationsPanel({ scope = all, scopeKey = 'all', initialId = null }) {
  const [selected, setSelected] = useState(initialId);
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      scope(client.from('conversations').select('*'))
        .order('last_message_at', { ascending: false, nullsFirst: false })
        .limit(500),
      { people: ['student_id'], institutions: ['institution_id'] },
    ),
    [scopeKey],
  );

  const rows = data?.rows ?? [];
  const current = rows.find((c) => c.id === selected) ?? rows[0];

  return (
    <DataState
      loading={loading && !data}
      error={error}
      empty={rows.length === 0}
      emptyIcon={MessageSquare}
      emptyTitle="No conversations"
    >
      <div className="grid gap-4 lg:grid-cols-[320px_1fr]">
        <SurfaceCard className="max-h-[70vh] overflow-y-auto scrollbar-thin p-2">
          {rows.map((c) => {
            const active = current?.id === c.id;
            return (
              <button
                key={c.id}
                type="button"
                onClick={() => setSelected(c.id)}
                className={`w-full rounded-tile px-3 py-2.5 text-left transition-colors cursor-pointer ${
                  active ? 'bg-accent/12' : 'hover:bg-white/5'
                }`}
              >
                <div className="truncate text-[13px] font-semibold">
                  {data.people[c.student_id]?.full_name ?? 'Student'}
                  <span className="font-normal text-subtle"> ↔ </span>
                  {data.institutions[c.institution_id]?.name ?? 'Institution'}
                </div>
                <div className="truncate text-[11.5px] text-subtle">
                  {c.subject || 'No subject'} · {relativeTime(c.last_message_at ?? c.created_at)}
                </div>
              </button>
            );
          })}
        </SurfaceCard>
        {current && (
          <Thread
            key={current.id}
            conversation={current}
            student={data.people[current.student_id]}
            institution={data.institutions[current.institution_id]}
          />
        )}
      </div>
    </DataState>
  );
}

/** One conversation, every message — including the ones its sender deleted. */
function Thread({ conversation, student, institution }) {
  const [actionError, setActionError] = useState(null);
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      client.from('messages').select('*')
        .eq('conversation_id', conversation.id)
        .order('created_at', { ascending: true })
        .limit(2000),
      { people: ['sender_id', 'deleted_by'] },
    ),
    [conversation.id],
  );

  async function openAttachment(message) {
    setActionError(null);
    const err = await openPrivateFile('message-attachments', message.attachment_path);
    if (err) setActionError(describeError(err));
  }

  const rows = data?.rows ?? [];
  const byId = Object.fromEntries(rows.map((m) => [m.id, m]));

  return (
    <SurfaceCard className="flex max-h-[70vh] flex-col">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-line px-5 py-3.5">
        <PersonChip id={conversation.student_id} person={student} />
        <span className="text-subtle">↔</span>
        <InstitutionChip id={conversation.institution_id} institution={institution} />
        <span className="ml-auto text-[12px] text-subtle">
          {conversation.subject || 'No subject'} · started {formatDate(conversation.created_at)}
        </span>
      </div>
      <div className="flex-1 overflow-y-auto scrollbar-thin px-5 py-4">
        {actionError && <Alert tone="error">{actionError}</Alert>}
        {loading && !data && <div className="text-[13px] text-subtle">Loading messages…</div>}
        {error && <Alert tone="error">{error}</Alert>}
        {data && rows.length === 0 && <div className="text-[13px] text-subtle">No messages yet.</div>}
        <div className="flex flex-col gap-3">
          {rows.map((m) => {
            const fromStudent = m.sender_id === conversation.student_id;
            const sender = data.people[m.sender_id];
            const quoted = m.reply_to_id ? byId[m.reply_to_id] : null;
            return (
              <div key={m.id} className={`flex ${fromStudent ? 'justify-start' : 'justify-end'}`}>
                <div className={`max-w-[75%] rounded-[16px] px-3.5 py-2.5 ${
                  fromStudent ? 'bg-surface-variant' : 'bg-accent/15'
                } ${m.deleted_at ? 'opacity-60' : ''}`}
                >
                  <div className="mb-1 flex items-center gap-2 text-[11px] text-subtle">
                    <span className="font-semibold text-white/75">{sender?.full_name ?? 'Unknown'}</span>
                    <span>{formatDateTime(m.created_at)}</span>
                    {m.is_forwarded && <span className="inline-flex items-center gap-0.5"><Forward size={11} /> forwarded</span>}
                  </div>
                  {quoted && (
                    <div className="mb-1.5 flex gap-1 border-l-2 border-white/20 pl-2 text-[12px] text-subtle">
                      <CornerDownRight size={12} className="mt-0.5 shrink-0" />
                      <span className="line-clamp-2">{quoted.body || 'Attachment'}</span>
                    </div>
                  )}
                  {m.body && <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed">{m.body}</p>}
                  {m.attachment_path && (
                    <button
                      type="button"
                      onClick={() => openAttachment(m)}
                      className="mt-1.5 inline-flex items-center gap-1.5 text-[12.5px] font-semibold text-accent hover:underline cursor-pointer"
                    >
                      {m.kind === 'voice' ? <Mic size={13} /> : <Paperclip size={13} />}
                      {m.kind === 'voice'
                        ? `Voice note${m.duration_ms ? ` · ${Math.round(m.duration_ms / 1000)}s` : ''}`
                        : m.attachment_name || (m.kind === 'image' ? 'Image' : 'File')}
                    </button>
                  )}
                  {m.deleted_at && (
                    <div className="mt-1 text-[11px] text-error">
                      Deleted {formatDateTime(m.deleted_at)}
                      {m.deleted_by && ` by ${data.people[m.deleted_by]?.full_name ?? 'someone'}`}
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </SurfaceCard>
  );
}

// ────────────────────────────────────────────────────────────── posts

export function PostsList({ scope = all, scopeKey = 'all' }) {
  const [removing, setRemoving] = useState(null);
  const [openComments, setOpenComments] = useState(null);

  const { data, loading, error, reload } = useQuery(async (client) => {
    const result = await withLookups(
      scope(client.from('posts').select('*'))
        .order('created_at', { ascending: false })
        .limit(300),
      { people: ['author_id'], institutions: ['institution_id'] },
    );
    if (result.error) return result;
    const ids = result.data.rows.map((p) => p.id);
    if (ids.length) {
      const { data: media, error: mediaError } = await client
        .from('post_media').select('*').in('post_id', ids).order('ord');
      if (mediaError) return { data: null, error: mediaError };
      result.data.media = media ?? [];
    } else {
      result.data.media = [];
    }
    return result;
  }, [scopeKey]);

  const rows = data?.rows ?? [];
  return (
    <DataState
      loading={loading && !data}
      error={error}
      empty={rows.length === 0}
      emptyIcon={Newspaper}
      emptyTitle="No posts"
    >
      <div className="flex flex-col gap-3">
        {rows.map((post) => {
          const media = data.media.filter((m) => m.post_id === post.id);
          return (
            <SurfaceCard key={post.id} className={`p-4 ${post.deleted_at ? 'opacity-70' : ''}`}>
              <div className="flex flex-wrap items-start gap-3">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    {post.institution_id ? (
                      <InstitutionChip id={post.institution_id} institution={data.institutions[post.institution_id]} />
                    ) : (
                      <PersonChip id={post.author_id} person={data.people[post.author_id]} sub="role" />
                    )}
                    {post.institution_id && (
                      <span className="text-[11.5px] text-subtle">
                        posted by {data.people[post.author_id]?.full_name ?? 'staff'}
                      </span>
                    )}
                    <Badge compact>{POST_KINDS[post.kind] ?? post.kind}</Badge>
                    {post.deleted_at && <Badge tone="error" compact>Removed</Badge>}
                    {post.pinned_at && <Badge tone="info" compact>Pinned</Badge>}
                    <span className="text-[11.5px] text-subtle">{formatDateTime(post.created_at)}</span>
                  </div>
                  <div className="mt-2.5"><Prose>{post.body}</Prose></div>
                  {post.link_url && (
                    <a href={post.link_url} target="_blank" rel="noreferrer" className="mt-1 block truncate text-[12.5px] text-accent hover:underline">
                      {post.link_url}
                    </a>
                  )}
                  {media.length > 0 && (
                    <div className="mt-3 flex flex-wrap gap-2">
                      {media.map((m) => {
                        const url = publicFileUrl('post-media', m.storage_path);
                        return (
                          <a key={m.id} href={url} target="_blank" rel="noreferrer">
                            <img src={url} alt={m.alt_text ?? ''} className="h-28 w-28 rounded-tile object-cover bg-surface-variant" />
                          </a>
                        );
                      })}
                    </div>
                  )}
                  <div className="mt-2.5 flex items-center gap-4 text-[12px] text-subtle">
                    <span>{post.like_count} likes</span>
                    <button
                      type="button"
                      onClick={() => setOpenComments(openComments === post.id ? null : post.id)}
                      className="hover:text-white cursor-pointer"
                    >
                      {post.comment_count} comments {openComments === post.id ? '▴' : '▾'}
                    </button>
                    <span>{post.repost_count} reshares</span>
                    <span>Replies: {post.reply_policy}</span>
                  </div>
                </div>
                {!post.deleted_at && (
                  <Button size="sm" variant="dangerGhost" icon={Trash2} onClick={() => setRemoving(post)}>
                    Remove
                  </Button>
                )}
              </div>
              {openComments === post.id && (
                <div className="mt-4 border-t border-line pt-4">
                  <CommentsList scope={(q) => q.eq('post_id', post.id)} scopeKey={`post:${post.id}`} compact />
                </div>
              )}
            </SurfaceCard>
          );
        })}
      </div>
      {removing && (
        <RemoveDialog
          title="Remove this post"
          onClose={() => setRemoving(null)}
          onConfirm={async (reason) => {
            const { error: rpcError } = await supabase.rpc('remove_post', {
              p_post_id: removing.id, p_reason: reason || null,
            });
            if (rpcError) return describeError(rpcError);
            setRemoving(null);
            await reload();
            return null;
          }}
        />
      )}
    </DataState>
  );
}

// ─────────────────────────────────────────────────────────── comments

export function CommentsList({ scope = all, scopeKey = 'all', compact = false }) {
  const [actionError, setActionError] = useState(null);
  const { data, loading, error, reload } = useQuery(async (client) => {
    const result = await withLookups(
      scope(client.from('comments').select('*'))
        .order('created_at', { ascending: !compact })
        .limit(500),
      { people: ['author_id'] },
    );
    if (result.error || compact) return result;
    const postIds = [...new Set(result.data.rows.map((c) => c.post_id))];
    const { data: posts } = postIds.length
      ? await client.from('posts').select('id, body').in('id', postIds)
      : { data: [] };
    result.data.posts = Object.fromEntries((posts ?? []).map((p) => [p.id, p]));
    return result;
  }, [scopeKey]);

  async function remove(comment) {
    setActionError(null);
    const { error: rpcError } = await supabase.rpc('remove_comment', { p_comment_id: comment.id });
    if (rpcError) setActionError(describeError(rpcError));
    await reload();
  }

  const rows = data?.rows ?? [];
  return (
    <div className="flex flex-col gap-2">
      {actionError && <Alert tone="error">{actionError}</Alert>}
      <DataState
        loading={loading && !data}
        error={error}
        empty={rows.length === 0}
        emptyIcon={MessageSquare}
        emptyTitle="No comments"
      >
        {rows.map((c) => (
          <div
            key={c.id}
            className={`flex items-start gap-3 rounded-tile px-3 py-2.5 ${compact ? 'bg-white/[0.03]' : 'bg-surface border border-line'} ${
              c.parent_id ? 'ml-8' : ''
            } ${c.deleted_at ? 'opacity-60' : ''}`}
          >
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <PersonChip id={c.author_id} person={data.people[c.author_id]} size={22} sub={null} />
                <span className="text-[11.5px] text-subtle">{formatDateTime(c.created_at)}</span>
                {c.deleted_at && <Badge tone="error" compact>Removed</Badge>}
              </div>
              <p className="mt-1 whitespace-pre-wrap text-[13px]">{c.body}</p>
              {!compact && data.posts?.[c.post_id] && (
                <p className="mt-1 truncate text-[11.5px] text-subtle">
                  On: “{data.posts[c.post_id].body}”
                </p>
              )}
            </div>
            {!c.deleted_at && (
              <button
                type="button"
                title="Remove comment"
                onClick={() => remove(c)}
                className="text-muted hover:text-error cursor-pointer"
              >
                <Trash2 size={15} />
              </button>
            )}
          </div>
        ))}
      </DataState>
    </div>
  );
}

// ─────────────────────────────────────────────────────────── meetings

export function MeetingsList({ scope = all, scopeKey = 'all', hide = [] }) {
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      scope(client.from('appointments').select('*'))
        .order('scheduled_for', { ascending: false, nullsFirst: false })
        .limit(500),
      { people: ['student_id', 'host_profile_id'], institutions: ['institution_id'], programs: ['program_id'] },
    ),
    [scopeKey],
  );
  const rows = data?.rows ?? [];
  return (
    <DataState
      loading={loading && !data}
      error={error}
      empty={rows.length === 0}
      emptyIcon={CalendarClock}
      emptyTitle="No meetings"
    >
      <TableCard minWidth={900}>
        <thead>
          <tr>
            <Th>When</Th>
            {!hide.includes('student') && <Th>Student</Th>}
            {!hide.includes('institution') && <Th>Institution</Th>}
            <Th>Host</Th>
            <Th>How</Th>
            <Th>Status</Th>
          </tr>
        </thead>
        <tbody>
          {rows.map((a) => (
            <Tr key={a.id}>
              <Td className="whitespace-nowrap">
                <div className="font-medium">{a.scheduled_for ? formatDateTime(a.scheduled_for) : 'Not scheduled'}</div>
                <div className="text-[11.5px] text-subtle">{a.duration_min ? `${a.duration_min} min` : ''}</div>
              </Td>
              {!hide.includes('student') && (
                <Td><PersonChip id={a.student_id} person={data.people[a.student_id]} /></Td>
              )}
              {!hide.includes('institution') && (
                <Td><InstitutionChip id={a.institution_id} institution={data.institutions[a.institution_id]} /></Td>
              )}
              <Td>
                {a.host_profile_id
                  ? <PersonChip id={a.host_profile_id} person={data.people[a.host_profile_id]} sub={null} />
                  : <span className="text-subtle">Unassigned</span>}
              </Td>
              <Td className="text-muted">
                {a.channel?.replace('_', ' ')}
                {data.programs[a.program_id] && (
                  <div className="text-[11.5px] text-subtle">{data.programs[a.program_id].name}</div>
                )}
                {a.student_message && (
                  <div className="mt-1 max-w-[260px] text-[11.5px] text-subtle line-clamp-2">“{a.student_message}”</div>
                )}
              </Td>
              <Td>
                <StatusBadge status={a.status} compact />
              </Td>
            </Tr>
          ))}
        </tbody>
      </TableCard>
    </DataState>
  );
}

// ──────────────────────────────────────────────────────────── reports

export function ReportsList({ scope = all, scopeKey = 'all' }) {
  const { data, loading, error } = useQuery(
    (client) => withLookups(
      scope(client.from('reports').select('*'))
        .order('created_at', { ascending: false })
        .limit(300),
      { people: ['reporter_id', 'reviewer_id'] },
    ),
    [scopeKey],
  );
  const rows = data?.rows ?? [];
  return (
    <DataState loading={loading && !data} error={error} empty={rows.length === 0} emptyIcon={Flag} emptyTitle="No reports">
      <TableCard minWidth={760}>
        <thead>
          <tr>
            <Th>Reason</Th>
            <Th>About</Th>
            <Th>Reported by</Th>
            <Th>When</Th>
            <Th>Status</Th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <Tr key={r.id}>
              <Td>
                <Badge tone={r.reason === 'child_safety' ? 'error' : 'neutral'} compact>
                  {REPORT_REASONS[r.reason] ?? r.reason}
                </Badge>
                {r.note && <div className="mt-1 max-w-[260px] text-[11.5px] text-subtle">{r.note}</div>}
              </Td>
              <Td className="text-muted capitalize">{r.subject_type}</Td>
              <Td><PersonChip id={r.reporter_id} person={data.people[r.reporter_id]} sub={null} /></Td>
              <Td className="text-muted whitespace-nowrap">{formatDateTime(r.created_at)}</Td>
              <Td><StatusBadge status={r.status} compact /></Td>
            </Tr>
          ))}
        </tbody>
      </TableCard>
    </DataState>
  );
}

// ──────────────────────────────────────────────────────────── dialogs

/** Asks for a reason, then runs `onConfirm(reason)`, which returns an error or null. */
export function RemoveDialog({ title, onClose, onConfirm }) {
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const err = await onConfirm(reason.trim());
    setBusy(false);
    if (err) setError(err);
  }

  return (
    <Dialog
      as="form"
      title={title}
      onClose={onClose}
      onSubmit={submit}
      width="max-w-[480px]"
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button variant="danger" type="submit" loading={busy}>Remove</Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <Field label="Reason" hint="Recorded with the removal.">
          <Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        </Field>
        {error && <Alert tone="error">{error}</Alert>}
      </div>
    </Dialog>
  );
}

