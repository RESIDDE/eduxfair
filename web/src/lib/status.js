/**
 * Status labels and tones for the consoles.
 *
 * Structure follows consult-app/admin_dashboard/src/lib/status.js so the kit's
 * Badge and StatusBadge work unchanged, but the statuses are this domain's:
 * application stages, verification states and appointment states.
 */

/** Badge colours per tone. `live` is the accent, for things needing attention now. */
export const TONES = {
  neutral: 'bg-surface-variant text-white/80',
  warning: 'bg-warning-bg text-warning',
  info: 'bg-info-bg text-info',
  live: 'bg-accent/12 text-accent',
  success: 'bg-success-bg text-success',
  error: 'bg-error-bg text-error',
};

/**
 * Application stages. `step` is how far through the pipeline the stage is, out
 * of STAGE_COUNT, for the progress bars.
 */
export const STATUS = {
  draft: { label: 'Draft', tone: 'neutral', step: 0 },
  submitted: { label: 'Submitted', tone: 'info', step: 1 },
  under_review: { label: 'Under review', tone: 'live', step: 2 },
  documents_requested: { label: 'Documents requested', tone: 'warning', step: 2 },
  conditional_offer: { label: 'Conditional offer', tone: 'info', step: 3 },
  offer: { label: 'Offer', tone: 'success', step: 4 },
  accepted: { label: 'Offer accepted', tone: 'success', step: 5 },
  deposit_paid: { label: 'Deposit paid', tone: 'success', step: 6 },
  visa: { label: 'Visa stage', tone: 'info', step: 7 },
  enrolled: { label: 'Enrolled', tone: 'success', step: 8 },
  rejected: { label: 'Not successful', tone: 'error', step: 0 },
  withdrawn: { label: 'Withdrawn', tone: 'neutral', step: 0 },

  // Verification
  unverified: { label: 'Not verified', tone: 'neutral', step: 0 },
  pending: { label: 'Pending review', tone: 'warning', step: 0 },
  verified: { label: 'Verified', tone: 'success', step: 0 },

  // Appointments
  requested: { label: 'Requested', tone: 'warning', step: 0 },
  confirmed: { label: 'Confirmed', tone: 'success', step: 0 },
  declined: { label: 'Declined', tone: 'error', step: 0 },
  rescheduled: { label: 'Rescheduled', tone: 'info', step: 0 },
  completed: { label: 'Completed', tone: 'neutral', step: 0 },
  no_show: { label: 'No show', tone: 'error', step: 0 },
  cancelled: { label: 'Cancelled', tone: 'neutral', step: 0 },
};

export const STAGE_COUNT = 8;

export const statusOf = (status) =>
  STATUS[status] ?? { label: status ?? '—', tone: 'neutral', step: 0 };

/** Applications that still need work from someone. */
export const OPEN_STAGES = [
  'submitted',
  'under_review',
  'documents_requested',
  'conditional_offer',
  'offer',
  'accepted',
  'deposit_paid',
  'visa',
];

export const CLOSED_STAGES = ['rejected', 'withdrawn', 'enrolled'];
