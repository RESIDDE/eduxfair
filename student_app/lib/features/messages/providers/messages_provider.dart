import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../models/conversation.dart';

/// Conversations and live messaging.
///
/// Delivery is via Supabase Realtime on `public.messages`, which the schema
/// adds to the `supabase_realtime` publication. The subscription is scoped to
/// one conversation at a time: subscribing to the whole table would deliver
/// nothing extra (RLS filters it) but would wake the client on every message
/// on the platform.
class MessagesProvider extends ChangeNotifier {
  /// The six, in agreement with the CHECK on `message_reactions`. Validated
  /// there too, because the client is not the place to decide what may be
  /// written to a table.
  static const reactionChoices = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  final _service = SupabaseService.instance;

  List<Conversation> _conversations = [];
  final Map<String, List<Message>> _messages = {};

  RealtimeChannel? _channel;
  String? _openConversationId;

  bool _loading = false;
  bool _sending = false;
  String? _error;

  /// conversation id -> the matching line, from `search_conversations`.
  Map<String, String> _matches = {};
  String _query = '';
  bool _searching = false;

  List<Conversation> get conversations => _conversations;
  bool get loading => _loading;
  bool get sending => _sending;
  String? get error => _error;

  String get query => _query;
  bool get searching => _searching;

  /// Unread counts the inbox, not the archive: a thread someone filed away is
  /// not something to badge them about.
  int get unreadCount =>
      _conversations.where((c) => c.hasUnread && !c.isArchived).length;

  /// The line that matched, for a thread the current search turned up.
  String? matchFor(String conversationId) => _matches[conversationId];

