// Mints a LiveKit join token for a Space or a 1:1 appointment.
//
// Scope one of: { space_id } | { appointment_id }
//
// This function makes NO authorization decision of its own. It calls
// `space_room_grant` / `appointment_room_grant` through callerClient(), so the
// question "may this person join, and as what" is answered by SQL running under
// the caller's own RLS — which is the same code supabase/tests/rls_test.mjs
// asserts against. Re-deriving those rules in TypeScript would mean two
// answers that can disagree, and only one of them is tested.
//
// Which is why adminClient() appears nowhere in this file, or in livekit-room.
// Nothing is written that the caller is not already allowed to cause. The only
// privileged material is the LiveKit secret, and that never touches the
// database.

import { json, preflight, requireUser, callerClient } from '../_shared/deps.ts';
import {
  livekitConfig,
  mintToken,
  NOT_CONFIGURED,
  type RoomGrant,
} from '../_shared/livekit.ts';

// A token mint is cheap for us and expensive for whoever is paying for the
// media, so there is a ceiling. Per-isolate rather than in Postgres: it is a
// speed bump against a loop, not a security control — the grant functions are
// that.
const MINTS = new Map<string, number[]>();
const WINDOW_MS = 60_000;
const MAX_PER_WINDOW = 60;

function overRateLimit(userId: string): boolean {
  const now = Date.now();
  const recent = (MINTS.get(userId) ?? []).filter((t) => now - t < WINDOW_MS);
  recent.push(now);
  MINTS.set(userId, recent);
  return recent.length > MAX_PER_WINDOW;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;

  const user = await requireUser(req);
  if (!user) return json({ error: 'authentication required' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const spaceId = typeof body.space_id === 'string' ? body.space_id : null;
  const apptId = typeof body.appointment_id === 'string' ? body.appointment_id : null;

  // Exactly one. Both would be ambiguous and neither is a mistake worth
  // guessing at, and the room-name prefixes only keep the two namespaces apart
  // if the caller has said which one it means.
  if (!spaceId === !apptId) {
    return json({ error: 'pass exactly one of space_id or appointment_id' }, 400);
  }

  // Checked BEFORE the RPC. space_room_grant() joins the caller as a side
  // effect, and minting a participant row for a call that cannot happen is
  // worse than a truthful refusal.
  const cfg = livekitConfig();
  if (!cfg) return json({ error: NOT_CONFIGURED }, 503);

  const db = callerClient(req);

  const { data, error } = spaceId
    ? await db.rpc('space_room_grant', { p_space_id: spaceId })
    : await db.rpc('appointment_room_grant', { p_appointment_id: apptId });

  if (error) {
    // The grant functions raise readable messages on purpose ('A host removed
    // you from this session.'), so they are passed through rather than
    // flattened into "forbidden".
    console.error('livekit-token refused:', error.message);
    return json({ error: error.message }, 403);
  }

  const grant = data as RoomGrant;

  // 'closed' (outside the window) and 'pending' (waiting to be admitted) are
  // both normal states with nothing to sign, and the client renders a different
  // screen for each. A 200 with no token, not an error.
  if (grant.admission !== 'admitted') return json(grant);

  if (overRateLimit(user.id)) {
    return json({ error: 'too many join attempts — wait a minute and try again' }, 429);
  }

  try {
    const { token, expires_in } = await mintToken(cfg, grant);
    return json({ ...grant, url: cfg.url, token, expires_in });
  } catch (err) {
    console.error('livekit-token could not sign:', err);
    return json({ error: (err as Error).message }, 500);
  }
});
