import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/match_card.dart';

/// The student's side of matching and reverse admission.
///
/// Scores are maintained by database triggers on every passport and program
/// change, so this provider only ever reads them. `refresh()` exists for the
/// pull-to-refresh gesture, not because anything here computes a match.
class MatchesProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  List<MatchCard> _matches = [];
  List<Invitation> _invitations = [];
  bool _loading = false;
  String? _error;

  List<MatchCard> get matches => _matches;
  List<Invitation> get invitations => _invitations;
  bool get loading => _loading;
  String? get error => _error;

  int get matchCount => _matches.length;
  int get invitationCount => _invitations.length;

  /// Matches worth leading with on the home screen.
  List<MatchCard> get topMatches => _matches.take(3).toList();

  List<MatchCard> get scholarshipMatches =>
      _matches.where((m) => m.hasScholarship).toList();

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchMatches(),
        _fetchInvitations(),
      ]);
      _matches = results[0] as List<MatchCard>;
      _invitations = results[1] as List<Invitation>;
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<MatchCard>> _fetchMatches() async {
    final id = _service.userId;
    if (id == null) return [];

    final rows = await _service.client
        .from('match_scores')
        .select('program_id, score, reasons, computed_at, '
            'programs!inner(*, institutions!inner(id, name, slug, country, '
            'city, logo_url, verification_status, tier))')
        .eq('student_id', id)
        .order('score', ascending: false)
        .limit(100);

    return (rows as List)
        .map((r) => MatchCard.fromMap(r as Map<String, dynamic>))
        // An inactive program can linger in match_scores between the
        // program update and the trigger's cleanup, so drop it client-side
        // rather than show a course nobody can apply to.
        .where((m) => m.program?.isActive ?? true)
        .toList();
  }

  Future<List<Invitation>> _fetchInvitations() async {
    final id = _service.userId;
    if (id == null) return [];

    // kind is filtered explicitly even though the policy already restricts it:
    // relying on RLS alone here would make the query's intent invisible.
    final rows = await _service.client
        .from('institution_interests')
        .select('id, institution_id, program_id, note, created_at, '
            'institutions!inner(id, name, logo_url, country, verification_status), '
            'programs(id, name)')
        .eq('profile_id', id)
        .eq('kind', 'invited')
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => Invitation.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> refresh() => load();

  /// Forces a recompute. Only needed after an unusual change — ordinarily the
  /// triggers have already done it before the student gets here.
  Future<bool> recompute() async {
    _error = null;
    try {
      await _service.invoke('compute-matches', body: {
        'student_id': _service.userId,
      });
      await load();
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
