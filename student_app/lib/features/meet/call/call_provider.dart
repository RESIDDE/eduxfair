import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/call_grant.dart';
import '../models/room_protocol.dart';
import '../models/space.dart';

/// Where the call screen is in its life, rather than a pile of booleans: the
/// screen renders something completely different for each and they are mutually
/// exclusive.
enum CallPhase {
  /// Asking for camera and microphone, with a self-preview.
  preflight,
  connecting,

  /// `admission == 'pending'` — a host has not let them in.
  waiting,

  /// Outside the join window.
  closed,
  live,

  /// They left, or the host ended it.
  ended,
  failed,
}

/// One participant, flattened for the widgets.
class CallPerson {
  final Participant participant;
  final bool isLocal;

  /// The role from our own grant, for the local participant only.
  ///
  /// `lk_role` is server-asserted and authoritative for everyone else, but for
  /// ourselves the freshly re-minted grant is the earlier of the two signals —
  /// so a newly appointed moderator wears the badge the moment the role lands,
  /// rather than whenever the attribute happens to propagate back.
  final String? ownRole;

  CallPerson(this.participant, {required this.isLocal, this.ownRole});

  String get identity => participant.identity;
  String get name =>
      participant.name.isNotEmpty ? participant.name : participant.identity;
  String get role =>
      ownRole ?? participant.attributes[RoomProtocol.attrRole] ?? 'listener';
  String? get participantId =>
      participant.attributes[RoomProtocol.attrParticipantId];
  bool get handRaised =>
      (participant.attributes[RoomProtocol.attrHand] ?? '').isNotEmpty;
  bool get isStaff => RoomProtocol.staffRoles.contains(role);
  bool get isModerator => RoomProtocol.moderatorRoles.contains(role);
  bool get isSpeaking => participant.isSpeaking;

  VideoTrack? get videoTrack => _videoFor(TrackSource.camera);
  VideoTrack? get screenTrack => _videoFor(TrackSource.screenShareVideo);

  bool get cameraOn => videoTrack != null;
  bool get micOn {
    final pub = participant.audioTrackPublications
        .where((p) => p.source == TrackSource.microphone)
        .firstOrNull;
    return pub != null && !pub.muted;
  }

  VideoTrack? _videoFor(TrackSource source) {
    final pub = participant.videoTrackPublications
        .where((p) => p.source == source && p.subscribed && !p.muted)
        .firstOrNull;
    return pub?.track as VideoTrack?;
  }

  /// Ranks tiles so the grid cap drops the least interesting ones.
  int get score =>
      (screenTrack != null ? 100 : 0) +
      (isSpeaking ? 50 : 0) +
      (handRaised ? 25 : 0) +
      (role == 'host' ? 20 : (role == 'cohost' ? 10 : (role == 'moderator' ? 8 : 0))) +
      (cameraOn ? 5 : 0) +
      (isLocal ? 1 : 0);
}

/// A reaction in flight.
class FloatingReaction {
  final int id;
  final String emoji;
  const FloatingReaction(this.id, this.emoji);
}

/// Owns one [Room] for the lifetime of a call screen.
///
/// Deliberately NOT registered in main.dart's MultiProvider, unlike every other
/// provider in this app: it holds a Room and a native media session that must
/// be disposed when the route leaves, so it is created at the route instead.
class CallProvider extends ChangeNotifier {
  CallProvider({required this.kind, required this.id});

  final CallKind kind;
  final String id;

  final _service = SupabaseService.instance;
  final _limiter = ReactionLimiter();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Timer? _admissionPoll;
  DateTime _lastHandWrite = DateTime.fromMillisecondsSinceEpoch(0);

  /// Guards against overlapping connects. Three things can ask to connect — the
  /// screen on open, the admission poll, and the consent upgrade — and two of
  /// them landing together would build a second Room while the first was still
  /// being torn down, leaving a spinner with nothing behind it.
  bool _connecting = false;

  /// Guards [_refreshGrant], which several events can ask for at once.
  bool _refreshingGrant = false;

  /// `livekit-token` rate-limits mints per user, and a permission update can
  /// arrive more than once as a room settles. A refresh is never urgent to the
  /// second, so duplicates inside this window are COALESCED rather than
  /// dropped — dropping one would mean a role change that arrived a moment
  /// after another never reached the client at all.
  DateTime _lastGrantRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _grantRefreshRetry;
  static const _grantRefreshGap = Duration(seconds: 3);
  int _reactionSeq = 0;

