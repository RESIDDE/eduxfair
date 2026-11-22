// Account deletion on the web.
//
// The in-app flow (Settings → Delete account) stays the primary path, because
// App Review 5.1.1(v) requires deletion to be startable inside the app. This
// page exists for everyone the app cannot reach — someone who has already
// uninstalled it — and it is the "delete account URL" Google Play requires in
// the Data safety form.
//
// It mirrors student_app/lib/features/account/screens/delete_account_screen.dart
// step for step and calls the same `delete-account` Edge Function, so there
// is one deletion and two doors to it. Signing in here is the
// re-authentication: the password proves it is the owner, not merely someone
// with the browser.

import { useEffect, useState } from 'react';
import { AlertTriangle, ArrowLeft, Building2, Check, Loader2, Lock, Mail, Trash2 } from 'lucide-react';
import Nav from '../components/Nav';
import Footer from '../components/Footer';
import { supabase, supabaseConfigured } from '../lib/supabase';
import { SITE } from '../lib/site';

const PHRASE = 'DELETE';

const STUDENT_REMOVES = [
  'Your Education Passport, including every document you uploaded',
  'Your profile, handle, bio and photo',
  'Your posts, comments, likes and saved items',
  'Your messages, and your place in any conversation',
  'Every institution’s access to you',
  'Your applications and meeting history',
];

const STAFF_REMOVES = [
  'Your profile, name and photo',
  'Posts you wrote, including ones published for your institution',
  'Messages you wrote in your institution’s conversations',
  'Your place on your institution’s team',
];

const KEPT = [
  'Records we have to keep by law, such as accounting records',
  'Any safety report you filed about someone else. The report stays, with your name removed from it, so that deleting an account cannot be used to withdraw it',
];

// Deleting some data without deleting the account — the "delete data URL" in
// Google Play's Data safety form points at #delete-some-data. Each path is the
// label the student app shows; keep them in step with student_app.
const PARTIAL = [
  ['A post', 'Tap ⋯ on your post, then Delete.'],
  ['A comment', 'Open the post, tap ⋯ next to your comment, then Delete comment.'],
  ['A message', 'Press and hold the message. Delete for me removes it from your view; Delete for everyone, on your own messages, removes it for both sides.'],
  ['A document', 'Settings → Documents, then tap the bin next to the document.'],
  ['Your profile photo', 'Settings → tap your photo → Remove photo.'],
  ['Passport details', 'Settings → Education Passport, then edit or clear any field.'],
  ['An institution’s access to you', 'Settings → Who can see me → Revoke. They stop seeing your name, contact details and documents.'],
  ['Saved items and follows', 'Settings → Saved, or Settings → Followers & Following.'],
];

const plural = (n, one, many) => (n === 1 ? `1 ${one}` : `${n} ${many}`);

function describe(error) {
  const msg = (error?.message ?? String(error ?? '')).toLowerCase();
  if (msg.includes('invalid login') || msg.includes('credential')) return 'That email and password do not match an account.';
  if (msg.includes('email not confirmed')) return 'This email address has not been verified yet. Open the app to finish signing up, or contact support.';
  if (msg.includes('failed to fetch') || msg.includes('network')) return 'We could not reach EduXFair. Check your connection and try again.';
  return error?.message || 'Something went wrong. Nothing has been removed.';
}

function Bullet({ children, tone = 'danger' }) {
  return (
    <li className="flex gap-3 text-[16px] leading-relaxed text-[#424245]">
      <span className={`mt-[0.6em] h-1.5 w-1.5 shrink-0 rounded-full ${tone === 'danger' ? 'bg-[#e0262f]' : 'bg-mute'}`} />
      <span>{children}</span>
    </li>
  );
}

function Field({ label, ...props }) {
  return (
    <label className="block">
      <span className="text-[14px] font-medium text-text">{label}</span>
      <input
        {...props}
        className="mt-2 block h-12 w-full rounded-xl border border-line bg-white px-4 text-[16px] text-text outline-none transition-shadow placeholder:text-mute focus:border-brand focus:ring-4 focus:ring-brand/15"
      />
    </label>
  );
}

function ErrorBox({ children }) {
  return (
    <div role="alert" className="flex items-start gap-2.5 rounded-xl bg-[#fdecee] p-3.5 text-[14px] leading-relaxed text-[#c41e27]">
      <AlertTriangle size={17} className="mt-0.5 shrink-0" />
      <span>{children}</span>
    </div>
  );
}

