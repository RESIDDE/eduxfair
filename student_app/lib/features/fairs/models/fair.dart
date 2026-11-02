/// A Lekkside education fair.
class Fair {
  final String id;
  final String name;
  final String slug;
  final String? city;
  final String? country;
  final String? venue;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  const Fair({
    required this.id,
    required this.name,
    required this.slug,
    this.city,
    this.country,
    this.venue,
    required this.startsAt,
    required this.endsAt,
    this.isActive = true,
  });

  bool get isUpcoming => startsAt.isAfter(DateTime.now());
  bool get isOver => endsAt.isBefore(DateTime.now());
  bool get isOnNow => !isUpcoming && !isOver;

  String get location => [city, country].whereType<String>().join(', ');

  factory Fair.fromMap(Map<String, dynamic> map) => Fair(
        id: map['id'] as String,
        name: map['name'] as String,
        slug: map['slug'] as String? ?? '',
        city: map['city'] as String?,
        country: map['country'] as String?,
        venue: map['venue'] as String?,
        startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(map['ends_at'] as String).toLocal(),
        isActive: map['is_active'] as bool? ?? true,
      );
}

/// The student's Fair Passport: the QR a booth scans.
///
/// `passCode` is the QR payload. It is scoped to one fair, so a leaked code
/// expires with the event, and the scan itself is authorized by the staff
/// member's booth membership — not by knowing the code.
class FairRegistration {
  final String id;
  final String fairId;
  final String passCode;
  final DateTime? checkedInAt;
  final DateTime createdAt;
  final Fair? fair;

  const FairRegistration({
    required this.id,
    required this.fairId,
    required this.passCode,
    this.checkedInAt,
    required this.createdAt,
    this.fair,
  });

  bool get isCheckedIn => checkedInAt != null;

  /// Grouped for legibility when read aloud at a registration desk.
  String get displayCode => passCode.length == 8
      ? '${passCode.substring(0, 4)} ${passCode.substring(4)}'
      : passCode;

  factory FairRegistration.fromMap(Map<String, dynamic> map) {
    final fair = map['fairs'] as Map<String, dynamic>?;
    return FairRegistration(
      id: map['id'] as String,
      fairId: map['fair_id'] as String,
      passCode: map['pass_code'] as String,
      checkedInAt: map['checked_in_at'] == null
          ? null
          : DateTime.parse(map['checked_in_at'] as String).toLocal(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      fair: fair == null ? null : Fair.fromMap(fair),
    );
  }
}

/// A booth the student connected with.
class BoothVisit {
  final String id;
  final String institutionName;
  final String? institutionLogoUrl;
  final String? boothLabel;
  final String? programInterest;
  final String interestLevel;
  final bool followUpRequested;
  final bool scholarshipDiscussed;
  final DateTime createdAt;

  const BoothVisit({
    required this.id,
    required this.institutionName,
    this.institutionLogoUrl,
    this.boothLabel,
    this.programInterest,
    this.interestLevel = 'medium',
    this.followUpRequested = false,
    this.scholarshipDiscussed = false,
    required this.createdAt,
  });

  factory BoothVisit.fromMap(Map<String, dynamic> map) {
    final exhibitor = map['fair_exhibitors'] as Map<String, dynamic>?;
    final institution = exhibitor?['institutions'] as Map<String, dynamic>?;
    final program = map['programs'] as Map<String, dynamic>?;
    return BoothVisit(
      id: map['id'] as String,
      institutionName: institution?['name'] as String? ?? 'Institution',
      institutionLogoUrl: institution?['logo_url'] as String?,
      boothLabel: exhibitor?['booth_label'] as String?,
      programInterest:
          program?['name'] as String? ?? map['program_interest'] as String?,
      interestLevel: map['interest_level'] as String? ?? 'medium',
      followUpRequested: map['follow_up_requested'] as bool? ?? false,
      scholarshipDiscussed: map['scholarship_discussed'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}

/// The end-of-event summary, assembled by the `fair_report` SQL function so the
/// app makes one call rather than six.
class FairReport {
  final String fairName;
  final int institutionsMet;
  final int programsMatched;
  final int followUpsRequested;
  final int scholarshipDiscussions;
  final int applicationsStarted;
  final List<BoothVisit> visits;

  const FairReport({
    required this.fairName,
    this.institutionsMet = 0,
    this.programsMatched = 0,
    this.followUpsRequested = 0,
    this.scholarshipDiscussions = 0,
    this.applicationsStarted = 0,
    this.visits = const [],
  });

  bool get isEmpty => institutionsMet == 0;

  factory FairReport.fromJson(Map<String, dynamic> json) {
    final fair = json['fair'] as Map<String, dynamic>?;
    final visits = json['visits'] as List?;
    return FairReport(
      fairName: fair?['name'] as String? ?? 'Eduxfair',
      institutionsMet: (json['institutions_met'] as num?)?.toInt() ?? 0,
      programsMatched: (json['programs_matched'] as num?)?.toInt() ?? 0,
      followUpsRequested: (json['follow_ups_requested'] as num?)?.toInt() ?? 0,
      scholarshipDiscussions:
          (json['scholarship_discussions'] as num?)?.toInt() ?? 0,
      applicationsStarted: (json['applications_started'] as num?)?.toInt() ?? 0,
      visits: visits == null
          ? const []
          : visits.map((v) {
              final m = v as Map<String, dynamic>;
              // fair_report returns a flattened shape, not the nested join the
              // BoothVisit.fromMap path expects.
              return BoothVisit(
                id: m['institution_id'] as String? ?? '',
                institutionName: m['institution'] as String? ?? 'Institution',
                institutionLogoUrl: m['logo_url'] as String?,
                boothLabel: m['booth_label'] as String?,
                programInterest: m['program_interest'] as String?,
                interestLevel: m['interest_level'] as String? ?? 'medium',
                followUpRequested: m['follow_up_requested'] as bool? ?? false,
                scholarshipDiscussed:
                    m['scholarship_discussed'] as bool? ?? false,
                createdAt: DateTime.parse(m['met_at'] as String).toLocal(),
              );
            }).toList(),
    );
  }
}
