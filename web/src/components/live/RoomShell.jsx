import { useState } from 'react';
import { ArrowLeft, Radio, WifiOff } from 'lucide-react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase, describeError } from '../../lib/supabase';
import { useQuery } from '../../lib/hooks';
import { useLiveRoom } from '../../lib/useLiveRoom';
import { canModerate as canModerateRole, isStaff as isStaffRole, roomAction } from '../../lib/livekit';
import { Button, EmptyState, Loading } from '../ui';
import { ChatPanel } from './ChatPanel';
import { ControlBar } from './ControlBar';
import { DevicePicker } from './DevicePicker';
import { IdentifyDialog } from './IdentifyDialog';
import { ParticipantsPanel } from './ParticipantsPanel';
import { ReactionsOverlay } from './ReactionsOverlay';
import { VideoGrid } from './VideoGrid';

/**
 * The call screen, shared by Spaces and 1:1 appointments.
 *
 * Rendered full-bleed, outside InstitutionShell: a 248px nav rail eating a
 * quarter of the screen during a call is wrong, so these two routes are the
 * only institution pages that are not shell children.
 */
export function RoomShell({ spaceId, appointmentId, myProfileId, backTo, backLabel }) {
  const isSpace = Boolean(spaceId);
  const [panel, setPanel] = useState(null);
  const [pinned, setPinned] = useState(null);
  const [consenting, setConsenting] = useState(false);
  const navigate = useNavigate();

  const {
    phase, error, grant, participants, local, metadata,
    reactions, notices, askedToUnmute, actions, notify,
  } = useLiveRoom({ spaceId, appointmentId });

  const { data: roster, loading: rosterLoading, reload: reloadRoster } = useQuery(
    (client) => (isSpace && spaceId
      ? client.from('space_roster').select('*').eq('space_id', spaceId)
      : Promise.resolve({ data: [], error: null })),
    [spaceId, isSpace, phase],
  );

  const role = grant?.role ?? 'listener';
  const canMod = canModerateRole(role);
  // Appointing a moderator, and ending the session, are the institution's.
  // An appointed moderator runs the room, not the people who appointed them.
  const isStaff = isStaffRole(role);
  const canPublish = Boolean(grant?.can_publish);
  const canScreenShare = Boolean(grant?.publish_sources?.includes('screen_share'));
  const institution = grant?.space?.institution ?? grant?.appointment?.institution ?? 'this institution';
  const title = grant?.space?.title ?? (grant?.appointment ? `Meeting with ${institution}` : 'Live room');

  const waiting = (roster ?? []).filter((r) => r.admission === 'pending');
  const hands = (roster ?? []).filter((r) => r.admission === 'admitted' && r.hand_raised_at);

  async function moderate(participantId, moderation) {
    try {
      const result = await roomAction('moderate', { participant_id: participantId, moderation });
      // The database decision stuck but LiveKit did not hear it: they cannot
      // rejoin, yet they are still connected right now. That is what the host
      // needs told, rather than a silent success.
      if (result?.livekit === false) {
        notify('Recorded, but the room did not confirm it — they may still be connected.');
      }
      await reloadRoster();
    } catch (err) {
      notify(err.message);
    }
  }

  /**
   * Silences everyone who is not running the session.
   *
   * Hosts, cohosts, the appointed moderators and the caller are exempt, and
   * that exemption is decided in SQL — a client choosing its own exemptions
   * would be a client that can mute a host.
   */
  async function muteEveryone(includeVideo) {
    try {
      const result = await roomAction('mute_all', {
        space_id: spaceId,
        include_video: includeVideo,
      });
      if (result?.livekit === false) {
        notify('Recorded, but the room did not confirm it.');
      } else if (!result?.count) {
        notify('Nobody to mute.');
      } else if (!result?.muted) {
        // The people were there; nothing of theirs was live. "Muted 40" here
        // would be a number that reads like a success and is not.
        notify(includeVideo
          ? 'Nobody had a microphone or camera on.'
          : 'Nobody had a microphone on.');
      } else {
        const people = `${result.count} ${result.count === 1 ? 'person' : 'people'}`;
        notify(includeVideo ? `Muted ${people} and their cameras.` : `Muted ${people}.`);
      }
      await reloadRoster();
    } catch (err) {
      notify(err.message);
    }
  }

  /** The two-tier upgrade: consent row first, then a publishing token. */
  async function identify() {
    const { error: rpcError } = await supabase.rpc('identify_in_space', { p_space_id: spaceId });
    if (rpcError) throw new Error(describeError(rpcError));
    setConsenting(false);
    // A short reconnect with the new token. It reads as the state change it is,
    // and it keeps one code path across the web and Flutter clients.
    await actions.reconnect();
    await reloadRoster();
  }

  if (phase === 'connecting') return <Centred><Loading label="Joining the room" /></Centred>;

  if (phase === 'failed') {
    return (
      <Centred>
        <EmptyState
          icon={WifiOff}
          title="This room could not be opened"
          subtitle={error}
          action={<Button onClick={actions.reconnect}>Try again</Button>}
        />
      </Centred>
    );
  }

  if (phase === 'closed') {
    return (
      <Centred>
        <EmptyState
          icon={Radio}
          title="This room is not open yet"
          subtitle={grant?.opens_at
            ? `It opens at ${new Date(grant.opens_at).toLocaleString()}.`
            : 'It opens ten minutes before the start.'}
          action={<Button variant="glass" onClick={actions.reconnect}>Check again</Button>}
        />
      </Centred>
    );
  }

  if (phase === 'waiting') {
    return (
      <Centred>
        <EmptyState
          icon={Radio}
          title="Waiting for the host to let you in"
          subtitle="You will join automatically as soon as they do."
        />
      </Centred>
    );
  }

  if (phase === 'ended') {
    return (
      <Centred>
        <EmptyState
          icon={Radio}
          title="You have left the room"
          action={<Button onClick={() => navigate(backTo)}>{backLabel}</Button>}
        />
      </Centred>
    );
  }

  return (
    <div className="flex h-full flex-col bg-canvas">
      <header className="flex items-center gap-3 border-b border-line px-4 py-3">
        <Link to={backTo} aria-label={backLabel} className="text-muted hover:text-white">
          <ArrowLeft size={18} />
        </Link>
        <div className="min-w-0">
          <h1 className="truncate text-[15px] font-bold text-white">{title}</h1>
          <p className="text-[11px] text-subtle">
            {institution} · {participants.length} here
            {metadata?.recording === false && ' · not recorded'}
          </p>
        </div>
        {/* isStaff, not canMod: space_set_status() is institution-only, so an
            appointed moderator pressing this would get a refusal. */}
        {isStaff && (
          <Button
            variant="dangerGhost"
            size="sm"
            className="ml-auto"
            onClick={async () => {
              try {
                await roomAction('end', { space_id: spaceId });
                await actions.leave();
              } catch (err) {
                notify(err.message);
              }
            }}
          >
            End for everyone
          </Button>
        )}
      </header>

      <div className="flex min-h-0 flex-1">
        <main className="relative flex min-h-0 flex-1 flex-col p-3">
          <VideoGrid participants={participants} pinnedIdentity={pinned} onPin={setPinned} />
          <ReactionsOverlay reactions={reactions} />

          <div className="pointer-events-none absolute left-1/2 top-3 z-20 flex -translate-x-1/2 flex-col items-center gap-2">
            {notices.map((n) => (
              <span key={n.id} className="glass rounded-full px-4 py-2 text-[12px] font-medium text-white animate-enter">
                {n.text}
              </span>
            ))}
          </div>
        </main>

        {panel && (
          <aside className="flex w-drawer min-h-0 shrink-0 flex-col overflow-y-auto scrollbar-thin border-l border-line bg-canvas">
            {panel === 'people' && (
              <ParticipantsPanel
                isSpace={isSpace}
                roster={roster}
                loading={rosterLoading}
                participants={participants}
                canModerate={canMod}
                isStaff={isStaff}
                onMuteEveryone={muteEveryone}
                onModerate={moderate}
                onAskUnmute={actions.askToUnmute}
              />
            )}
            {panel === 'chat' && (
              <ChatPanel
                isSpace={isSpace}
                chatId={isSpace ? spaceId : grant?.appointment?.conversation_id}
                myParticipantId={grant?.participant_id}
                myProfileId={myProfileId}
                roster={roster}
                canModerate={canMod}
                canPost={canPublish}
                onNeedsConsent={() => setConsenting(true)}
              />
            )}
            {panel === 'devices' && <DevicePicker actions={actions} />}
          </aside>
        )}
      </div>

      {!canPublish && (
        <p className="mx-4 mb-1 shrink-0 rounded-[18px] border border-line bg-surface px-4 py-3 text-[13px] font-medium text-muted">
          You are listening as{' '}
          <span className="text-white">{grant?.display_name}</span>. Raise your hand or
          unmute to take part — that shares your passport with {institution}.
        </p>
      )}

      <ControlBar
        local={local}
        canPublish={canPublish}
        canScreenShare={canScreenShare}
        actions={actions}
        panel={panel}
        onToggle={setPanel}
        waitingCount={canMod ? waiting.length : 0}
        handCount={canMod ? hands.length : 0}
        askedToUnmute={askedToUnmute}
        onNeedsConsent={() => setConsenting(true)}
      />

      {consenting && (
        <IdentifyDialog
          institution={institution}
          onConfirm={identify}
          onClose={() => setConsenting(false)}
        />
      )}
    </div>
  );
}

function Centred({ children }) {
  return <div className="grid h-full place-items-center p-6">{children}</div>;
}
