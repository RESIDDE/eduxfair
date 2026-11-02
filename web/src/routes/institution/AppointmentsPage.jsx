import { useState } from 'react';
import { Link } from 'react-router-dom';
import { CalendarCheck, CalendarPlus, Check, Video, X } from 'lucide-react';
import {
  Alert,
  Button,
  Dialog,
  EmptyState,
  Field,
  Input,
  Loading,
  SegmentedControl,
  StatusBadge,
  SurfaceCard,
  Toolbar,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDateTime, initials, isCallWindowOpen } from '../../lib/format';

/**
 * Meeting requests and published availability.
 *
 * Confirming a video meeting now defaults to a Lekkside room — we host the
 * call, and both sides join from here. `meeting_mode = 'external_link'` keeps
 * Meet/Zoom/Teams available for an institution whose process depends on it,
 * which is why the distinction is a column rather than inferred from whether
 * `meeting_url` happens to be null.
 */
export default function AppointmentsPage() {
  const { institutionId, user } = useAuth();
  const [confirming, setConfirming] = useState(null);
  const [publishing, setPublishing] = useState(false);
  const [actionError, setActionError] = useState(null);

  const { data: appointments, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('appointments')
        .select(
          'id, status, scheduled_for, duration_min, channel, meeting_url, ' +
            'meeting_mode, ' +
            'student_message, notes, student_id, ' +
            'student:profiles!student_id(id, full_name), programs(id, name)',
        )
        .eq('institution_id', institutionId)
        .order('scheduled_for', { ascending: true, nullsFirst: true }),
    [institutionId],
  );

  const { data: slots, reload: reloadSlots } = useQuery(
    (client) =>
      client
        .from('availability_slots')
        .select('*')
        .eq('institution_id', institutionId)
        .gte('starts_at', new Date().toISOString())
        .order('starts_at'),
    [institutionId],
  );

  async function setStatus(appointment, status, extra = {}) {
    setActionError(null);
    const { error: writeError } = await supabase
      .from('appointments')
      .update({ status, ...extra })
      .eq('id', appointment.id);

    if (writeError) {
      setActionError(describeError(writeError));
      return false;
    }
    reload();
    return true;
  }

  if (loading) return <Loading label="Loading appointments" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const rows = appointments ?? [];
  const requested = rows.filter((r) => r.status === 'requested');
  const upcoming = rows.filter(
    (r) => r.status === 'confirmed' && new Date(r.scheduled_for) > new Date(),
  );
  const rest = rows.filter((r) => !requested.includes(r) && !upcoming.includes(r));

  return (
    <div className="flex flex-col gap-5 pb-4">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <Toolbar
        summary={`${(slots ?? []).filter((s) => !s.is_booked).length} open slot${
          (slots ?? []).filter((s) => !s.is_booked).length === 1 ? '' : 's'
        } published`}
      >
        <Button icon={CalendarPlus} onClick={() => setPublishing(true)}>
          Publish availability
        </Button>
      </Toolbar>

      {rows.length === 0 ? (
        <EmptyState
          icon={CalendarCheck}
          title="No meeting requests yet"
          subtitle="Publish some availability and students can book a time directly from your institution page."
        />
      ) : (
        <>
          <Section
            title={`Waiting on you (${requested.length})`}
            rows={requested}
            onConfirm={setConfirming}
            onDecline={(a) => setStatus(a, 'declined')}
          />
          <Section title={`Upcoming (${upcoming.length})`} rows={upcoming} />
          <Section title="Past and closed" rows={rest} />
        </>
      )}

      {confirming && (
        <ConfirmDialog
          appointment={confirming}
          onClose={() => setConfirming(null)}
          onConfirm={async (payload) => {
            const ok = await setStatus(confirming, 'confirmed', payload);
            if (ok) setConfirming(null);
          }}
        />
      )}

      {publishing && (
        <PublishSlotsDialog
          institutionId={institutionId}
          hostProfileId={user?.id}
          onClose={() => setPublishing(false)}
          onSaved={() => {
            setPublishing(false);
            reloadSlots();
          }}
        />
      )}
    </div>
  );
}

function Section({ title, rows, onConfirm, onDecline }) {
  if (rows.length === 0) return null;

  return (
    <div>
      <div className="text-[11px] uppercase tracking-[1px] text-white/45 font-bold">
        {title}
      </div>
      <div className="mt-3 flex flex-col gap-2.5">
        {rows.map((appointment) => (
          <SurfaceCard key={appointment.id} className="p-4">
            <div className="flex items-start gap-3.5 flex-wrap">
              <div className="size-9 rounded-full bg-surface-variant grid place-items-center text-[12px] font-bold shrink-0">
                {initials(appointment.student?.full_name) || '?'}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2.5 flex-wrap">
                  <span className="font-semibold">
                    {appointment.student?.full_name || 'Student'}
                  </span>
                  <StatusBadge status={appointment.status} compact />
                </div>
                <div className="mt-0.5 text-[12.5px] text-muted">
                  {appointment.programs?.name ?? 'General enquiry'} ·{' '}
                  {appointment.channel.replace('_', ' ')} ·{' '}
                  {appointment.scheduled_for
                    ? `${formatDateTime(appointment.scheduled_for)} (${appointment.duration_min} min)`
                    : 'no time proposed yet'}
                </div>
                {appointment.student_message && (
                  <p className="mt-2 text-[12.5px] text-muted leading-relaxed">
                    “{appointment.student_message}”
                  </p>
                )}
              </div>

              {appointment.meeting_mode === 'lekkside_room'
                && isCallWindowOpen(appointment) && (
                <Link to={`/institution/appointments/${appointment.id}/call`}>
                  <Button size="sm" icon={Video}>Join</Button>
                </Link>
              )}

              {onConfirm && (
                <div className="flex items-center gap-2">
                  <Button size="sm" icon={Check} onClick={() => onConfirm(appointment)}>
                    Confirm
                  </Button>
                  <Button
                    size="sm"
                    variant="dangerGhost"
                    icon={X}
                    onClick={() => onDecline(appointment)}
                    title="Decline"
                  />
                </div>
              )}
            </div>
          </SurfaceCard>
        ))}
      </div>
    </div>
  );
}

