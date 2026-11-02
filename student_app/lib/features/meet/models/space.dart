/// A scheduled live session. Mirrors `public.spaces`.
class Space {
  final String id;
  final String institutionId;
  final String hostProfileId;
  final String title;
  final String? description;
  final String kind;
  final String status;
  final DateTime scheduledFor;
  final int durationMin;
  final bool requiresAdmission;
  final int maxParticipants;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Only present when the row was read with the institution embedded.
  final String? institutionName;
  final String? institutionLogoUrl;
  final String? institutionSlug;

  const Space({
    required this.id,
    required this.institutionId,
    required this.hostProfileId,
    required this.title,
    required this.scheduledFor,
    this.description,
    this.kind = 'admissions_hour',
    this.status = 'scheduled',
    this.durationMin = 45,
    this.requiresAdmission = false,
    this.maxParticipants = 200,
    this.startedAt,
    this.endedAt,
    this.institutionName,
    this.institutionLogoUrl,
    this.institutionSlug,
  });

  bool get isLive => status == 'live';
  bool get isScheduled => status == 'scheduled';
  bool get isOver => status == 'ended' || status == 'cancelled';

  DateTime get endsAt => scheduledFor.add(Duration(minutes: durationMin));

  /// Mirrors `space_is_open()` in SQL, so the join button and the server cannot
  /// disagree. Ten minutes early, thirty past the end.
  bool get isOpen {
    if (isOver) return false;
    final now = DateTime.now();
    return now.isAfter(scheduledFor.subtract(const Duration(minutes: 10))) &&
        now.isBefore(endsAt.add(const Duration(minutes: 30)));
  }

  String get kindLabel => switch (kind) {
        'admissions_hour' => 'Admissions hour',
        'scholarship_qa' => 'Scholarship Q&A',
        'country_briefing' => 'Country briefing',
        'open_day' => 'Open day',
        _ => kind,
      };

  String get statusLabel => switch (status) {
        'scheduled' => 'Scheduled',
        'live' => 'Live now',
        'ended' => 'Ended',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  factory Space.fromMap(Map<String, dynamic> map) {
    final inst = map['institutions'] as Map<String, dynamic>?;
    return Space(
      id: map['id'] as String,
      institutionId: map['institution_id'] as String,
      hostProfileId: map['host_profile_id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      kind: map['kind'] as String? ?? 'admissions_hour',
      status: map['status'] as String? ?? 'scheduled',
      scheduledFor: DateTime.parse(map['scheduled_for'] as String).toLocal(),
      durationMin: (map['duration_min'] as num?)?.toInt() ?? 45,
      requiresAdmission: map['requires_admission'] as bool? ?? false,
      maxParticipants: (map['max_participants'] as num?)?.toInt() ?? 200,
      startedAt: map['started_at'] == null
          ? null
          : DateTime.parse(map['started_at'] as String).toLocal(),
      endedAt: map['ended_at'] == null
          ? null
          : DateTime.parse(map['ended_at'] as String).toLocal(),
      institutionName: inst?['name'] as String?,
      institutionLogoUrl: inst?['logo_url'] as String?,
      institutionSlug: inst?['slug'] as String?,
    );
  }
}

/// A row of `space_roster` — the institution's view of its own room.
///
/// Deliberately has no profile id. That absence is what lets a host admit, mute
/// and remove a listener they still cannot name.
class SpaceRosterEntry {
  final String participantId;
  final String spaceId;
  final String role;
  final String admission;
  final String? handle;
  final String? sharedName;
  final bool isIdentified;
  final DateTime? handRaisedAt;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  const SpaceRosterEntry({
    required this.participantId,
    required this.spaceId,
    required this.role,
    required this.admission,
    this.handle,
    this.sharedName,
    this.isIdentified = false,
    this.handRaisedAt,
    this.joinedAt,
    this.leftAt,
  });

  bool get isWaiting => admission == 'pending';
  bool get isIn => admission == 'admitted';
  bool get isStaff => role == 'host' || role == 'cohost';

  /// A name only once they have shared it; a handle until then.
  String get label =>
      sharedName ?? (handle != null ? '@$handle' : 'A student');

  factory SpaceRosterEntry.fromMap(Map<String, dynamic> map) => SpaceRosterEntry(
        participantId: map['participant_id'] as String,
        spaceId: map['space_id'] as String,
        role: map['role'] as String,
        admission: map['admission'] as String,
        handle: map['handle'] as String?,
        sharedName: map['shared_name'] as String?,
        isIdentified: map['is_identified'] as bool? ?? false,
        handRaisedAt: map['hand_raised_at'] == null
            ? null
            : DateTime.parse(map['hand_raised_at'] as String).toLocal(),
        joinedAt: map['joined_at'] == null
            ? null
            : DateTime.parse(map['joined_at'] as String).toLocal(),
        leftAt: map['left_at'] == null
            ? null
            : DateTime.parse(map['left_at'] as String).toLocal(),
      );
}

/// One in-room chat message. `space_messages` for a Space; the existing
/// `messages` thread for a 1:1 appointment.
class SpaceMessage {
  final String id;
  final String? participantId;
  final String? senderId;
  final String body;
  final DateTime createdAt;

  const SpaceMessage({
    required this.id,
    required this.body,
    required this.createdAt,
    this.participantId,
    this.senderId,
  });

  factory SpaceMessage.fromMap(Map<String, dynamic> map) => SpaceMessage(
        id: map['id'] as String,
        participantId: map['participant_id'] as String?,
        senderId: map['sender_id'] as String?,
        body: map['body'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}
