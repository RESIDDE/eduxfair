import { useState } from 'react';
import {
  Check, Hand, MicOff, Shield, ShieldMinus, ShieldOff, ShieldPlus, UserX,
  VideoOff, Volume2, VolumeX, X,
} from 'lucide-react';
import { Avatar, Button, Eyebrow, Loading } from '../ui';

/**
 * The host's view of the room, and every moderation control.
 *
 * Rows come from `space_roster` — the view with no profile_id column — joined
 * to live LiveKit state by participant id. So a host can admit, mute and remove
 * a listener they still cannot name.
 *
 * Every action is one `roomAction('moderate', …)` call. The UI never talks to
 * LiveKit for a privileged operation: the database decides and records it
 * first, and the Edge Function carries it through.
 */
export function ParticipantsPanel({
  roster, loading, participants, canModerate, isStaff, onModerate, onAskUnmute,
  onMuteEveryone, isSpace,
}) {
  const [busy, setBusy] = useState(null);
  const [silencing, setSilencing] = useState(false);

  const liveByPid = new Map(
    participants.filter((p) => p.participantId).map((p) => [p.participantId, p]),
  );

  const act = async (participantId, moderation) => {
    setBusy(`${participantId}:${moderation}`);
    try {
      await onModerate(participantId, moderation);
    } finally {
      setBusy(null);
    }
  };

  if (!isSpace) {
    // A 1:1 appointment has no roster view and nothing to moderate — the two
    // people in it are already named to each other.
    return (
      <div className="flex flex-col gap-2 p-4">
        {participants.map((p) => (
          <Row key={p.identity} name={p.name} sub={p.role} person={p} />
        ))}
      </div>
    );
  }

  if (loading) return <Loading label="Reading the roster" />;

  const rows = (roster ?? []).filter((r) => r.admission !== 'removed' && r.admission !== 'denied');
  const waiting = rows.filter((r) => r.admission === 'pending');
  const hands = rows
    .filter((r) => r.admission === 'admitted' && r.hand_raised_at)
    .sort((a, b) => new Date(a.hand_raised_at) - new Date(b.hand_raised_at));
  const rest = rows.filter((r) => r.admission === 'admitted' && !r.hand_raised_at);

  async function silence(includeVideo) {
    setSilencing(true);
    try {
      await onMuteEveryone(includeVideo);
    } finally {
      setSilencing(false);
    }
  }

  return (
    <div className="flex flex-col gap-5 p-4">
      {canModerate && (
        <section className="flex flex-col gap-2 rounded-tile bg-surface p-3">
          <Eyebrow>Everyone at once</Eyebrow>
          <p className="text-[11px] leading-relaxed text-subtle">
            Silences everyone except the hosts and moderators. They can turn
            their own microphone back on, so this quiets the room rather than
            locking it.
          </p>
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm" variant="glass" icon={VolumeX} loading={silencing}
              onClick={() => silence(false)}
            >
              Mute everyone
            </Button>
            <Button
              size="sm" variant="ghost" icon={VideoOff} loading={silencing}
              onClick={() => silence(true)}
            >
              Mics and cameras
            </Button>
          </div>
        </section>
      )}

      {waiting.length > 0 && (
        <section className="flex flex-col gap-2">
          <Eyebrow>Waiting to be let in · {waiting.length}</Eyebrow>
          {waiting.map((r) => (
            <Row key={r.participant_id} name={label(r)} sub="Asking to join">
              {canModerate && (
                <>
                  <Button
                    size="sm" variant="glass" icon={Check}
                    loading={busy === `${r.participant_id}:admitted`}
                    onClick={() => act(r.participant_id, 'admitted')}
                  >
                    Admit
                  </Button>
                  <Button
                    size="sm" variant="ghost" icon={X}
                    loading={busy === `${r.participant_id}:denied`}
                    onClick={() => act(r.participant_id, 'denied')}
                  >
                    Deny
                  </Button>
                </>
              )}
            </Row>
          ))}
        </section>
      )}

      {hands.length > 0 && (
        <section className="flex flex-col gap-2">
          <Eyebrow>Hands up · {hands.length}</Eyebrow>
          {hands.map((r, i) => (
            <Row
              key={r.participant_id}
              name={label(r)}
              sub={`${i + 1} in the queue`}
              icon={Hand}
              person={liveByPid.get(r.participant_id)}
            >
              {canModerate && (
                <Controls
                  r={r} act={act} busy={busy} isStaff={isStaff}
                  onAskUnmute={onAskUnmute} live={liveByPid.get(r.participant_id)}
                />
              )}
            </Row>
          ))}
        </section>
      )}

      <section className="flex flex-col gap-2">
        <Eyebrow>In the room · {rest.length}</Eyebrow>
        {rest.map((r) => (
          <Row
            key={r.participant_id}
            name={label(r)}
            sub={r.role === 'listener' ? 'Listening' : r.role}
            person={liveByPid.get(r.participant_id)}
          >
            {/* A non-staff moderator is shown no controls against the people
                who appointed them, or against another moderator — the server
                refuses those, and a button that always fails is worse than no
                button. */}
            {canModerate && r.role !== 'host'
              && (isStaff || !['cohost', 'moderator'].includes(r.role)) && (
              <Controls
                r={r} act={act} busy={busy} isStaff={isStaff}
                onAskUnmute={onAskUnmute} live={liveByPid.get(r.participant_id)}
              />
            )}
          </Row>
        ))}
      </section>
    </div>
  );
}

