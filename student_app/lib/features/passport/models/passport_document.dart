import '../../../core/constants/app_constants.dart';

/// A document attached to the passport. Mirrors `public.passport_documents`.
///
/// `storagePath` always begins with the owner's uuid: the storage policy
/// authorizes on that first path segment, and there is a CHECK constraint
/// enforcing it. Build paths with `SupabaseService.passportDocPath`.
class PassportDocument {
  final String id;
  final String profileId;
  final String kind;
  final String storagePath;
  final String fileName;
  final String? mime;
  final int? sizeBytes;
  final String verificationStatus;
  final String? reviewNote;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const PassportDocument({
    required this.id,
    required this.profileId,
    required this.kind,
    required this.storagePath,
    required this.fileName,
    this.mime,
    this.sizeBytes,
    this.verificationStatus = 'pending',
    this.reviewNote,
    this.reviewedAt,
    required this.createdAt,
  });

  String get kindLabel => AppConstants.documentKinds[kind] ?? kind;

  bool get isVerified => verificationStatus == 'verified';
  bool get isRejected => verificationStatus == 'rejected';
  bool get isPending => verificationStatus == 'pending';

  bool get isImage => (mime ?? '').startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  String get sizeDisplay {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory PassportDocument.fromMap(Map<String, dynamic> map) => PassportDocument(
        id: map['id'] as String,
        profileId: map['profile_id'] as String,
        kind: map['kind'] as String,
        storagePath: map['storage_path'] as String,
        fileName: map['file_name'] as String,
        mime: map['mime'] as String?,
        sizeBytes: (map['size_bytes'] as num?)?.toInt(),
        verificationStatus: map['verification_status'] as String? ?? 'pending',
        reviewNote: map['review_note'] as String?,
        reviewedAt: map['reviewed_at'] == null
            ? null
            : DateTime.parse(map['reviewed_at'] as String),
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}
