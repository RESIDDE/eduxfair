import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { GraduationCap } from 'lucide-react';
import { Alert, Button, Field, Input, Select, Textarea } from '../../components/ui';
import { useAuth } from '../../context/AuthContext';
import { describeError, supabase } from '../../lib/supabase';
import { COUNTRIES } from '../../lib/vocab';

/**
 * Creates the institution listing for a new account.
 *
 * Goes through `create_institution()` rather than inserting directly: RLS
 * cannot let someone add a membership row for an institution they are not yet
 * a member of, so the function creates the listing, makes the caller its owner,
 * opens a basic subscription and queues the domain check — in one transaction.
 */
export default function OnboardInstitution() {
  const navigate = useNavigate();
  const { refresh, signOut } = useAuth();

  const [form, setForm] = useState({
    name: '',
    country: '',
    city: '',
    website: '',
    email_domain: '',
    description: '',
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const set = (key) => (event) =>
    setForm((prev) => ({ ...prev, [key]: event.target.value }));

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const { error: rpcError } = await supabase.rpc('create_institution', {
      p_name: form.name,
      p_country: form.country,
      p_website: form.website || null,
      // The CHECK constraint requires a bare domain, so strip anything pasted.
      p_email_domain: form.email_domain || null,
      p_city: form.city || null,
      p_description: form.description || null,
    });

    setBusy(false);

    if (rpcError) {
      setError(describeError(rpcError));
      return;
    }

    await refresh();
    navigate('/institution', { replace: true });
  }

  return (
    <div className="aurora h-full overflow-auto grid place-items-center px-6 py-10">
      <form onSubmit={handleSubmit} className="w-full max-w-[560px] animate-enter">
        <div className="size-12 rounded-tile gradient-accent grid place-items-center">
          <GraduationCap size={24} className="text-on-accent" strokeWidth={2.2} />
        </div>

        <h1 className="mt-6 text-[26px] font-bold leading-tight">
          Create your institution listing
        </h1>
        <p className="mt-2 text-muted leading-relaxed">
          This is what students see. You can add programs next, and verify your
          domain to get the verified badge.
        </p>

        {error && (
          <div className="mt-5">
            <Alert tone="error">{error}</Alert>
          </div>
        )}

        <div className="mt-7 flex flex-col gap-4">
          <Field label="Institution name">
            <Input
              value={form.name}
              onChange={set('name')}
              placeholder="Maplecrest University"
              required
            />
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
              <Input value={form.city} onChange={set('city')} placeholder="Toronto" />
            </Field>
          </div>

          <Field label="Website">
            <Input
              type="url"
              value={form.website}
              onChange={set('website')}
              placeholder="https://maplecrest.ca"
            />
          </Field>

          <Field
            label="Email domain"
            hint="Bare domain only, e.g. maplecrest.ca. This is what we check your staff email against for the verified badge."
          >
            <Input
              value={form.email_domain}
              onChange={set('email_domain')}
              placeholder="maplecrest.ca"
            />
          </Field>

          <Field label="About" hint="A few sentences students will read.">
            <Textarea
              rows={4}
              value={form.description}
              onChange={set('description')}
              placeholder="Research university with strong co-op placement in technology and engineering."
            />
          </Field>

          <Button type="submit" loading={busy} className="mt-2 w-full">
            Create listing
          </Button>
          <button
            type="button"
            onClick={signOut}
            className="text-[13px] text-muted hover:text-white cursor-pointer transition-colors"
          >
            Sign out
          </button>
        </div>
      </form>
    </div>
  );
}