/** A name only once they have shared it; a handle until then. */
function label(r) {
  return r.shared_name ?? (r.handle ? `@${r.handle}` : 'A student');
}

function Row({ name, sub, icon: Icon, person, children }) {
  return (
    <div className="flex items-center gap-3 rounded-tile bg-surface px-3 py-2">
      <Avatar name={name} size={32} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-[13px] font-semibold text-white">{name}</span>
          {Icon && <Icon size={13} className="text-warning" />}
          {person && !person.audioEnabled && <MicOff size={12} className="text-subtle" />}
        </div>
        <span className="text-[11px] capitalize text-subtle">{sub}</span>
      </div>
      <div className="flex shrink-0 items-center gap-1">{children}</div>
    </div>
  );
}

function Controls({ r, act, busy, isStaff, onAskUnmute, live }) {
  const key = (a) => busy === `${r.participant_id}:${a}`;
  return (
    <>
      {/* Mute is one-way on a default LiveKit deployment: remote unmute is
          disabled unless enable_remote_unmute is set. So the pair is "mute"
          and "ask them to unmute", not a toggle that half-works. */}
      {live?.audioEnabled ? (
        <IconAction label="Mute" icon={MicOff} loading={key('muted')} onClick={() => act(r.participant_id, 'muted')} />
      ) : (
        live && <IconAction label="Ask them to unmute" icon={Volume2} onClick={() => onAskUnmute(live.identity)} />
      )}
      {/* Cameras, unlike microphones, have no "ask them to turn it back on":
          a camera the participant re-enables is one they chose to, and that is
          the whole of the interaction. */}
      {live?.videoEnabled && (
        <IconAction label="Turn their camera off" icon={VideoOff} loading={key('camera_muted')} onClick={() => act(r.participant_id, 'camera_muted')} />
      )}
      {r.hand_raised_at && (
        <IconAction label="Lower their hand" icon={Hand} loading={key('hand_lowered')} onClick={() => act(r.participant_id, 'hand_lowered')} />
      )}
      {r.role === 'listener' ? (
        <IconAction
          label={r.is_identified ? 'Give them the floor' : 'They have not shared their passport yet'}
          icon={ShieldPlus}
          disabled={!r.is_identified}
          loading={key('promoted')}
          onClick={() => act(r.participant_id, 'promoted')}
        />
      ) : r.role !== 'moderator' && (
        <IconAction label="Take back the floor" icon={ShieldMinus} loading={key('demoted')} onClick={() => act(r.participant_id, 'demoted')} />
      )}

      {/* Appointing is staff-only: an appointed moderator runs the room, not
          the people who appointed them. */}
      {isStaff && r.role !== 'cohost' && (
        r.role === 'moderator' ? (
          <IconAction
            label="Take back their moderator role"
            icon={ShieldOff}
            loading={key('moderator_revoked')}
            onClick={() => act(r.participant_id, 'moderator_revoked')}
          />
        ) : (
          <IconAction
            label={r.is_identified ? 'Make them a moderator' : 'They have not shared their passport yet'}
            icon={Shield}
            disabled={!r.is_identified}
            loading={key('moderator_granted')}
            onClick={() => act(r.participant_id, 'moderator_granted')}
          />
        )
      )}

      <IconAction label="Remove from the session" icon={UserX} danger loading={key('removed')} onClick={() => act(r.participant_id, 'removed')} />
    </>
  );
}

function IconAction({ label: text, icon: Icon, danger, loading, disabled, onClick }) {
  return (
    <button
      type="button"
      title={text}
      aria-label={text}
      disabled={loading || disabled}
      onClick={onClick}
      className={`grid h-8 w-8 cursor-pointer place-items-center rounded-full transition-colors disabled:cursor-not-allowed disabled:opacity-35 ${
        danger ? 'text-error hover:bg-error-bg' : 'text-muted hover:bg-white/8 hover:text-white'
      }`}
    >
      <Icon size={15} />
    </button>
  );
}
