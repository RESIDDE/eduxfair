import '../../discover/models/institution.dart';

/// An open slot an institution has published.
class AvailabilitySlot {
  final String id;
  final String institutionId;
  final String hostProfileId;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isBooked;

  const AvailabilitySlot({
    required this.id,
    required this.institutionId,
    required this.hostProfileId,
    required this.startsAt,
    required this.endsAt,
    this.isBooked = false,
  });

  Duration get duration => endsAt.difference(startsAt);

  factory AvailabilitySlot.fromMap(Map<String, dynamic> map) => AvailabilitySlot(
        id: map['id'] as String,
        institutionId: map['institution_id'] as String,
        hostProfileId: map['host_profile_id'] as String,
        startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(map['ends_at'] as String).toLocal(),
        isBooked: map['is_booked'] as bool? ?? false,
      );
}

/// A Meet Me appointment. Mirrors `public.appointments`.
///
/// A confirmed video appointment is held in a Lekkside room by default, and
/// `meetingMode` is what says so — a null `meetingUrl` used to mean both "we
/// host it" and "the institution has not supplied a link yet", which is why the
/// distinction is a column rather than an absence.
class Appointment {
  final String id;
  final String studentId;
  final String institutionId;
  final String? programId;
  final String? programName;
  final DateTime? scheduledFor;
  final int durationMin;
  final String channel;
  final String status;

  /// `lekkside_room` or `external_link`.
  final String meetingMode;
  final String? meetingUrl;
  final String? studentMessage;
  final String? notes;
  final DateTime createdAt;
  final Institution? institution;

  const Appointment({
    required this.id,
    required this.studentId,
    required this.institutionId,
    this.programId,
    this.programName,
    this.scheduledFor,
    this.durationMin = 30,
    this.channel = 'video',
    this.status = 'requested',
    this.meetingMode = 'lekkside_room',
    this.meetingUrl,
    this.studentMessage,
    this.notes,
    required this.createdAt,
    this.institution,
  });

  bool get isRequested => status == 'requested';
  bool get isConfirmed => status == 'confirmed';
  bool get isDeclined => status == 'declined';
  bool get isCancelled => status == 'cancelled';
  bool get isComplete => status == 'completed';

  /// Held in a Lekkside room, rather than on a link the institution pasted.
  bool get isLekksideRoom =>
      channel == 'video' && meetingMode == 'lekkside_room';

  /// Still ahead and not called off, so it belongs in "upcoming".
  bool get isUpcoming =>
      (isConfirmed || isRequested) &&
      (scheduledFor?.isAfter(DateTime.now()) ?? true);

  /// Whether the join button should be live. Opens ten minutes early, because
  /// nobody joins a call at exactly the appointed second.
  ///
  /// A Lekkside room needs no `meetingUrl` — the room is derived from the
  /// appointment id, and `appointment_room_grant()` enforces this same window
  /// server-side. An external meeting still needs its link, because there is
  /// nothing to open without one.
  bool get canJoinNow {
    if (!isConfirmed || scheduledFor == null) return false;
    if (!isLekksideRoom && meetingUrl == null) return false;
    final now = DateTime.now();
    return now.isAfter(scheduledFor!.subtract(const Duration(minutes: 10))) &&
        now.isBefore(scheduledFor!.add(Duration(minutes: durationMin + 15)));
  }

  String get statusLabel => switch (status) {
        'requested' => 'Awaiting confirmation',
        'confirmed' => 'Confirmed',
        'declined' => 'Declined',
        'rescheduled' => 'Rescheduled',
        'completed' => 'Completed',
        'no_show' => 'Missed',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  String get channelLabel => switch (channel) {
        'video' => 'Video call',
        'phone' => 'Phone call',
        'in_person' => 'In person',
        'chat' => 'Chat',
        _ => channel,
      };

  factory Appointment.fromMap(Map<String, dynamic> map) {
    final inst = map['institutions'] as Map<String, dynamic>?;
    final prog = map['programs'] as Map<String, dynamic>?;
    return Appointment(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      institutionId: map['institution_id'] as String,
      programId: map['program_id'] as String?,
      programName: prog?['name'] as String?,
      scheduledFor: map['scheduled_for'] == null
          ? null
          : DateTime.parse(map['scheduled_for'] as String).toLocal(),
      durationMin: (map['duration_min'] as num?)?.toInt() ?? 30,
      channel: map['channel'] as String? ?? 'video',
      status: map['status'] as String? ?? 'requested',
      meetingMode: map['meeting_mode'] as String? ?? 'lekkside_room',
      meetingUrl: map['meeting_url'] as String?,
      studentMessage: map['student_message'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      institution: inst == null ? null : Institution.fromMap(inst),
    );
  }
}
