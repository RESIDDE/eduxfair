import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Check, Flag, Trash2, X } from 'lucide-react';
import {
  Alert, Badge, Button, Dialog, EmptyState, Field, Loading,
  SegmentedControl, SurfaceCard, Textarea,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDateTime } from '../../lib/format';

/** Mirrors `report_reason`. */
const REASONS = {
  spam: 'Spam',
  harassment: 'Harassment',
  misinformation: 'Misinformation',
  impersonation: 'Impersonation',
  inappropriate: 'Inappropriate',
  child_safety: 'Child safety',
  other: 'Other',
};

/** Mirrors `report_subject`. */
const SUBJECTS = {
  post: 'Post',
  comment: 'Comment',
  profile: 'Profile',
  space: 'Live Space',
  message: 'Message',
  conversation: 'Conversation',
};

/**
 * The reports queue.
 *
 * `reports` reuses `verification_status` rather than inventing its own, so this
 * reads the same way the verification queue does — deliberately, per that
 * table's own comment: one set of habits, not two.
 *
 * `child_safety` is pulled to the top regardless of age. The enum's own comment
 * says it is "routed ahead of everything else", and a queue sorted purely by
 * arrival does not do that.
 */
export default function AdminModerationPage() {
  const { profile } = useAuth();
  const [filter, setFilter] = useState('pending');
  const [resolving, setResolving] = useState(null);
  const [actionError, setActionError] = useState(null);

  const { data: rows, loading, error, reload } = useQuery(
    (client) => {
      let query = client
        .from('reports')
        .select('*')
        .order('created_at', { ascending: filter === 'pending' });
      if (filter !== 'all') query = query.eq('status', filter);
      return query.limit(200);
    },
    [filter],
  );

  async function removeContent(report) {
    setActionError(null);
    if (report.subject_type !== 'post' && report.subject_type !== 'comment') {
      setActionError('Only posts and comments can be removed from here.');
      return;
    }
    // A comment has its own remover. Sending a comment id to remove_post
    // found no post and failed, so a reported comment could not be taken down.
    const { error: rpcError } = report.subject_type === 'comment'
      ? await supabase.rpc('remove_comment', { p_comment_id: report.subject_id })
      : await supabase.rpc('remove_post', {
        p_post_id: report.subject_id,
        p_reason: `Reported: ${REASONS[report.reason] ?? report.reason}`,
      });
    if (rpcError) setActionError(describeError(rpcError));
    else await reload();
  }

  if (loading) return <Loading label="Loading reports" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  // Child safety first, then oldest first — a queue that buries the urgent
  // thing under the recent thing is not a queue.
  const queue = [...(rows ?? [])].sort((a, b) => {
    const urgent = (r) => (r.reason === 'child_safety' ? 0 : 1);
    if (urgent(a) !== urgent(b)) return urgent(a) - urgent(b);
    return new Date(a.created_at) - new Date(b.created_at);
  });

  return (
    <div className="flex flex-col gap-5 pb-4">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <SegmentedControl
          value={filter}
          onChange={setFilter}
          options={[
            { value: 'pending', label: 'Open' },
            { value: 'verified', label: 'Actioned' },
            { value: 'rejected', label: 'Dismissed' },
            { value: 'all', label: 'All' },
          ]}
        />
        <span className="text-[13px] text-subtle">
          {queue.length} report{queue.length === 1 ? '' : 's'}
        </span>
      </div>

      {queue.length === 0 ? (
        <EmptyState
          icon={Flag}
          title={filter === 'pending' ? 'Nothing reported' : 'Nothing here'}
          subtitle={
            filter === 'pending'
              ? 'No open reports. Students and institutions can report a post, a comment, a profile or a Space.'
              : 'Try a different filter.'
          }
        />
      ) : (
        <div className="flex flex-col gap-3">
          {queue.map((report) => (
            <SurfaceCard key={report.id} className="p-4">
              <div className="flex flex-wrap items-start gap-3.5">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge
                      tone={report.reason === 'child_safety' ? 'error' : 'warning'}
                      compact
                      pulse={report.reason === 'child_safety'}
                    >
                      {REASONS[report.reason] ?? report.reason}
                    </Badge>
                    <span className="text-[13px] font-semibold">
                      {SUBJECTS[report.subject_type] ?? report.subject_type}
                    </span>
                    {report.status !== 'pending' && (
                      <Badge
                        tone={report.status === 'verified' ? 'success' : 'neutral'}
                        compact
                      >
                        {report.status === 'verified' ? 'Actioned' : 'Dismissed'}
                      </Badge>
                    )}
                  </div>

                  {report.note && (
                    <p className="mt-2 text-[13px] leading-relaxed text-muted">
                      “{report.note}”
                    </p>
                  )}

                  {(report.subject_type === 'message'
                    || report.subject_type === 'conversation') && (
                    <ReportedConversation report={report} />
                  )}

                  <div className="mt-1.5 font-mono text-[11px] text-subtle">
                    {report.subject_type}:{report.subject_id}
                  </div>
                  <div className="mt-0.5 text-[11.5px] text-subtle">
                    Reported {formatDateTime(report.created_at)}
                    {report.decided_at && ` · decided ${formatDateTime(report.decided_at)}`}
                  </div>
                  {report.review_note && (
                    <div className="mt-1 text-[12px] text-muted">
                      Note: {report.review_note}
                    </div>
                  )}
                </div>

                {report.status === 'pending' && (
                  <div className="flex shrink-0 flex-wrap items-center gap-2">
                    {(report.subject_type === 'post'
                      || report.subject_type === 'comment') && (
                      <Button
                        size="sm"
                        variant="dangerGhost"
                        icon={Trash2}
                        onClick={() => removeContent(report)}
                      >
                        Remove
                      </Button>
                    )}
                    <Button
                      size="sm"
                      icon={Check}
                      onClick={() => setResolving({ report, outcome: 'verified' })}
                    >
                      Action
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      icon={X}
                      onClick={() => setResolving({ report, outcome: 'rejected' })}
                    >
                      Dismiss
                    </Button>
                  </div>
                )}
              </div>
            </SurfaceCard>
          ))}
        </div>
      )}

      {resolving && (
        <ResolveDialog
          report={resolving.report}
          outcome={resolving.outcome}
          reviewerId={profile?.id}
          onClose={() => setResolving(null)}
          onSaved={async () => { setResolving(null); await reload(); }}
        />
      )}
    </div>
  );
}

