import { useState } from 'react';
import { ShieldCheck } from 'lucide-react';
import { Alert, Button, Dialog } from '../ui';

/**
 * The one consent step in the whole feature.
 *
 * Shown before a listener's first mic, camera, hand or message. The wording is
 * the same sentence the Flutter app uses, and the last line is true because
 * `grant_passport_share` writes an ordinary revocable share — the same row
 * applying, booking and a booth scan produce. Saying so is what makes asking
 * acceptable.
 */
export function IdentifyDialog({ institution, onConfirm, onClose }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  return (
    <Dialog
      title="Share your passport to speak?"
      eyebrow={institution}
      onClose={onClose}
      width="max-w-[460px]"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>Keep listening</Button>
          <Button
            icon={ShieldCheck}
            loading={busy}
            onClick={async () => {
              setBusy(true);
              setError(null);
              try {
                await onConfirm();
              } catch (err) {
                setError(err.message);
              } finally {
                setBusy(false);
              }
            }}
          >
            Share and speak
          </Button>
        </>
      }
    >
      <p className="text-[14px] leading-relaxed text-muted">
        Speaking here shares your Education Passport with{' '}
        <span className="font-semibold text-white">{institution}</span>, so they will
        see your name and verified documents. You can take that back any time in
        Passport → Sharing.
      </p>
      <p className="text-[13px] leading-relaxed text-subtle">
        Until you do, you are only <span className="text-white">@your handle</span> in
        this room, and nobody can hear or see you.
      </p>
      {error && <Alert tone="error">{error}</Alert>}
    </Dialog>
  );
}
