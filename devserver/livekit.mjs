// LiveKit token signing for the dev server.
//
// The authorization, the consent write and the audit row all run for real here
// — they are SQL, and this server runs the real schema. The one thing it cannot
// do without credentials is sign a token, and when it cannot it says so rather
// than handing back something that fails at connect.
//
// This uses the real `livekit-server-sdk` rather than hand-rolling the JWT with
// node:crypto, which auth.mjs already has the pieces for. The dev server is
// lean on purpose, but a second hand-written implementation of the exact claim
// shape LiveKit validates is the one place a local/production divergence would
// be invisible — which is the whole lesson of …025_api_grants.sql. One
// dependency is far cheaper than that class of bug.

import { AccessToken, TrackSource } from 'livekit-server-sdk';

// The grant functions name publish sources the way LiveKit's documentation
// does, but the SDK's canPublishSources takes its numeric TrackSource enum and
// renders those strings itself. See the same note in
// supabase/functions/_shared/livekit.ts — these two must agree.
const TRACK_SOURCES = {
  microphone: TrackSource.MICROPHONE,
  camera: TrackSource.CAMERA,
  screen_share: TrackSource.SCREEN_SHARE,
  screen_share_audio: TrackSource.SCREEN_SHARE_AUDIO,
};

/** The three secrets, or null when any is missing. */
export function livekitEnv() {
  const url = process.env.LIVEKIT_URL;
  const key = process.env.LIVEKIT_API_KEY;
  const secret = process.env.LIVEKIT_API_SECRET;
  if (!url || !key || !secret) return null;
  return { url, key, secret };
}

/** Signs a join token from a grant the database has already authorized. */
export async function signToken(cfg, grant) {
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

  const video = {
    room: grant.room,
    roomJoin: true,
    canSubscribe: grant.can_subscribe,
    canPublish: grant.can_publish,
    canPublishData: grant.can_publish_data,
    canUpdateOwnMetadata: grant.can_publish,
  };
  const sources = (grant.publish_sources ?? [])
    .map((s) => TRACK_SOURCES[s])
    .filter((s) => s !== undefined);
  if (sources.length) video.canPublishSources = sources;
  at.addGrant(video);

  return at.toJwt();
}

export const NOT_CONFIGURED =
  'The dev server has no LiveKit credentials, so it cannot sign a token. The '
  + 'authorization above is real. Export LIVEKIT_URL, LIVEKIT_API_KEY and '
  + 'LIVEKIT_API_SECRET before `npm start` to join a real room from here.';