function ConfirmDialog({ appointment, onClose, onConfirm }) {
  const [when, setWhen] = useState(
    appointment.scheduled_for
      ? toLocalInput(appointment.scheduled_for)
      : toLocalInput(new Date(Date.now() + 86400000).toISOString()),
  );
  const [meetingUrl, setMeetingUrl] = useState('');
  const [mode, setMode] = useState('lekkside_room');
  const [busy, setBusy] = useState(false);

  const isVideo = appointment.channel === 'video';
  const needsLink = isVideo && mode === 'external_link';

  return (
    <Dialog
      as="form"
      title="Confirm this meeting"
      eyebrow={appointment.student?.full_name}
      onClose={onClose}
      onSubmit={async (event) => {
        event.preventDefault();
        setBusy(true);
        await onConfirm({
          scheduled_for: new Date(when).toISOString(),
          meeting_mode: isVideo ? mode : 'lekkside_room',
          meeting_url: needsLink ? meetingUrl || null : null,
        });
        setBusy(false);
      }}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            Confirm
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <Field label="Date and time">
          <Input
            type="datetime-local"
            value={when}
            onChange={(e) => setWhen(e.target.value)}
            required
          />
        </Field>
        {isVideo && (
          <Field label="Where it is held">
            <SegmentedControl
              value={mode}
              onChange={setMode}
              options={[
                { value: 'lekkside_room', label: 'Eduxfair room' },
                { value: 'external_link', label: 'External link' },
              ]}
            />
          </Field>
        )}

        {isVideo && mode === 'lekkside_room' && (
          <p className="text-[12.5px] leading-relaxed text-muted">
            We host this one. You both join from Eduxfair — no link to paste and
            nothing to install. The room opens 10 minutes before the start.
          </p>
        )}

        {needsLink && (
          <Field
            label="Joining link"
            hint="Paste your Meet, Zoom or Teams link. The student sees it 10 minutes before the start."
          >
            <Input
              type="url"
              value={meetingUrl}
              onChange={(e) => setMeetingUrl(e.target.value)}
              placeholder="https://meet.google.com/…"
              required
            />
          </Field>
        )}
      </div>
    </Dialog>
  );
}

function PublishSlotsDialog({ institutionId, hostProfileId, onClose, onSaved }) {
  const [date, setDate] = useState('');
  const [startTime, setStartTime] = useState('10:00');
  const [endTime, setEndTime] = useState('16:00');
  const [minutes, setMinutes] = useState(30);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    // Split the working window into back-to-back slots. The exclusion
    // constraint on the table rejects any that overlap something already
    // published, which is why a clash surfaces as a readable error.
    const slots = [];
    let cursor = new Date(`${date}T${startTime}`);
    const end = new Date(`${date}T${endTime}`);

    while (cursor < end) {
      const slotEnd = new Date(cursor.getTime() + minutes * 60000);
      if (slotEnd > end) break;
      slots.push({
        institution_id: institutionId,
        host_profile_id: hostProfileId,
        starts_at: cursor.toISOString(),
        ends_at: slotEnd.toISOString(),
      });
      cursor = slotEnd;
    }

    if (slots.length === 0) {
      setBusy(false);
      setError('That window is shorter than one slot.');
      return;
    }

    const { error: writeError } = await supabase
      .from('availability_slots')
      .insert(slots);

    setBusy(false);

    if (writeError) {
      setError(describeError(writeError));
      return;
    }
    onSaved();
  }

  return (
    <Dialog
      as="form"
      title="Publish availability"
      onClose={onClose}
      onSubmit={handleSubmit}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={busy}>
            Publish
          </Button>
        </>
      }
    >
      {error && (
        <div className="mb-5">
          <Alert tone="error">{error}</Alert>
        </div>
      )}

      <p className="text-muted leading-relaxed">
        We will split this window into back-to-back slots students can book.
      </p>

      <div className="mt-5 flex flex-col gap-4">
        <Field label="Date">
          <Input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            required
          />
        </Field>
        <div className="grid grid-cols-3 gap-4">
          <Field label="From">
            <Input
              type="time"
              value={startTime}
              onChange={(e) => setStartTime(e.target.value)}
              required
            />
          </Field>
          <Field label="Until">
            <Input
              type="time"
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              required
            />
          </Field>
          <Field label="Each (min)">
            <Input
              type="number"
              min="10"
              step="5"
              value={minutes}
              onChange={(e) => setMinutes(Number(e.target.value))}
              required
            />
          </Field>
        </div>
      </div>
    </Dialog>
  );
}

/** `datetime-local` wants local wall time, not a UTC ISO string. */
function toLocalInput(iso) {
  const date = new Date(iso);
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(
    date.getHours(),
  )}:${pad(date.getMinutes())}`;
}
