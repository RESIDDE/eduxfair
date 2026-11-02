import { supabase, describeError } from './supabase';

/*
 * The in-room protocol, and the only two calls that reach the server.
 *
 * ──────────────────────────────────────────────────────────────────────────
 *  THIS FILE HAS A TWIN:
 *  student_app/lib/features/meet/models/room_protocol.dart
 *
 *  Every constant below is part of a wire contract between the React console
 *  and the Flutter app. They talk to each other through LiveKit, which does no
 *  validation of its own, so a value that differs between the two does not
 *  error — it silently fails to arrive, or mutes the wrong person. Change one
 *  file and you must change the other.
 * ──────────────────────────────────────────────────────────────────────────
 *
 * Identities are minted ONLY by the `livekit-token` Edge Function, never
 * constructed here:
 *
 *   space        sp_<space_participants.id>
 *   appointment  ap_<appointments.id>_s   (student)
 *                ap_<appointments.id>_h   (host)
 *
 * RoomService compares identities byte for byte, so parsing them is fine and
 * building them is not.
 */

/** The protocol version, carried in room metadata and every data payload. */
export const PROTOCOL_VERSION = 1;

/**
 * Participant attributes: server-stored, and synced to anyone who joins later.
 *
 * Three of these are set inside the signed token, which is what makes them
 * unforgeable — a client cannot claim to be a host by writing its own metadata.
 * Only `hand` is client-written. Authority is server-set; intent is client-set.
 */
export const ATTR = {
  /** host | cohost | moderator | speaker | listener — server-asserted. */
  role: 'lk_role',
  /** space_participants.id — server-asserted. */
  participantId: 'pid',
  /** The public handle, without the @ — server-asserted. */
  handle: 'handle',
  /** '' when down, or an ISO-8601 instant — written by the participant. */
  hand: 'hand',
};

/** Data-packet topics. One, deliberately: everything durable goes in Postgres. */
export const TOPIC = {
  reaction: 'reaction',
  /**
   * LiveKit refuses remote UNmute unless the deployment sets
   * `enable_remote_unmute`, so a host cannot simply turn someone's mic back
   * on. Asking is a packet; muting is a server call.
   */
  askUnmute: 'ask_unmute',
};

/**
 * The roles that may moderate, in agreement with space_can_moderate() in SQL.
 *
 * `moderator` is an attendee the host appointed, NOT staff: they hold the same
 * mute and remove buttons and none of the institution's visibility, so nothing
 * that reveals who somebody is may key off this list.
 */
export const MODERATOR_ROLES = ['host', 'cohost', 'moderator'];

/** Staff of the hosting institution. Appointing a moderator is theirs alone. */
export const STAFF_ROLES = ['host', 'cohost'];

/**
 * The six reactions, fixed.
 *
 * An open emoji field is an open text field, and these rooms can have minors in
 * them. Validated on RECEIVE as well as on send, because a malicious client can
 * publish whatever it likes.
 */
export const REACTIONS = ['👏', '❤️', '😂', '😮', '🎉', '👍'];

/** Reactions per participant, beyond which packets are dropped. */
const REACTION_LIMIT = { count: 3, windowMs: 2000 };

/** Hand-raise is an attribute, and attributes are not for sub-second updates. */
export const HAND_DEBOUNCE_MS = 1000;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function encodeReaction(emoji, participantId) {
  return encoder.encode(JSON.stringify({
    v: PROTOCOL_VERSION,
    t: 'reaction',
    emoji,
    pid: participantId ?? '',
    at: Date.now(),
  }));
}

/** Decodes a received packet, or null if it is anything we did not agree on. */
export function decodeReaction(payload) {
  try {
    const msg = JSON.parse(decoder.decode(payload));
    if (msg.v !== PROTOCOL_VERSION || msg.t !== 'reaction') return null;
    if (!REACTIONS.includes(msg.emoji)) return null;
    return msg;
  } catch {
    // An unknown or malformed packet is dropped without logging: a misbehaving
    // client is not worth a console line per packet.
    return null;
  }
}

export function encodeAskUnmute() {
  return encoder.encode(JSON.stringify({ v: PROTOCOL_VERSION, t: 'ask_unmute' }));
}

/** A per-sender rate limiter for inbound reactions. */
export function makeReactionLimiter() {
  const seen = new Map();
  return (identity) => {
    const now = Date.now();
    const recent = (seen.get(identity) ?? []).filter((t) => now - t < REACTION_LIMIT.windowMs);
    if (recent.length >= REACTION_LIMIT.count) return false;
    recent.push(now);
    seen.set(identity, recent);
    return true;
  };
}

export const roleOf = (p) => p?.attributes?.[ATTR.role] ?? 'listener';
export const handRaisedAt = (p) => p?.attributes?.[ATTR.hand] || null;
export const participantIdOf = (p) => p?.attributes?.[ATTR.participantId] || null;
export const canModerate = (role) => MODERATOR_ROLES.includes(role);
export const isStaff = (role) => STAFF_ROLES.includes(role);

/** Room metadata, as livekit-room writes it on go_live. */
export function parseRoomMetadata(raw) {
  try {
    const meta = JSON.parse(raw || '{}');
    return meta.v === PROTOCOL_VERSION ? meta : null;
  } catch {
    return null;
  }
}

// ── The server ─────────────────────────────────────────────────────────────

/**
 * Asks for a join token.
 *
 * Returns the grant whatever the answer is: `admission` is 'admitted',
 * 'pending' (waiting to be let in) or 'closed' (outside the window), and only
 * the first carries a token. The URL comes back with it, so there is no
 * VITE_LIVEKIT_URL to drift out of step with the server signing the tokens.
 */
export async function fetchToken({ spaceId, appointmentId }) {
  const { data, error } = await supabase.functions.invoke('livekit-token', {
    body: spaceId ? { space_id: spaceId } : { appointment_id: appointmentId },
  });
  // A non-2xx arrives as `error`, but the function also returns 200 with an
  // `error` string when LiveKit is not configured — both are a sentence to
  // show, not a crash.
  if (error) throw new Error(await readFunctionError(error));
  if (data?.error && !data.token) throw new Error(data.error);
  return data;
}

/** Every privileged room operation. The UI never calls LiveKit for these. */
export async function roomAction(action, payload = {}) {
  const { data, error } = await supabase.functions.invoke('livekit-room', {
    body: { action, ...payload },
  });
  if (error) throw new Error(await readFunctionError(error));
  if (data?.error && data.ok !== true) throw new Error(data.error);
  return data;
}

/**
 * supabase-js wraps a non-2xx in a FunctionsHttpError whose message is just
 * "Edge Function returned a non-2xx status code". The body holds the sentence
 * the function actually wrote, which is the one worth showing.
 */
async function readFunctionError(error) {
  try {
    const body = await error.context?.json?.();
    if (body?.error) return body.error;
  } catch {
    /* fall through to the generic message */
  }
  return describeError(error) ?? error.message ?? 'Could not reach the room.';
}

/*
 * `connectRoom` deliberately lives in useLiveRoom.js, not here.
 *
 * livekit-client is ~850 KB of WebRTC machinery. This module is imported by
 * SpacesPage, which only needs the protocol constants and the two Edge Function
 * calls — so keeping every `livekit-client` import on the far side of the lazy
 * boundary is what stops a console that is mostly tables from shipping a media
 * stack to every page view.
 */
