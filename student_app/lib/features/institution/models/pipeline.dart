import '../../../core/utils/formatters.dart';

/// One conversation in an institution's inbox.
///
/// Identified by [token], not by an account id. The student's real name is
/// [sharedName], which is null until they share their passport — so the inbox
/// works for an anonymous student without revealing who they are. The console's
/// version read `profiles.full_name` directly, which RLS refuses before a
/// share, so every unshared conversation rendered nameless.
class InboxThread {
  final String conversationId;
  final String token;
  final bool isShared;
  final String? sharedName;

  /// Null until the student shares, exactly like [sharedName]. An avatar is as
  /// identifying as a name here: the same image is on their public handle
  /// profile, so one on an anonymous row would match the thread to a handle.
  final String? sharedAvatarUrl;
  final String? subject;
  final String? lastMessageBody;
  final bool lastMessageFromStudent;
  final int unreadCount;
  final DateTime? lastMessageAt;

  /// The CALLER's own, not the institution's: one officer filing a thread
  /// away must not take it off a colleague's list.
  final DateTime? pinnedAt;
  final DateTime? archivedAt;

  const InboxThread({
    required this.conversationId,
    required this.token,
    required this.isShared,
    this.sharedName,
    this.sharedAvatarUrl,
    this.subject,
    this.lastMessageBody,
    this.lastMessageFromStudent = false,
    this.unreadCount = 0,
    this.lastMessageAt,
    this.pinnedAt,
    this.archivedAt,
  });

  bool get isPinned => pinnedAt != null;
  bool get isArchived => archivedAt != null;

  /// What to put at the top of the row.
  ///
  /// A shortened token rather than "Student": several anonymous threads need
  /// to be told apart, and the same token appears on their match card, so the
  /// two line up.
  String get displayName =>
      sharedName ?? 'Student ${token.substring(0, 6).toUpperCase()}';

  /// Two letters for the avatar fallback, from the name if there is one and
  /// from the token if there is not — so anonymous rows are still told apart.
  String get initials {
    final name = sharedName?.trim();
    if (name == null || name.isEmpty) {
      return token.isEmpty ? '?' : token.substring(0, 2).toUpperCase();
    }
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  bool get hasUnread => unreadCount > 0;

  String get when =>
      lastMessageAt == null ? '' : formatRelative(lastMessageAt!);

  factory InboxThread.fromMap(Map<String, dynamic> map) => InboxThread(
        conversationId: map['conversation_id'] as String,
        token: map['token'] as String? ?? '',
        isShared: map['is_shared'] as bool? ?? false,
        sharedName: map['shared_name'] as String?,
        sharedAvatarUrl: map['shared_avatar_url'] as String?,
        subject: map['subject'] as String?,
        lastMessageBody: map['last_message_body'] as String?,
        lastMessageFromStudent:
            map['last_message_from_student'] as bool? ?? false,
        unreadCount: (map['unread_count'] as num?)?.toInt() ?? 0,
        lastMessageAt: map['last_message_at'] == null
            ? null
            : DateTime.parse(map['last_message_at'] as String),
        pinnedAt: map['pinned_at'] == null
            ? null
            : DateTime.parse(map['pinned_at'] as String).toLocal(),
        archivedAt: map['archived_at'] == null
            ? null
            : DateTime.parse(map['archived_at'] as String).toLocal(),
      );
}

/// One application in the pipeline.
///
/// Carries bands rather than figures — the same non-identifying attributes a
/// match card shows — so staff can judge an application without the passport
/// having been shared.
class PipelineEntry {
  final String applicationId;
  final String token;
  final bool isShared;
  final String? sharedName;

  /// Null until the student shares, exactly like [sharedName]. An avatar is as
  /// identifying as a name here: the same image is on their public handle
  /// profile, so one on an anonymous row would match the thread to a handle.
  final String? sharedAvatarUrl;

