import '../../fairs/models/fair.dart';

/// An exhibitor booth assignment for this institution.
class OrgExhibitor {
  final String id;
  final String fairId;
  final String boothCode;
  final String? boothLabel;
  final String package;
  final Fair? fair;

  const OrgExhibitor({
    required this.id,
    required this.fairId,
    required this.boothCode,
    this.boothLabel,
    this.package = 'booth_only',
    this.fair,
  });

  factory OrgExhibitor.fromMap(Map<String, dynamic> map) {
    final fairData = map['fairs'] as Map<String, dynamic>?;
    return OrgExhibitor(
      id: map['id'] as String,
      fairId: map['fair_id'] as String,
      boothCode: map['booth_code'] as String? ?? '',
      boothLabel: map['booth_label'] as String?,
      package: map['package'] as String? ?? 'booth_only',
      fair: fairData != null ? Fair.fromMap(fairData) : null,
    );
  }
}

/// A lead recorded at a booth during an education fair.
class OrgBoothLead {
  final String id;
  final String exhibitorId;
  final String? studentId;
  final String studentName;
  final String? studentCountry;
  final String? programId;
  final String? programName;
  final String? programInterest;
  final String interestLevel;
  final bool followUpRequested;
  final bool scholarshipDiscussed;
  final String? note;
  final DateTime createdAt;

  const OrgBoothLead({
    required this.id,
    required this.exhibitorId,
    this.studentId,
    required this.studentName,
    this.studentCountry,
    this.programId,
    this.programName,
    this.programInterest,
    this.interestLevel = 'medium',
    this.followUpRequested = false,
    this.scholarshipDiscussed = false,
    this.note,
    required this.createdAt,
  });

  factory OrgBoothLead.fromMap(Map<String, dynamic> map) {
    final student = map['student'] as Map<String, dynamic>?;
    final program = map['programs'] as Map<String, dynamic>?;

    return OrgBoothLead(
      id: map['id'] as String,
      exhibitorId: map['exhibitor_id'] as String,
      studentId: student?['id'] as String? ?? map['profile_id'] as String?,
      studentName: student?['full_name'] as String? ?? 'Student',
      studentCountry: student?['country'] as String?,
      programId: map['program_id'] as String?,
      programName: program?['name'] as String?,
      programInterest: map['program_interest'] as String?,
      interestLevel: map['interest_level'] as String? ?? 'medium',
      followUpRequested: map['follow_up_requested'] as bool? ?? false,
      scholarshipDiscussed: map['scholarship_discussed'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