  CallPhase _phase = CallPhase.preflight;
  String? _error;
  CallGrant? _grant;
  List<CallPerson> _people = [];
  List<SpaceRosterEntry> _roster = [];
  final List<FloatingReaction> _reactions = [];
  final List<String> _notices = [];
  bool _askedToUnmute = false;
  String? _pinned;
  bool _permissionsDenied = false;

  CallPhase get phase => _phase;
  String? get error => _error;
  CallGrant? get grant => _grant;
  List<CallPerson> get people => _people;
  List<SpaceRosterEntry> get roster => _roster;
  List<FloatingReaction> get reactions => List.unmodifiable(_reactions);
  List<String> get notices => List.unmodifiable(_notices);
  bool get askedToUnmute => _askedToUnmute;
  bool get permissionsDenied => _permissionsDenied;
  String? get pinned => _pinned;

  bool get isSpace => kind == CallKind.space;

  /// Whether a closed room is closed because it has not started, rather than
  /// because it finished. Null `opensAt` is treated as "not yet", since that is
  /// the only case an appointment grant leaves it unset.
  bool get opensInFuture {
    final opensAt = _grant?.opensAt;
    return opensAt == null || opensAt.isAfter(DateTime.now());
  }
  bool get canPublish => _grant?.canPublish ?? false;
  bool get canModerate => _grant?.canModerate ?? false;
  bool get isStaff => _grant?.isStaff ?? false;
  String get institutionName => _grant?.institutionName ?? 'this institution';

  CallPerson? get local => _people.where((p) => p.isLocal).firstOrNull;
  LocalParticipant? get _me => _room?.localParticipant;

  bool get micEnabled => _me?.isMicrophoneEnabled() ?? false;
  bool get cameraEnabled => _me?.isCameraEnabled() ?? false;
  bool get screenShareEnabled => _me?.isScreenShareEnabled() ?? false;
  bool get handRaised => local?.handRaised ?? false;

  List<SpaceRosterEntry> get waitingRoom =>
      _roster.where((r) => r.isWaiting).toList();

  List<SpaceRosterEntry> get hands => _roster
      .where((r) => r.isIn && r.handRaisedAt != null)
      .toList()
    ..sort((a, b) => a.handRaisedAt!.compareTo(b.handRaisedAt!));

  // ── Joining ──────────────────────────────────────────────────────────────

  /// Asks for camera and microphone before the room, not during it.
  ///
  /// A denial is not fatal: a student can listen perfectly well without either,
  /// which is exactly what a listener's grant allows anyway.
  Future<void> requestPermissions() async {
    try {
      final result = await [Permission.camera, Permission.microphone].request();
      _permissionsDenied =
          result.values.any((s) => s.isPermanentlyDenied || s.isDenied);
    } catch (e) {
      if (kDebugMode) debugPrint('permission request failed: $e');
    }
    notifyListeners();
  }

  Future<void> openSettings() => openAppSettings();

