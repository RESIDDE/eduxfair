import { useState } from 'react';
import {
  Hand, LogOut, MessageSquare, Mic, MicOff, MonitorUp, Settings,
  Smile, Users, Video, VideoOff,
} from 'lucide-react';
import { Button, GlassIconButton } from '../ui';
import { REACTIONS } from '../../lib/livekit';

export function ControlBar({
  local, canPublish, canScreenShare, actions, onToggle, panel,
  waitingCount = 0, handCount = 0, askedToUnmute = false, onNeedsConsent,
}) {
  const [showReactions, setShowReactions] = useState(false);

  // A listener's buttons are not hidden — they are the thing that explains the
  // room. Pressing one opens the consent sheet, which is the only way to get a
  // publishing token, so an empty-handed listener never wonders why the mic is
  // missing.
  const publishOrConsent = (fn) => () => (canPublish ? fn() : onNeedsConsent?.());

  return (
    <div className="relative flex flex-wrap items-center justify-center gap-2 border-t border-line bg-canvas/80 px-4 py-3 backdrop-blur">
      <GlassIconButton
        icon={local?.audioEnabled ? Mic : MicOff}
        label={local?.audioEnabled ? 'Mute' : 'Unmute'}
        onClick={publishOrConsent(() => actions.setMicrophone(!local?.audioEnabled))}
        className={askedToUnmute && !local?.audioEnabled ? 'ring-2 ring-warning' : ''}
      />
      <GlassIconButton
        icon={local?.videoEnabled ? Video : VideoOff}
        label={local?.videoEnabled ? 'Turn camera off' : 'Turn camera on'}
        onClick={publishOrConsent(() => actions.setCamera(!local?.videoEnabled))}
      />
      {canScreenShare && (
        <GlassIconButton
          icon={MonitorUp}
          label={local?.screenTrack ? 'Stop sharing' : 'Share your screen'}
          onClick={() => actions.setScreenShare(!local?.screenTrack)}
        />
      )}

      <GlassIconButton
        icon={Hand}
        label={local?.hand ? 'Lower your hand' : 'Raise your hand'}
        onClick={publishOrConsent(() => actions.raiseHand(!local?.hand))}
        className={local?.hand ? 'ring-2 ring-warning' : ''}
      />

      <div className="relative">
        <GlassIconButton
          icon={Smile}
          label="React"
          onClick={publishOrConsent(() => setShowReactions((v) => !v))}
        />
        {showReactions && (
          <div className="glass absolute bottom-[56px] left-1/2 flex -translate-x-1/2 gap-1 rounded-full px-2 py-1.5 animate-enter">
            {REACTIONS.map((emoji) => (
              <button
                key={emoji}
                type="button"
                aria-label={`React ${emoji}`}
                onClick={() => { actions.react(emoji); setShowReactions(false); }}
                className="grid h-9 w-9 cursor-pointer place-items-center rounded-full text-[19px] transition-transform hover:scale-125"
              >
                {emoji}
              </button>
            ))}
          </div>
        )}
      </div>

      <span className="mx-1 h-7 w-px bg-line" aria-hidden />

      <GlassIconButton
        icon={Users}
        label="Participants"
        badge={waitingCount + handCount}
        onClick={() => onToggle(panel === 'people' ? null : 'people')}
        className={panel === 'people' ? 'ring-1 ring-accent-light' : ''}
      />
      <GlassIconButton
        icon={MessageSquare}
        label="Chat"
        onClick={() => onToggle(panel === 'chat' ? null : 'chat')}
        className={panel === 'chat' ? 'ring-1 ring-accent-light' : ''}
      />
      <GlassIconButton
        icon={Settings}
        label="Devices"
        onClick={() => onToggle(panel === 'devices' ? null : 'devices')}
        className={panel === 'devices' ? 'ring-1 ring-accent-light' : ''}
      />

      <Button variant="danger" icon={LogOut} size="sm" className="ml-1" onClick={actions.leave}>
        Leave
      </Button>
    </div>
  );
}
