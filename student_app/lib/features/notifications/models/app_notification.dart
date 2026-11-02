/// An in-app notification. Mirrors `public.notifications`.
///
/// Rows are written by the `send-notification` Edge Function on the service
/// role, because the sender is usually not the recipient (an institution
/// notifies a student) and no client-side insert policy should allow that.
class AppNotification {
  final String id;
  final String kind;
  final String title;
  final String? body;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.payload = const {},
    this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  /// Where tapping this should take the student. Returns null when the
  /// notification is purely informational.
  String? get deepLinkTarget => switch (kind) {
        'institution_invited_you' => '/matches',
        // An institution asking to see the passport. Lands on the sharing
        // screen, because granting is the only answer to it.
        'institution_requested_access' => '/passport/sharing',
        'appointment_requested' ||
        'appointment_confirmed' ||
        'appointment_declined' => '/appointments',
        'application_stage_changed' || 'documents_requested' => '/applications',
        'passport_verified' => '/passport',
        'new_message' => '/messages',
        // The Spaces tab, not the room itself: by the time this is tapped the
        // session may have ended, and the tab says so where a dead room cannot.
        'space_live' || 'space_scheduled' || 'space_starting' => '/spaces',
        'post_tagged' => payload['post_id'] != null
            ? '/post/${payload['post_id']}'
            : '/feed',
        _ => null,
      };

  factory AppNotification.fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        kind: map['kind'] as String,
        title: map['title'] as String,
        body: map['body'] as String?,
        payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        readAt: map['read_at'] == null
            ? null
            : DateTime.parse(map['read_at'] as String).toLocal(),
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}