  Future<void> connect() async {
    if (_connecting) return;
    _connecting = true;

    _phase = CallPhase.connecting;
    _error = null;
    notifyListeners();

    try {
      final body = isSpace ? {'space_id': id} : {'appointment_id': id};
      final grant = CallGrant.fromMap(await _service.invoke('livekit-token', body: body));
      _grant = grant;

      if (grant.isPending) {
        _phase = CallPhase.waiting;
        _startAdmissionPoll();
        notifyListeners();
        return;
      }
      if (grant.isClosed) {
        _phase = CallPhase.closed;
        notifyListeners();
        return;
      }
      if (!grant.canConnect) {
        // Authorized, but nothing was signed — the dev server without
        // credentials, or a misconfigured project. Its own sentence is better
        // than anything this layer could invent.
        _error = grant.error ?? 'This room could not be opened.';
        _phase = CallPhase.failed;
        notifyListeners();
        return;
      }

      await _disposeRoom();

      final room = Room(
        roomOptions: const RoomOptions(
          // Not optional. The other end is often a mid-range phone on
          // cellular, and nine decoded streams is where one falls over.
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      _listener = room.createListener();
      _wire(_listener!);

      await room.connect(grant.url!, grant.token!);
      _room = room;
      _phase = CallPhase.live;
      _sync();
      await loadRoster();
    } catch (e) {
      if (kDebugMode) debugPrint('Call connect error: $e');
      _error = SupabaseService.describeError(e);
      _phase = CallPhase.failed;
      notifyListeners();
    } finally {
      _connecting = false;
    }
  }

  /// Re-reads the grant when the server changes what this participant IS.
  ///
  /// The role lives inside the signed token, so being appointed a moderator
  /// cannot appear in [_grant] on its own: `canModerate`, `isStaff` and
  /// `canPublish` are all read from there, and without this a newly appointed
  /// moderator keeps a listener's or speaker's grant and gets no moderation
  /// UI at all — the bug this exists to fix.
  ///
  /// The ROOM is deliberately left alone. Tearing it down and rebuilding fires
  /// the permissions event again, which is the loop the handler below warns
  /// about; a grant is just JSON, and fetching one costs nothing.
  Future<void> _refreshGrant() async {
    if (_phase != CallPhase.live) return;

    final since = DateTime.now().difference(_lastGrantRefresh);
    if (_refreshingGrant || since < _grantRefreshGap) {
      // Queue one retry for when the window opens, replacing any already
      // waiting: several events asking at once still cost a single mint.
      _grantRefreshRetry?.cancel();
      _grantRefreshRetry = Timer(_grantRefreshGap - since, () {
        _grantRefreshRetry = null;
        _refreshGrant();
      });
      return;
    }

    _grantRefreshRetry?.cancel();
    _grantRefreshRetry = null;
    _lastGrantRefresh = DateTime.now();
    _refreshingGrant = true;
    try {
      final body = isSpace ? {'space_id': id} : {'appointment_id': id};
      final next =
          CallGrant.fromMap(await _service.invoke('livekit-token', body: body));
      if (!next.isAdmitted) return;

      final was = _grant?.role;
      _grant = next;
      notifyListeners();
      if (was == next.role) return;

      // Said out loud, because a mute button appearing in a sheet they may not
      // have open is not something anyone notices.
      if (next.role == 'moderator') {
        _notify('You are a moderator of this session now.');
      } else if (was == 'moderator') {
        _notify('You are no longer a moderator of this session.');
      }
      await loadRoster();
    } catch (e) {
      if (kDebugMode) debugPrint('grant refresh failed: $e');
    } finally {
      _refreshingGrant = false;
    }
  }

  /// Asks for a new grant only when the server-set role has actually moved.
  ///
  /// `lk_role` is server-asserted and arrives on the attribute change, so it
  /// is the cheapest reliable signal that the token is now out of date.
  void _maybeRefreshGrant() {
    final live = local?.role;
    if (live == null || live == _grant?.role) return;
    _refreshGrant();
  }

  /// A waiting participant polls their participant row in the database rather
  /// than hitting the Edge Function in a loop, preventing rate limit traps.
  void _startAdmissionPoll() {
    _admissionPoll?.cancel();
    _admissionPoll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_phase != CallPhase.waiting) {
        _admissionPoll?.cancel();
        return;
      }
      final pid = _grant?.participantId;
      if (pid == null) {
        connect();
        return;
      }
      try {
        final row = await _service.client
            .from('space_participants')
            .select('admission')
            .eq('id', pid)
            .maybeSingle();
        final admission = row?['admission'] as String?;
        if (admission == 'admitted') {
          _admissionPoll?.cancel();
          connect();
        } else if (admission == 'removed' || admission == 'denied') {
          _admissionPoll?.cancel();
          _error = 'The host did not admit you to this session.';
          _phase = CallPhase.failed;
          notifyListeners();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('admission poll check error: $e');
      }
    });
  }

