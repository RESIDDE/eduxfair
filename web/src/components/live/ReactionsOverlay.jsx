/**
 * Reactions float up and remove themselves.
 *
 * `pointer-events-none` throughout: a reaction drifting across the controls
 * must never be the thing that swallows a click on Leave.
 */
export function ReactionsOverlay({ reactions }) {
  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden">
      {reactions.map((r, i) => (
        <span
          key={r.id}
          className="absolute bottom-6 text-[34px] [animation:reaction-float_3s_ease-out_forwards]"
          style={{ left: `${12 + ((i * 17) % 70)}%` }}
        >
          {r.emoji}
        </span>
      ))}
    </div>
  );
}
