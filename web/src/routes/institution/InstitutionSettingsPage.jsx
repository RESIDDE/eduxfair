import { useState } from 'react';
import { BadgeCheck, Save, ShieldCheck } from 'lucide-react';
import {
  Alert,
  Button,
  Field,
  Input,
  Loading,
  Select,
  SurfaceCard,
  Textarea,
} from '../../components/ui';
import { VerifiedBadge } from '../../components/VerifiedBadge';
import { useAuth } from '../../context/AuthContext';
import { describeError, supabase } from '../../lib/supabase';
import { COUNTRIES, VERIFICATION_MEANING } from '../../lib/vocab';

export default function InstitutionSettingsPage() {
  const { institution, institutionId, refresh } = useAuth();

  if (!institution) return <Loading />;

  return (
    <div className="flex flex-col gap-5 pb-4 max-w-[760px]">
      <DomainVerification institution={institution} onVerified={refresh} />
      <ListingForm
        institution={institution}
        institutionId={institutionId}
        onSaved={refresh}
      />
    </div>
  );
}

/**
 * Domain verification — what earns the verified badge.
 *
 * Two steps through the `verify-institution-domain` Edge Function: it emails a
 * code to an address on the institution's own domain, then checks it. The code
 * is stored hashed in a table with no RLS policies at all, so staff cannot read
 * their own code and skip the email.
 */
function DomainVerification({ institution, onVerified }) {
  const [step, setStep] = useState('idle');
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);

  const isVerified = institution.verification_status === 'verified';

  async function sendCode(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);

    const { data, error: fnError } = await supabase.functions.invoke(
      'verify-institution-domain',
      { body: { institution_id: institution.id, email } },
    );

    setBusy(false);

    if (fnError || data?.error) {
      setError(data?.error ?? describeError(fnError) ?? 'Could not send the code.');
      return;
    }

    setStep('code');
    setNotice(
      data?.sent
        ? `We sent a code to ${email}. It expires in ${data.expires_in_minutes} minutes.`
        : 'The code was created but the email could not be sent. Contact Eduxfair support.',
    );
  }

  async function confirmCode(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { data, error: fnError } = await supabase.functions.invoke(
      'verify-institution-domain',
      { body: { institution_id: institution.id, code } },
    );

    setBusy(false);

    if (fnError || data?.error) {
      setError(data?.error ?? describeError(fnError) ?? 'That code was not accepted.');
      return;
    }

    setStep('idle');
    setNotice('Verified. Your badge is now showing to students.');
    onVerified();
  }

  return (
    <SurfaceCard className="p-6">
      <div className="flex items-start gap-4">
        <div className="size-11 rounded-tile bg-success-bg grid place-items-center shrink-0">
          <ShieldCheck size={21} className="text-success" strokeWidth={2.1} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-3 flex-wrap">
            <h2 className="font-bold text-[16px]">Domain verification</h2>
            <VerifiedBadge
              subject="institution"
              status={institution.verification_status}
            />
          </div>
          <p className="mt-2 text-[13px] text-muted leading-relaxed">
            {VERIFICATION_MEANING.institution}
          </p>

          {error && (
            <div className="mt-4">
              <Alert tone="error">{error}</Alert>
            </div>
          )}
          {notice && (
            <div className="mt-4">
              <Alert tone="success">{notice}</Alert>
            </div>
          )}

          {isVerified ? (
            <div className="mt-4 flex items-center gap-2 text-[13px] text-success">
              <BadgeCheck size={15} strokeWidth={2.4} />
              Verified on {institution.email_domain}
            </div>
          ) : step === 'code' ? (
            <form onSubmit={confirmCode} className="mt-5 flex items-end gap-3">
              <Field label="6-digit code" className="w-[180px]">
                <Input
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder="123456"
                  inputMode="numeric"
                  maxLength={6}
                  required
                />
              </Field>
              <Button type="submit" loading={busy}>
                Verify
              </Button>
              <Button variant="ghost" type="button" onClick={() => setStep('idle')}>
                Start over
              </Button>
            </form>
          ) : (
            <form onSubmit={sendCode} className="mt-5 flex items-end gap-3 flex-wrap">
              <Field
                label="An email address on your domain"
                hint={
                  institution.email_domain
                    ? `Must be @${institution.email_domain}`
                    : 'Add your domain below first.'
                }
                className="flex-1 min-w-[260px]"
              >
                <Input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder={`admissions@${institution.email_domain ?? 'your-domain.edu'}`}
                  required
                />
              </Field>
              <Button type="submit" loading={busy} disabled={!institution.email_domain}>
                Send code
              </Button>
            </form>
          )}
        </div>
      </div>
    </SurfaceCard>
  );
}

function ListingForm({ institution, institutionId, onSaved }) {
  const [form, setForm] = useState({
    name: institution.name ?? '',
    country: institution.country ?? '',
    city: institution.city ?? '',
    website: institution.website ?? '',
    email_domain: institution.email_domain ?? '',
    description: institution.description ?? '',
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [saved, setSaved] = useState(false);

  const set = (key) => (event) =>
    setForm((prev) => ({ ...prev, [key]: event.target.value }));

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);

    const { error: writeError } = await supabase
      .from('institutions')
      .update({
        name: form.name.trim(),
        country: form.country,
        city: form.city || null,
        website: form.website || null,
        // The CHECK constraint requires a bare domain.
        email_domain: form.email_domain
          ? form.email_domain.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/.*$/, '')
          : null,
        description: form.description || null,
      })
      .eq('id', institutionId);

    setBusy(false);

    if (writeError) {
      setError(describeError(writeError));
      return;
    }
    setSaved(true);
    onSaved();
  }

  return (
    <SurfaceCard className="p-6">
      <form onSubmit={handleSubmit}>
        <h2 className="font-bold text-[16px]">Your listing</h2>
        <p className="mt-1.5 text-[13px] text-muted">This is what students see.</p>

        {error && (
          <div className="mt-4">
            <Alert tone="error">{error}</Alert>
          </div>
        )}
        {saved && (
          <div className="mt-4">
            <Alert tone="success">Saved.</Alert>
          </div>
        )}

        <div className="mt-5 flex flex-col gap-4">
          <Field label="Institution name">
            <Input value={form.name} onChange={set('name')} required />
          </Field>

          <div className="grid grid-cols-2 gap-4">
            <Field label="Country">
              <Select value={form.country} onChange={set('country')} required>
                <option value="">Choose…</option>
                {Object.entries(COUNTRIES).map(([code, name]) => (
                  <option key={code} value={code}>
                    {name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="City">
              <Input value={form.city} onChange={set('city')} />
            </Field>
          </div>

          <Field label="Website">
            <Input type="url" value={form.website} onChange={set('website')} />
          </Field>

          <Field
            label="Email domain"
            hint="Bare domain only, e.g. maplecrest.ca — no https:// or path."
          >
            <Input value={form.email_domain} onChange={set('email_domain')} />
          </Field>

          <Field label="About">
            <Textarea rows={5} value={form.description} onChange={set('description')} />
          </Field>

          <Button type="submit" loading={busy} icon={Save} className="w-fit">
            Save changes
          </Button>
        </div>
      </form>
    </SurfaceCard>
  );
}