  void _wire(EventsListener<RoomEvent> listener) {
    listener
      ..on<ParticipantConnectedEvent>((_) => _sync())
      ..on<ParticipantDisconnectedEvent>((_) => _sync())
      ..on<TrackSubscribedEvent>((_) => _sync())
      ..on<TrackUnsubscribedEvent>((_) => _sync())
      ..on<TrackPublishedEvent>((_) => _sync())
      ..on<TrackUnpublishedEvent>((_) => _sync())
      ..on<LocalTrackPublishedEvent>((_) => _sync())
      ..on<LocalTrackUnpublishedEvent>((_) => _sync())
      ..on<TrackMutedEvent>((_) => _sync())
      ..on<TrackUnmutedEvent>((_) => _sync())
      ..on<ActiveSpeakersChangedEvent>((_) => _sync())
      ..on<ParticipantAttributesChanged>((_) {
        _sync();
        // Being appointed a moderator arrives here first, as `lk_role`.
        _maybeRefreshGrant();
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (_phase == CallPhase.live) _phase = CallPhase.ended;
        notifyListeners();
      })
      ..on<ParticipantPermissionsUpdatedEvent>((event) {
        // This used to call connect() unconditionally, which was a loop: the
        // event fires as permissions are applied on join, connect() tears the
        // room down and rebuilds it, and the rebuild fires the event again. A
        // host opening their own room span forever on "Your permissions in
        // this room changed".
        //
        // No reconnect is needed. The SDK applies new permissions to the live
        // session in place, and a revoked token only matters for a FUTURE
        // reconnect — which connect() covers anyway, because it mints a fresh
        // token every time rather than reusing the old one.
        //
        // Remote participants' permissions change too (a host promoting
        // someone), and those are not ours to announce.
        if (event.participant is! LocalParticipant) return;

        final could = event.oldPermissions.canPublish;
        final can = event.permissions.canPublish;
        _sync();

        // No reconnect — but the grant behind `canModerate` and `canPublish`
        // is now stale, and that is a refresh, not a rebuild.
        _refreshGrant();

        // Only say something when it changed what they can actually do.
        if (could != can) {
          _notify(can
              ? 'You can speak in this room now.'
              : 'A host took back the floor.');
        }
      })
      ..on<DataReceivedEvent>((event) {
        final identity = event.participant?.identity ?? '';
        if (event.topic == RoomProtocol.topicReaction) {
          if (!_limiter.allow(identity)) return;
          final emoji = RoomProtocol.decodeReaction(event.data);
          if (emoji == null) return;
          _floatReaction(emoji);
        } else if (event.topic == RoomProtocol.topicAskUnmute &&
            RoomProtocol.isAskUnmute(event.data)) {
          _askedToUnmute = true;
          _notify('The host is asking you to unmute.');
        }
      });
  }

  /// Puts one emoji on screen and takes it off again.
  ///
  /// Called for packets that arrive AND for the one being sent: LiveKit does
  /// not loop a data packet back to its publisher, so without this the one
  /// person who cannot see a reaction is whoever sent it.
  void _floatReaction(String emoji) {
    final reaction = FloatingReaction(_reactionSeq++, emoji);
    _reactions.add(reaction);
    notifyListeners();
    Timer(const Duration(milliseconds: 3200), () {
      _reactions.remove(reaction);
      notifyListeners();
    });
  }

  void _sync() {
    final room = _room;
    if (room == null) return;
    final people = <CallPerson>[
      CallPerson(room.localParticipant!, isLocal: true, ownRole: _grant?.role),
      ...room.remoteParticipants.values.map((p) => CallPerson(p, isLocal: false)),
    ]..sort((a, b) => b.score.compareTo(a.score));
    _people = people;
    notifyListeners();
  }

  void _notify(String text) {
    _notices.add(text);
    notifyListeners();
    Timer(const Duration(seconds: 4), () {
      _notices.remove(text);
      notifyListeners();
    });
  }

  // ── In the room ──────────────────────────────────────────────────────────

  Future<void> setMicrophone(bool on) async {
    await _setSource(TrackSource.microphone, on);
    if (on) _askedToUnmute = false;
    notifyListeners();
  }

  Future<void> setCamera(bool on) async {
    await _setSource(TrackSource.camera, on);
    notifyListeners();
  }

