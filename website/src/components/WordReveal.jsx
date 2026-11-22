import { useScrollProgress } from '../lib/hooks';

/**
 * A paragraph that lights up word by word as you scroll through it.
 *
 * `parts` is a list of [text, accent?] pairs, so a phrase can be picked out in
 * the brand colour without splitting the copy across components.
 */
export default function WordReveal({ parts, className = '', dim = 'rgba(255,255,255,0.16)', lit = '#f5f5f7' }) {
  const [ref, progress] = useScrollProgress({ start: 0.9, end: 0.35 });
  const words = parts.flatMap(([text, accent]) =>
    text.split(' ').filter(Boolean).map((w) => ({ w, accent })),
  );
  const litCount = progress * words.length;

  return (
    <p ref={ref} className={className} aria-label={parts.map(([t]) => t).join(' ')}>
      {words.map(({ w, accent }, i) => {
        const on = Math.min(1, Math.max(0, litCount - i));
        const color = accent ? 'var(--color-brand)' : lit;
        return (
          <span
            key={i}
            aria-hidden="true"
            style={{
              color: on > 0.5 ? color : dim,
              opacity: accent && on <= 0.5 ? 0.55 : 1,
              transition: 'color 0.35s ease, opacity 0.35s ease',
            }}
          >
            {w}{' '}
          </span>
        );
      })}
    </p>
  );
}
