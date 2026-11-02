import '../../../core/constants/app_constants.dart';
import '../../discover/models/institution.dart';
import '../../discover/models/program.dart';

/// One step in an application's history. Mirrors `public.application_events`,
/// which is append-only: there is no UPDATE or DELETE policy for any role,
/// admin included, because a decision history that can be edited is not one.
class ApplicationEvent {
  final String id;
  final String? fromStage;
  final String toStage;
  final String? note;
  final DateTime createdAt;

  const ApplicationEvent({
    required this.id,
    this.fromStage,
    required this.toStage,
    this.note,
    required this.createdAt,
  });

  String get stageLabel =>
      AppConstants.applicationStages[toStage] ?? toStage;

  factory ApplicationEvent.fromMap(Map<String, dynamic> map) => ApplicationEvent(
        id: map['id'] as String,
        fromStage: map['from_stage'] as String?,
        toStage: map['to_stage'] as String,
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}

/// A document the institution has asked for.
class DocumentRequest {
  final String id;
  final String applicationId;
  final String kind;
  final String? note;
  final DateTime? fulfilledAt;
  final DateTime createdAt;

  const DocumentRequest({
    required this.id,
    required this.applicationId,
    required this.kind,
    this.note,
    this.fulfilledAt,
    required this.createdAt,
  });

  bool get isOutstanding => fulfilledAt == null;
  String get kindLabel => AppConstants.documentKinds[kind] ?? kind;

  factory DocumentRequest.fromMap(Map<String, dynamic> map) => DocumentRequest(
        id: map['id'] as String,
        applicationId: map['application_id'] as String,
        kind: map['kind'] as String,
        note: map['note'] as String?,
        fulfilledAt: map['fulfilled_at'] == null
            ? null
            : DateTime.parse(map['fulfilled_at'] as String).toLocal(),
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}

/// An application. Mirrors `public.applications`.
class Application {
  final String id;
  final String profileId;
  final String institutionId;
  final String programId;
  final String? intake;
  final String stage;
  final String? studentNote;
  final DateTime? submittedAt;
  final DateTime? decisionAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  final Institution? institution;
  final Program? program;
  final List<ApplicationEvent> events;
  final List<DocumentRequest> documentRequests;

  const Application({
    required this.id,
    required this.profileId,
    required this.institutionId,
    required this.programId,
    this.intake,
    this.stage = 'draft',
    this.studentNote,
    this.submittedAt,
    this.decisionAt,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.program,
    this.events = const [],
    this.documentRequests = const [],
  });

  String get stageLabel => AppConstants.applicationStages[stage] ?? stage;

  bool get isDraft => stage == 'draft';
  bool get isClosed => stage == 'rejected' || stage == 'withdrawn';
  bool get hasOffer => stage == 'offer' || stage == 'conditional_offer';
  bool get isSuccessful =>
      stage == 'accepted' || stage == 'deposit_paid' ||
      stage == 'visa' || stage == 'enrolled';

  List<DocumentRequest> get outstandingRequests =>
      documentRequests.where((r) => r.isOutstanding).toList();

  /// Which stage transitions to offer the student a button for.
  ///
  /// `guard_application_stage()` in the database is the authority; this only
  /// decides what to render, so a student is never shown an action that will
  /// be refused.
  List<String> get availableActions {
    if (stage == 'draft') return const ['submitted'];
    if (hasOffer) return const ['accepted', 'withdrawn'];
    if (isClosed || isSuccessful) return const [];
    return const ['withdrawn'];
  }

  /// Rough progress through the pipeline, for the tracker bar. Closed
  /// applications report 0 so a rejection does not render as near-complete.
  double get progress {
    if (isClosed) return 0;
    const order = [
      'draft', 'submitted', 'under_review', 'documents_requested',
      'conditional_offer', 'offer', 'accepted', 'deposit_paid',
      'visa', 'enrolled',
    ];
    final index = order.indexOf(stage);
    if (index < 0) return 0;
    return (index + 1) / order.length;
  }

  factory Application.fromMap(Map<String, dynamic> map) {
    final inst = map['institutions'] as Map<String, dynamic>?;
    final prog = map['programs'] as Map<String, dynamic>?;
    final events = map['application_events'] as List?;
    final requests = map['application_document_requests'] as List?;

    return Application(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      institutionId: map['institution_id'] as String,
      programId: map['program_id'] as String,
      intake: map['intake'] as String?,
      stage: map['stage'] as String? ?? 'draft',
      studentNote: map['student_note'] as String?,
      submittedAt: map['submitted_at'] == null
          ? null
          : DateTime.parse(map['submitted_at'] as String).toLocal(),
      decisionAt: map['decision_at'] == null
          ? null
          : DateTime.parse(map['decision_at'] as String).toLocal(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      institution: inst == null ? null : Institution.fromMap(inst),
      program: prog == null ? null : Program.fromMap(prog),
      events: events == null
          ? const []
          : events
              .map((e) => ApplicationEvent.fromMap(e as Map<String, dynamic>))
              .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      documentRequests: requests == null
          ? const []
          : requests
              .map((r) => DocumentRequest.fromMap(r as Map<String, dynamic>))
              .toList(),
    );
  }
}
