import { statusOf, TONES } from '../../lib/status';

/** Pill with a dot and a label, coloured by tone (see TONES). */
export function Badge({ tone = 'neutral', compact = false, pulse = false, children }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 w-fit rounded-full font-semibold whitespace-nowrap ${
        compact ? 'px-2 py-1 text-[11px]' : 'px-3 py-1.5 text-[12px]'
      } ${TONES[tone]}`}
    >
      <span className={`size-1.5 rounded-full bg-current ${pulse ? 'animate-pulse-dot' : ''}`} />
      {children}
    </span>
  );
}

/**
 * An application stage, verification state or appointment state (see
 * lib/status.js). Pulses for the states that are waiting on someone, so a long
 * board still shows where attention is needed.
 */
export function StatusBadge({ status, compact = false }) {
  const { label, tone } = statusOf(status);
  const needsAttention =
    status === 'under_review' ||
    status === 'documents_requested' ||
    status === 'requested' ||
    status === 'pending';

  return (
    <Badge tone={tone} compact={compact} pulse={needsAttention}>
      {label}
    </Badge>
  );
}
