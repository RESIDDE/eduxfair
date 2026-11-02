import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/space.dart';

/// Live Spaces: finding them, scheduling them, and running them.
///
/// Same shape as [MeetProvider]: `_loading` / `_busy` / `_error`, a `load()`,
/// mutators returning a bool, and `clearError()`.
class SpacesProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  List<Space> _spaces = [];
  bool _loading = false;
  bool _busy = false;
  String? _error;
  RealtimeChannel? _channel;

  List<Space> get spaces => _spaces;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;

  List<Space> get live => _spaces.where((s) => s.isLive).toList();

  List<Space> get upcoming => _spaces.where((s) => s.isScheduled).toList()
    ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));

  List<Space> get past => _spaces.where((s) => s.isOver).toList();

  /// Everything a student may see. The RLS policy decides the audience, so this
  /// deliberately filters nothing: `spaces_select_signed_in` already means a
  /// scheduled session is visible to anyone signed in, which is the point — the
  /// Spaces tab is how a student finds one.
  Future<void> load({String? institutionId}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      var query = _service.client
          .from('spaces')
          .select('*, institutions!inner(id, name, slug, logo_url, '
              'verification_status, kind)');
      if (institutionId != null) {
        query = query.eq('institution_id', institutionId);
      }
      final rows = await query
          .neq('status', 'cancelled')
          .order('scheduled_for', ascending: false)
          .limit(100);

      _spaces = (rows as List)
          .map((r) => Space.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// A session going live has to arrive without a pull-to-refresh, because
  /// "drop in" is what the tab promises.
  void subscribe({String? institutionId}) {
    unsubscribe();
    _channel = _service.client
        .channel('spaces:${institutionId ?? 'all'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'spaces',
          callback: (_) => load(institutionId: institutionId),
        )
        .subscribe();
  }

  void unsubscribe() {
    final channel = _channel;
    if (channel == null) return;
    _channel = null;
    _service.client.removeChannel(channel);
  }

  /// The roster for one Space, for the attendance summary on a past session.
  ///
  /// Reads `space_roster`, so it carries handles and consented names and no
  /// account ids — the view is the only thing an institution reads about who
  /// was in its room.
  Future<List<SpaceRosterEntry>> rosterFor(String spaceId) async {
    final rows = await _service.client
        .from('space_roster')
        .select()
        .eq('space_id', spaceId);
    return (rows as List)
        .map((r) => SpaceRosterEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Staff ────────────────────────────────────────────────────────────────

  Future<bool> schedule({
    required String institutionId,
    required String hostProfileId,
    required String title,
    required DateTime scheduledFor,
    String? description,
    String kind = 'admissions_hour',
    int durationMin = 45,
    int maxParticipants = 200,
    bool requiresAdmission = false,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client.from('spaces').insert({
        'institution_id': institutionId,
        'host_profile_id': hostProfileId,
        'title': title.trim(),
        'description': description?.trim(),
        'kind': kind,
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'duration_min': durationMin,
        'max_participants': maxParticipants,
        'requires_admission': requiresAdmission,
      });
      await load(institutionId: institutionId);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Going live creates the LiveKit room, so it goes through the Edge Function
  /// rather than a direct status update.
  Future<bool> goLive(Space space) => _roomAction(
        space,
        {'action': 'go_live', 'space_id': space.id},
      );

  Future<bool> end(Space space) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      try {
        final result = await _service.invoke('livekit-room', body: {
          'action': 'end',
          'space_id': space.id,
        });
        if (result['livekit'] == false && result['error'] != null) {
          _error = result['error'] as String;
        }
      } catch (_) {
        // Fallback directly to Postgres RPC so status always updates to ended
        await _service.client.rpc('space_set_status', params: {
          'p_space_id': space.id,
          'p_status': 'ended',
        });
      }
      await load(institutionId: space.institutionId);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _roomAction(Space space, Map<String, dynamic> body) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.invoke('livekit-room', body: body);
      // The status moved even if LiveKit did not answer. Saying so beats
      // letting a host walk into a room that was never created.
      if (result['livekit'] == false && result['error'] != null) {
        _error = result['error'] as String;
      }
      await load(institutionId: space.institutionId);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> cancel(Space space) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client.rpc('space_set_status', params: {
        'p_space_id': space.id,
        'p_status': 'cancelled',
      });
      await load(institutionId: space.institutionId);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> deleteSpace(Space space) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client.from('spaces').delete().eq('id', space.id);
      _spaces.removeWhere((s) => s.id == space.id);
      notifyListeners();
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
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}