  /// Turns a microphone or camera on or off, and can recover from a mute that
  /// a HOST applied.
  ///
  /// Those are not the same operation, which is what made "the host muted me
  /// and now my button does nothing" look like a permissions problem and was
  /// really a hardware one. LiveKit's capture options default
  /// `stopAudioCaptureOnMute` and `stopCameraCaptureOnMute` to true, so a
  /// remote mute STOPS the device and disposes the media stream. Unmuting then
  /// means `restartTrack()`, which re-acquires the camera or microphone — and
  /// that throws when the sender has gone or the OS declines
  /// (`Native.ensureMicrophoneAccess` on Apple raises outright).
  ///
  /// Nothing awaited that throw, so it vanished into an unhandled future and
  /// the control simply sat there. The cheap path is tried first; failing
  /// that, the stopped publication is dropped and a fresh track published,
  /// which is the one path that cannot inherit a dead device. If even that
  /// fails the person is told, rather than left tapping.
  Future<void> _setSource(TrackSource source, bool on) async {
    final me = _me;
    if (me == null) return;

    Future<void> apply(bool value) => source == TrackSource.microphone
        ? me.setMicrophoneEnabled(value)
        : me.setCameraEnabled(value);

    final isMic = source == TrackSource.microphone;
    try {
      await apply(on);
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('set ${source.name} $on failed: $e');
      // Turning something OFF that is already broken is not worth a second
      // attempt: the device is not running either way.
      if (!on) return;
    }

    try {
      final pub = me.getTrackPublicationBySource(source);
      if (pub != null) await me.removePublishedTrack(pub.sid);
      await apply(true);
    } catch (e) {
      if (kDebugMode) debugPrint('republish ${source.name} failed: $e');
      _notify(isMic
          ? 'Your microphone could not be turned back on. Check that this app '
              'still has permission to use it.'
          : 'Your camera could not be turned back on. Check that this app '
              'still has permission to use it.');
    }
  }

  Future<void> setScreenShare(bool on) async {
    try {
      await _me?.setScreenShareEnabled(on);
    } catch (e) {
      _notify('Screen sharing did not start.');
      if (kDebugMode) debugPrint('screen share failed: $e');
    }
    notifyListeners();
  }

  Future<void> raiseHand(bool up) async {
    final now = DateTime.now();
    if (now.difference(_lastHandWrite) < RoomProtocol.handDebounce) return;
    _lastHandWrite = now;
    await _me?.setAttributes({
      ..._me!.attributes,
      RoomProtocol.attrHand: up ? now.toUtc().toIso8601String() : '',
    });
    notifyListeners();
  }

  Future<void> react(String emoji) async {
    if (!RoomProtocol.reactions.contains(emoji)) return;

    // The same limiter the receive path uses, keyed on our own identity, so
    // holding a finger on the button cannot flood our own screen either.
    final identity = _me?.identity ?? 'local';
    if (!_limiter.allow(identity)) return;

    // Shown before it is sent, not after. The packet is unreliable by design
    // and a tap that paints nothing reads as a broken button.
    _floatReaction(emoji);

    await _me?.publishData(
      RoomProtocol.encodeReaction(emoji, _grant?.participantId),
      reliable: false,
      topic: RoomProtocol.topicReaction,
    );
  }

  Future<void> askToUnmute(String identity) async {
    await _me?.publishData(
      RoomProtocol.encodeAskUnmute(),
      reliable: true,
      topic: RoomProtocol.topicAskUnmute,
      destinationIdentities: [identity],
    );
    _notify('Asked them to unmute.');
  }

  void pin(String? identity) {
    _pinned = identity;
    notifyListeners();
  }

  // ── The consent step ─────────────────────────────────────────────────────

  /// Listening becomes speaking.
  ///
  /// Writes an ordinary, revocable `passport_shares` row through
  /// `identify_in_space`, then re-mints the token. A short reconnect: it reads
  /// as the state change it is, and it keeps one code path across this app and
  /// the React console.
  Future<void> identifyAndUpgrade() async {
    await _service.client.rpc('identify_in_space', params: {'p_space_id': id});
    await connect();
  }

  // ── Moderation ───────────────────────────────────────────────────────────

  Future<void> loadRoster() async {
    if (!isSpace || !canModerate) return;
    try {
      final rows = await _service.client
          .from('space_roster')
          .select()
          .eq('space_id', id);
      _roster = (rows as List)
          .map((r) => SpaceRosterEntry.fromMap(r as Map<String, dynamic>))
          .where((r) => r.admission != 'removed' && r.admission != 'denied')
          .toList();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('roster failed: $e');
    }
  }

  /// Every moderation action. The app never calls LiveKit for a privileged
  /// operation: the database decides and records it, then the Edge Function
  /// carries it through.
  Future<void> moderate(String participantId, String action, {String? reason}) async {
    try {
      final result = await _service.invoke('livekit-room', body: {
        'action': 'moderate',
        'participant_id': participantId,
        'moderation': action,
        if (reason != null) 'reason': reason,
      });
      if (result['livekit'] == false) {
        _notify('Recorded, but the room did not confirm it.');
      }
      await loadRoster();
    } catch (e) {
      _notify(SupabaseService.describeError(e));
    }
  }

