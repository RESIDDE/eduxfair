/// A student's grant of passport access to one institution.
///
/// Mirrors `public.passport_shares`, which is the single consent gate for all
/// identifying student data. Applying to an institution, requesting a meeting
/// and connecting at a fair booth all create one of these — so this list is a
/// complete answer to "who can see me", and every entry can be revoked.
class PassportShare {
  final String id;
  final String institutionId;
  final String institutionName;
  final String? institutionLogoUrl;
  final String? institutionCountry;
  final DateTime grantedAt;
  final DateTime? revokedAt;

  /// Why the grant exists, e.g. "You connected at Lekkside Lagos 2026".
  /// Written by the database so the student is never surprised by an entry.
  final String? reason;

  const PassportShare({
    required this.id,
    required this.institutionId,
    required this.institutionName,
    this.institutionLogoUrl,
    this.institutionCountry,
    required this.grantedAt,
    this.revokedAt,
    this.reason,
  });

  bool get isActive => revokedAt == null;

  factory PassportShare.fromMap(Map<String, dynamic> map) {
    // The query joins institutions, so the nested object may be absent when a
    // listing was fetched without it.
    final institution = map['institutions'] as Map<String, dynamic>?;
    return PassportShare(
      id: map['id'] as String,
      institutionId: map['institution_id'] as String,
      institutionName: institution?['name'] as String? ?? 'Institution',
      institutionLogoUrl: institution?['logo_url'] as String?,
      institutionCountry: institution?['country'] as String?,
      grantedAt: DateTime.parse(map['granted_at'] as String),
      revokedAt: map['revoked_at'] == null
          ? null
          : DateTime.parse(map['revoked_at'] as String),
      reason: map['reason'] as String?,
    );
  }
}
