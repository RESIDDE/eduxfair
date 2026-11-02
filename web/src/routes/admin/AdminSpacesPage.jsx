import { useState } from 'react';
import { Hand, MessageSquare, Radio, ShieldAlert, Users } from 'lucide-react';
import {
  Alert, Badge, Button, Dialog, EmptyState, Loading, SegmentedControl, SurfaceCard,
} from '../../components/ui';
import { useQuery } from '../../lib/hooks';
import { describeError, supabase } from '../../lib/supabase';
import { formatDateTime } from '../../lib/format';

const KINDS = {
  admissions_hour: 'Admissions hour',
  scholarship_qa: 'Scholarship Q&A',
  country_briefing: 'Country briefing',
  open_day: 'Open day',
};

/**
 * Oversight of every live session on the platform.
 *
 * An admin can already read `spaces`, `space_participants`,
 * `space_messages` and `space_moderation_events` — all four carry an
 * `is_admin()` policy. What was missing was anywhere to look at them.
 *
 * Read-mostly on purpose. Running a room is the institution's job and the host
 * controls live in the room itself; what an admin needs is the ability to see
 * what happened and, if it comes to it, end a session that should not be
 * running. `space_set_status()` lets an admin do that without being a member.
 */
export default function AdminSpacesPage() {
  const [filter, setFilter] = useState('live');
  const [ending, setEnding] = useState(null);
  const [inspecting, setInspecting] = useState(null);
  const [actionError, setActionError] = useState(null);

  const { data: rows, loading, error, reload } = useQuery(
    (client) => {
      let query = client
        .from('spaces')
        .select('*, institutions!inner(id, name, verification_status)')
        .order('scheduled_for', { ascending: false });
      if (filter === 'live') query = query.eq('status', 'live');
      else if (filter === 'scheduled') query = query.eq('status', 'scheduled');
      else if (filter === 'past') query = query.in('status', ['ended', 'cancelled']);
      return query.limit(200);
    },
    [filter],
  );

  async function endSession(space) {
    setActionError(null);
    const { error: rpcError } = await supabase.rpc('space_set_status', {
      p_space_id: space.id,
      p_status: 'ended',
    });
    if (rpcError) setActionError(describeError(rpcError));
    setEnding(null);
    await reload();
  }

  if (loading) return <Loading label="Loading sessions" />;
  if (error) return <Alert tone="error">{error}</Alert>;

  const spaces = rows ?? [];

  return (
    <div className="flex flex-col gap-5 pb-4">
      {actionError && <Alert tone="error">{actionError}</Alert>}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <SegmentedControl
          value={filter}
          onChange={setFilter}
          options={[
            { value: 'live', label: 'Live now' },
            { value: 'scheduled', label: 'Upcoming' },
            { value: 'past', label: 'Past' },
            { value: 'all', label: 'All' },
          ]}
        />
        <span className="text-[13px] text-subtle">
          {spaces.length} session{spaces.length === 1 ? '' : 's'}
        </span>
      </div>

      {spaces.length === 0 ? (
        <EmptyState
          icon={Radio}
          title={filter === 'live' ? 'Nothing live' : 'No sessions'}
          subtitle="Institutions schedule these from their own console or the staff app."
        />
      ) : (
        <div className="flex flex-col gap-3">
          {spaces.map((space) => (
            <SurfaceCard key={space.id} className="p-4">
              <div className="flex flex-wrap items-start gap-3.5">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-semibold">{space.title}</span>
                    {space.status === 'live' && (
                      <Badge tone="success" compact pulse>Live</Badge>
                    )}
                    {space.status === 'cancelled' && (
                      <Badge tone="neutral" compact>Cancelled</Badge>
                    )}
                    {space.requires_admission && (
                      <Badge tone="warning" compact>Waiting room</Badge>
                    )}
                  </div>

                  <div className="mt-1 text-[12.5px] text-muted">
                    {space.institutions?.name}
                    {space.institutions?.verification_status !== 'verified' && (
                      <span className="text-warning">
                        {' '}· {space.institutions?.verification_status}
                      </span>
                    )}
                    {' '}· {KINDS[space.kind] ?? space.kind}
                  </div>

                  <div className="mt-0.5 text-[11.5px] text-subtle">
                    {formatDateTime(space.scheduled_for)} · {space.duration_min} min ·
                    cap {space.max_participants}
                    {space.started_at && ` · started ${formatDateTime(space.started_at)}`}
                    {space.ended_at && ` · ended ${formatDateTime(space.ended_at)}`}
                  </div>

                  {space.description && (
                    <p className="mt-2 text-[12.5px] leading-relaxed text-muted">
                      {space.description}
                    </p>
                  )}
                </div>

                <div className="flex shrink-0 flex-wrap items-center gap-2">
                  <Button
                    size="sm"
                    variant="outline"
                    icon={Users}
                    onClick={() => setInspecting(space)}
                  >
                    Inspect
                  </Button>
                  {(space.status === 'live' || space.status === 'scheduled') && (
                    <Button
                      size="sm"
                      variant="dangerGhost"
                      icon={ShieldAlert}
                      onClick={() => setEnding(space)}
                    >
                      End
                    </Button>
                  )}
                </div>
              </div>
            </SurfaceCard>
          ))}
        </div>
      )}

      {inspecting && (
        <InspectDialog space={inspecting} onClose={() => setInspecting(null)} />
      )}

      {ending && (
        <Dialog
          title="End this session?"
          eyebrow={ending.institutions?.name}
          onClose={() => setEnding(null)}
          width="max-w-[440px]"
          footer={
            <>
              <Button variant="ghost" onClick={() => setEnding(null)}>Cancel</Button>
              <Button variant="danger" onClick={() => endSession(ending)}>
                End it
              </Button>
            </>
          }
        >
          <p className="text-[13.5px] leading-relaxed text-muted">
            “{ending.title}” is marked ended and everyone is disconnected. The
            institution is not asked first, and the decision is recorded against
            your account in the session's moderation log.
          </p>
        </Dialog>
      )}
    </div>
  );
}

