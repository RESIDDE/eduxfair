import { useState } from 'react';
import { FileText, Upload, Workflow } from 'lucide-react';
import {
  Alert,
  Badge,
  Button,
  Dialog,
  EmptyState,
  Field,
  Loading,
  Select,
  SurfaceCard,
  Textarea,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDate, initials } from '../../lib/format';
import {
  APPLICATION_STAGES,
  DOCUMENT_KINDS,
  INSTITUTION_SETTABLE_STAGES,
  PIPELINE_COLUMNS,
} from '../../lib/vocab';

/**
 * The admission pipeline as a board.
 *
 * Which stages this console may set is enforced by `guard_application_stage()`
 * in the database — notably 'accepted' is the student's decision alone and the
 * trigger refuses it from an institution, so that column is read-only here.
 * Every move writes an `application_events` row that nobody, admin included,
 * can edit or delete.
 */
export default function PipelinePage() {
  const { institutionId } = useAuth();
  const [detail, setDetail] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [dragging, setDragging] = useState(null);

  const { data: applications, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('applications')
        .select(
          'id, stage, intake, submitted_at, updated_at, student_note, profile_id, ' +
            'programs!inner(id, name, level), ' +
            'student:profiles!profile_id(id, full_name, country), ' +
            'application_document_requests(id, kind, fulfilled_at)',
        )
        .eq('institution_id', institutionId)
        .order('updated_at', { ascending: false }),
    [institutionId],
  );

  async function move(application, stage) {
    if (!INSTITUTION_SETTABLE_STAGES.includes(stage)) return;
    setActionError(null);

    const { error: writeError } = await supabase
      .from('applications')
      .update({ stage })
      .eq('id', application.id);

    if (writeError) {
      // The guard trigger raises a readable message, so it is shown as-is.
      setActionError(describeError(writeError));
      return;
    }
    reload();
  }

  if (loading) return <Loading label="Loading your pipeline" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = applications ?? [];

  if (rows.length === 0) {
    return (
      <EmptyState
        icon={Workflow}
        title="No applications yet"
        subtitle="When a student submits an application to one of your programs, it appears here and you can move it through the pipeline."
      />
    );
  }

  return (
    <div className="flex flex-col gap-4 h-full">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <div className="flex-1 min-h-0 flex gap-4 overflow-x-auto scrollbar-thin pb-2">
        {PIPELINE_COLUMNS.map((stage) => {
          const columnRows = rows.filter((row) => row.stage === stage);
          const canDrop = INSTITUTION_SETTABLE_STAGES.includes(stage);

          return (
            <div
              key={stage}
              onDragOver={(e) => {
                if (canDrop) e.preventDefault();
              }}
              onDrop={() => {
                if (canDrop && dragging) move(dragging, stage);
                setDragging(null);
              }}
              className={`w-[300px] shrink-0 flex flex-col rounded-card border p-3 transition-colors ${
                canDrop && dragging
                  ? 'border-accent/40 bg-accent/5'
                  : 'border-line/60'
              }`}
            >
              <div className="px-1 pb-3 flex items-center justify-between">
                <span className="text-[12px] font-bold uppercase tracking-[1px] text-white/50">
                  {APPLICATION_STAGES[stage]}
                </span>
                <span className="text-[12px] text-subtle tabular-nums">
                  {columnRows.length}
                </span>
              </div>

              {!canDrop && (
                <p className="px-1 pb-2 text-[11.5px] text-subtle leading-relaxed">
                  {stage === 'accepted'
                    ? 'The student accepts their own offer — you cannot move a card here.'
                    : 'Read-only.'}
                </p>
              )}

              <div className="flex-1 min-h-0 overflow-y-auto scrollbar-thin flex flex-col gap-2.5">
                {columnRows.map((application) => (
                  <ApplicationCard
                    key={application.id}
                    application={application}
                    onOpen={() => setDetail(application)}
                    onDragStart={() => setDragging(application)}
                    onDragEnd={() => setDragging(null)}
                  />
                ))}
                {columnRows.length === 0 && (
                  <div className="px-1 py-6 text-center text-[12.5px] text-subtle">
                    Nothing here
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {detail && (
        <ApplicationDialog
          application={detail}
          onClose={() => setDetail(null)}
          onChanged={() => {
            setDetail(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

function ApplicationCard({ application, onOpen, onDragStart, onDragEnd }) {
  const outstanding = (application.application_document_requests ?? []).filter(
    (r) => !r.fulfilled_at,
  );

  // The student's name is present only because they shared their passport,
  // which submitting an application does. RLS returns no profiles row otherwise.
  const name = application.student?.full_name;

  return (
    <SurfaceCard
      draggable
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      onClick={onOpen}
      radius="rounded-tile"
      className="p-3.5 cursor-grab active:cursor-grabbing hover:bg-white/[0.03] transition-colors"
    >
      <div className="flex items-start gap-2.5">
        <div className="size-8 rounded-full bg-surface-variant grid place-items-center text-[11px] font-bold shrink-0">
          {initials(name) || '?'}
        </div>
        <div className="min-w-0 flex-1">
          <div className="font-semibold text-[13.5px] truncate">
            {name || 'Student'}
          </div>
          <div className="text-[12px] text-muted truncate">
            {application.programs?.name}
          </div>
        </div>
      </div>

      <div className="mt-3 flex items-center gap-2 flex-wrap">
        {application.intake && (
          <span className="text-[11.5px] text-subtle">{application.intake}</span>
        )}
        {outstanding.length > 0 && (
          <Badge tone="warning" compact>
            <Upload size={10} strokeWidth={2.6} /> {outstanding.length} needed
          </Badge>
        )}
      </div>

      <div className="mt-2 text-[11px] text-subtle">
        Updated {formatDate(application.updated_at)}
      </div>
    </SurfaceCard>
  );
}

function ApplicationDialog({ application, onClose, onChanged }) {
  const [stage, setStage] = useState(application.stage);
  const [note, setNote] = useState('');
  const [requestKind, setRequestKind] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const { data: events } = useQuery(
    (client) =>
      client
        .from('application_events')
        .select('*')
        .eq('application_id', application.id)
        .order('created_at'),
    [application.id],
  );

  async function save() {
    setBusy(true);
    setError(null);

    if (stage !== application.stage) {
      const { error: stageError } = await supabase
        .from('applications')
        .update({ stage })
        .eq('id', application.id);
      if (stageError) {
        setBusy(false);
        setError(describeError(stageError));
        return;
      }
    }

    if (note.trim()) {
      // Appended to the audit trail rather than overwriting anything.
      const { error: noteError } = await supabase
        .from('application_events')
        .insert({
          application_id: application.id,
          to_stage: stage,
          from_stage: application.stage === stage ? null : application.stage,
          note: note.trim(),
        });
      if (noteError) {
        setBusy(false);
        setError(describeError(noteError));
        return;
      }
    }

    if (requestKind) {
      const { error: requestError } = await supabase
        .from('application_document_requests')
        .insert({
          application_id: application.id,
          kind: requestKind,
          note: note.trim() || null,
        });
      if (requestError) {
        setBusy(false);
        setError(describeError(requestError));
        return;
      }
    }

    setBusy(false);
    onChanged();
  }

  return (
    <Dialog
      title={application.student?.full_name || 'Application'}
      eyebrow={application.programs?.name}
      onClose={onClose}
      width="max-w-[640px]"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            Close
          </Button>
          <Button onClick={save} loading={busy}>
            Save
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      {application.student_note && (
        <div className="mb-5 p-3.5 rounded-tile bg-surface-variant">
          <div className="text-[11px] uppercase tracking-[0.8px] text-subtle">
            From the student
          </div>
          <p className="mt-1.5 text-[13px] leading-relaxed">
            {application.student_note}
          </p>
        </div>
      )}

      <div className="flex flex-col gap-4">
        <Field
          label="Stage"
          hint="Offer acceptance is the student's decision — it is not in this list."
        >
          <Select value={stage} onChange={(e) => setStage(e.target.value)}>
            {INSTITUTION_SETTABLE_STAGES.map((value) => (
              <option key={value} value={value}>
                {APPLICATION_STAGES[value]}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Request a document" hint="Optional.">
          <Select value={requestKind} onChange={(e) => setRequestKind(e.target.value)}>
            <option value="">Nothing to request</option>
            {Object.entries(DOCUMENT_KINDS).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </Select>
        </Field>

        <Field
          label="Note"
          hint="Appended to the history. It cannot be edited or removed afterwards, by anyone."
        >
          <Textarea
            rows={3}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Transcript verified; awaiting English test result."
          />
        </Field>
      </div>

      {(events ?? []).length > 0 && (
        <div className="mt-6">
          <div className="text-[11px] uppercase tracking-[0.8px] text-subtle">
            History
          </div>
          <ol className="mt-3 flex flex-col gap-2.5">
            {events.map((event) => (
              <li key={event.id} className="flex items-start gap-3">
                <FileText size={13} className="text-accent mt-1 shrink-0" strokeWidth={2.2} />
                <div className="min-w-0">
                  <div className="text-[13px] font-medium">
                    {APPLICATION_STAGES[event.to_stage] ?? event.to_stage}
                  </div>
                  <div className="text-[11.5px] text-subtle">
                    {formatDate(event.created_at)}
                  </div>
                  {event.note && (
                    <p className="mt-1 text-[12.5px] text-muted leading-relaxed">
                      {event.note}
                    </p>
                  )}
                </div>
              </li>
            ))}
          </ol>
        </div>
      )}
    </Dialog>
  );
}