  /// Pinned first, then by recency — the order both tabs render in.
  List<Conversation> _ordered(Iterable<Conversation> rows) {
    final list = rows.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final at = a.lastMessageAt ?? a.createdAt;
        final bt = b.lastMessageAt ?? b.createdAt;
        return bt.compareTo(at);
      });
    return list;
  }

  /// Threads for the main tab: everything not archived, filtered by the
  /// current search.
  List<Conversation> get inbox =>
      _ordered(_visible.where((c) => !c.isArchived));

  List<Conversation> get archived =>
      _ordered(_visible.where((c) => c.isArchived));

  int get archivedCount => _conversations.where((c) => c.isArchived).length;

  /// Applies the search to both tabs.
  ///
  /// Two halves, deliberately. The other party's name is already in memory, so
  /// matching it needs no round trip and stays instant as you type; message
  /// bodies live in a table only the server can search under RLS, which is
  /// what `search_conversations` is for.
  Iterable<Conversation> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations.where((c) =>
        c.title.toLowerCase().contains(q) ||
        (c.subject ?? '').toLowerCase().contains(q) ||
        _matches.containsKey(c.id));
  }

  List<Message> messagesFor(String conversationId) =>
      _messages[conversationId] ?? const [];

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final id = _service.userId;
      if (id == null) return;

      // The embedded participants are filtered to OUR row. `can_access_
      // conversation` lets a student read the institution's row on their own
      // thread too, so taking the first one meant reading an officer's unread
      // state as your own — and, now that the row carries pins, an officer's
      // pins as well.
      final rows = await _service.client
          .from('conversations')
          .select('*, institutions!inner(id, name, slug, country, city, '
              'logo_url, verification_status, tier), '
              'conversation_participants(profile_id, last_read_at, '
              'pinned_at, archived_at)')
          .eq('student_id', id)
          .eq('conversation_participants.profile_id', id)
          .order('last_message_at', ascending: false, nullsFirst: false);

      _conversations = (rows as List)
          .map((r) => Conversation.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Finds or creates the thread with an institution.
  ///
  /// There is a unique constraint on (student_id, institution_id), so the
  /// insert is attempted and a collision is treated as "it already exists"
  /// rather than checked for first.
  Future<String?> openConversation({
    required String institutionId,
    String? studentId,
    String? subject,
  }) async {
    _error = null;
    try {
      final targetStudentId = studentId ?? _service.userId;
      if (targetStudentId == null) {
        _error = 'User not signed in.';
        notifyListeners();
        return null;
      }

      final existing = await _service.client
          .from('conversations')
          .select('id')
          .eq('student_id', targetStudentId)
          .eq('institution_id', institutionId)
          .maybeSingle();

      if (existing != null) return existing['id'] as String;

      final row = await _service.client
          .from('conversations')
          .insert({
            'student_id': targetStudentId,
            'institution_id': institutionId,
            'subject': subject,
          })
          .select('id')
          .single();

      if (studentId == null) {
        await loadConversations();
      }
      return row['id'] as String;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  // ── Searching, pinning, archiving ─────────────────────────────────────────

  /// Runs a search over message bodies, and re-filters the list either way.
  ///
  /// `search_conversations` is invoker-rights in SQL, so the policy on
  /// `messages` decides what it can see — this cannot become a way to read a
  /// thread the caller is not on.
  Future<void> search(String query) async {
    _query = query;
    final q = query.trim();

    if (q.isEmpty) {
      _matches = {};
      _searching = false;
      notifyListeners();
      return;
    }

    _searching = true;
    notifyListeners();

    try {
      final rows = await _service.client
          .rpc('search_conversations', params: {'p_query': q});
      // Discarded if the box has moved on: a slow response for an older query
      // must not overwrite the results for what is on screen now.
      if (_query.trim() != q) return;
      _matches = {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['conversation_id'] as String: (r['snippet'] as String?) ?? '',
      };
    } catch (e) {
      // A failed body search still leaves name matching working, so this is a
      // degraded search rather than a broken screen.
      if (kDebugMode) debugPrint('conversation search failed: $e');
      _matches = {};
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _query = '';
    _matches = {};
    _searching = false;
    notifyListeners();
  }

  /// Pins or archives a thread for this person alone.
  ///
  /// Null leaves a flag alone. Pinning un-archives, and that rule lives in
  /// `set_conversation_state` so no client has to remember it — which is why
  /// the row is read back rather than patched optimistically.
  Future<bool> setConversationState(String conversationId,
      {bool? pinned, bool? archived}) async {
    try {
      await _service.client.rpc('set_conversation_state', params: {
        'p_conversation_id': conversationId,
        'p_pinned': pinned,
        'p_archived': archived,
      });
      await loadConversations();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<void> loadMessages(String conversationId) async {
    _error = null;
    try {
      final me = _service.userId;
      // The embedded hides are filtered to OUR rows, so a non-empty list means
      // this person chose not to see this message. Delete-for-me is a reading
      // preference: the row is untouched and the other side never learns of it.
      final rows = await _service.client
          .from('messages')
          .select('*, message_hides(profile_id), '
              'message_reactions(profile_id, emoji)')
          .eq('conversation_id', conversationId)
          .eq('message_hides.profile_id', me ?? '')
          .order('created_at', ascending: true)
          .limit(200);

      _messages[conversationId] = (rows as List)
          .cast<Map<String, dynamic>>()
          .where((r) => (r['message_hides'] as List? ?? const []).isEmpty)
          .map(Message.fromMap)
          .toList();
      notifyListeners();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
    }
  }

  /// Subscribes to new messages in one conversation.
  void subscribe(String conversationId) {
    if (_openConversationId == conversationId && _channel != null) return;
    unsubscribe();
    _openConversationId = conversationId;

    _channel = _service.client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final message = Message.fromMap(payload.newRecord);
            final existing = _messages[conversationId] ?? [];

            // The sender already appended this optimistically, so ignore the
            // echo rather than show the message twice.
            if (existing.any((m) => m.id == message.id)) return;

            _messages[conversationId] = [...existing, message];
            notifyListeners();
          },
        )
        // A delete-for-everyone is an UPDATE, not an insert. Without this the
        // other party keeps reading a message its sender has withdrawn until
        // they happen to reopen the thread.
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final updated = Message.fromMap(payload.newRecord);
            final existing = _messages[conversationId] ?? [];
            final index = existing.indexWhere((m) => m.id == updated.id);
            if (index < 0) return;
            final next = [...existing]..[index] = updated;
            _messages[conversationId] = next;
            notifyListeners();
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    final channel = _channel;
    if (channel != null) {
      _service.client.removeChannel(channel);
    }
    _channel = null;
    _openConversationId = null;
  }

  /// Sends a message, with an attachment that knows what it is.
  ///
  /// [kind] is passed rather than inferred: the schema stores it, and a client
  /// that guessed from the extension would render a voice player for any .m4a
  /// a student deliberately attached.
  Future<bool> send({
    required String conversationId,
    String? body,
    Uint8List? attachment,
    String? attachmentName,
    String? attachmentMime,
    String kind = 'text',
    int? durationMs,
    String? replyToId,
    bool isForwarded = false,
  }) async {
    final hasBody = (body ?? '').trim().isNotEmpty;
    if (!hasBody && attachment == null) return false;

    _sending = true;
    _error = null;
    notifyListeners();

    try {
      String? path;
      if (attachment != null && attachmentName != null) {
        path = _service.messageAttachmentPath(conversationId, attachmentName);
        await _service.uploadBytes(
          bucket: AppConstants.bucketMessageAttachments,
          path: path,
          bytes: attachment,
          contentType: attachmentMime,
        );
      }

      final row = await _service.client
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': _service.userId,
            'body': hasBody ? body!.trim() : null,
            'attachment_path': path,
            'kind': path == null ? 'text' : kind,
            'attachment_name': path == null ? null : attachmentName,
            'attachment_mime': path == null ? null : attachmentMime,
            'duration_ms': durationMs,
            'reply_to_id': replyToId,
            'is_forwarded': isForwarded,
          })
          .select()
          .single();

      // Append immediately so the thread feels responsive; the realtime echo
      // is de-duplicated by id in the subscription callback.
      final message = Message.fromMap(row);
      final existing = _messages[conversationId] ?? [];
      if (!existing.any((m) => m.id == message.id)) {
        _messages[conversationId] = [...existing, message];
      }
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Marks the thread read. Upsert because the participant row is created
  /// lazily — a student who never opened a thread has none.
  Future<void> markRead(String conversationId) async {
    try {
      await _service.client.from('conversation_participants').upsert({
        'conversation_id': conversationId,
        'profile_id': _service.userId,
        'last_read_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'conversation_id,profile_id');

      _conversations = _conversations
          .map((c) => c.id == conversationId
              ? Conversation(
                  id: c.id,
                  studentId: c.studentId,
                  institutionId: c.institutionId,
                  subject: c.subject,
                  lastMessageAt: c.lastMessageAt,
                  createdAt: c.createdAt,
                  institution: c.institution,
                  lastReadAt: DateTime.now(),
                  lastMessageBody: c.lastMessageBody,
                )
              : c)
          .toList();
      notifyListeners();
    } catch (e) {
      // Read state is a convenience; failing to record it should not surface
      // an error over the thread the student is reading.
      if (kDebugMode) debugPrint('markRead failed: $e');
    }
  }

  /// Adds, changes or clears this person's reaction to a message.
  ///
  /// One per person, so choosing a different emoji is an UPDATE and choosing
  /// the same one again clears it — which is what tapping a reaction you
  /// already gave obviously means.
  Future<bool> react(Message message, String emoji) async {
    final me = _service.userId;
    if (me == null) return false;
    if (!reactionChoices.contains(emoji)) return false;

    final mine = message.myReaction(me);
    try {
      if (mine == emoji) {
        await _service.client
            .from('message_reactions')
            .delete()
            .eq('message_id', message.id)
            .eq('profile_id', me);
      } else {
        await _service.client.from('message_reactions').upsert({
          'message_id': message.id,
          'profile_id': me,
          'emoji': emoji,
        }, onConflict: 'message_id,profile_id');
      }

      // Applied locally rather than reloading the thread: a reaction is one
      // cell changing, and a two-hundred-row refetch to repaint it would make
      // the tap feel like a round trip.
      final next = <String, List<String>>{
        for (final e in message.reactions.entries)
          e.key: e.value.where((p) => p != me).toList(),
      };
      if (mine != emoji) (next[emoji] ??= []).add(me);
      next.removeWhere((_, who) => who.isEmpty);
      _replace(message.copyWith(reactions: next));
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Sends a copy of a message into another thread.
  ///
  /// The attachment is COPIED in storage, not referenced: object paths are
  /// keyed on the conversation and the storage policy authorizes on that first
  /// segment, so pointing the new row at the old path would produce a message
  /// nobody on the receiving thread could open.
  Future<bool> forward(Message message, String toConversationId) async {
    _sending = true;
    _error = null;
    notifyListeners();

    try {
      String? path;
      if (message.attachmentPath != null) {
        path = _service.messageAttachmentPath(
            toConversationId, message.attachmentName);
        await _service.client.storage
            .from(AppConstants.bucketMessageAttachments)
            .copy(message.attachmentPath!, path);
      }

      final row = await _service.client
          .from('messages')
          .insert({
            'conversation_id': toConversationId,
            'sender_id': _service.userId,
            'body': message.body,
            'attachment_path': path,
            'kind': path == null ? 'text' : message.kind,
            'attachment_name': path == null ? null : message.attachmentName,
            'attachment_mime': path == null ? null : message.attachmentMime,
            'duration_ms': message.durationMs,
            'is_forwarded': true,
          })
          .select()
          .single();

      final forwarded = Message.fromMap(row);
      final existing = _messages[toConversationId] ?? [];
      if (!existing.any((m) => m.id == forwarded.id)) {
        _messages[toConversationId] = [...existing, forwarded];
      }
      await loadConversations();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Swaps one message for an updated copy, wherever it is.
  void _replace(Message message) {
    final list = _messages[message.conversationId];
    if (list == null) return;
    final index = list.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    _messages[message.conversationId] = [...list]..[index] = message;
    notifyListeners();
  }

  /// Deletes a message for the caller, or for everyone.
  ///
  /// `everyone` is the sender's own only, and the rule is enforced in SQL
  /// rather than by hiding the button — a client that decided this could
  /// withdraw the other party's words.
  Future<bool> deleteMessage(Message message, {required bool forEveryone}) async {
    try {
      await _service.client.rpc('delete_message', params: {
        'p_message_id': message.id,
        'p_scope': forEveryone ? 'everyone' : 'me',
      });

      final list = _messages[message.conversationId] ?? [];
      if (forEveryone) {
        // Reloaded rather than patched: the tombstone's shape is the server's
        // to decide, and guessing it here is how the two come to disagree.
        await loadMessages(message.conversationId);
      } else {
        _messages[message.conversationId] =
            list.where((m) => m.id != message.id).toList();
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  Future<String?> attachmentUrl(Message message) async {
    final path = message.attachmentPath;
    if (path == null) return null;
    try {
      return await _service.signedUrl(
        bucket: AppConstants.bucketMessageAttachments,
        path: path,
      );
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }

  // ── Safety: blocking and reporting a conversation ───────────────────────

  /// Which sides have blocked this conversation: 'student', 'institution',
  /// both or neither. Either one stops new messages, in the database.
  Future<Set<String>> blockedSides(String conversationId) async {
    try {
      final rows = await _service.client
          .from('conversation_blocks')
          .select('side')
          .eq('conversation_id', conversationId);
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['side'] as String,
      };
    } catch (_) {
      // An unknown state is shown as open; the insert policy still refuses a
      // message to a blocked conversation, so this cannot leak one through.
      return const {};
    }
  }

  /// Blocks or unblocks the conversation for the caller's side. The database
  /// works out which side that is.
  Future<bool> setBlocked(String conversationId, bool blocked) async {
    _error = null;
    try {
      await _service.client.rpc('set_conversation_blocked', params: {
        'p_conversation_id': conversationId,
        'p_blocked': blocked,
      });
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Reports one message, or the conversation as a whole when [messageId] is
  /// null. The database checks the caller can see what they are reporting.
  Future<bool> report(String conversationId, String reason,
      {String? messageId}) async {
    _error = null;
    try {
      await _service.client.rpc('report_conversation', params: {
        'p_conversation_id': conversationId,
        'p_reason': reason,
        'p_message_id': messageId,
      });
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
