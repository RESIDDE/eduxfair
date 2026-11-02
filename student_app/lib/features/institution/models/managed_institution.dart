import '../../discover/models/institution.dart';
import '../../discover/models/prospectus.dart';

/// The institution the signed-in person works for, as staff see it.
///
/// Distinct from `Institution`, which is the public listing a student browses:
/// this carries the membership role, the subscription tier and the editable
/// profile, none of which belong on the public view.
class ManagedInstitution {
  final Institution institution;
  final InstitutionProfile profile;

  /// 'owner' or 'admissions_officer'. Owners manage seats.
  final String memberRole;

  final String tier;
  final int seats;

  const ManagedInstitution({
    required this.institution,
    required this.profile,
    required this.memberRole,
    this.tier = 'basic',
    this.seats = 1,
  });

  bool get isOwner => memberRole == 'owner';
  bool get isEmbassy => institution.kind == 'embassy';
  bool get isVerified => institution.isVerified;

  int get completeness => profile.completeness;

  /// What to nudge staff to do next, in the order that makes the page useful
  /// soonest. Mirrors how the student passport reports what is missing.
  List<String> get missingPieces {
    final missing = <String>[];
    if ((profile.about ?? '').trim().isEmpty) missing.add('Describe your institution');
    if (profile.costOfLivingMax == null) missing.add('Add living costs');
    if ((profile.campusLife ?? '').trim().isEmpty) missing.add('Describe campus life');
    if ((profile.accommodation ?? '').trim().isEmpty) {
      missing.add('Explain accommodation');
    }
    if (profile.applicationSteps.isEmpty) missing.add('Add how to apply');
    if (profile.rankings.isEmpty && profile.accreditation.isEmpty) {
      missing.add('Add accreditation or rankings');
    }
    return missing;
  }

  String get tierLabel => switch (tier) {
        'enterprise' => 'Enterprise',
        'professional' => 'Professional',
        _ => 'Basic',
      };
}

/// The headline numbers on the institution dashboard, from
/// `my_institution_demand()`.
class InstitutionDemand {
  final int matchedStudents;
  final int sharedPassports;
  final int openApplications;
  final int pendingAppointments;
  final int unreadConversations;
  final int followers;
  final List<FieldDemand> topFields;

  const InstitutionDemand({
    this.matchedStudents = 0,
    this.sharedPassports = 0,
    this.openApplications = 0,
    this.pendingAppointments = 0,
    this.unreadConversations = 0,
    this.followers = 0,
    this.topFields = const [],
  });

  /// Anything waiting on a person, for the badge on the nav.
  int get needsAttention => pendingAppointments + unreadConversations;

  factory InstitutionDemand.fromJson(Map<String, dynamic> json) =>
      InstitutionDemand(
        matchedStudents: (json['matched_students'] as num?)?.toInt() ?? 0,
        sharedPassports: (json['shared_passports'] as num?)?.toInt() ?? 0,
        openApplications: (json['open_applications'] as num?)?.toInt() ?? 0,
        pendingAppointments: (json['pending_appointments'] as num?)?.toInt() ?? 0,
        unreadConversations: (json['unread_conversations'] as num?)?.toInt() ?? 0,
        followers: (json['followers'] as num?)?.toInt() ?? 0,
        topFields: (json['top_fields'] as List? ?? const [])
            .map((e) => FieldDemand.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class FieldDemand {
  final String field;
  final int students;

  const FieldDemand({required this.field, required this.students});

  factory FieldDemand.fromMap(Map<String, dynamic> map) => FieldDemand(
        field: map['field'] as String? ?? '',
        students: (map['students'] as num?)?.toInt() ?? 0,
      );
}
