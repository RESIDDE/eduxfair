import { useCallback, useEffect, useRef, useState } from 'react';
import { Room, RoomEvent, Track, VideoPresets } from 'livekit-client';
import {
  ATTR,
  HAND_DEBOUNCE_MS,
  REACTIONS,
  TOPIC,
  decodeReaction,
  encodeAskUnmute,
  encodeReaction,
  fetchToken,
  makeReactionLimiter,
  parseRoomMetadata,
  participantIdOf,
  roleOf,
} from './livekit';

/**
 * Connects to a room with a grant already in hand.
 *
 * `adaptiveStream` and `dynacast` are not optional: the other end of this call
 * is frequently a mid-range Android phone on cellular data, and nine decoded
 * streams is where one falls over.
 */
async function connectRoom(grant) {
  const room = new Room({
    adaptiveStream: true,
    dynacast: true,
    videoCaptureDefaults: { resolution: VideoPresets.h720.resolution },
  });
  await room.connect(grant.url, grant.token);
  return room;
}

/**
 * Owns one LiveKit Room for the lifetime of a call screen.
 *
 * Phases rather than a pile of booleans, because the screen renders something
 * completely different for each and they are mutually exclusive:
 *
 *   connecting  asking for a token
 *   waiting     admitted === 'pending' — a host has not let them in
 *   closed      outside the join window
 *   live        connected
 *   ended       they left, or the host ended it
 *   failed      `error` says why, in a sentence
 */
