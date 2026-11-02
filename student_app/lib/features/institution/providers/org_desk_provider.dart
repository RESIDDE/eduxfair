import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/pipeline.dart';

/// The two screens an admissions officer works in: the inbox and the pipeline.
///
/// One provider rather than two, because they are the same job seen twice — a
/// conversation usually becomes an application, and both are keyed by the same
/// match token, so a thread and a pipeline row for one student can be lined up
/// without either knowing who that student is.
class OrgDeskProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  List<InboxThread> _threads = [];

  /// conversation id -> the matching line, from `search_conversations`.
  Map<String, String> _inboxMatches = {};
  String _inboxQuery = '';
  bool _inboxSearching = false;
  List<PipelineEntry> _applications = [];

  bool _loading = false;
  bool _busy = false;
  String? _error;

  List<InboxThread> get threads => _threads;

  String get inboxQuery => _inboxQuery;
  bool get inboxSearching => _inboxSearching;

  /// The line that matched, for a thread the current search turned up.
  String? inboxMatchFor(String conversationId) => _inboxMatches[conversationId];

  /// Pinned first, then by recency — the order both tabs render in.
  List<InboxThread> _orderedThreads(Iterable<InboxThread> rows) {
    final list = rows.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        final at = a.lastMessageAt;
        final bt = b.lastMessageAt;
        if (at == null || bt == null) return at == null ? 1 : -1;
        return bt.compareTo(at);
      });
    return list;
  }

  /// Two halves, deliberately. The student's name or token is already in
  /// memory, so matching it needs no round trip and stays instant as you type;
  /// message bodies live in a table only the server can search under RLS.
  Iterable<InboxThread> get _visibleThreads {
    final q = _inboxQuery.trim().toLowerCase();
    if (q.isEmpty) return _threads;
    return _threads.where((t) =>
        t.displayName.toLowerCase().contains(q) ||
        (t.subject ?? '').toLowerCase().contains(q) ||
        _inboxMatches.containsKey(t.conversationId));
  }

  List<InboxThread> get inbox =>
      _orderedThreads(_visibleThreads.where((t) => !t.isArchived));

  List<InboxThread> get archivedThreads =>
      _orderedThreads(_visibleThreads.where((t) => t.isArchived));

  int get archivedCount => _threads.where((t) => t.isArchived).length;
  List<PipelineEntry> get applications => _applications;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;

  /// Counts the inbox, not the archive: a thread somebody filed away is not
  /// something to badge them about.
  int get unreadThreads =>
      _threads.where((t) => t.hasUnread && !t.isArchived).length;

  /// Applications that need somebody to do something: a document was asked for
  /// and has not arrived, or nobody has looked at it yet.
  int get needingAttention => _applications
      .where((a) => a.needsAttention || a.stage == 'submitted')
      .length;

  /// Grouped for the board, in the order an application actually travels.
  Map<String, List<PipelineEntry>> get byStage {
    final grouped = <String, List<PipelineEntry>>{};
    for (final stage in pipelineStages) {
      final inStage =
          _applications.where((a) => a.stage == stage).toList(growable: false);
      if (inStage.isNotEmpty) grouped[stage] = inStage;
    }
    return grouped;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Both views scope themselves to the caller's institution, so neither
      // call needs — or is trusted with — an institution id from the client.
      final results = await Future.wait([
        _service.client
            .from('institution_inbox')
            .select()
            .order('last_message_at', ascending: false, nullsFirst: false),
        _service.client
            .from('institution_pipeline')
            .select()
            .order('updated_at', ascending: false),
      ]);

      _threads = (results[0] as List)
          .map((r) => InboxThread.fromMap((r as Map).cast<String, dynamic>()))
          .toList();
      _applications = (results[1] as List)
          .map((r) => PipelineEntry.fromMap((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Runs a search over message bodies, and re-filters the list either way.
  ///
  /// `search_conversations` is invoker-rights in SQL, so the policy on
  /// `messages` decides what it can see.
  Future<void> searchInbox(String query) async {
    _inboxQuery = query;
    final q = query.trim();

    if (q.isEmpty) {
      _inboxMatches = {};
      _inboxSearching = false;
      notifyListeners();
      return;
    }

    _inboxSearching = true;
    notifyListeners();

    try {
      final rows = await _service.client
          .rpc('search_conversations', params: {'p_query': q});
      // Discarded if the box has moved on: a slow answer for an older query
      // must not overwrite what is on screen now.
      if (_inboxQuery.trim() != q) return;
      _inboxMatches = {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['conversation_id'] as String: (r['snippet'] as String?) ?? '',
      };
    } catch (e) {
      // A failed body search still leaves name matching working, so this is a
      // degraded search rather than a broken screen.
      if (kDebugMode) debugPrint('inbox search failed: $e');
      _inboxMatches = {};
    } finally {
      _inboxSearching = false;
      notifyListeners();
    }
  }

  void clearInboxSearch() {
    _inboxQuery = '';
    _inboxMatches = {};
    _inboxSearching = false;
    notifyListeners();
  }

  /// Pins or archives a thread for this officer alone.
  Future<bool> setThreadState(String conversationId,
      {bool? pinned, bool? archived}) async {
    try {
      await _service.client.rpc('set_conversation_state', params: {
        'p_conversation_id': conversationId,
        'p_pinned': pinned,
        'p_archived': archived,
      });
      await load();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Moves an application on, with the reason that goes into its history.
  ///
  /// Through `set_application_stage` rather than an UPDATE: the note has to
  /// reach the `application_events` row the trigger writes, and a plain update
  /// leaves it nowhere.
  Future<bool> setStage(String applicationId, String stage,
      {String? note}) async {
    return _run(() async {
      await _service.client.rpc('set_application_stage', params: {
        'p_application_id': applicationId,
        'p_stage': stage,
        'p_note': note,
      });
    });
  }

  Future<bool> requestDocument(String applicationId, String kind,
      {String? note}) async {
    return _run(() async {
      await _service.client.rpc('request_application_document', params: {
        'p_application_id': applicationId,
        'p_kind': kind,
        'p_note': note,
      });
    });
  }

  /// The history behind one application, oldest first.
  Future<List<Map<String, dynamic>>> history(String applicationId) async {
    try {
      final rows = await _service.client
          .from('application_events')
          .select()
          .eq('application_id', applicationId)
          .order('created_at');
      return (rows as List)
          .map((r) => (r as Map).cast<String, dynamic>())
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return const [];
    }
  }

  Future<bool> _run(Future<void> Function() work) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await work();
      await load();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