  final String programId;
  final String programName;
  final String? programLevel;
  final String? intake;
  final String stage;
  final String? studentNote;

  final int documentCount;
  final int outstandingRequests;

  final int? completeness;
  final String? passportVerification;
  final String? gradeBand;
  final double? englishBand;
  final String? currentCountry;
  final String? nationality;

  final DateTime? submittedAt;
  final DateTime? decisionAt;
  final DateTime updatedAt;

  const PipelineEntry({
    required this.applicationId,
    required this.token,
    required this.isShared,
    this.sharedName,
    this.sharedAvatarUrl,
    required this.programId,
    required this.programName,
    this.programLevel,
    this.intake,
    required this.stage,
    this.studentNote,
    this.documentCount = 0,
    this.outstandingRequests = 0,
    this.completeness,
    this.passportVerification,
    this.gradeBand,
    this.englishBand,
    this.currentCountry,
    this.nationality,
    this.submittedAt,
    this.decisionAt,
    required this.updatedAt,
  });

  String get displayName =>
      sharedName ?? 'Student ${token.substring(0, 6).toUpperCase()}';

  /// Two letters for the avatar fallback, from the name if there is one and
  /// from the token if there is not — so anonymous rows are still told apart.
  String get initials {
    final name = sharedName?.trim();
    if (name == null || name.isEmpty) {
      return token.isEmpty ? '?' : token.substring(0, 2).toUpperCase();
    }
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  bool get needsAttention => outstandingRequests > 0;

  factory PipelineEntry.fromMap(Map<String, dynamic> map) => PipelineEntry(
        applicationId: map['application_id'] as String,
        token: map['token'] as String? ?? '',
        isShared: map['is_shared'] as bool? ?? false,
        sharedName: map['shared_name'] as String?,
        sharedAvatarUrl: map['shared_avatar_url'] as String?,
        programId: map['program_id'] as String,
        programName: map['program_name'] as String? ?? 'Programme',
        programLevel: map['program_level'] as String?,
        intake: map['intake'] as String?,
        stage: map['stage'] as String? ?? 'submitted',
        studentNote: map['student_note'] as String?,
        documentCount: (map['document_count'] as num?)?.toInt() ?? 0,
        outstandingRequests:
            (map['outstanding_requests'] as num?)?.toInt() ?? 0,
        completeness: (map['completeness'] as num?)?.toInt(),
        passportVerification: map['passport_verification'] as String?,
        gradeBand: map['grade_band'] as String?,
        // numeric arrives from Postgres as a string, so this cannot be a cast.
        englishBand: map['english_band'] == null
            ? null
            : double.tryParse(map['english_band'].toString()),
        currentCountry: map['current_country'] as String?,
        nationality: map['nationality'] as String?,
        submittedAt: map['submitted_at'] == null
            ? null
            : DateTime.parse(map['submitted_at'] as String),
        decisionAt: map['decision_at'] == null
            ? null
            : DateTime.parse(map['decision_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

/// The stages, in the order an application actually travels.
///
/// `draft` is absent on purpose: it means the student has not sent it, so it
/// never appears in an institution's pipeline.
const pipelineStages = <String>[
  'submitted',
  'under_review',
  'documents_requested',
  'conditional_offer',
  'offer',
  'accepted',
  'deposit_paid',
  'visa',
  'enrolled',
  'rejected',
  'withdrawn',
];

String stageLabel(String stage) => switch (stage) {
      'draft' => 'Draft',
      'submitted' => 'Submitted',
      'under_review' => 'Under review',
      'documents_requested' => 'Documents requested',
      'conditional_offer' => 'Conditional offer',
      'offer' => 'Offer',
      'rejected' => 'Rejected',
      'accepted' => 'Accepted',
      'deposit_paid' => 'Deposit paid',
      'visa' => 'Visa',
      'enrolled' => 'Enrolled',
      'withdrawn' => 'Withdrawn',
      _ => stage,
    };
