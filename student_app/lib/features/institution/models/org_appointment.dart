/// An appointment viewed from the institution admissions desk.
class OrgAppointment {
  final String id;
  final String status;
  final DateTime? scheduledFor;
  final int durationMin;
  final String channel;
  final String meetingMode;
  final String? meetingUrl;
  final String? studentMessage;
  final String? notes;
  final String studentId;
  final String studentName;
  final String? programId;
  final String? programName;
  final DateTime? createdAt;

  const OrgAppointment({
    required this.id,
    required this.status,
    this.scheduledFor,
    this.durationMin = 30,
    this.channel = 'video',
    this.meetingMode = 'lekkside_room',
    this.meetingUrl,
    this.studentMessage,
    this.notes,
    required this.studentId,
    required this.studentName,
    this.programId,
    this.programName,
    this.createdAt,
  });

  bool get isRequested => status == 'requested';
  bool get isConfirmed => status == 'confirmed';
  bool get isDeclined => status == 'declined';
  bool get isCancelled => status == 'cancelled';
  bool get isCompleted => status == 'completed';

  bool get isUpcoming =>
      isConfirmed &&
      scheduledFor != null &&
      scheduledFor!.isAfter(DateTime.now().subtract(Duration(minutes: durationMin)));

  bool get isLekksideRoom =>
      channel == 'video' && meetingMode == 'lekkside_room';

  bool get canJoinNow {
    if (!isConfirmed || scheduledFor == null) return false;
    final now = DateTime.now();
    return now.isAfter(scheduledFor!.subtract(const Duration(minutes: 10))) &&
        now.isBefore(scheduledFor!.add(Duration(minutes: durationMin + 15)));
  }

  String get statusLabel => switch (status) {
        'requested' => 'Pending request',
        'confirmed' => 'Confirmed',
        'declined' => 'Declined',
        'cancelled' => 'Cancelled',
        'completed' => 'Completed',
        _ => status,
      };

  factory OrgAppointment.fromMap(Map<String, dynamic> map) {
    final student = map['student'] as Map<String, dynamic>?;
    final program = map['programs'] as Map<String, dynamic>?;

    return OrgAppointment(
      id: map['id'] as String,
      status: map['status'] as String? ?? 'requested',
      scheduledFor: map['scheduled_for'] != null
          ? DateTime.tryParse(map['scheduled_for'] as String)?.toLocal()
          : null,
      durationMin: (map['duration_min'] as num?)?.toInt() ?? 30,
      channel: map['channel'] as String? ?? 'video',
      meetingMode: map['meeting_mode'] as String? ?? 'lekkside_room',
      meetingUrl: map['meeting_url'] as String?,
      studentMessage: map['student_message'] as String?,
      notes: map['notes'] as String?,
      studentId: map['student_id'] as String? ?? student?['id'] as String? ?? '',
      studentName: student?['full_name'] as String? ?? 'Student',
      programId: map['program_id'] as String?,
      programName: program?['name'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toLocal()
          : null,
    );
  }
}