/**
 * What happened in one room.
 *
 * Reads `space_participants` directly rather than `space_roster`: the roster
 * view is scoped to the institution that owns the room, and an admin looking at
 * somebody else's session gets nothing from it. The admin policy on the table
 * is what makes this readable.
 */
function InspectDialog({ space, onClose }) {
  const { data, loading } = useQuery(async (client) => {
    const [participants, messages, events] = await Promise.all([
      client.from('space_participants').select('*').eq('space_id', space.id),
      client.from('space_messages').select('id', { count: 'exact', head: true })
        .eq('space_id', space.id).is('deleted_at', null),
      client.from('space_moderation_events').select('*')
        .eq('space_id', space.id).order('created_at', { ascending: false }).limit(50),
    ]);
    if (participants.error) return { data: null, error: participants.error };
    return {
      data: {
        participants: participants.data ?? [],
        messageCount: messages.count ?? 0,
        events: events.data ?? [],
      },
      error: null,
    };
  }, [space.id]);

  const people = data?.participants ?? [];

  return (
    <Dialog title={space.title} eyebrow="Session detail" onClose={onClose} width="max-w-[640px]">
      {loading ? (
        <Loading label="Reading the room" />
      ) : (
        <div className="flex flex-col gap-5">
          <div className="grid grid-cols-4 gap-3">
            <Tile icon={Users} label="joined" value={people.filter((p) => p.joined_at).length} />
            <Tile
              icon={Hand}
              label="asked to speak"
              value={people.filter((p) => p.hand_raised_at).length}
            />
            <Tile icon={MessageSquare} label="messages" value={data?.messageCount ?? 0} />
            <Tile
              icon={ShieldAlert}
              label="identified"
              value={people.filter((p) => p.identified_at && p.role !== 'host' && p.role !== 'cohost').length}
            />
          </div>

          <div>
            <h4 className="mb-2 text-[12px] font-bold uppercase tracking-[1px] text-subtle">
              Moderation log
            </h4>
            {(data?.events ?? []).length === 0 ? (
              <p className="text-[13px] text-subtle">Nothing was moderated.</p>
            ) : (
              <div className="flex flex-col gap-1.5">
                {data.events.map((e) => (
                  <div
                    key={e.id}
                    className="flex flex-wrap items-center gap-2 rounded-tile bg-surface-variant px-3 py-2 text-[12.5px]"
                  >
                    <Badge tone="neutral" compact>{e.action.replace('_', ' ')}</Badge>
                    <span className="text-subtle">{formatDateTime(e.created_at)}</span>
                    {e.reason && <span className="text-muted">— {e.reason}</span>}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      )}
    </Dialog>
  );
}

function Tile({ icon: Icon, label, value }) {
  return (
    <div className="rounded-tile bg-surface-variant p-3">
      <Icon size={14} className="text-subtle" />
      <div className="mt-1.5 text-[20px] font-extrabold leading-none">{value}</div>
      <div className="mt-1 text-[11px] text-subtle">{label}</div>
    </div>
  );
}