function ResolveDialog({ report, outcome, reviewerId, onClose, onSaved }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const actioned = outcome === 'verified';

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const { error: writeError } = await supabase
      .from('reports')
      .update({
        status: outcome,
        reviewer_id: reviewerId,
        review_note: note.trim() || null,
        decided_at: new Date().toISOString(),
      })
      .eq('id', report.id);
    setBusy(false);
    if (writeError) setError(describeError(writeError));
    else await onSaved();
  }

  return (
    <Dialog
      as="form"
      title={actioned ? 'Mark this actioned' : 'Dismiss this report'}
      eyebrow={REASONS[report.reason] ?? report.reason}
      onClose={onClose}
      onSubmit={submit}
      width="max-w-[480px]"
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button variant={actioned ? 'primary' : 'outline'} type="submit" loading={busy}>
            {actioned ? 'Action' : 'Dismiss'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p className="text-[13px] leading-relaxed text-muted">
          {actioned
            ? 'Say what was done. Removing the content is a separate button — this records the decision.'
            : 'Say why this needed nothing. The reporter does not see this note; the next admin does.'}
        </p>
        <Field label="Note">
          <Textarea
            rows={3}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            maxLength={500}
          />
        </Field>
        {error && <Alert tone="error">{error}</Alert>}
      </div>
    </Dialog>
  );
}

/**
 * What a reported message actually said, who sent it, and a way into the
 * whole thread — a report about a conversation cannot be judged from an id.
 */
function ReportedConversation({ report }) {
  const isMessage = report.subject_type === 'message';
  const { data, loading } = useQuery(async (client) => {
    if (!isMessage) {
      return { data: { conversationId: report.subject_id }, error: null };
    }
    const { data: message, error } = await client
      .from('messages')
      .select('id, conversation_id, sender_id, body, kind, attachment_name, created_at, deleted_at')
      .eq('id', report.subject_id)
      .maybeSingle();
    if (error || !message) return { data: { conversationId: null }, error };
    const { data: sender } = await client
      .from('admin_people')
      .select('id, full_name, email')
      .eq('id', message.sender_id)
      .maybeSingle();
    return { data: { conversationId: message.conversation_id, message, sender }, error: null };
  }, [report.id]);

  if (loading) return <div className="mt-2 text-[12px] text-subtle">Loading the message…</div>;
  if (!data?.conversationId) {
    return <div className="mt-2 text-[12px] text-subtle">The message no longer exists.</div>;
  }
  return (
    <div className="mt-2 flex flex-col gap-1.5">
      {data.message && (
        <div className="rounded-tile bg-white/[0.04] px-3 py-2 text-[13px]">
          <div className="mb-0.5 text-[11.5px] text-subtle">
            {data.sender ? (
              <Link to={`/admin/people/${data.sender.id}`} className="hover:text-accent">
                {data.sender.full_name || data.sender.email}
              </Link>
            ) : 'Unknown sender'}
            {' '}· {formatDateTime(data.message.created_at)}
            {data.message.deleted_at && ' · deleted by sender'}
          </div>
          <p className="whitespace-pre-wrap">
            {data.message.body || data.message.attachment_name || `(${data.message.kind})`}
          </p>
        </div>
      )}
      <Link
        to={`/admin/messages?conversation=${data.conversationId}`}
        className="w-fit text-[12.5px] font-semibold text-accent hover:underline"
      >
        Open the whole conversation →
      </Link>
    </div>
  );
}
