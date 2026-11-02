/// An institution listing. Mirrors `public.institutions`.
///
/// The directory is open to any signed-in user; verification controls the
/// badge, not visibility.
class Institution {
  final String id;
  final String name;
  final String slug;
  final String country;
  final String? city;
  final String? website;
  final String? logoUrl;
  final String? description;
  final String verificationStatus;
  final String tier;

  /// The bare domain staff addresses live on, e.g. `maplecrest.ca`. A CHECK
  /// constraint rejects a scheme or a path. Domain verification sends its code
  /// to an address here, which is what earns the badge — so settings needs it
  /// even though the public directory never shows it.
  final String? emailDomain;

  /// university | college | embassy | agency. Embassies reuse the whole
  /// institution machinery and simply have no programs.
  final String kind;
  final int followerCount;

  const Institution({
    required this.id,
    required this.name,
    required this.slug,
    required this.country,
    this.city,
    this.website,
    this.logoUrl,
    this.description,
    this.verificationStatus = 'unverified',
    this.tier = 'basic',
    this.kind = 'university',
    this.emailDomain,
    this.followerCount = 0,
  });

  /// True only when a party controlling an address on the institution's own
  /// domain confirmed the listing. It is NOT a claim about accreditation — the
  /// UI copy next to this badge has to say so.
  bool get isVerified => verificationStatus == 'verified';

  String get location => city == null ? country : '$city, $country';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && p.length > 2)
        .toList();
    if (parts.isEmpty) return name.isEmpty ? '?' : name[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  factory Institution.fromMap(Map<String, dynamic> map) => Institution(
        id: map['id'] as String,
        name: map['name'] as String,
        slug: map['slug'] as String? ?? '',
        country: map['country'] as String? ?? '',
        city: map['city'] as String?,
        website: map['website'] as String?,
        logoUrl: map['logo_url'] as String?,
        description: map['description'] as String?,
        verificationStatus: map['verification_status'] as String? ?? 'unverified',
        tier: map['tier'] as String? ?? 'basic',
        kind: map['kind'] as String? ?? 'university',
        emailDomain: map['email_domain'] as String?,
        followerCount: (map['follower_count'] as num?)?.toInt() ?? 0,
      );
}