export function useLiveRoom({ spaceId, appointmentId, autoConnect = true }) {
  const [phase, setPhase] = useState('connecting');
  const [error, setError] = useState(null);
  const [grant, setGrant] = useState(null);
  const [room, setRoom] = useState(null);
  const [participants, setParticipants] = useState([]);
  const [reactions, setReactions] = useState([]);
  const [notices, setNotices] = useState([]);
  const [askedToUnmute, setAskedToUnmute] = useState(false);

  const roomRef = useRef(null);
  const lastHandWrite = useRef(0);
  const limiter = useRef(makeReactionLimiter());

  /**
   * Puts one emoji on screen and takes it off again.
   *
   * Used by the receive path AND by the send path: LiveKit does not loop a
   * data packet back to its publisher, so without this the one person who
   * cannot see a reaction is whoever sent it.
   */
  const floatReaction = useCallback((emoji, identity) => {
    const id = `${Date.now()}-${Math.random()}`;
    setReactions((prev) => [...prev, { id, emoji, identity }]);
    setTimeout(() => setReactions((prev) => prev.filter((x) => x.id !== id)), 3200);
  }, []);

  /** A transient in-room message. No toast library exists in this console. */
  const notify = useCallback((text) => {
    const id = `${Date.now()}-${Math.random()}`;
    setNotices((prev) => [...prev, { id, text }]);
    setTimeout(() => setNotices((prev) => prev.filter((n) => n.id !== id)), 4000);
  }, []);

  // One array of everyone, local participant first, rebuilt on every event
  // that could change a tile. Cheap next to decoding video, and it means the
  // render path never has to reason about which event changed what.
  const sync = useCallback(() => {
    const r = roomRef.current;
    if (!r) return;
    const all = [r.localParticipant, ...Array.from(r.remoteParticipants.values())];
    setParticipants(
      all.filter(Boolean).map((p) => ({
        sid: p.sid,
        identity: p.identity,
        name: p.name || p.identity,
        isLocal: p === r.localParticipant,
        role: roleOf(p),
        participantId: participantIdOf(p),
        hand: p.attributes?.[ATTR.hand] || null,
        isSpeaking: p.isSpeaking,
        audioEnabled: p.isMicrophoneEnabled,
        videoEnabled: p.isCameraEnabled,
        screenTrack: p.getTrackPublication(Track.Source.ScreenShare)?.videoTrack ?? null,
        videoTrack: p.getTrackPublication(Track.Source.Camera)?.videoTrack ?? null,
        audioTrack: p.getTrackPublication(Track.Source.Microphone)?.audioTrack ?? null,
        participant: p,
      })),
    );
  }, []);

  const connect = useCallback(async () => {
    setPhase('connecting');
    setError(null);
    try {
      const next = await fetchToken({ spaceId, appointmentId });
      setGrant(next);

      if (next.admission === 'pending') return setPhase('waiting');
      if (next.admission === 'closed') return setPhase('closed');

      const r = await connectRoom(next);
      roomRef.current = r;
      setRoom(r);
      setPhase('live');
      sync();
    } catch (err) {
      setError(err.message);
      setPhase('failed');
    }
  }, [spaceId, appointmentId, sync]);

  useEffect(() => {
    if (autoConnect) connect();
    return () => {
      roomRef.current?.disconnect();
      roomRef.current = null;
    };
  }, [connect, autoConnect]);

  // A waiting participant POLLS rather than subscribing. The devserver cannot
  // broadcast changes made inside an RPC — it never sees which rows they
  // touched — so a subscription would work in production and silently not
  // locally. One code path that behaves the same in both is worth the poll.
  useEffect(() => {
    if (phase !== 'waiting') return undefined;
    const timer = setInterval(connect, 3000);
    return () => clearInterval(timer);
  }, [phase, connect]);

  useEffect(() => {
    if (!room) return undefined;

    const onData = (payload, participant, _kind, topic) => {
      if (topic === TOPIC.reaction) {
        if (!limiter.current(participant?.identity ?? '')) return;
        const msg = decodeReaction(payload);
        if (!msg) return;
        floatReaction(msg.emoji, participant?.identity);
      } else if (topic === TOPIC.askUnmute) {
        setAskedToUnmute(true);
        notify('The host is asking you to unmute.');
      }
    };

    const onPermissions = () => {
      // A permission change revokes the current token. Re-minting now beats
      // finding out on the next reconnect, which would look like a random drop.
      notify('Your permissions in this room changed.');
      connect();
    };

    const onDisconnected = () => setPhase((p) => (p === 'live' ? 'ended' : p));

    const events = [
      RoomEvent.ParticipantConnected, RoomEvent.ParticipantDisconnected,
      RoomEvent.TrackSubscribed, RoomEvent.TrackUnsubscribed,
      RoomEvent.TrackPublished, RoomEvent.TrackUnpublished,
      RoomEvent.TrackMuted, RoomEvent.TrackUnmuted,
      RoomEvent.LocalTrackPublished, RoomEvent.LocalTrackUnpublished,
      RoomEvent.ActiveSpeakersChanged, RoomEvent.ParticipantAttributesChanged,
      RoomEvent.ParticipantMetadataChanged, RoomEvent.ConnectionStateChanged,
    ];
    events.forEach((e) => room.on(e, sync));
    room.on(RoomEvent.DataReceived, onData);
    room.on(RoomEvent.ParticipantPermissionsChanged, onPermissions);
    room.on(RoomEvent.Disconnected, onDisconnected);

    return () => {
      events.forEach((e) => room.off(e, sync));
      room.off(RoomEvent.DataReceived, onData);
      room.off(RoomEvent.ParticipantPermissionsChanged, onPermissions);
      room.off(RoomEvent.Disconnected, onDisconnected);
    };
  }, [room, sync, notify, connect, floatReaction]);

  /**
   * Turns a microphone or camera on or off, and can recover from a mute a HOST
   * applied.
   *
   * Those are not the same operation. A remote mute can leave the publication
   * holding a stopped device, and the unmute then has to re-acquire hardware —
   * which throws. Nothing awaited that throw, so the control simply sat there
   * and the person had no way back. The cheap path first; failing that, drop
   * the publication and publish a fresh track; failing that, say so.
   */
  async function setSource(source, on) {
    const me = room?.localParticipant;
    if (!me) return;
    const apply = (value) => (source === 'microphone'
      ? me.setMicrophoneEnabled(value)
      : me.setCameraEnabled(value));

    try {
      await apply(on);
      return;
    } catch {
      // Turning something OFF that is already broken is not worth retrying:
      // the device is not running either way.
      if (!on) return;
    }

    try {
      const pub = me.getTrackPublication(
        source === 'microphone' ? Track.Source.Microphone : Track.Source.Camera,
      );
      if (pub?.track) await me.unpublishTrack(pub.track, true);
      await apply(true);
    } catch {
      notify(source === 'microphone'
        ? 'Your microphone could not be turned back on. Check that this site still has permission to use it.'
        : 'Your camera could not be turned back on. Check that this site still has permission to use it.');
    }
  }

  const local = participants.find((p) => p.isLocal) ?? null;
  const metadata = parseRoomMetadata(room?.metadata);

  const actions = {
    async setMicrophone(on) {
      await setSource('microphone', on);
      if (on) setAskedToUnmute(false);
    },
    setCamera: (on) => setSource('camera', on),
    async setScreenShare(on) {
      try {
        await room?.localParticipant?.setScreenShareEnabled(on, { audio: true });
      } catch (err) {
        // The browser's own picker being dismissed is a DOMException, not a
        // problem worth a red banner.
        if (err?.name !== 'NotAllowedError') notify('Screen sharing did not start.');
      }
    },
    async raiseHand(up) {
      const now = Date.now();
      if (now - lastHandWrite.current < HAND_DEBOUNCE_MS) return;
      lastHandWrite.current = now;
      await room?.localParticipant?.setAttributes({
        ...room.localParticipant.attributes,
        [ATTR.hand]: up ? new Date().toISOString() : '',
      });
    },
    react(emoji) {
      if (!REACTIONS.includes(emoji)) return undefined;

      // The same limiter the receive path uses, keyed on our own identity, so
      // holding the button down cannot flood our own screen either.
      const me = room?.localParticipant;
      if (!limiter.current(me?.identity ?? 'local')) return undefined;

      // Shown before it is sent, not after. The packet is unreliable by
      // design and a click that paints nothing reads as a broken button.
      floatReaction(emoji, me?.identity);

      return me?.publishData(
        encodeReaction(emoji, local?.participantId),
        { reliable: false, topic: TOPIC.reaction },
      );
    },
    askToUnmute: (identity) => room?.localParticipant?.publishData(
      encodeAskUnmute(),
      { reliable: true, topic: TOPIC.askUnmute, destinationIdentities: [identity] },
    ),
    leave: async () => {
      await room?.disconnect();
      setPhase('ended');
    },
    switchDevice: (kind, deviceId) => room?.switchActiveDevice(kind, deviceId),
    reconnect: connect,
  };

  return {
    phase, error, grant, room, participants, local, metadata,
    reactions, notices, askedToUnmute, actions, notify,
  };
}
