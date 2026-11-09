// Deletes an account, and everything in it.
//
// App Review guideline 5.1.1(v): "If your app supports account creation, you
// must also offer account deletion within the app." Apple's own reference
// page is explicit that this means the *entire account record* along with the
// personal data and the user-generated content attached to it — offering only
// to deactivate is not enough, and neither is directing people to email
// support.
//
//   POST { confirm: "DELETE" }  -> removes the caller's account
//
// Runs as the service role because deleting from auth.users is privileged.
// The caller's own JWT still decides *whose* account goes: `requireUser`
// resolves the subject, and nothing in the body can name a different one.
//
// Storage objects are removed before the database rows, because the rows are
// what tell us which objects exist. The other way round leaves orphans no one
// can find.

import { adminClient, json, preflight, requireUser } from '../_shared/deps.ts';

/** Buckets holding things a student owns, and the column naming the path. */
const OWNED_FILES: Array<{ bucket: string; table: string; column: string; owner: string }> = [
  { bucket: 'passport-docs', table: 'passport_documents', column: 'storage_path', owner: 'profile_id' },
  { bucket: 'post-media', table: 'post_media', column: 'storage_path', owner: 'author_id' },
  { bucket: 'message-attachments', table: 'message_attachments', column: 'storage_path', owner: 'sender_id' },
];

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const user = await requireUser(req);
  if (!user) return json({ error: 'authentication required' }, 401);

  let body: { confirm?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid request body' }, 400);
  }

  // A deliberate, typed confirmation. The screen asks for it too, but a
  // destructive endpoint should not be reachable by an accidental POST.
  if (body.confirm !== 'DELETE') {
    return json({ error: 'confirmation required' }, 400);
  }

  const admin = adminClient();
  const uid = user.id;

  // ── 1. Storage ─────────────────────────────────────────────────────────
  // Avatars are keyed by the user id, so they can be listed directly.
  try {
    const { data: avatars } = await admin.storage.from('avatars').list(uid);
    if (avatars?.length) {
      await admin.storage
        .from('avatars')
        .remove(avatars.map((f) => `${uid}/${f.name}`));
    }
  } catch (_) {
    // A storage failure must not strand the account half-deleted. The row
    // deletion below is what the guideline is actually about; orphaned bytes
    // are a cleanup job, not a reason to refuse.
  }

  for (const spec of OWNED_FILES) {
    try {
      const { data: rows } = await admin
        .from(spec.table)
        .select(spec.column)
        .eq(spec.owner, uid);
      const paths = (rows ?? [])
        .map((r: Record<string, unknown>) => r[spec.column] as string)
        .filter(Boolean);
      if (paths.length) {
        await admin.storage.from(spec.bucket).remove(paths);
      }
    } catch (_) {
      // Same reasoning as above.
    }
  }

  // ── 2. Rows ────────────────────────────────────────────────────────────
  // One transaction in the database rather than a cascade of calls from
  // here, so a half-finished delete cannot be left behind by a dropped
  // connection. The function is SECURITY DEFINER and takes the id it is
  // given, which is why only the service role may execute it.
  const { error: purgeError } = await admin.rpc('purge_account', {
    p_profile_id: uid,
  });
  if (purgeError) {
    return json({ error: `could not delete account data: ${purgeError.message}` }, 500);
  }

  // ── 3. The login itself ────────────────────────────────────────────────
  // Last, so a failure above leaves an account its owner can still sign in
  // to and retry, rather than data with no way to reach it.
  const { error: authError } = await admin.auth.admin.deleteUser(uid);
  if (authError) {
    return json({ error: `could not delete sign-in: ${authError.message}` }, 500);
  }

  return json({ deleted: true });
});
