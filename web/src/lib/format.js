// Formatting shared by both consoles. Mirrors the Flutter app's display logic
// (student_app/lib/features/.../models) so a figure reads the same on both sides.

const thousands = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });

export const formatMoney = (amount, currency = 'USD') =>
  `${currency} ${thousands.format(Math.round(Number(amount) || 0))}`;

export const formatCount = (n) => thousands.format(Number(n) || 0);

/** Up to two initials, e.g. `Maplecrest University` → `MU`. */
export const initials = (name) => {
  const parts = String(name ?? '')
    .trim()
    .split(/\s+/)
    .filter((p) => p.length > 2);
  if (parts.length === 0) {
    const fallback = String(name ?? '').trim();
    return fallback ? fallback[0].toUpperCase() : '?';
  }
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
};

export const formatDate = (value) => {
  if (!value) return '—';
  return new Date(value).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
};

export const formatDateTime = (value) => {
  if (!value) return '—';
  return new Date(value).toLocaleString('en-GB', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
};

export const relativeTime = (value) => {
  if (!value) return '';
  const diff = Date.now() - new Date(value).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d`;
  return `${Math.floor(days / 7)}w`;
};

/** Tuition range as the institution published it. */
export const tuitionRange = (program) => {
  if (program.tuition_min == null) return 'Not published';
  const currency = program.tuition_currency ?? 'USD';
  const min = thousands.format(Math.round(program.tuition_min));
  if (program.tuition_max == null || program.tuition_max === program.tuition_min) {
    return `${currency} ${min}`;
  }
  return `${currency} ${min}–${thousands.format(Math.round(program.tuition_max))}`;
};

/**
 * Whether an appointment's Lekkside room is open.
 *
 * Ten minutes early, fifteen past the end. The same window
 * `appointment_room_grant()` enforces in SQL and `Appointment.canJoinNow`
 * applies in the Flutter app — three copies of one rule, so this is the only
 * one the console is allowed to have.
 */
export const isCallWindowOpen = (appointment) => {
  if (appointment?.status !== 'confirmed' || !appointment.scheduled_for) return false;
  const start = new Date(appointment.scheduled_for).getTime();
  const duration = (appointment.duration_min ?? 30) * 60000;
  const now = Date.now();
  return now >= start - 10 * 60000 && now <= start + duration + 15 * 60000;
};
