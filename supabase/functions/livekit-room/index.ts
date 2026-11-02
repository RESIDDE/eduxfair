// Running and moderating a live room: go live, end, admit, mute, remove,
// promote, appoint a moderator, and silence everybody at once.
//
// One function with an `action` switch rather than five functions. deps.ts
// already makes this argument ("Only three functions exist, not the five
// originally planned"): each extra function costs a README deploy line, a
// hand-written devserver branch and its own copy of the auth preamble. An
// action switch where every branch re-authorizes through the same SQL function
// costs nothing in safety.
//
// Every action is SQL FIRST, LiveKit SECOND, and that order is the point. The
// database decides whether the caller may do this, and records that they did,
// in one transaction. A kick LiveKit performed and the database did not record
// is a kick that did not happen — and if the LiveKit call then fails, the
// response says so rather than pretending.

import { json, preflight, requireUser, callerClient } from '../_shared/deps.ts';
import {
  livekitConfig,
  roomService,
  trackSources,
  NOT_CONFIGURED,
  TrackSource,
  TrackType,
} from '../_shared/livekit.ts';

type Action = 'go_live' | 'end' | 'moderate' | 'mute_all' | 'participants';

/** The moderation actions `space_moderate()` accepts from a client. */
const MODERATIONS = new Set([
  'admitted', 'denied', 'removed', 'muted', 'camera_muted', 'promoted', 'demoted',
  'hand_lowered', 'moderator_granted', 'moderator_revoked',
]);

/**
 * What "mute their microphone" and "turn their camera off" actually select.
 *
 * Matched on TrackSource, not TrackType, for two reasons. Source is the
 * narrower question — muting a microphone should not also silence a shared
 * screen's audio, and hiding a camera should not kill a screen share.
 *
 * And the raw numbers are a trap. TrackType is AUDIO=0, VIDEO=1, DATA=2, so
 * the hardcoded "1, meaning audio" this used to carry was selecting VIDEO:
 * muting a microphone turned the student's camera off instead, and turning a
 * camera off asked for DATA and matched nothing. Neither failed loudly,
 * because LiveKit was being asked a perfectly valid question. Hence the enum,
 * imported, never retyped.
 *
 * `type` survives only as a fallback for a publication that did not declare a
 * source, which no client of ours produces but a future one might.
 */
const MUTE_TARGETS = {
  microphone: { source: TrackSource.MICROPHONE, type: TrackType.AUDIO },
  camera: { source: TrackSource.CAMERA, type: TrackType.VIDEO },
} as const;

type MuteTarget = keyof typeof MUTE_TARGETS;

/**
 * Mutes one participant's published microphone and/or camera.
 *
 * There is no "mute the participant" call in LiveKit, only "mute this track",
 * so the publications have to be found first. One-way on a default deployment:
 * LiveKit refuses remote UNmute unless enable_remote_unmute is set, which is
 * why the clients offer "ask them to unmute" as a data packet rather than a
 * toggle here.
 *
 * Returns how many tracks it actually muted, so a caller can tell "nothing to
 * mute" from "muted" rather than reporting success either way.
 */
