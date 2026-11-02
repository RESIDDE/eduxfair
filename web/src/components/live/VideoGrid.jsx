import { VideoTile } from './VideoTile';

/**
 * Grid, or one pinned tile with the rest as a filmstrip.
 *
 * The grid is capped and everyone past the cap is unsubscribed, not just
 * hidden. Hiding a tile still decodes its video, and the other end of this call
 * is often a mid-range phone on cellular — nine decoded streams is where one
 * falls over. Speakers and raised hands are kept ahead of silent listeners so
 * the cap drops the least interesting tiles.
 */
const VISIBLE_CAP = 6;

export function VideoGrid({ participants, pinnedIdentity, onPin }) {
  const screenSharer = participants.find((p) => p.screenTrack);
  const ranked = [...participants].sort((a, b) => score(b) - score(a));

  const visible = ranked.slice(0, VISIBLE_CAP);
  const overflow = ranked.slice(VISIBLE_CAP);

  // Subscription follows visibility, so bandwidth and CPU follow it too.
  visible.forEach((p) => setSubscribed(p, true));
  overflow.forEach((p) => setSubscribed(p, false));

  const pinned = screenSharer
    ?? visible.find((p) => p.identity === pinnedIdentity)
    ?? null;

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      {pinned && (
        <div className="min-h-0 flex-1">
          <VideoTile
            person={pinned}
            pinned
            screen={Boolean(pinned.screenTrack)}
            onPin={screenSharer ? undefined : onPin}
          />
        </div>
      )}

      <div
        className={`grid min-h-0 gap-3 ${pinned ? 'h-[22%] grid-flow-col auto-cols-[180px] overflow-x-auto scrollbar-thin' : 'flex-1 grid-cols-[repeat(auto-fit,minmax(220px,1fr))] content-center'}`}
      >
        {visible
          .filter((p) => p !== pinned)
          .map((p) => (
            <VideoTile key={p.sid || p.identity} person={p} onPin={onPin} />
          ))}
      </div>

      {overflow.length > 0 && (
        <p className="text-center text-[12px] text-subtle">
          and {overflow.length} more listening
        </p>
      )}
    </div>
  );
}

function score(p) {
  return (p.screenTrack ? 100 : 0)
    + (p.isSpeaking ? 50 : 0)
    + (p.hand ? 25 : 0)
    + (p.role === 'host' ? 20 : p.role === 'cohost' ? 10 : 0)
    + (p.videoEnabled ? 5 : 0)
    + (p.isLocal ? 1 : 0);
}

function setSubscribed(person, want) {
  if (person.isLocal) return;
  for (const pub of person.participant?.trackPublications?.values() ?? []) {
    if (pub.isSubscribed !== want) pub.setSubscribed(want);
  }
}
