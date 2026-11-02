import { useState } from 'react';
import { BadgeCheck, CircleAlert, Clock, Info } from 'lucide-react';
import { Dialog } from './ui';
import { VERIFICATION_MEANING } from '../lib/vocab';

const LABELS = {
  institution: 'Verified institution',
  passport: 'Verified student',
  document: 'Verified document',
  educator: 'Verified educator',
};

/**
 * A verification badge that can explain itself.
 *
 * Each badge is a trust claim with real weight — an institution's listing being
 * "verified" means only that someone on its own domain confirmed it, not that
 * Lekkside has assessed its accreditation. A badge nobody can interrogate is
 * how a platform ends up implying more than it checked, so this one always
 * carries the explanation.
 */
export function VerifiedBadge({ subject, status = 'verified' }) {
  const [open, setOpen] = useState(false);

  const look = {
    verified: {
      icon: BadgeCheck,
      className: 'bg-success-bg text-success',
      label: LABELS[subject] ?? 'Verified',
    },
    pending: {
      icon: Clock,
      className: 'bg-warning-bg text-warning',
      label: 'Verification pending',
    },
    rejected: {
      icon: CircleAlert,
      className: 'bg-error-bg text-error',
      label: 'Verification declined',
    },
    unverified: {
      icon: Info,
      className: 'bg-surface-variant text-white/70',
      label: 'Not verified',
    },
  }[status] ?? {
    icon: Info,
    className: 'bg-surface-variant text-white/70',
    label: 'Not verified',
  };

  const Icon = look.icon;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        title="What does this mean?"
        className={`inline-flex items-center gap-1.5 w-fit px-2.5 py-1 rounded-full text-[11.5px] font-semibold cursor-pointer transition-[filter] hover:brightness-110 ${look.className}`}
      >
        <Icon size={13} strokeWidth={2.4} />
        {look.label}
      </button>

      {open && (
        <Dialog title={look.label} onClose={() => setOpen(false)}>
          <p className="text-muted leading-relaxed">
            {status === 'verified'
              ? VERIFICATION_MEANING[subject]
              : status === 'pending'
                ? 'This is in the Eduxfair review queue. Until it is reviewed, no badge is shown to students.'
                : status === 'rejected'
                  ? 'This did not pass review. Check the reviewer’s note and submit again.'
                  : 'Nothing has been verified yet. Students see listings either way — verification is what adds the badge.'}
          </p>
        </Dialog>
      )}
    </>
  );
}