function InstitutionImpact({ impact }) {
  const removes = impact.removes_institution === true;
  const others = Number(impact.other_members ?? 0);
  const apps = Number(impact.applications ?? 0);
  const convs = Number(impact.conversations ?? 0);
  const name = impact.name || 'Your institution';
  return (
    <div className={`rounded-2xl p-4 ${removes ? 'bg-[#fdecee]' : 'bg-cloud'}`}>
      <p className={`flex items-center gap-2 text-[15px] font-semibold ${removes ? 'text-[#c41e27]' : 'text-text'}`}>
        {removes ? <AlertTriangle size={17} /> : <Building2 size={17} className="text-mute-2" />}
        {removes ? `${name} will be deleted too` : `${name} stays`}
      </p>
      <p className="mt-1.5 text-[14px] leading-relaxed text-[#424245]">
        {removes
          ? `You are its only team member, so its page, programmes, posts and prospectus are removed with you, along with ${plural(apps, 'application', 'applications')} and ${plural(convs, 'conversation', 'conversations')} with students. To keep it, add a colleague in the app from More → Team before you delete your account.`
          : `${plural(others, 'colleague', 'colleagues')} ${others === 1 ? 'keeps' : 'keep'} running it, and its page, applications and conversations are unaffected.${
              impact.hands_over_ownership ? ' You are its only owner, so ownership passes to the longest-serving colleague.' : ''
            }`}
      </p>
    </div>
  );
}

/* ── Step 1: sign in ─────────────────────────────────────────────────── */
function SignIn({ onSignedIn }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });
      if (authError) throw authError;

      const user = data.user;
      const { data: profile } = await supabase
        .from('profiles')
        .select('role, full_name')
        .eq('id', user.id)
        .maybeSingle();
      const role = profile?.role ?? 'student';
      const isStaff = role !== 'student';

      let impact = [];
      if (isStaff) {
        const { data: rows } = await supabase.rpc('my_deletion_impact');
        impact = Array.isArray(rows) ? rows : [];
      }
      onSignedIn({ email: user.email, name: profile?.full_name, isStaff, impact });
    } catch (err) {
      setError(describe(err));
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-5">
      <div>
        <h2 className="text-[24px] font-semibold tracking-[-0.025em] text-text">Sign in to continue</h2>
        <p className="mt-1.5 text-[15px] leading-relaxed text-mute-2">
          Use the email and password for the account you want to delete. Signing in here only
          confirms it is you. Nothing is deleted until the last step.
        </p>
      </div>
      <Field label="Email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" />
      <Field label="Password" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Your password" />
      {error && <ErrorBox>{error}</ErrorBox>}
      <button type="submit" disabled={busy} className="btn btn-brand h-12 w-full text-[16px] font-semibold disabled:opacity-60">
        {busy ? <Loader2 size={18} className="animate-spin" /> : <Lock size={17} />}
        {busy ? 'Checking…' : 'Continue'}
      </button>
      <p className="text-center text-[14px] text-mute-2">
        Forgot your password? Reset it from the sign-in screen in the app.
      </p>
    </form>
  );
}

