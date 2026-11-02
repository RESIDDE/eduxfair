import { useState } from 'react';
import { ShieldCheck } from 'lucide-react';
import { Alert, Button, Field, Input } from '../components/ui';
import { useAuth } from '../context/AuthContext';
import { describeError } from '../lib/supabase';

/**
 * Sign-in for the super admin console. Sign-in only.
 *
 * There is deliberately no sign-up here. `handle_new_user()` clamps the role a
 * signup can request to student / institution_member / educator, so an account
 * created from this screen could never reach this console anyway — the form
 * would exist only to disappoint. An admin is made by an existing admin, from
 * the People page.
 *
 * Students and institutions sign up in the Lekkside Connect app; this build
 * serves neither.
 */
export default function SignInPage() {
  const { signIn } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  async function handleSubmit(event) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const authError = await signIn(email, password);

    setBusy(false);
    if (authError) setError(describeError(authError) ?? authError.message);
  }

  return (
    <div className="aurora h-full overflow-auto grid place-items-center px-6 py-10">
      <div className="w-full max-w-[420px] animate-enter">
        <div className="flex w-fit items-center gap-3">
          <img src="/logo.png" alt="Eduxfair logo" className="size-12 rounded-2xl shadow-sm object-contain bg-white p-1" />
          <div>
            <div className="text-lg font-bold leading-tight">Eduxfair</div>
            <div className="text-[13px] text-subtle">Super admin</div>
          </div>
        </div>

        <h1 className="mt-8 text-[26px] font-bold leading-tight">Sign in</h1>
        <p className="mt-2 leading-relaxed text-muted">
          Platform administration — verification, accounts, moderation and live
          sessions.
        </p>

        {error && (
          <div className="mt-5">
            <Alert tone="error">{error}</Alert>
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-7 flex flex-col gap-4">
          <Field label="Email">
            <Input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@eduxfair.com"
              autoComplete="email"
              required
            />
          </Field>
          <Field label="Password">
            <Input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Your password"
              autoComplete="current-password"
              required
            />
          </Field>

          <Button type="submit" loading={busy} className="mt-2 w-full">
            Sign in
          </Button>
        </form>

        <p className="mt-6 text-center text-[12.5px] leading-relaxed text-subtle">
          Students and institutions use the Eduxfair app, not this
          console. Admin accounts are created by an existing admin.
        </p>
      </div>
    </div>
  );
}
