import 'dart:convert';
import 'dart:typed_data';

/// The in-room protocol.
///
/// ───────────────────────────────────────────────────────────────────────────
///  THIS FILE HAS A TWIN: `web/src/lib/livekit.js`
///
///  Every constant here is part of a wire contract between the Flutter app and
///  the React console. They talk to each other through LiveKit, which does no
///  validation of its own, so a value that differs between the two does not
///  error — it silently fails to arrive, or mutes the wrong person. Change one
///  file and you must change the other.
/// ───────────────────────────────────────────────────────────────────────────
///
/// Identities are minted ONLY by the `livekit-token` Edge Function, never built
/// here:
///
///   space        `sp_<space_participants.id>`
///   appointment  `ap_<appointments.id>_s`   (student)
///                `ap_<appointments.id>_h`   (host)
///
/// RoomService compares identities byte for byte, so parsing one is fine and
/// constructing one is not.
class RoomProtocol {
  const RoomProtocol._();

  /// Carried in room metadata and every data payload. A client that sees a
  /// version it does not know says so rather than guessing.
  static const int version = 1;

  // ── Participant attributes ───────────────────────────────────────────────
  //
  // Server-stored, and synced to anyone who joins later. Three of these are set
  // inside the signed token, which is what makes them unforgeable — a client
  // cannot claim to be a host by writing its own metadata. Only [attrHand] is
  // client-written. Authority is server-set; intent is client-set.

  /// `host` | `cohost` | `moderator` | `speaker` | `listener` —
  /// server-asserted.
  static const String attrRole = 'lk_role';

  /// The `space_participants.id` — server-asserted.
  static const String attrParticipantId = 'pid';

  /// The public handle, without the `@` — server-asserted.
  static const String attrHandle = 'handle';

  /// `''` when down, or an ISO-8601 instant — written by the participant.
  ///
  /// An empty string rather than removing the key: deletion semantics differ
  /// across SDK versions, and both clients read `''` as down.
  static const String attrHand = 'hand';

  // ── Data-packet topics ───────────────────────────────────────────────────
  //
  // One, deliberately. Everything durable lives in Postgres.

  static const String topicReaction = 'reaction';

  /// LiveKit refuses remote UNmute unless the deployment sets
  /// `enable_remote_unmute`, so a host cannot simply turn someone's microphone
  /// back on. Asking is a packet; muting is a server call.
  static const String topicAskUnmute = 'ask_unmute';

  /// The roles that may moderate, in agreement with `space_can_moderate()`.
  ///
  /// `moderator` is an attendee the host appointed, NOT staff: they hold the
  /// same mute and remove buttons and none of the institution's visibility, so
  /// nothing that reveals who somebody is may key off this list.
  static const List<String> moderatorRoles = ['host', 'cohost', 'moderator'];

  /// Staff of the hosting institution. Appointing a moderator is theirs alone.
  static const List<String> staffRoles = ['host', 'cohost'];

  /// The six reactions, fixed.
  ///
  /// An open emoji field is an open text field, and these rooms can have minors
  /// in them. Validated on RECEIVE as well as on send, because a misbehaving
  /// client can publish whatever it likes.
  static const List<String> reactions = ['👏', '❤️', '😂', '😮', '🎉', '👍'];

  /// Attributes are explicitly not for sub-second updates.
  static const Duration handDebounce = Duration(seconds: 1);

  static const int _reactionLimit = 3;
  static const Duration _reactionWindow = Duration(seconds: 2);

  // ── Codecs ───────────────────────────────────────────────────────────────

  static Uint8List encodeReaction(String emoji, String? participantId) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'v': version,
        't': 'reaction',
        'emoji': emoji,
        'pid': participantId ?? '',
        'at': DateTime.now().millisecondsSinceEpoch,
      })));

  /// Decodes a received packet, or null for anything we did not agree on.
  static String? decodeReaction(List<int> payload) {
    try {
      final msg = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      if (msg['v'] != version || msg['t'] != 'reaction') return null;
      final emoji = msg['emoji'] as String?;
      if (emoji == null || !reactions.contains(emoji)) return null;
      return emoji;
    } catch (_) {
      // Dropped without logging: a misbehaving client is not worth a line of
      // output per packet.
      return null;
    }
  }

  static Uint8List encodeAskUnmute() => Uint8List.fromList(
      utf8.encode(jsonEncode({'v': version, 't': 'ask_unmute'})));

  static bool isAskUnmute(List<int> payload) {
    try {
      final msg = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return msg['v'] == version && msg['t'] == 'ask_unmute';
    } catch (_) {
      return false;
    }
  }

  /// Room metadata, as `livekit-room` writes it on `go_live`.
  static Map<String, dynamic>? parseRoomMetadata(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      return meta['v'] == version ? meta : null;
    } catch (_) {
      return null;
    }
  }
}

/// Drops inbound reactions from a sender who is sending too many.
class ReactionLimiter {
  final Map<String, List<DateTime>> _seen = {};

  bool allow(String identity) {
    final now = DateTime.now();
    final recent = (_seen[identity] ?? [])
        .where((t) => now.difference(t) < RoomProtocol._reactionWindow)
        .toList();
    if (recent.length >= RoomProtocol._reactionLimit) return false;
    recent.add(now);
    _seen[identity] = recent;
    return true;
  }
}

/// Which kind of room a route is asking for.
enum CallKind {
  space,
  appointment;

  static CallKind parse(String raw) =>
      raw == 'appointment' ? CallKind.appointment : CallKind.space;

  String get wire => name;
}
