/// A student as an institution sees them through `institution_student_passport`.
///
/// [isShared] decides how much there is. Without a share only [applications]
/// and the [documents] the student sent are filled in; everything identifying
/// stays null, exactly as the database returned it.
class SharedStudent {
  final String token;
  final bool isShared;
  final DateTime? sharedAt;
  final String? shareReason;

  final String? fullName;
  final String? avatarUrl;
  final String? email;
  final String? phone;
  final String? country;
  final String? handle;

  /// The `student_passports` row, as-is. Null without a share, or if they
  /// never started one.
  final Map<String, dynamic>? passport;
  final Map<String, String> fieldLabels;

  final List<SharedDocument> documents;
  final List<SharedApplication> applications;

  const SharedStudent({
    required this.token,
    required this.isShared,
    this.sharedAt,
    this.shareReason,
    this.fullName,
    this.avatarUrl,
    this.email,
    this.phone,
    this.country,
    this.handle,
    this.passport,
    this.fieldLabels = const {},
    this.documents = const [],
    this.applications = const [],
  });

  String get displayName =>
      fullName ?? 'Student ${token.length >= 6 ? token.substring(0, 6).toUpperCase() : token}';

  String get initials {
    final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return token.length >= 2 ? token.substring(0, 2).toUpperCase() : '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory SharedStudent.fromMap(Map<String, dynamic> map,
      {Map<String, String> fieldLabels = const {}}) {
    final student = (map['student'] as Map?)?.cast<String, dynamic>();
    final share = (map['share'] as Map?)?.cast<String, dynamic>();
    return SharedStudent(
      token: map['token'] as String? ?? '',
      isShared: map['shared'] as bool? ?? false,
      sharedAt: _date(share?['granted_at']),
      shareReason: share?['reason'] as String?,
      fullName: student?['full_name'] as String?,
      avatarUrl: student?['avatar_url'] as String?,
      email: student?['email'] as String?,
      phone: student?['phone'] as String?,
      country: student?['country'] as String?,
      handle: student?['handle'] as String?,
      passport: (map['passport'] as Map?)?.cast<String, dynamic>(),
      fieldLabels: fieldLabels,
      documents: [
        for (final d in (map['documents'] as List? ?? const []))
          SharedDocument.fromMap((d as Map).cast<String, dynamic>()),
      ],
      applications: [
        for (final a in (map['applications'] as List? ?? const []))
          SharedApplication.fromMap((a as Map).cast<String, dynamic>()),
      ],
    );
  }
}

class SharedDocument {
  final String id;
  final String kind;
  final String fileName;
  final String? mime;
  final int? sizeBytes;
  final String storagePath;
  final String verificationStatus;
  final DateTime? createdAt;

  const SharedDocument({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.storagePath,
    this.mime,
    this.sizeBytes,
    this.verificationStatus = 'unverified',
    this.createdAt,
  });

  factory SharedDocument.fromMap(Map<String, dynamic> map) => SharedDocument(
        id: map['id'] as String,
        kind: map['kind'] as String? ?? '',
        fileName: map['file_name'] as String? ?? 'Document',
        mime: map['mime'] as String?,
        sizeBytes: (map['size_bytes'] as num?)?.toInt(),
        storagePath: map['storage_path'] as String,
        verificationStatus: map['verification_status'] as String? ?? 'unverified',
        createdAt: _date(map['created_at']),
      );
}

class SharedApplication {
  final String id;
  final String? programName;
  final String? programLevel;
  final String? intake;
  final String stage;
  final DateTime? submittedAt;
  final List<SharedRequest> requests;
  final Set<String> documentIds;

  const SharedApplication({
    required this.id,
    required this.stage,
    this.programName,
    this.programLevel,
    this.intake,
    this.submittedAt,
    this.requests = const [],
    this.documentIds = const {},
  });

  factory SharedApplication.fromMap(Map<String, dynamic> map) => SharedApplication(
        id: map['id'] as String,
        stage: map['stage'] as String? ?? 'submitted',
        programName: map['program_name'] as String?,
        programLevel: map['program_level'] as String?,
        intake: map['intake'] as String?,
        submittedAt: _date(map['submitted_at']),
        requests: [
          for (final r in (map['requests'] as List? ?? const []))
            SharedRequest.fromMap((r as Map).cast<String, dynamic>()),
        ],
        documentIds: {
          for (final id in (map['document_ids'] as List? ?? const [])) id as String,
        },
      );
}

class SharedRequest {
  final String id;
  final String kind;
  final String? note;
  final DateTime? fulfilledAt;
  final DateTime? createdAt;

  const SharedRequest({
    required this.id,
    required this.kind,
    this.note,
    this.fulfilledAt,
    this.createdAt,
  });

  bool get isOutstanding => fulfilledAt == null;

  factory SharedRequest.fromMap(Map<String, dynamic> map) => SharedRequest(
        id: map['id'] as String,
        kind: map['kind'] as String? ?? '',
        note: map['note'] as String?,
        fulfilledAt: _date(map['fulfilled_at']),
        createdAt: _date(map['created_at']),
      );
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