async function muteTracks(
  // deno-lint-ignore no-explicit-any
  svc: any,
  room: string,
  identity: string,
  targets: readonly MuteTarget[],
  // deno-lint-ignore no-explicit-any
  people?: any[],
): Promise<number> {
  const roster = people ?? await svc.listParticipants(room);
  const target = roster.find((p: { identity: string }) => p.identity === identity);
  const wanted = targets.map((t) => MUTE_TARGETS[t]);

  let muted = 0;
  for (const track of target?.tracks ?? []) {
    if (track.muted) continue;
    const hit = wanted.some((w) =>
      track.source === w.source
      || (track.source === TrackSource.UNKNOWN && track.type === w.type));
    if (!hit) continue;
    await svc.mutePublishedTrack(room, identity, track.sid, true);
    muted += 1;
  }
  return muted;
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

  const action = body.action as Action;
  const db = callerClient(req);
  const cfg = livekitConfig();

  try {
    // ---- going live -------------------------------------------------------
    if (action === 'go_live' || action === 'end') {
      const spaceId = body.space_id;
      if (typeof spaceId !== 'string') {
        return json({ error: 'space_id is required' }, 400);
      }

      const status = action === 'go_live' ? 'live' : 'ended';
      const { error } = await db.rpc('space_set_status', {
        p_space_id: spaceId,
        p_status: status,
      });
      if (error) return json({ error: error.message }, 403);

      if (!cfg) return json({ ok: true, status, livekit: false, error: NOT_CONFIGURED });

      const room = `space_${spaceId}`;
      try {
        const svc = roomService(cfg);
        if (action === 'go_live') {
          // Read back through the caller's RLS rather than trusting the body
          // for the cap and the title: the client asking to go live is not the
          // authority on how many people the room may hold.
          const { data: space } = await db
            .from('spaces')
            .select('title, kind, max_participants, institution_id, duration_min')
            .eq('id', spaceId)
            .single();

          const { data: inst } = await db
            .from('institutions').select('name')
            .eq('id', space?.institution_id ?? '').maybeSingle();

          await svc.createRoom({
            name: room,
            // Five minutes, so an abandoned room stops billing without
            // punishing a host whose wifi dropped mid-session.
            emptyTimeout: 300,
            maxParticipants: space?.max_participants ?? 200,
            metadata: JSON.stringify({
              v: 1,
              kind: 'space',
              id: spaceId,
              title: space?.title ?? '',
              institution: inst?.name ?? '',
              chat: 'space_messages',
              chat_id: spaceId,
              recording: false,
            }),
          });
        } else {
          // "The session has ended" has to mean everyone is disconnected, or
          // the room outlives the thing it was for.
          await svc.deleteRoom(room);
        }
        return json({ ok: true, status, room, livekit: true });
      } catch (err) {
        const errMsg = (err as Error).message ?? '';
        if (action === 'go_live' && errMsg.toLowerCase().includes('already exists')) {
          return json({ ok: true, status, room, livekit: true });
        }
        console.error(`livekit-room ${action} reached the database but not LiveKit:`, err);
        return json({ ok: true, status, livekit: false, error: errMsg });
      }
    }

    // ---- moderating -------------------------------------------------------
    if (action === 'moderate') {
      const participantId = body.participant_id;
      const moderation = body.moderation;
      if (typeof participantId !== 'string' || typeof moderation !== 'string') {
        return json({ error: 'participant_id and moderation are required' }, 400);
      }
      if (!MODERATIONS.has(moderation)) {
        return json({ error: `unknown moderation '${moderation}'` }, 400);
      }

      const { data, error } = await db.rpc('space_moderate', {
        p_participant_id: participantId,
        p_action: moderation,
        p_reason: typeof body.reason === 'string' ? body.reason : null,
      });
      if (error) return json({ error: error.message }, 403);

      const { room, identity } = data as { room: string; identity: string };
      if (!cfg) return json({ ok: true, ...data, livekit: false, error: NOT_CONFIGURED });

      try {
        const svc = roomService(cfg);

        if (moderation === 'muted' || moderation === 'camera_muted') {
          await muteTracks(svc, room, identity,
            moderation === 'muted' ? ['microphone'] : ['camera']);
        } else if (moderation === 'removed' || moderation === 'denied') {
          await svc.removeParticipant(room, identity);
        } else if (moderation === 'hand_lowered') {
          // Empty string rather than deleting the key: deletion semantics
          // differ across SDK versions, and both clients read "" as down.
          //
          // The options-object overload, not the positional one — the latter
          // takes (metadata, permission, name) and has no attributes slot at
          // all, so this silently set the display name instead.
          await svc.updateParticipant(room, identity, { attributes: { hand: '' } });
        } else if (
          moderation === 'promoted' || moderation === 'demoted'
          || moderation === 'moderator_granted' || moderation === 'moderator_revoked'
        ) {
          // `role` comes back from space_moderate() rather than being derived
          // from the action, because the SQL decides what the row ended up as
          // — a revoked moderator drops to speaker, not to listener, and
          // guessing that here is how the two would come to disagree.
          const role = (data as { role?: string }).role ?? 'listener';
          const speaking = role !== 'listener';

          // Note what is NOT granted here: a moderator gets a microphone, a
          // camera and `lk_role: moderator`, and no roomAdmin. Their mute
          // button reaches LiveKit only by coming back through this function,
          // which means it cannot be pressed without an audit row.
          await svc.updateParticipant(room, identity, {
            // Permissions are applied atomically, so every one the participant
            // should keep has to be restated here, not just the changed ones.
            permission: {
              canSubscribe: true,
              canPublish: speaking,
              canPublishData: speaking,
              // `canUpdateMetadata` here, NOT `canUpdateOwnMetadata`. The two
              // APIs name the same capability differently: the token's
              // VideoGrant uses canUpdateOwnMetadata, this server-side
              // ParticipantPermission message uses canUpdateMetadata. Getting
              // it wrong leaves a newly promoted speaker unable to raise a
              // hand, because hand-raise is an attribute write.
              canUpdateMetadata: speaking,
              canPublishSources: speaking
                ? trackSources(['microphone', 'camera'])
                : [],
            },
            attributes: { lk_role: role, hand: '' },
          });

          // A permission change revokes the participant's current token, so
          // the client has to re-mint before its next reconnect rather than
          // discovering it at the worst possible moment.
          return json({ ok: true, ...data, livekit: true, reconnect: true });
        }
        // 'admitted' needs no LiveKit call: they were never in the room. The
        // waiting client is polling livekit-token and will be let through on
        // its next tick.

        return json({ ok: true, ...data, livekit: true });
      } catch (err) {
        console.error('livekit-room moderate reached the database but not LiveKit:', err);
        // Deliberately ok: true. The durable decision stuck — they cannot
        // rejoin — but they are still connected right now, and that is exactly
        // what the host needs told.
        return json({ ok: true, ...data, livekit: false, error: (err as Error).message });
      }
    }

    // ---- silencing the whole room -----------------------------------------
    //
    // A room with two hundred people in it is not moderated one row at a time.
    // SQL decides who may do this and who is exempt — hosts, cohosts, the
    // appointed moderators and the caller themselves — and records it as one
    // event rather than one per person, so the log stays readable.
    if (action === 'mute_all') {
      const spaceId = body.space_id;
      if (typeof spaceId !== 'string') {
        return json({ error: 'space_id is required' }, 400);
      }
      const includeVideo = body.include_video === true;

      const { data, error } = await db.rpc('space_mute_all', {
        p_space_id: spaceId,
        p_include_video: includeVideo,
      });
      if (error) return json({ error: error.message }, 403);

      const { room, identities, count } = data as {
        room: string; identities: string[]; count: number;
      };
      if (!cfg) return json({ ok: true, count, livekit: false, error: NOT_CONFIGURED });

      const targets: readonly MuteTarget[] =
        includeVideo ? ['microphone', 'camera'] : ['microphone'];

      try {
        const svc = roomService(cfg);
        // One listParticipants for the whole sweep, not one per person: the
        // roster is the same for all of them and the call is not free.
        const people = await svc.listParticipants(room);
        // Counted in tracks, not in people: "muted 40" when thirty of them had
        // nothing published is a number that reads like a success and is not.
        let muted = 0;
        for (const identity of identities) {
          try {
            muted += await muteTracks(svc, room, identity, targets, people);
          } catch (err) {
            // One participant who has already left must not abandon the other
            // hundred and ninety-nine.
            console.error(`mute_all could not mute ${identity}:`, err);
          }
        }
        // `count` is people the database selected; `muted` is tracks actually
        // silenced. They differ whenever somebody was already muted or had
        // published nothing, and the client says something different for zero.
        return json({ ok: true, count, muted, livekit: true });
      } catch (err) {
        console.error('livekit-room mute_all reached the database but not LiveKit:', err);
        return json({ ok: true, count, livekit: false, error: (err as Error).message });
      }
    }

    // ---- reconciling the roster -------------------------------------------
    if (action === 'participants') {
      const spaceId = body.space_id;
      if (typeof spaceId !== 'string') {
        return json({ error: 'space_id is required' }, 400);
      }
      const { data: allowed, error } = await db.rpc('space_can_moderate', {
        p_space_id: spaceId,
      });
      if (error) return json({ error: error.message }, 403);
      if (!allowed) return json({ error: 'that session is not yours to moderate' }, 403);

      if (!cfg) return json({ participants: [], livekit: false, error: NOT_CONFIGURED });

      const people = await roomService(cfg).listParticipants(`space_${spaceId}`);
      return json({
        livekit: true,
        participants: people.map((p) => ({
          identity: p.identity,
          name: p.name,
          state: p.state,
          attributes: p.attributes,
          tracks: p.tracks.length,
        })),
      });
    }

    return json(
      { error: 'specify action: go_live, end, moderate, mute_all or participants' },
      400,
    );
  } catch (err) {
    console.error('livekit-room failed:', err);
    return json({ error: (err as Error).message }, 500);
  }
});
