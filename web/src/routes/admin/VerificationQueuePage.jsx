import { useState } from 'react';
import { Check, ExternalLink, ShieldCheck, X } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Dialog,
  EmptyState,
  Field,
  Loading,
  SegmentedControl,
  SurfaceCard,
  Textarea,
} from '../../components/ui';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDateTime } from '../../lib/format';
import { VERIFICATION_MEANING, VERIFICATION_SUBJECTS } from '../../lib/vocab';

/**
 * One queue for every kind of verification.
 *
 * Deliberately a single inbox rather than four screens: four screens is how
 * half of them end up unreviewed. Resolving a row propagates the decision to
 * the subject via `apply_verification_decision()`, so a badge in the apps can
 * never disagree with this queue.
 */
export default function VerificationQueuePage() {
  const [filter, setFilter] = useState('pending');
  const [deciding, setDeciding] = useState(null);
  const [actionError, setActionError] = useState(null);

  const { data: rows, loading, error, reload } = useQuery(
    (client) => {
      let query = client
        .from('verifications')
        .select('*')
        .order('created_at', { ascending: filter === 'pending' });
      if (filter !== 'all') query = query.eq('status', filter);
      return query.limit(200);
    },
    [filter],
  );

  if (loading) return <Loading label="Loading the queue" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const queue = rows ?? [];

  return (
    <div className="flex flex-col gap-5 pb-4">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <div className="flex items-center justify-between gap-4 flex-wrap">
        <SegmentedControl
          value={filter}
          onChange={setFilter}
          options={[
            { value: 'pending', label: 'Pending' },
            { value: 'verified', label: 'Verified' },
            { value: 'rejected', label: 'Rejected' },
            { value: 'all', label: 'All' },
          ]}
        />
        <span className="text-[13px] text-subtle">
          {queue.length} item{queue.length === 1 ? '' : 's'}
        </span>
      </div>

      <SurfaceCard className="p-4">
        <p className="text-[12.5px] text-muted leading-relaxed">
          Each badge is a specific, narrow claim. Approving one says only what
          is written in <code className="text-accent-light">evidence</code> —
          and that wording is what students and institutions rely on, so it is
          worth reading before you approve.
        </p>
      </SurfaceCard>

      {queue.length === 0 ? (
        <EmptyState
          icon={ShieldCheck}
          title={filter === 'pending' ? 'Queue is clear' : 'Nothing here'}
          subtitle={
            filter === 'pending'
              ? 'Nothing is waiting for review.'
              : 'Try a different filter.'
          }
        />
      ) : (
        <div className="flex flex-col gap-3">
          {queue.map((row) => (
            <QueueRow
              key={row.id}
              row={row}
              onDecide={() => setDeciding(row)}
            />
          ))}
        </div>
      )}

      {deciding && (
        <DecisionDialog
          row={deciding}
          onClose={() => setDeciding(null)}
          onDecided={async (status, note) => {
            setActionError(null);
            const { error: writeError } = await supabase
              .from('verifications')
              .update({ status, review_note: note || null })
              .eq('id', deciding.id);

            if (writeError) {
              setActionError(describeError(writeError));
              return;
            }
            setDeciding(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

function QueueRow({ row, onDecide }) {
  const tone =
    row.status === 'verified'
      ? 'success'
      : row.status === 'rejected'
        ? 'error'
        : 'warning';

  return (
    <SurfaceCard className="p-5">
      <div className="flex items-start gap-4 flex-wrap">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2.5 flex-wrap">
            <Badge tone="live" compact>
              {VERIFICATION_SUBJECTS[row.subject_type] ?? row.subject_type}
            </Badge>
            <Badge tone={tone} compact>
              {row.status}
            </Badge>
            <span className="text-[12px] text-subtle">
              Requested {formatDateTime(row.created_at)}
            </span>
          </div>

          <div className="mt-2.5 font-mono text-[12px] text-muted break-all">
            {row.subject_id}
          </div>

          {Object.keys(row.evidence ?? {}).length > 0 && (
            <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-[12.5px]">
              {Object.entries(row.evidence).map(([key, value]) => (
                <div key={key} className="contents">
                  <dt className="text-subtle">{key.replace(/_/g, ' ')}</dt>
                  <dd className="text-muted break-words">{String(value)}</dd>
                </div>
              ))}
            </dl>
          )}

          {row.review_note && (
            <p className="mt-3 text-[12.5px] text-muted leading-relaxed">
              Note: {row.review_note}
            </p>
          )}
        </div>

        {row.status === 'pending' && (
          <Button size="sm" onClick={onDecide}>
            Review
          </Button>
        )}
      </div>
    </SurfaceCard>
  );
}

function DecisionDialog({ row, onClose, onDecided }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  // Documents are private, so the reviewer needs a signed URL rather than a
  // path — fetched on demand, not held in the list.
  const [documentUrl, setDocumentUrl] = useState(null);
  const [loadingDoc, setLoadingDoc] = useState(false);

  async function openDocument() {
    setLoadingDoc(true);
    const { data: doc } = await supabase
      .from('passport_documents')
      .select('storage_path, file_name')
      .eq('id', row.subject_id)
      .maybeSingle();

    if (doc) {
      const { data: signed } = await supabase.storage
        .from('passport-docs')
        .createSignedUrl(doc.storage_path, 3600);
      setDocumentUrl(signed?.signedUrl ?? null);
    }
    setLoadingDoc(false);
  }

  async function decide(status) {
    setBusy(true);
    await onDecided(status, note);
    setBusy(false);
  }

  return (
    <Dialog
      title={`Review this ${VERIFICATION_SUBJECTS[row.subject_type]?.toLowerCase() ?? 'request'}`}
      onClose={onClose}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="danger" icon={X} loading={busy} onClick={() => decide('rejected')}>
            Reject
          </Button>
          <Button icon={Check} loading={busy} onClick={() => decide('verified')}>
            Approve
          </Button>
        </>
      }
    >
      <SurfaceCard radius="rounded-tile" className="p-4">
        <div className="text-[11px] uppercase tracking-[0.8px] text-subtle">
          Approving will state
        </div>
        <p className="mt-1.5 text-[13px] leading-relaxed">
          {VERIFICATION_MEANING[row.subject_type]}
        </p>
      </SurfaceCard>

      {row.subject_type === 'document' && (
        <div className="mt-5">
          {documentUrl ? (
            <a
              href={documentUrl}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-2 text-accent font-semibold text-[13.5px] hover:brightness-110"
            >
              <ExternalLink size={15} strokeWidth={2.2} /> Open the document
            </a>
          ) : (
            <Button
              size="sm"
              variant="outline"
              loading={loadingDoc}
              onClick={openDocument}
            >
              Fetch the document
            </Button>
          )}
        </div>
      )}

      <div className="mt-5">
        <Field
          label="Reviewer note"
          hint="Shown to the subject. Required in practice for a rejection — it is how they know what to fix."
        >
          <Textarea
            rows={3}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Transcript is legible and matches the stated WASSCE results."
          />
        </Field>
      </div>
    </Dialog>
  );
}
