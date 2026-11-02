import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';

/// The Education Passport: built once, reused at every institution.
///
/// Mirrors `public.student_passports`. Three fields are computed by the
/// database and must never be written from here:
///   * `completeness`      — trigger-maintained, and the gate for matching
///   * `normalizedGrade`   — generated, cross-scheme comparable 0–100
///   * `englishBand`       — generated, IELTS-equivalent
class Passport {
  final String profileId;

  final DateTime? dateOfBirth;
  final String? nationality;
  final String? currentCountry;

  final String? highestQualification;
  final double? gradeValue;
  final String? gradeScheme;
  final String englishTestName;
  final double? englishScore;

  final List<String> targetCountries;
  final List<String> targetLevels;
  final List<String> targetFields;
  final double? budgetMin;
  final double? budgetMax;
  final String budgetCurrency;
  final String? intendedIntake;

  final String? bio;

  // Database-computed. Read-only here.
  final int completeness;
  final double? normalizedGrade;
  final double? englishBand;
  final String verificationStatus;
  final DateTime? verifiedAt;

  const Passport({
    required this.profileId,
    this.dateOfBirth,
    this.nationality,
    this.currentCountry,
    this.highestQualification,
    this.gradeValue,
    this.gradeScheme,
    this.englishTestName = 'none',
    this.englishScore,
    this.targetCountries = const [],
    this.targetLevels = const [],
    this.targetFields = const [],
    this.budgetMin,
    this.budgetMax,
    this.budgetCurrency = 'USD',
    this.intendedIntake,
    this.bio,
    this.completeness = 0,
    this.normalizedGrade,
    this.englishBand,
    this.verificationStatus = 'unverified',
    this.verifiedAt,
  });

  bool get isVerified => verificationStatus == 'verified';
  bool get isPendingVerification => verificationStatus == 'pending';

  /// Whether this passport is complete enough to be matched at all. Mirrors
  /// `min_completeness_to_match()`; below it, institutions see nothing.
  bool get isMatchable => completeness >= AppConstants.minCompletenessToMatch;

  /// What to fill in next, in the order that unlocks the most value. Drives the
  /// passport screen's checklist, so the student is never guessing why their
  /// passport is "incomplete".
  List<String> get missingPieces {
    final missing = <String>[];
    if (targetFields.isEmpty) missing.add('Choose your field of study');
    if (targetCountries.isEmpty) missing.add('Choose where you want to study');
    if (targetLevels.isEmpty) missing.add('Choose your study level');
    if (gradeValue == null) missing.add('Add your grades');
    if (highestQualification == null) missing.add('Add your highest qualification');
    if (englishBand == null) missing.add('Add an English test result');
    if (nationality == null) missing.add('Add your nationality');
    if (dateOfBirth == null) missing.add('Add your date of birth');
    return missing;
  }

  String get gradeSchemeLabel =>
      AppConstants.gradingSchemes[gradeScheme] ?? '—';

  String get englishTestLabel =>
      AppConstants.englishTests[englishTestName] ?? 'Not taken yet';

