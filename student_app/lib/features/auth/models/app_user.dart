import '../../../core/constants/app_constants.dart';

/// The signed-in person, as the app needs them.
///
/// Mirrors `public.profiles`. The role is assigned at signup and clamped to the
/// three self-serve roles by `handle_new_user()` — nothing a client sends can
/// request `admin`.
class AppUser {
  final String id;
  final String role;
  final String fullName;
  final String? avatarUrl;
  final String? phone;
  final String? country;
  final bool isEmailVerified;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.role,
    required this.fullName,
    this.avatarUrl,
    this.phone,
    this.country,
    this.isEmailVerified = false,
    required this.createdAt,
  });

  bool get isStudent => role == 'student';

  /// Anyone who belongs in the `/org` shell rather than the student tabs.
  /// Educators and admins land there too — neither has a shell of its own.
  bool get isStaff => !isStudent;
  bool get isInstitutionMember => role == 'institution_member';
  bool get isEducator => role == 'educator';
  bool get isAdmin => role == 'admin';

  /// First name only, for greetings. Falls back to the whole string rather than
  /// to an empty one, so a mononym still greets properly.
  String get firstName {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'there';
    final parts = trimmed.split(RegExp(r'\s+'));
    return parts.first;
  }

  /// Up to two initials for the avatar fallback.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AppUser.fromMap(Map<String, dynamic> map) => AppUser(
        id: map['id'] as String,
        role: map['role'] as String? ?? 'student',
        fullName: map['full_name'] as String? ?? '',
        avatarUrl: map['avatar_url'] as String?,
        phone: map['phone'] as String?,
        country: map['country'] as String?,
        isEmailVerified: map['email_verified'] as bool? ?? false,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toUpdateMap() => {
        'full_name': fullName,
        'phone': phone,
        'country': country,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

  AppUser copyWith({
    String? fullName,
    String? avatarUrl,
    bool clearAvatar = false,
    String? phone,
    String? country,
    bool? isEmailVerified,
  }) =>
      AppUser(
        id: id,
        role: role,
        fullName: fullName ?? this.fullName,
        avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
        phone: phone ?? this.phone,
        country: country ?? this.country,
        isEmailVerified: isEmailVerified ?? this.isEmailVerified,
        createdAt: createdAt,
      );
}

/// Where a signed-in person belongs on arrival.
///
/// ONE definition, because the splash screen and the router's redirect both
/// need it and a disagreement between them is visible: the splash used to send
/// everyone to /home, which resolves to /feed inside the student shell, so
/// staff saw a frame of the student app before the redirect moved them. Two
/// copies of this rule is how that comes back.
///
/// A null user means the profile row could not be read at all. The student
/// side is the right default there — it is the one that works without a role.
String landingRouteFor(AppUser? user) {
  if (user != null && !user.isEmailVerified) {
    return AppConstants.routeOtp;
  }
  return (user?.isStaff ?? false)
      ? AppConstants.routeOrgHome
      : AppConstants.routeHome;
}
