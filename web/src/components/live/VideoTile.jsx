import { useEffect, useRef } from 'react';
import { Hand, MicOff, MonitorUp, Pin } from 'lucide-react';
import { Avatar } from '../ui';

/**
 * One participant.
 *
 * `track.attach(el)` rather than a src: LiveKit owns the MediaStream and
 * re-attaches it whenever the publication changes quality, so the element is
 * handed to the track rather than the other way round.
 */
export function VideoTile({ person, pinned = false, screen = false, onPin }) {
  const videoRef = useRef(null);
  const audioRef = useRef(null);

  const videoTrack = screen ? person.screenTrack : person.videoTrack;

  useEffect(() => {
    const el = videoRef.current;
    if (!el || !videoTrack) return undefined;
    videoTrack.attach(el);
    return () => videoTrack.detach(el);
  }, [videoTrack]);

  useEffect(() => {
    const el = audioRef.current;
    // Never play your own microphone back at yourself.
    if (!el || !person.audioTrack || person.isLocal) return undefined;
    person.audioTrack.attach(el);
    return () => person.audioTrack.detach(el);
  }, [person.audioTrack, person.isLocal]);

  const isStaff = person.role === 'host' || person.role === 'cohost';

  return (
    <div
      className={`group relative overflow-hidden rounded-tile bg-surface border transition-colors ${
        person.isSpeaking ? 'border-accent-light' : 'border-line'
      } ${pinned ? 'col-span-full row-span-2' : ''}`}
    >
      {videoTrack ? (
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted={person.isLocal}
          className={`h-full w-full ${screen ? 'object-contain bg-black' : 'object-cover'} ${
            person.isLocal && !screen ? 'scale-x-[-1]' : ''
          }`}
        />
      ) : (
        <div className="grid h-full w-full place-items-center bg-surface-variant">
          <Avatar name={person.name} size={pinned ? 96 : 56} />
        </div>
      )}

      {!person.isLocal && <audio ref={audioRef} autoPlay />}

      <div className="absolute inset-x-0 bottom-0 flex items-center gap-2 bg-gradient-to-t from-black/80 to-transparent px-3 pb-2 pt-6">
        <span className="truncate text-[13px] font-semibold text-white">
          {person.name}
          {person.isLocal && <span className="text-subtle"> (you)</span>}
        </span>
        {isStaff && (
          <span className="rounded-full bg-white/15 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white">
            {person.role}
          </span>
        )}
        {screen && <MonitorUp size={14} className="text-accent-light" />}
        <div className="ml-auto flex items-center gap-1.5">
          {person.hand && <Hand size={15} className="text-warning" />}
          {!person.audioEnabled && <MicOff size={15} className="text-subtle" />}
        </div>
      </div>

      {onPin && (
        <button
          type="button"
          onClick={() => onPin(pinned ? null : person.identity)}
          aria-label={pinned ? 'Unpin' : 'Pin'}
          className="glass absolute right-2 top-2 grid h-8 w-8 cursor-pointer place-items-center rounded-full text-white opacity-0 transition-opacity group-hover:opacity-100"
        >
          <Pin size={14} />
        </button>
      )}
    </div>
  );
}
