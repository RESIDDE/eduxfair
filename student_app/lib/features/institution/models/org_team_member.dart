/// A staff member or admissions officer seat in the institution.
class OrgTeamMember {
  final String id;
  final String profileId;
  final String memberRole;
  final String fullName;
  final DateTime createdAt;

  const OrgTeamMember({
    required this.id,
    required this.profileId,
    required this.memberRole,
    required this.fullName,
    required this.createdAt,
  });

  bool get isOwner => memberRole == 'owner';

  String get roleLabel => isOwner ? 'Owner' : 'Admissions officer';

  factory OrgTeamMember.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return OrgTeamMember(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      memberRole: map['member_role'] as String? ?? 'admissions_officer',
      fullName: profile?['full_name'] as String? ?? 'Pending invite',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
