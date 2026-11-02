import 'room_protocol.dart';

/// The `livekit-token` response.
///
/// Three shapes come back, distinguished by [admission]:
///
///   admitted  carries a token and the full grant
///   pending   a host has not let them in yet
///   closed    outside the join window
///
/// Only the first has a token, and the server decides every permission on it —
/// a client that could choose its own `displayName` could put somebody else's
/// name on its own video.
class CallGrant {
  final String admission;
  final String? url;
  final String? token;
  final String? room;
  final String? identity;
  final String? participantId;
  final String? handle;
  final String displayName;
  final String role;
  final bool isHost;
  final bool canPublish;
  final bool canPublishData;
  final bool canSubscribe;
  final List<String> publishSources;

  /// Set when the function ran but LiveKit is not configured. A sentence to
  /// show, not a crash: the authorization above it was still real.
  final String? error;

  /// Present for a Space.
  final Map<String, dynamic>? space;

  /// Present for an appointment, and carries `conversation_id` so the call
  /// screen knows where its chat lives without a second query.
  final Map<String, dynamic>? appointment;

  final DateTime? opensAt;

  const CallGrant({
    required this.admission,
    this.url,
    this.token,
    this.room,
    this.identity,
    this.participantId,
    this.handle,
    this.displayName = '',
    this.role = 'listener',
    this.isHost = false,
    this.canPublish = false,
    this.canPublishData = false,
    this.canSubscribe = true,
    this.publishSources = const [],
    this.error,
    this.space,
    this.appointment,
    this.opensAt,
  });

  bool get isAdmitted => admission == 'admitted';
  bool get isPending => admission == 'pending';
  bool get isClosed => admission == 'closed';
  bool get canModerate => RoomProtocol.moderatorRoles.contains(role);

  /// Staff of the hosting institution. Appointing a moderator, and acting on
  /// one, is theirs alone — an appointed moderator runs the room, not the
  /// people who appointed them.
  bool get isStaff => RoomProtocol.staffRoles.contains(role);
  bool get canScreenShare => publishSources.contains('screen_share');

  /// Signed and ready to connect with. False when LiveKit is unconfigured,
  /// which the dev server reports truthfully rather than faking a token.
  bool get canConnect => isAdmitted && (token?.isNotEmpty ?? false);

  String get title =>
      space?['title'] as String? ??
      (appointment != null ? 'Meeting with $institutionName' : 'Live room');

  String get institutionName =>
      space?['institution'] as String? ??
      appointment?['institution'] as String? ??
      'this institution';

  String? get spaceId => space?['id'] as String?;
  String? get conversationId => appointment?['conversation_id'] as String?;

  factory CallGrant.fromMap(Map<String, dynamic> map) => CallGrant(
        admission: map['admission'] as String? ?? 'closed',
        url: map['url'] as String?,
        token: map['token'] as String?,
        room: map['room'] as String?,
        identity: map['identity'] as String?,
        participantId: map['participant_id'] as String?,
        handle: map['handle'] as String?,
        displayName: map['display_name'] as String? ?? '',
        role: map['role'] as String? ?? 'listener',
        isHost: map['is_host'] as bool? ?? false,
        canPublish: map['can_publish'] as bool? ?? false,
        canPublishData: map['can_publish_data'] as bool? ?? false,
        canSubscribe: map['can_subscribe'] as bool? ?? true,
        publishSources:
            ((map['publish_sources'] as List?) ?? const []).cast<String>(),
        error: map['error'] as String?,
        space: map['space'] as Map<String, dynamic>?,
        appointment: map['appointment'] as Map<String, dynamic>?,
        opensAt: map['opens_at'] == null
            ? null
            : DateTime.parse(map['opens_at'] as String).toLocal(),
      );
}
