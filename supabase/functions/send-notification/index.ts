// Writes a notification row and, where it warrants an email, sends one.
//
// Called from the clients for the handful of events that genuinely need to
// reach someone who is not currently looking at the app: an institution
// inviting a student, an appointment being confirmed, a pipeline decision.
//
// It runs on the service-role key because the sender is usually NOT the
// recipient — an institution notifies a student — which no RLS insert policy
// should ever allow directly. So authorization is explicit here: the caller
// must have a real relationship with the recipient, checked per kind.

import { adminClient, json, preflight, requireUser, sendEmail } from '../_shared/deps.ts';

type Kind =
  // NOTE: for invites and access requests, prefer the database functions
  // `institution_invite_student` / `institution_request_access` — they record
  // the interest and notify in one transaction, keyed on the match token, so an
  // invite cannot end up recorded but unannounced.
  | 'institution_invited_you'
  | 'institution_requested_access'
  | 'appointment_requested'
  | 'appointment_confirmed'
  | 'appointment_declined'
  | 'application_stage_changed'
  | 'documents_requested'
  | 'passport_verified'
  | 'new_message'
  | 'space_scheduled'
  | 'space_starting';

/** Whether each kind also deserves an email, and how it should read. */
const TEMPLATES: Record<Kind, { email: boolean; subject: (t: string) => string }> = {
  institution_invited_you:      { email: true, subject: (t) => t },
  institution_requested_access: { email: true, subject: (t) => t },
  appointment_requested:     { email: true,  subject: (t) => t },
  appointment_confirmed:     { email: true,  subject: (t) => t },
  appointment_declined:      { email: true,  subject: (t) => t },
  application_stage_changed: { email: true,  subject: (t) => t },
  documents_requested:       { email: true,  subject: (t) => t },
  passport_verified:         { email: true,  subject: (t) => t },
  // In-app only. Emailing every chat message is how a product teaches people
  // to filter its mail.
  new_message:               { email: false, subject: (t) => t },
  // In-app only, for the reason above and one more: there is no scheduler in
  // this project, so a "starting in ten minutes" email has nothing to send it.
  space_scheduled:           { email: false, subject: (t) => t },
  space_starting:            { email: false, subject: (t) => t },
};

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const user = await requireUser(req);
  if (!user) return json({ error: 'authentication required' }, 401);

  let body: {
    recipient_id?: string;
    kind?: Kind;
    title?: string;
    message?: string;
    payload?: Record<string, unknown>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const { recipient_id: recipientId, kind, title } = body;
  if (!recipientId || !kind || !title) {
    return json({ error: 'recipient_id, kind and title are required' }, 400);
  }
  if (!(kind in TEMPLATES)) {
    return json({ error: `unknown notification kind: ${kind}` }, 400);
  }

  const db = adminClient();

  const { data: profile } = await db
    .from('profiles').select('role').eq('id', user.id).single();
  const isAdmin = profile?.role === 'admin';

  // ------------------------------------------------------- authorization
  // The caller must already be connected to the recipient. Without this the
  // function would be an open relay for messaging any user on the platform.
  let allowed = isAdmin || recipientId === user.id;

  if (!allowed) {
    const { data: institutions } = await db
      .from('institution_members').select('institution_id').eq('profile_id', user.id);
    const institutionIds = (institutions ?? []).map((m) => m.institution_id);

    if (institutionIds.length > 0) {
      // A relationship is any of: the student shared their passport with us,
      // applied to us, booked with us, or is in a thread with us.
      const checks = await Promise.all([
        db.from('passport_shares').select('id')
          .eq('profile_id', recipientId).in('institution_id', institutionIds)
          .is('revoked_at', null).limit(1),
        db.from('applications').select('id')
          .eq('profile_id', recipientId).in('institution_id', institutionIds).limit(1),
        db.from('appointments').select('id')
          .eq('student_id', recipientId).in('institution_id', institutionIds).limit(1),
        db.from('conversations').select('id')
          .eq('student_id', recipientId).in('institution_id', institutionIds).limit(1),
        // Reverse admission: we may have matched a student we cannot yet
        // identify. A token issued to us for them is the proof of that
        // relationship — and the only handle we are supposed to have.
        db.from('match_tokens').select('token')
          .eq('student_id', recipientId)
          .in('institution_id', institutionIds).limit(1),
      ]);
      allowed = checks.some((c) => (c.data ?? []).length > 0);
    }
  }

  if (!allowed) {
    return json({ error: 'no relationship with that recipient' }, 403);
  }

  // ---------------------------------------------------------- the write
  const { data: notification, error } = await db
    .from('notifications')
    .insert({
      profile_id: recipientId,
      kind,
      title,
      body: body.message ?? null,
      payload: body.payload ?? {},
    })
    .select('id')
    .single();

  if (error) {
    console.error('could not write the notification:', error);
    return json({ error: error.message }, 500);
  }

  // ------------------------------------------------------------- email
  const template = TEMPLATES[kind];
  let emailed = false;

  if (template.email) {
    const { data: recipient } = await db.auth.admin.getUserById(recipientId);
    const address = recipient?.user?.email;

    if (address) {
      const result = await sendEmail({
        to: address,
        subject: template.subject(title),
        html: `
          <p>${title}</p>
          ${body.message ? `<p>${body.message}</p>` : ''}
          <p><a href="${Deno.env.get('APP_URL') ?? 'https://connect.lekkside.com'}">
            Open Lekkside Connect</a></p>
        `,
      });
      emailed = result.ok;
    }
  }

  return json({ id: notification.id, emailed });
});
