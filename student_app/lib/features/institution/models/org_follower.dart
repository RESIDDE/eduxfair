/// A student following the institution.
class OrgFollower {
  final String studentId;
  final String fullName;
  final String? avatarUrl;
  final String? country;
  final DateTime followedAt;

  const OrgFollower({
    required this.studentId,
    required this.fullName,
    this.avatarUrl,
    this.country,
    required this.followedAt,
  });

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'S';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  factory OrgFollower.fromMap(Map<String, dynamic> map) => OrgFollower(
        studentId: map['student_id']?.toString() ?? '',
        fullName: map['full_name']?.toString() ?? 'Student',
        avatarUrl: map['avatar_url']?.toString(),
        country: map['country']?.toString(),
        followedAt: DateTime.tryParse(map['followed_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}