/* ── Step 2: review and confirm ──────────────────────────────────────── */
function Confirm({ account, onDeleted, onCancel }) {
  const [phrase, setPhrase] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const ready = phrase.trim().toUpperCase() === PHRASE;

  const remove = async () => {
    setBusy(true);
    setError(null);
    try {
      const { data, error: fnError } = await supabase.functions.invoke('delete-account', {
        body: { confirm: PHRASE },
      });
      if (fnError) {
        // The function returns { error } with a non-2xx status; surface it.
        let message = fnError.message;
        try {
          const body = await fnError.context?.json?.();
          if (body?.error) message = body.error;
        } catch {
          /* keep the generic message */
        }
        throw new Error(message);
      }
      if (data?.deleted !== true) {
        throw new Error(data?.error || 'The account could not be deleted. Nothing has been removed.');
      }
      await supabase.auth.signOut().catch(() => {});
      onDeleted();
    } catch (err) {
      setError(describe(err));
      setBusy(false);
    }
  };

  return (
    <div className="space-y-7">
      <div className="flex items-center gap-3 rounded-2xl bg-cloud p-4">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-gradient-to-br from-brand to-navy text-[14px] font-bold text-white">
          {(account.name || account.email || '?').trim().charAt(0).toUpperCase()}
        </span>
        <div className="min-w-0">
          <p className="truncate text-[15px] font-semibold text-text">{account.name || 'Your account'}</p>
          <p className="truncate text-[14px] text-mute-2">{account.email}</p>
        </div>
        <button type="button" onClick={onCancel} disabled={busy} className="ml-auto shrink-0 text-[14px] text-brand hover:underline">
          Not you?
        </button>
      </div>

      <div>
        <h2 className="text-[24px] font-semibold tracking-[-0.025em] text-[#c41e27]">This cannot be undone.</h2>
        <p className="mt-4 text-[16px] font-medium text-text">Deleting your account removes:</p>
        <ul className="mt-3 space-y-2">
          {(account.isStaff ? STAFF_REMOVES : STUDENT_REMOVES).map((l) => (
            <Bullet key={l}>{l}</Bullet>
          ))}
        </ul>
      </div>

      {account.isStaff && account.impact.length > 0 && (
        <div className="space-y-3">
          {account.impact.map((i) => (
            <InstitutionImpact key={i.institution_id} impact={i} />
          ))}
        </div>
      )}

      <div>
        <p className="text-[16px] font-medium text-text">What stays:</p>
        <ul className="mt-3 space-y-2">
          {KEPT.map((l) => (
            <Bullet key={l} tone="muted">{l}</Bullet>
          ))}
        </ul>
      </div>

      <div className="space-y-4 border-t border-line pt-7">
        <Field
          label={`Type ${PHRASE} to confirm`}
          value={phrase}
          onChange={(e) => setPhrase(e.target.value)}
          placeholder={PHRASE}
          autoCapitalize="characters"
          autoComplete="off"
          spellCheck="false"
        />
        {error && <ErrorBox>{error}</ErrorBox>}
        <button
          type="button"
          onClick={remove}
          disabled={!ready || busy}
          className="btn h-12 w-full bg-[#e0262f] text-[16px] font-semibold text-white hover:bg-[#c41e27] disabled:cursor-not-allowed disabled:opacity-40"
        >
          {busy ? <Loader2 size={18} className="animate-spin" /> : <Trash2 size={17} />}
          {busy ? 'Deleting…' : 'Delete my account'}
        </button>
        <button type="button" onClick={onCancel} disabled={busy} className="block w-full py-2 text-center text-[15px] text-text hover:underline">
          Keep my account
        </button>
      </div>
    </div>
  );
}

/* ── Step 3: done ────────────────────────────────────────────────────── */
function Done() {
  return (
    <div className="py-6 text-center">
      <span className="mx-auto grid h-14 w-14 place-items-center rounded-full bg-[#def7ec] text-ok">
        <Check size={28} strokeWidth={2.6} />
      </span>
      <h2 className="mt-5 text-[26px] font-semibold tracking-[-0.025em] text-text">Your account has been deleted.</h2>
      <p className="mx-auto mt-3 max-w-[400px] text-[16px] leading-relaxed text-mute-2">
        Your passport, documents, messages and posts have been removed. If the app is still on your
        phone, it will sign you out the next time it opens.
      </p>
      <a href="/" className="btn btn-dark mt-7 h-11 px-5 text-[15px]">
        <ArrowLeft size={16} /> Back to EduXFair
      </a>
    </div>
  );
}

