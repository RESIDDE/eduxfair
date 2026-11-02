import { useState } from 'react';
import { Link } from 'react-router-dom';
import { CalendarPlus, Hand, MessageSquare, Radio, Users, Video } from 'lucide-react';
import {
  Alert, Badge, Button, Dialog, EmptyState, Field, Input, Loading,
  Select, SectionHeader, SurfaceCard, Textarea, Toolbar,
} from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { roomAction } from '../../lib/livekit';
import { formatDateTime } from '../../lib/format';

/** Mirrors the `space_kind` enum. */
const KINDS = {
  admissions_hour: 'Admissions hour',
  scholarship_qa: 'Scholarship Q&A',
  country_briefing: 'Country briefing',
  open_day: 'Open day',
};

/**
 * Live Spaces: schedule a session, go live, and see how the last one went.
 *
 * The attendance summary on a past Space is the point of scheduling one. A list
 * of sessions that happened tells an admissions team nothing; how many came,
 * how many asked something, and how many then shared their passport is the
 * thing worth coming back for.
 */
export default function SpacesPage() {
  const { institutionId, user, institution } = useAuth();
  const [scheduling, setScheduling] = useState(false);
  const [actionError, setActionError] = useState(null);
  const [busyId, setBusyId] = useState(null);

  const { data: spaces, loading, error, reload } = useQuery(
    (client) =>
      client
        .from('spaces')
        .select('*')
        .eq('institution_id', institutionId)
        .order('scheduled_for', { ascending: false }),
    [institutionId],
  );

  async function goLive(space) {
    setActionError(null);
    setBusyId(space.id);
    try {
      const result = await roomAction('go_live', { space_id: space.id });
      // The status moved even when LiveKit did not answer, so the host is told
      // rather than left to discover an empty room.
      if (result?.livekit === false) {
        setActionError(result.error ?? 'The session is live, but the room did not confirm it.');
      }
      await reload();
    } catch (err) {
      setActionError(err.message);
    } finally {
      setBusyId(null);
    }
  }

  async function cancel(space) {
    setActionError(null);
    const { error: rpcError } = await supabase.rpc('space_set_status', {
      p_space_id: space.id,
      p_status: 'cancelled',
    });
    if (rpcError) setActionError(describeError(rpcError));
    await reload();
  }

  if (loading) return <Loading label="Loading your sessions" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const live = (spaces ?? []).filter((s) => s.status === 'live');
  const upcoming = (spaces ?? [])
    .filter((s) => s.status === 'scheduled')
    .sort((a, b) => new Date(a.scheduled_for) - new Date(b.scheduled_for));
  const past = (spaces ?? []).filter((s) => s.status === 'ended' || s.status === 'cancelled');

  return (
    <div className="flex flex-col gap-6">
      <Toolbar summary={`${upcoming.length} scheduled · ${live.length} live now`}>
        <Button icon={CalendarPlus} onClick={() => setScheduling(true)}>
          Schedule a session
        </Button>
      </Toolbar>

      {actionError && <Alert tone="error">{actionError}</Alert>}

      {(spaces ?? []).length === 0 && (
        <EmptyState
          icon={Radio}
          title="Run your first live session"
          subtitle="An admissions hour, a scholarship Q&A or a country briefing. Students see it on their Spaces tab and drop in to listen."
          action={<Button icon={CalendarPlus} onClick={() => setScheduling(true)}>Schedule a session</Button>}
        />
      )}

      {live.length > 0 && (
        <section className="flex flex-col gap-3">
          <SectionHeader title="Live now" />
          {live.map((s) => (
            <SpaceRow key={s.id} space={s} onCancel={cancel} />
          ))}
        </section>
      )}

      {upcoming.length > 0 && (
        <section className="flex flex-col gap-3">
          <SectionHeader title="Upcoming" />
          {upcoming.map((s) => (
            <SpaceRow
              key={s.id}
              space={s}
              busy={busyId === s.id}
              onGoLive={goLive}
              onCancel={cancel}
            />
          ))}
        </section>
      )}

      {past.length > 0 && (
        <section className="flex flex-col gap-3">
          <SectionHeader title="Past sessions" />
          {past.map((s) => (
            <SpaceRow key={s.id} space={s} showAttendance />
          ))}
        </section>
      )}

      {scheduling && (
        <ScheduleDialog
          institutionId={institutionId}
          hostProfileId={user?.id}
          isVerified={institution?.verification_status === 'verified'}
          onClose={() => setScheduling(false)}
          onSaved={async () => { setScheduling(false); await reload(); }}
        />
      )}
    </div>
  );
}

function SpaceRow({ space, busy, onGoLive, onCancel, showAttendance }) {
  return (
    <SurfaceCard className="flex flex-col gap-3 p-4">
      <div className="flex flex-wrap items-start gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="truncate text-[15px] font-bold text-white">{space.title}</h3>
            {space.status === 'live' && <Badge tone="success" pulse compact>Live</Badge>}
            {space.status === 'cancelled' && <Badge tone="neutral" compact>Cancelled</Badge>}
          </div>
          <p className="mt-0.5 text-[12px] text-subtle">
            {KINDS[space.kind] ?? space.kind} · {formatDateTime(space.scheduled_for)} ·{' '}
            {space.duration_min} min
            {space.requires_admission && ' · waiting room on'}
          </p>
          {space.description && (
            <p className="mt-1.5 text-[13px] leading-relaxed text-muted">{space.description}</p>
          )}
        </div>

        <div className="flex shrink-0 flex-wrap items-center gap-2">
          {space.status === 'live' && (
            <>
              <Link to={`/institution/spaces/${space.id}`}>
                <Button size="sm" icon={Video}>Join the room</Button>
              </Link>
              <Button size="sm" variant="ghost" onClick={() => onCancel(space)}>End</Button>
            </>
          )}
          {space.status === 'scheduled' && (
            <>
              <Button size="sm" variant="glass" icon={Radio} loading={busy} onClick={() => onGoLive(space)}>
                Go live
              </Button>
              <Button size="sm" variant="ghost" onClick={() => onCancel(space)}>Cancel</Button>
            </>
          )}
        </div>
      </div>

      {showAttendance && <Attendance spaceId={space.id} />}
    </SurfaceCard>
  );
}

