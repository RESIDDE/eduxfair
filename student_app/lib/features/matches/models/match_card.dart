import '../../discover/models/program.dart';

/// One reason a program was matched, as written by the database scorer.
///
/// Every score carries these so the student can read exactly why something was
/// suggested. No black box: the point of reverse admission is that both sides
/// can see the reasoning.
class MatchReason {
  final String code;
  final int weight;
  final String detail;

  const MatchReason({
    required this.code,
    required this.weight,
    required this.detail,
  });

  /// Scholarship availability is surfaced at weight 0 — it does not make a
  /// program a better fit, but it changes whether a student can actually go.
  bool get isHighlight => code == 'scholarship_available';

  factory MatchReason.fromMap(Map<String, dynamic> map) => MatchReason(
        code: map['code'] as String? ?? '',
        weight: (map['weight'] as num?)?.toInt() ?? 0,
        detail: map['detail'] as String? ?? '',
      );
}

/// A matched program, from `public.match_scores` joined to the program.
class MatchCard {
  final String programId;
  final int score;
  final List<MatchReason> reasons;
  final DateTime computedAt;
  final Program? program;

  const MatchCard({
    required this.programId,
    required this.score,
    this.reasons = const [],
    required this.computedAt,
    this.program,
  });

  /// Bands for the UI. The database floor is 40, so anything below "fair"
  /// never reaches a student at all.
  String get strengthLabel {
    if (score >= 85) return 'Excellent match';
    if (score >= 70) return 'Strong match';
    if (score >= 55) return 'Good match';
    return 'Possible match';
  }

  bool get hasScholarship => reasons.any((r) => r.isHighlight);

  /// Reasons worth showing, highest-weight first, with the scholarship flag
  /// kept at the end where it reads as a note rather than a scoring factor.
  List<MatchReason> get rankedReasons {
    final scoring = reasons.where((r) => !r.isHighlight).toList()
      ..sort((a, b) => b.weight.compareTo(a.weight));
    final highlights = reasons.where((r) => r.isHighlight);
    return [...scoring, ...highlights];
  }

  factory MatchCard.fromMap(Map<String, dynamic> map) {
    final rawReasons = map['reasons'];
    final nested = map['programs'] as Map<String, dynamic>?;
    return MatchCard(
      programId: map['program_id'] as String,
      score: (map['score'] as num).toInt(),
      reasons: rawReasons == null
          ? const []
          : (rawReasons as List)
              .map((r) => MatchReason.fromMap(r as Map<String, dynamic>))
              .toList(),
      computedAt: DateTime.parse(map['computed_at'] as String),
      program: nested == null ? null : Program.fromMap(nested),
    );
  }
}

/// An institution reaching out first — the reverse-admission signal.
///
/// Only `kind = 'invited'` rows ever reach a student: `shortlisted` and
/// `passed` are internal institution notes and the RLS policies keep them that
/// way, so there is no equivalent model for them here on purpose.
class Invitation {
  final String id;
  final String institutionId;
  final String institutionName;
  final String? institutionLogoUrl;
  final String? institutionCountry;
  final bool institutionVerified;
  final String? programId;
  final String? programName;
  final String? note;
  final DateTime createdAt;

  const Invitation({
    required this.id,
    required this.institutionId,
    required this.institutionName,
    this.institutionLogoUrl,
    this.institutionCountry,
    this.institutionVerified = false,
    this.programId,
    this.programName,
    this.note,
    required this.createdAt,
  });

  factory Invitation.fromMap(Map<String, dynamic> map) {
    final inst = map['institutions'] as Map<String, dynamic>?;
    final prog = map['programs'] as Map<String, dynamic>?;
    return Invitation(
      id: map['id'] as String,
      institutionId: map['institution_id'] as String,
      institutionName: inst?['name'] as String? ?? 'An institution',
      institutionLogoUrl: inst?['logo_url'] as String?,
      institutionCountry: inst?['country'] as String?,
      institutionVerified: inst?['verification_status'] == 'verified',
      programId: map['program_id'] as String?,
      programName: prog?['name'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
