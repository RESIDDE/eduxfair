// Confirms that someone controlling an address on an institution's own domain
// vouches for its listing. This is the entire basis of the VERIFIED
// INSTITUTION badge, so the badge means exactly this and nothing more — not
// accreditation, not quality, not a partnership.
//
//   POST { institution_id, email }   -> sends a 6-digit code to that address
//   POST { institution_id, code }    -> confirms and marks the institution verified
//
// The code is stored hashed in institution_domain_verifications, a table with
// RLS on and no policies, so institution staff cannot read their own code and
// skip the email.

import { adminClient, json, preflight, requireUser, sendEmail } from '../_shared/deps.ts';

const CODE_TTL_MINUTES = 30;
const MAX_ATTEMPTS = 5;

async function sha256(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function sixDigitCode(): string {
  // Rejection-free range: 0..899999 offset by 100000 keeps it uniform.
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return String(100000 + (buf[0] % 900000));
}

/** Bare, lowercase, no scheme or path — matching institutions.email_domain. */
function normalizeDomain(input: string): string {
  return input.trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/.*$/, '');
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const user = await requireUser(req);
  if (!user) return json({ error: 'authentication required' }, 401);

  let body: { institution_id?: string; email?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const institutionId = body.institution_id;
  if (!institutionId) return json({ error: 'institution_id is required' }, 400);

  const db = adminClient();

  // Only staff of that institution (or an admin) may drive its verification.
  const { data: member } = await db
    .from('institution_members')
    .select('id')
    .eq('profile_id', user.id)
    .eq('institution_id', institutionId)
    .maybeSingle();
  const { data: profile } = await db
    .from('profiles').select('role').eq('id', user.id).single();

  if (!member && profile?.role !== 'admin') {
    return json({ error: 'not your institution' }, 403);
  }

  const { data: institution, error: instErr } = await db
    .from('institutions')
    .select('id, name, email_domain, website, verification_status')
    .eq('id', institutionId)
    .single();
  if (instErr || !institution) return json({ error: 'institution not found' }, 404);

  // ------------------------------------------------------- step 2: confirm
  if (body.code) {
    const { data: pending } = await db
      .from('institution_domain_verifications')
      .select('*')
      .eq('institution_id', institutionId)
      .is('consumed_at', null)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!pending) return json({ error: 'no verification is in progress' }, 400);

    if (new Date(pending.expires_at) < new Date()) {
      return json({ error: 'that code has expired — request a new one' }, 400);
    }
    if (pending.attempts >= MAX_ATTEMPTS) {
      return json({ error: 'too many attempts — request a new code' }, 429);
    }

    const matches = (await sha256(body.code.trim())) === pending.token_hash;

    if (!matches) {
      await db
        .from('institution_domain_verifications')
        .update({ attempts: pending.attempts + 1 })
        .eq('id', pending.id);
      return json(
        { error: 'incorrect code', attempts_left: MAX_ATTEMPTS - pending.attempts - 1 },
        400,
      );
    }

    await db
      .from('institution_domain_verifications')
      .update({ consumed_at: new Date().toISOString() })
      .eq('id', pending.id);

    // Resolve the open queue entry. The verifications trigger propagates the
    // decision onto institutions.verification_status, so the badge and the
    // queue can never disagree.
    const { data: queued } = await db
      .from('verifications')
      .select('id')
      .eq('subject_type', 'institution')
      .eq('subject_id', institutionId)
      .eq('status', 'pending')
      .maybeSingle();

    const evidence = {
      method: 'domain_email',
      domain: pending.domain,
      email: pending.email,
      confirmed_at: new Date().toISOString(),
      // Stated plainly so nobody later mistakes the badge for more than it is.
      attests: 'control of an email address on the institution domain',
      does_not_attest: 'accreditation, programme quality, or partnership with Lekkside',
    };

    if (queued) {
      await db.from('verifications')
        .update({ status: 'verified', evidence, reviewer_id: null })
        .eq('id', queued.id);
    } else {
      await db.from('verifications').insert({
        subject_type: 'institution', subject_id: institutionId,
        status: 'pending', evidence,
      });
      await db.from('verifications')
        .update({ status: 'verified', evidence })
        .eq('subject_type', 'institution').eq('subject_id', institutionId)
        .eq('status', 'pending');
    }

    return json({ verified: true, domain: pending.domain });
  }

  // -------------------------------------------------------- step 1: send
  const requested = body.email?.trim().toLowerCase();
  if (!requested || !requested.includes('@')) {
    return json({ error: 'a valid email address is required' }, 400);
  }

  const emailDomain = requested.split('@')[1];
  // Prefer the stored domain; fall back to the website so a listing created
  // without email_domain can still start verification.
  const expected = normalizeDomain(
    institution.email_domain ?? institution.website ?? '',
  ).replace(/^www\./, '');

  if (!expected) {
    return json(
      { error: 'this institution has no domain on file — add a website first' },
      400,
    );
  }

  // Accept the domain itself or any subdomain of it (admissions.univ.ac.uk).
  const onDomain = emailDomain === expected || emailDomain.endsWith(`.${expected}`);
  if (!onDomain) {
    return json(
      { error: `the address must be on ${expected}, which is this institution's own domain` },
      400,
    );
  }

  const code = sixDigitCode();
  const { error: insertErr } = await db
    .from('institution_domain_verifications')
    .insert({
      institution_id: institutionId,
      email: requested,
      domain: expected,
      token_hash: await sha256(code),
      expires_at: new Date(Date.now() + CODE_TTL_MINUTES * 60_000).toISOString(),
    });
  if (insertErr) {
    console.error('could not store the verification token:', insertErr);
    return json({ error: 'could not start verification' }, 500);
  }

  const sent = await sendEmail({
    to: requested,
    subject: `Verify ${institution.name} on Lekkside Connect`,
    html: `
      <p>Hello,</p>
      <p>Someone is claiming the <strong>${institution.name}</strong> listing on
         Lekkside Connect. If that was you, your verification code is:</p>
      <p style="font-size:28px;letter-spacing:4px;font-weight:600">${code}</p>
      <p>It expires in ${CODE_TTL_MINUTES} minutes.</p>
      <p>Verifying confirms that someone with an
         <strong>@${expected}</strong> address vouches for this listing. It is not
         a claim about accreditation, and Lekkside does not assess programme
         quality.</p>
      <p>If this wasn't you, you can ignore this email and the claim will lapse.</p>
    `,
  });

  // The code is already stored, so a mail failure is recoverable by retrying
  // rather than something that should lose the attempt.
  return json({
    sent: sent.ok,
    email: requested,
    domain: expected,
    expires_in_minutes: CODE_TTL_MINUTES,
    ...(sent.ok ? {} : { warning: sent.detail }),
  });
});