/**
 * How the session actually went.
 *
 * Counted from `space_roster` and `space_messages` rather than stored on the
 * row: both are already readable by this institution, and a denormalised count
 * would be one more thing that can be wrong.
 */
function Attendance({ spaceId }) {
  const { data } = useQuery(async (client) => {
    const [roster, messages] = await Promise.all([
      client.from('space_roster').select('role, is_identified, hand_raised_at, joined_at')
        .eq('space_id', spaceId),
      client.from('space_messages').select('id', { count: 'exact', head: true })
        .eq('space_id', spaceId).is('deleted_at', null),
    ]);
    if (roster.error) return { data: null, error: roster.error };
    const rows = roster.data ?? [];
    return {
      data: {
        joined: rows.filter((r) => r.joined_at && r.role === 'listener').length,
        identified: rows.filter((r) => r.is_identified && r.role !== 'host' && r.role !== 'cohost').length,
        hands: rows.filter((r) => r.hand_raised_at).length,
        messages: messages.count ?? 0,
      },
      error: null,
    };
  }, [spaceId]);

  if (!data) return null;

  return (
    <div className="flex flex-wrap gap-4 border-t border-line pt-3">
      <Stat icon={Users} label="attended" value={data.joined} />
      <Stat icon={Hand} label="asked to speak" value={data.hands} />
      <Stat icon={MessageSquare} label="messages" value={data.messages} />
      <Stat icon={Radio} label="shared their passport" value={data.identified} />
    </div>
  );
}

function Stat({ icon: Icon, label, value }) {
  return (
    <span className="flex items-center gap-1.5 text-[12px] text-muted">
      <Icon size={13} className="text-subtle" />
      <span className="font-bold text-white">{value}</span> {label}
    </span>
  );
}

/** Modelled on PublishSlotsDialog: one form, one insert, errors inline. */
function ScheduleDialog({ institutionId, hostProfileId, isVerified, onClose, onSaved }) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [kind, setKind] = useState('admissions_hour');
  const [when, setWhen] = useState('');
  const [duration, setDuration] = useState(45);
  const [capacity, setCapacity] = useState(200);
  const [waitingRoom, setWaitingRoom] = useState(!isVerified);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error: insertError } = await supabase.from('spaces').insert({
      institution_id: institutionId,
      host_profile_id: hostProfileId,
      title: title.trim(),
      description: description.trim() || null,
      kind,
      scheduled_for: new Date(when).toISOString(),
      duration_min: Number(duration),
      max_participants: Number(capacity),
      requires_admission: waitingRoom,
    });

    setBusy(false);
    if (insertError) setError(describeError(insertError));
    else await onSaved();
  }

  return (
    <Dialog
      as="form"
      title="Schedule a live session"
      onClose={onClose}
      onSubmit={submit}
      footer={
        <>
          <Button variant="ghost" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={busy}>Schedule</Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <Field label="Title">
          <Input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Computer Science admissions hour"
            required
            maxLength={120}
          />
        </Field>

        <Field label="What is it for">
          <Select value={kind} onChange={(e) => setKind(e.target.value)}>
            {Object.entries(KINDS).map(([value, label]) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </Select>
        </Field>

        <Field label="Description" hint="Shown to students on their Spaces tab.">
          <Textarea
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Bring your questions about entry requirements and scholarships."
            maxLength={600}
          />
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field label="Starts">
            <Input
              type="datetime-local"
              value={when}
              onChange={(e) => setWhen(e.target.value)}
              required
            />
          </Field>
          <Field label="Minutes">
            <Input
              type="number"
              min={5}
              max={480}
              value={duration}
              onChange={(e) => setDuration(e.target.value)}
              required
            />
          </Field>
        </div>

        <Field label="Capacity" hint="The room will not admit more than this.">
          <Input
            type="number"
            min={2}
            max={1000}
            value={capacity}
            onChange={(e) => setCapacity(e.target.value)}
            required
          />
        </Field>

        <label className="flex items-start gap-3 rounded-tile bg-surface p-3">
          <input
            type="checkbox"
            checked={waitingRoom}
            disabled={!isVerified}
            onChange={(e) => setWaitingRoom(e.target.checked)}
            className="mt-0.5 h-4 w-4 accent-white"
          />
          <span className="text-[13px] text-muted">
            <span className="font-semibold text-white">Let people in one at a time.</span>{' '}
            {isVerified
              ? 'Students wait until you admit them. Leave this off for an open session.'
              : 'Required until your institution is verified.'}
          </span>
        </label>

        <p className="text-[12px] leading-relaxed text-subtle">
          Students join to listen without sharing who they are. If one raises their
          hand, unmutes or writes in the chat, they are asked to share their Education
          Passport first — and then you see their name.
        </p>

        {error && <Alert tone="error">{error}</Alert>}
      </div>
    </Dialog>
  );
}