  /// Human-readable grade, in whatever scheme the student entered it.
  String get gradeDisplay {
    if (gradeValue == null) return 'Not added';
    final v = gradeValue!;
    switch (gradeScheme) {
      case 'percentage':
        return '${_trim(v)}%';
      case 'gpa_4':
        return '${_trim(v)} / 4.0';
      case 'gpa_5':
        return '${_trim(v)} / 5.0';
      case 'ib':
        return '${_trim(v)} / 45';
      case 'waec':
        return _waecLabel(v);
      case 'uk_class':
        return _ukClassLabel(v);
      case 'a_level':
        return '${_trim(v)} points';
      default:
        return _trim(v);
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static String _waecLabel(double v) {
    const labels = {
      1: 'A1', 2: 'B2', 3: 'B3', 4: 'C4',
      5: 'C5', 6: 'C6', 7: 'D7', 8: 'E8', 9: 'F9',
    };
    return labels[v.round()] ?? _trim(v);
  }

  static String _ukClassLabel(double v) {
    if (v <= 1.0) return 'First class';
    if (v <= 2.1) return 'Upper second (2:1)';
    if (v <= 2.2) return 'Lower second (2:2)';
    return 'Third class';
  }

  String get budgetDisplay {
    if (budgetMax == null) return 'Not set';
    final max = budgetMax!.round();
    if (budgetMin == null) return 'Up to $budgetCurrency ${formatThousands(max)}';
    return '$budgetCurrency ${formatThousands(budgetMin!.round())}–${formatThousands(max)}';
  }


  factory Passport.fromMap(Map<String, dynamic> map) => Passport(
        profileId: map['profile_id'] as String,
        dateOfBirth: map['date_of_birth'] == null
            ? null
            : DateTime.parse(map['date_of_birth'] as String),
        nationality: map['nationality'] as String?,
        currentCountry: map['current_country'] as String?,
        highestQualification: map['highest_qualification'] as String?,
        gradeValue: _toDouble(map['grade_value']),
        gradeScheme: map['grade_scheme'] as String?,
        englishTestName: map['english_test_name'] as String? ?? 'none',
        englishScore: _toDouble(map['english_score']),
        targetCountries: _toStringList(map['target_countries']),
        targetLevels: _toStringList(map['target_levels']),
        targetFields: _toStringList(map['target_fields']),
        budgetMin: _toDouble(map['budget_min']),
        budgetMax: _toDouble(map['budget_max']),
        budgetCurrency: map['budget_currency'] as String? ?? 'USD',
        intendedIntake: map['intended_intake'] as String?,
        bio: map['bio'] as String?,
        completeness: (map['completeness'] as num?)?.toInt() ?? 0,
        normalizedGrade: _toDouble(map['normalized_grade']),
        englishBand: _toDouble(map['english_band']),
        verificationStatus: map['verification_status'] as String? ?? 'unverified',
        verifiedAt: map['verified_at'] == null
            ? null
            : DateTime.parse(map['verified_at'] as String),
      );

  /// Only the writable columns. Omitting the generated ones is not optional:
  /// Postgres rejects a write to a generated column outright.
  Map<String, dynamic> toUpsertMap() => {
        'profile_id': profileId,
        'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
        'nationality': nationality,
        'current_country': currentCountry,
        'highest_qualification': highestQualification,
        'grade_value': gradeValue,
        'grade_scheme': gradeScheme,
        'english_test_name': englishTestName,
        'english_score': englishScore,
        'target_countries': targetCountries,
        'target_levels': targetLevels,
        'target_fields': targetFields,
        'budget_min': budgetMin,
        'budget_max': budgetMax,
        'budget_currency': budgetCurrency,
        'intended_intake': intendedIntake,
        'bio': bio,
      };

  Passport copyWith({
    DateTime? dateOfBirth,
    String? nationality,
    String? currentCountry,
    String? highestQualification,
    double? gradeValue,
    String? gradeScheme,
    String? englishTestName,
    double? englishScore,
    List<String>? targetCountries,
    List<String>? targetLevels,
    List<String>? targetFields,
    double? budgetMin,
    double? budgetMax,
    String? budgetCurrency,
    String? intendedIntake,
    String? bio,
  }) =>
      Passport(
        profileId: profileId,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        nationality: nationality ?? this.nationality,
        currentCountry: currentCountry ?? this.currentCountry,
        highestQualification: highestQualification ?? this.highestQualification,
        gradeValue: gradeValue ?? this.gradeValue,
        gradeScheme: gradeScheme ?? this.gradeScheme,
        englishTestName: englishTestName ?? this.englishTestName,
        englishScore: englishScore ?? this.englishScore,
        targetCountries: targetCountries ?? this.targetCountries,
        targetLevels: targetLevels ?? this.targetLevels,
        targetFields: targetFields ?? this.targetFields,
        budgetMin: budgetMin ?? this.budgetMin,
        budgetMax: budgetMax ?? this.budgetMax,
        budgetCurrency: budgetCurrency ?? this.budgetCurrency,
        intendedIntake: intendedIntake ?? this.intendedIntake,
        bio: bio ?? this.bio,
        completeness: completeness,
        normalizedGrade: normalizedGrade,
        englishBand: englishBand,
        verificationStatus: verificationStatus,
        verifiedAt: verifiedAt,
      );

  static double? _toDouble(dynamic v) =>
      v == null ? null : (v as num).toDouble();

  static List<String> _toStringList(dynamic v) =>
      v == null ? const [] : (v as List).map((e) => e.toString()).toList();
}