  /// Silences everyone who is not running the session.
  ///
  /// Hosts, cohosts, the appointed moderators and whoever pressed it are
  /// exempt, and that exemption is decided in SQL rather than here — a client
  /// that chose its own exemptions would be a client that could mute a host.
  Future<void> muteEveryone({bool includeVideo = false}) async {
    try {
      final result = await _service.invoke('livekit-room', body: {
        'action': 'mute_all',
        'space_id': id,
        'include_video': includeVideo,
      });
      final count = (result['count'] as num?)?.toInt() ?? 0;
      final tracks = (result['muted'] as num?)?.toInt() ?? 0;
      if (result['livekit'] == false) {
        _notify('Recorded, but the room did not confirm it.');
      } else if (count == 0) {
        _notify('Nobody to mute.');
      } else if (tracks == 0) {
        // The people were there; nothing of theirs was live. Saying "muted 40"
        // here would be a number that reads like a success and is not.
        _notify(includeVideo
            ? 'Nobody had a microphone or camera on.'
            : 'Nobody had a microphone on.');
      } else {
        _notify(includeVideo
            ? 'Muted $count ${count == 1 ? 'person' : 'people'} and their cameras.'
            : 'Muted $count ${count == 1 ? 'person' : 'people'}.');
      }
      await loadRoster();
    } catch (e) {
      _notify(SupabaseService.describeError(e));
    }
  }

  Future<void> endForEveryone() async {
    try {
      await _service.invoke('livekit-room',
          body: {'action': 'end', 'space_id': id});
    } catch (e) {
      _notify(SupabaseService.describeError(e));
    }
    await leave();
  }

  // ── Devices ──────────────────────────────────────────────────────────────

  Future<List<MediaDevice>> devices() async {
    try {
      return await Hardware.instance.enumerateDevices();
    } catch (_) {
      return const [];
    }
  }

  Future<void> selectDevice(MediaDevice device) async {
    try {
      switch (device.kind) {
        case 'audioinput':
          await Hardware.instance.selectAudioInput(device);
        case 'audiooutput':
          await Hardware.instance.selectAudioOutput(device);
        case 'videoinput':
          // Cameras are switched on the published track, not on Hardware:
          // there is no selectVideoInput, because changing camera means
          // restarting the track that is already being sent.
          final track = _cameraTrack;
          if (track != null) await track.switchCamera(device.deviceId);
      }
      notifyListeners();
    } catch (e) {
      _notify('That device could not be selected.');
      if (kDebugMode) debugPrint('device select failed: $e');
    }
  }

  LocalVideoTrack? get _cameraTrack => _me?.videoTrackPublications
      .where((p) => p.source == TrackSource.camera)
      .firstOrNull
      ?.track;

  /// Flipping between the front and back camera, which is what a phone
  /// actually needs — the device list is for desktop.
  Future<void> flipCamera() async {
    final track = _cameraTrack;
    if (track == null) return;
    try {
      // cameraPosition lives on CameraCaptureOptions, not on the base class:
      // a screen-share track has no camera to be in front of or behind.
      final options = track.currentOptions;
      final front = options is CameraCaptureOptions
          ? options.cameraPosition == CameraPosition.front
          : true;
      await track.setCameraPosition(
        front ? CameraPosition.back : CameraPosition.front,
      );
      notifyListeners();
    } catch (e) {
      _notify('That camera could not be used.');
      if (kDebugMode) debugPrint('camera flip failed: $e');
    }
  }

  // ── Leaving ──────────────────────────────────────────────────────────────

  Future<void> leave() async {
    if (isSpace) {
      // Best effort: the roster should say they left even if the network is
      // already gone, but failing to record it must not block the exit.
      try {
        await _service.client.rpc('leave_space', params: {'p_space_id': id});
      } catch (_) {/* leaving is not the moment to raise */}
    }
    await _disposeRoom();
    _phase = CallPhase.ended;
    notifyListeners();
  }

  Future<void> _disposeRoom() async {
    _admissionPoll?.cancel();
    _admissionPoll = null;
    // A reconnect mints a fresh grant anyway, so a queued refresh is at best
    // a wasted mint and at worst one that fires into a disposed provider.
    _grantRefreshRetry?.cancel();
    _grantRefreshRetry = null;
    await _listener?.dispose();
    _listener = null;
    await _room?.disconnect();
    await _room?.dispose();
    _room = null;
  }

  @override
  void dispose() {
    _disposeRoom();
    super.dispose();
  }
}
