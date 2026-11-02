/// A pseudonymous student card returned by `matched_student_cards`.
///
/// Designed with privacy first: exposes matching criteria (level, field, grade band,
/// budget, score) and keeps the student anonymous until they grant a passport share.
class MatchedStudentCard {
  final String token;
  final String programId;
  final String institutionId;
  final String programName;
  final int score;
  final List<String> reasons;
  final DateTime? computedAt;
  final String? currentCountry;
  final String? nationality;
  final List<String> targetLevels;
  final List<String> targetFields;
  final String? intendedIntake;
  final String? gradeBand;
  final String? ageBand;
  final String? englishBand;
  final String? budgetBand;
  final int completeness;
  final String? passportVerification;
  final bool isShared;
  final String? sharedName;
  final bool alreadyActioned;

  const MatchedStudentCard({
    required this.token,
    required this.programId,
    required this.institutionId,
    required this.programName,
    required this.score,
    this.reasons = const [],
    this.computedAt,
    this.currentCountry,
    this.nationality,
    this.targetLevels = const [],
    this.targetFields = const [],
    this.intendedIntake,
    this.gradeBand,
    this.ageBand,
    this.englishBand,
    this.budgetBand,
    this.completeness = 0,
    this.passportVerification,
    this.isShared = false,
    this.sharedName,
    this.alreadyActioned = false,
  });

  static List<String> _parseArray(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        final inner = trimmed.substring(1, trimmed.length - 1).trim();
        if (inner.isEmpty) return const [];
        return inner
            .split(',')
            .map((s) => s.replaceAll('"', '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (trimmed.isNotEmpty) return [trimmed];
    }
    return const [];
  }

  static List<String> _parseReasons(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((e) {
        if (e is Map) {
          final detail = e['detail']?.toString().trim();
          if (detail != null && detail.isNotEmpty) return detail;
          final code = e['code']?.toString().trim();
          if (code != null && code.isNotEmpty) return code;
        }
        return e.toString().trim();
      }).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  factory MatchedStudentCard.fromMap(Map<String, dynamic> map) {
    return MatchedStudentCard(
      token: map['token']?.toString() ?? '',
      programId: map['program_id']?.toString() ?? '',
      institutionId: map['institution_id']?.toString() ?? '',
      programName: map['program_name']?.toString() ?? 'Program',
      score: (map['score'] as num?)?.toInt() ?? 0,
      reasons: _parseReasons(map['reasons']),
      computedAt: map['computed_at'] != null
          ? DateTime.tryParse(map['computed_at'].toString())?.toLocal()
          : null,
      currentCountry: map['current_country']?.toString(),
      nationality: map['nationality']?.toString(),
      targetLevels: _parseArray(map['target_levels']),
      targetFields: _parseArray(map['target_fields']),
      intendedIntake: map['intended_intake']?.toString(),
      gradeBand: map['grade_band']?.toString(),
      ageBand: map['age_band']?.toString(),
      englishBand: map['english_band']?.toString(),
      budgetBand: map['budget_band']?.toString(),
      completeness: (map['completeness'] as num?)?.toInt() ?? 0,
      passportVerification: map['passport_verification']?.toString(),
      isShared: map['is_shared'] == true,
      sharedName: map['shared_name']?.toString(),
      alreadyActioned: map['already_actioned'] == true,
    );
  }
}
