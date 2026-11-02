// Shared LiveKit plumbing: configuration, token signing, and the room service.
//
// `npm:` rather than `jsr:` — livekit-server-sdk is not published to JSR, so
// this is the one dependency in the project that cannot follow the import style
// deps.ts sets. Pinned exactly, unlike supabase-js at `@2`: this module signs
// the tokens that decide who may speak in a room that can have minors in it,
// and a minor release is not something to take on trust.
import {
  AccessToken,
  RoomServiceClient,
  TrackSource,
  TrackType,
  type VideoGrant,
} from 'npm:livekit-server-sdk@2.19.2';

export type { VideoGrant };

// Re-exported so that nothing downstream has to hardcode a protobuf number.
// `TrackType.AUDIO` is 0 and `VIDEO` is 1 — not 1 and 2 — and a wrong guess
// does not fail, it mutes the wrong device.
export { TrackSource, TrackType };

/**
 * The grant functions name publish sources the way LiveKit's own documentation
 * does — 'microphone', 'camera', 'screen_share', 'screen_share_audio' — but the
 * SDK's `canPublishSources` takes its numeric TrackSource enum and converts it
 * back to those strings itself. Passing the strings through raises
 * "Cannot convert TrackSource microphone to string" at signing time, which is
 * invisible until something actually signs a token. So the SQL keeps the names
 * that match the documentation, and the mapping lives here, at the one boundary
 * that cares.
 */
const TRACK_SOURCES: Record<string, TrackSource> = {
  microphone: TrackSource.MICROPHONE,
  camera: TrackSource.CAMERA,
  screen_share: TrackSource.SCREEN_SHARE,
  screen_share_audio: TrackSource.SCREEN_SHARE_AUDIO,
};

/** Maps our source names onto the enum, dropping anything unrecognised. */
export function trackSources(names: readonly string[]): TrackSource[] {
  return names
    .map((name) => TRACK_SOURCES[name])
    .filter((source): source is TrackSource => source !== undefined);
}

export interface LivekitConfig {
  /** The websocket URL clients connect to, e.g. wss://meet.lekksideexpo.com */
  url: string;
  /** The https origin the server APIs live on, derived from `url`. */
  host: string;
  key: string;
  secret: string;
}

/**
 * The three secrets, or null when any is missing.
 *
 * Null rather than a throw, so the caller can return a sentence explaining what
 * is not configured — the same "no-op loudly" shape sendEmail() uses. A video
 * call that cannot happen should say so, not 500.
 */
export function livekitConfig(): LivekitConfig | null {
  const url = Deno.env.get('LIVEKIT_URL');
  const key = Deno.env.get('LIVEKIT_API_KEY');
  const secret = Deno.env.get('LIVEKIT_API_SECRET');
  if (!url || !key || !secret) {
    console.warn('LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET are not all set.');
    return null;
  }
  // The RoomService APIs are Twirp over https; clients speak wss. One env var
  // rather than two, because two would eventually point at different servers.
  const host = url.replace(/^ws/, 'http');
  return { url, host, key, secret };
}

/** What `space_room_grant` / `appointment_room_grant` hand back when admitted. */
export interface RoomGrant {
  admission: string;
  kind: 'space' | 'appointment';
  room: string;
  identity: string;
  display_name: string;
  role: 'host' | 'cohost' | 'moderator' | 'speaker' | 'listener';
  is_host: boolean;
  can_publish: boolean;
  can_publish_data: boolean;
  can_subscribe: boolean;
  publish_sources: string[];
  participant_id?: string;
  handle?: string | null;
  ttl_seconds: number;
}

/**
 * Signs a join token from a grant the database has already authorized.
 *
 * `attributes` are set here, which is what makes `lk_role`, `pid` and `handle`
 * unforgeable: they are inside the signature, so a client cannot claim to be a
 * host by writing its own metadata. Only `hand` is left for the client to set.
 * Server-asserted attributes carry authority; the one client-written attribute
 * carries intent.
 *
 * Note `roomAdmin` is deliberately absent for EVERY caller, hosts included.
 * Moderation goes through livekit-room, which mints its own short-lived admin
 * token after the audit row is written — so there is no privileged capability
 * sitting in a browser tab with nothing recording its use.
 */
export async function mintToken(
  cfg: LivekitConfig,
  grant: RoomGrant,
): Promise<{ token: string; expires_in: number }> {
  const at = new AccessToken(cfg.key, cfg.secret, {
    identity: grant.identity,
    name: grant.display_name,
    ttl: grant.ttl_seconds,
    attributes: {
      lk_role: grant.role,
      pid: grant.participant_id ?? '',
      handle: grant.handle ?? '',
    },
  });

  const video: VideoGrant = {
    room: grant.room,
    roomJoin: true,
    canSubscribe: grant.can_subscribe,
    canPublish: grant.can_publish,
    canPublishData: grant.can_publish_data,
    // Hand-raise is a participant attribute, so writing one requires this —
    // and a listener cannot raise a hand without identifying, which promotes
    // them in the same call. So this tracks canPublish rather than being its
    // own decision.
    canUpdateOwnMetadata: grant.can_publish,
  };
  const sources = trackSources(grant.publish_sources);
  if (sources.length > 0) video.canPublishSources = sources;
  at.addGrant(video);

  // `toJwt()` is async in v2. Forgetting the await hands the client the string
  // "[object Promise]", which fails at connect with an opaque 401.
  return { token: await at.toJwt(), expires_in: grant.ttl_seconds };
}

/** A RoomServiceClient for the privileged room APIs. Requires roomAdmin. */
export function roomService(cfg: LivekitConfig): RoomServiceClient {
  return new RoomServiceClient(cfg.host, cfg.key, cfg.secret);
}

/** The message every client shows when the three secrets are not set. */
export const NOT_CONFIGURED =
  'Live video is not configured on this environment. Set LIVEKIT_URL, '
  + 'LIVEKIT_API_KEY and LIVEKIT_API_SECRET before joining a room.';