export default function DeleteAccount() {
  const [account, setAccount] = useState(null);
  const [deleted, setDeleted] = useState(false);

  // Leaving the page mid-flow should not leave a session behind.
  useEffect(() => () => void supabase?.auth.signOut().catch(() => {}), []);

  const cancel = async () => {
    await supabase?.auth.signOut().catch(() => {});
    setAccount(null);
  };

  return (
    <>
      <Nav />
      <main id="main">
        <header data-nav="dark" className="bg-black pt-36 pb-14 text-white md:pt-44 md:pb-16">
          <div className="container-x max-w-[880px]!">
            <p className="eyebrow">Account</p>
            <h1 className="display mt-4 text-[clamp(2.6rem,6.5vw,4.5rem)]">Delete your account</h1>
            <p className="lede mt-5 max-w-[36ch] text-white/60">
              Permanently remove your EduXFair account and everything in it. You can also do this in
              the app, from Settings → Delete account.
            </p>
          </div>
        </header>

        <section data-nav="light" className="bg-cloud py-14 md:py-20">
          <div className="container-x max-w-[880px]! grid gap-8 lg:grid-cols-[1fr_280px]">
            <div className="rounded-[28px] bg-white p-6 shadow-[0_1px_0_rgba(0,0,0,0.04)] md:p-9">
              {!supabaseConfigured ? (
                <div className="space-y-4">
                  <ErrorBox>Account deletion on the web is not available right now.</ErrorBox>
                  <p className="text-[15px] leading-relaxed text-mute-2">
                    You can delete your account straight away in the app, from Settings → Delete
                    account. If you no longer have the app, write to{' '}
                    <a className="text-brand hover:underline" href={`mailto:${SITE.supportEmail}?subject=Delete%20my%20account`}>
                      {SITE.supportEmail}
                    </a>{' '}
                    from the email address on the account.
                  </p>
                </div>
              ) : deleted ? (
                <Done />
              ) : account ? (
                <Confirm account={account} onCancel={cancel} onDeleted={() => setDeleted(true)} />
              ) : (
                <SignIn onSignedIn={setAccount} />
              )}
            </div>

            <aside className="space-y-5 text-[14px] leading-relaxed text-mute-2">
              <div>
                <p className="font-semibold text-text">Prefer the app?</p>
                <p className="mt-1">Open EduXFair, go to your profile, then Settings → Delete account. It does exactly the same thing.</p>
              </div>
              <div>
                <p className="font-semibold text-text">Only want to remove some things?</p>
                <p className="mt-1">
                  You can keep your account.{' '}
                  <a className="text-brand hover:underline" href="#delete-some-data">See how below.</a>
                </p>
              </div>
              <div>
                <p className="font-semibold text-text">What we keep</p>
                <p className="mt-1">
                  Only what the law requires, and safety reports you filed about others. The{' '}
                  <a className="text-brand hover:underline" href="/privacy/#how-long-we-keep-things">Privacy Policy</a> has the details.
                </p>
              </div>
              <div>
                <p className="font-semibold text-text">Need help?</p>
                <p className="mt-1">
                  <a className="inline-flex items-center gap-1.5 text-brand hover:underline" href={`mailto:${SITE.supportEmail}`}>
                    <Mail size={14} /> {SITE.supportEmail}
                  </a>
                </p>
              </div>
            </aside>
          </div>
        </section>

        <section id="delete-some-data" data-nav="light" className="scroll-mt-24 bg-white py-14 md:py-20">
          <div className="container-x max-w-[880px]!">
            <p className="eyebrow">Keep your account</p>
            <h2 className="mt-3 text-[clamp(1.75rem,4vw,2.4rem)] font-semibold tracking-[-0.025em] text-text">
              Delete some of your data
            </h2>
            <p className="mt-4 max-w-[60ch] text-[16px] leading-relaxed text-[#424245]">
              You do not have to delete your whole EduXFair account to remove something. Each of
              these is done in the app, takes effect straight away, and leaves the rest of your
              account as it is.
            </p>

            <dl className="mt-8 divide-y divide-line rounded-[28px] bg-cloud px-6 md:px-9">
              {PARTIAL.map(([what, how]) => (
                <div key={what} className="grid gap-1 py-5 md:grid-cols-[220px_1fr] md:gap-6">
                  <dt className="text-[16px] font-semibold text-text">{what}</dt>
                  <dd className="text-[16px] leading-relaxed text-[#424245]">{how}</dd>
                </div>
              ))}
            </dl>

            <p className="mt-8 max-w-[60ch] text-[15px] leading-relaxed text-mute-2">
              Anything you cannot remove yourself, write to{' '}
              <a className="text-brand hover:underline" href={`mailto:${SITE.supportEmail}?subject=Delete%20some%20of%20my%20data`}>
                {SITE.supportEmail}
              </a>{' '}
              from the email address on your account and tell us what to delete. We reply within 30
              days. What you delete is removed, apart from records the law requires us to keep and
              safety reports, as the{' '}
              <a className="text-brand hover:underline" href="/privacy/#how-long-we-keep-things">Privacy Policy</a> explains.
            </p>
          </div>
        </section>
      </main>
      <Footer />
    </>
  );
}
