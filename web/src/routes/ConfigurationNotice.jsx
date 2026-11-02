import { Settings } from 'lucide-react';

/**
 * Shown when the Supabase env vars are missing, which is the most likely
 * first-run problem. Failing here with instructions beats a stack trace from
 * inside the client on the first query.
 */
export default function ConfigurationNotice() {
  return (
    <div className="aurora h-full grid place-items-center px-6">
      <div className="max-w-lg text-center">
        <Settings size={40} className="mx-auto text-accent" strokeWidth={1.6} />
        <h1 className="mt-5 text-2xl font-bold">Supabase is not configured</h1>
        <p className="mt-3 text-muted leading-relaxed">
          Copy <code className="text-accent-light">web/.env.example</code> to{' '}
          <code className="text-accent-light">web/.env.local</code>, fill in{' '}
          <code className="text-accent-light">VITE_SUPABASE_URL</code> and{' '}
          <code className="text-accent-light">VITE_SUPABASE_ANON_KEY</code>, then
          restart the dev server.
        </p>
      </div>
    </div>
  );
}
