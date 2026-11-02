import '../../discover/models/institution.dart';

/// A thread between one student and one institution.
///
/// Group threads and Live Educator Rooms are Phase 2 and will need their own
/// shape — this is deliberately a two-party conversation.
class Conversation {
  final String id;
  final String studentId;
  final String institutionId;
  final String? subject;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final Institution? institution;

  /// From the caller's `conversation_participants` row.
  final DateTime? lastReadAt;

  /// Joined in for the list preview.
  final String? lastMessageBody;

  /// Per-person, from the caller's `conversation_participants` row: one
  /// officer archiving a thread must not take it off a colleague's list.
  final DateTime? pinnedAt;
  final DateTime? archivedAt;

  const Conversation({
    required this.id,
    required this.studentId,
    required this.institutionId,
    this.subject,
    this.lastMessageAt,
    required this.createdAt,
    this.institution,
    this.lastReadAt,
    this.lastMessageBody,
    this.pinnedAt,
    this.archivedAt,
  });

  bool get isPinned => pinnedAt != null;
  bool get isArchived => archivedAt != null;

  bool get hasUnread {
    final last = lastMessageAt;
    if (last == null) return false;
    final read = lastReadAt;
    return read == null || read.isBefore(last);
  }

  String get title => institution?.name ?? subject ?? 'Conversation';

  factory Conversation.fromMap(Map<String, dynamic> map) {
    final inst = map['institutions'] as Map<String, dynamic>?;
    final participants = map['conversation_participants'] as List?;
    final messages = map['messages'] as List?;
    // The query filters the embedded rows to the caller's, so there is at most
    // one — but `can_access_conversation` would happily return the other
    // party's as well, so this does not rely on ordering to pick.
    final mine = (participants != null && participants.isNotEmpty)
        ? participants.first as Map<String, dynamic>
        : null;
    DateTime? stamp(String key) => mine?[key] == null
        ? null
        : DateTime.parse(mine![key] as String).toLocal();

    return Conversation(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      institutionId: map['institution_id'] as String,
      subject: map['subject'] as String?,
      lastMessageAt: map['last_message_at'] == null
          ? null
          : DateTime.parse(map['last_message_at'] as String).toLocal(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      institution: inst == null ? null : Institution.fromMap(inst),
      lastReadAt: stamp('last_read_at'),
      pinnedAt: stamp('pinned_at'),
      archivedAt: stamp('archived_at'),
      lastMessageBody: (messages != null && messages.isNotEmpty)
          ? messages.first['body'] as String?
          : null,
    );
  }
}

/// One message. Mirrors `public.messages`, which has no UPDATE or DELETE policy
/// for anyone — a thread a student may later need to point back to cannot be
/// one an institution can rewrite.
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final String? attachmentPath;

  /// `text` | `file` | `image` | `voice` — decided by the sender and stored,
  /// never guessed from the file extension. An .m4a somebody attached
  /// deliberately is a file; an .m4a the recorder produced is a voice note,
  /// and nothing in the path tells the two apart.
  final String kind;

  /// The name as the sender had it. Stored since 20261030000052; before that
  /// both clients reconstructed it by splitting the path on its first dash,
  /// which mangled every filename that already contained one.
  final String? attachmentNameRaw;
  final String? attachmentMime;
  final int? durationMs;

  /// Set when the SENDER deleted this for everyone. The row survives as a
  /// tombstone: body and attachment are gone, and what it said lives only in
  /// `message_redactions`, which neither party can read.
  final DateTime? deletedAt;

  /// What this answers, on the same thread. A trigger enforces that — the
  /// quoted snippet is rendered from the row this points at, so an id from
  /// another conversation would be a way to display it.
  final String? replyToId;

  /// Shown as a "Forwarded" label. Carries no pointer to where it came from:
  /// that would name a conversation the reader is not on.
  final bool isForwarded;

  /// emoji -> the profile ids who chose it. One reaction per person, so a
  /// person appears at most once across the whole map.
  final Map<String, List<String>> reactions;

  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.body,
    this.attachmentPath,
    this.kind = 'text',
    this.attachmentNameRaw,
    this.attachmentMime,
    this.durationMs,
    this.deletedAt,
    this.replyToId,
    this.isForwarded = false,
    this.reactions = const {},
    required this.createdAt,
  });

  bool get isDeleted => deletedAt != null;
  bool get hasReactions => reactions.isNotEmpty;

  /// What this person chose, if anything.
  String? myReaction(String? profileId) {
    if (profileId == null) return null;
    for (final entry in reactions.entries) {
      if (entry.value.contains(profileId)) return entry.key;
    }
    return null;
  }

  /// A one-line stand-in for a quoted reply, where the body is not the point.
  String get quotedLabel {
    if (isDeleted) return 'This message was deleted';
    final text = body?.trim();
    if (text != null && text.isNotEmpty) return text;
    return switch (kind) {
      'voice' => 'Voice note',
      'image' => 'Photo',
      _ => attachmentName.isEmpty ? 'Attachment' : attachmentName,
    };
  }

  Message copyWith({Map<String, List<String>>? reactions}) => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        body: body,
        attachmentPath: attachmentPath,
        kind: kind,
        attachmentNameRaw: attachmentNameRaw,
        attachmentMime: attachmentMime,
        durationMs: durationMs,
        deletedAt: deletedAt,
        replyToId: replyToId,
        isForwarded: isForwarded,
        reactions: reactions ?? this.reactions,
        createdAt: createdAt,
      );

  bool get hasAttachment => attachmentPath != null;
  bool get isVoice => kind == 'voice';
  bool get isImage => kind == 'image';

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  /// `0:07`, for a voice note's bubble.
  String get durationLabel {
    final d = duration;
    if (d == null) return '';
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$seconds';
  }

  String get attachmentName {
    final stored = attachmentNameRaw;
    if (stored != null && stored.trim().isNotEmpty) return stored;

    final path = attachmentPath;
    if (path == null) return '';
    // The fallback for rows written before attachment_name existed: strip the
    // millisecond prefix the upload path carries for uniqueness.
    final base = path.split('/').last;
    final dash = base.indexOf('-');
    return dash > 0 ? base.substring(dash + 1) : base;
  }

  factory Message.fromMap(Map<String, dynamic> map) => Message(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String,
        senderId: map['sender_id'] as String,
        body: map['body'] as String?,
        attachmentPath: map['attachment_path'] as String?,
        kind: map['kind'] as String? ?? 'text',
        attachmentNameRaw: map['attachment_name'] as String?,
        attachmentMime: map['attachment_mime'] as String?,
        durationMs: (map['duration_ms'] as num?)?.toInt(),
        deletedAt: map['deleted_at'] == null
            ? null
            : DateTime.parse(map['deleted_at'] as String).toLocal(),
        replyToId: map['reply_to_id'] as String?,
        isForwarded: map['is_forwarded'] as bool? ?? false,
        reactions: _groupReactions(map['message_reactions'] as List?),
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );

  /// Rows of (emoji, profile_id) into emoji -> who.
  static Map<String, List<String>> _groupReactions(List? rows) {
    if (rows == null || rows.isEmpty) return const {};
    final out = <String, List<String>>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final emoji = row['emoji'] as String?;
      final who = row['profile_id'] as String?;
      if (emoji == null || who == null) continue;
      (out[emoji] ??= []).add(who);
    }
    return out;
  }
}
