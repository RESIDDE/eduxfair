import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/institution.dart';
import '../models/program.dart';
import '../models/prospectus.dart';

/// Browsing institutions and programs, plus the student's saved list.
///
/// Search runs server-side: a student on a Lagos mobile connection should not
/// be downloading the whole program catalogue to filter it on-device.
class DiscoverProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  static const int _pageSize = 20;

  List<Program> _programs = [];
  List<Institution> _institutions = [];
  Set<String> _savedProgramIds = {};

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  // Active filters.
  String _query = '';
  String? _levelFilter;
  String? _fieldFilter;
  String? _countryFilter;
  bool _scholarshipOnly = false;

  List<Program> get programs => _programs;
  List<Institution> get institutions => _institutions;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  String get query => _query;
  String? get levelFilter => _levelFilter;
  String? get fieldFilter => _fieldFilter;
  String? get countryFilter => _countryFilter;
  bool get scholarshipOnly => _scholarshipOnly;

  bool get hasFilters =>
      _query.isNotEmpty ||
      _levelFilter != null ||
      _fieldFilter != null ||
      _countryFilter != null ||
      _scholarshipOnly;

  bool isSaved(String programId) => _savedProgramIds.contains(programId);

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    _error = null;
    _programs = [];
    _hasMore = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchPrograms(offset: 0),
        _fetchInstitutions(),
        _fetchSaved(),
      ]);
      _programs = results[0] as List<Program>;
      _institutions = results[1] as List<Institution>;
      _savedProgramIds = results[2] as Set<String>;
      _hasMore = _programs.length >= _pageSize;
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    _loadingMore = true;
    notifyListeners();

    try {
      final next = await _fetchPrograms(offset: _programs.length);
      _programs = [..._programs, ...next];
      _hasMore = next.length >= _pageSize;
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<List<Program>> _fetchPrograms({required int offset}) async {
    // The `programs_select_active` policy already hides drafts, so no is_active
    // filter is needed here — but it is included anyway so the intent is
    // readable without having to know the policy.
    var builder = _service.client
        .from('programs')
        .select('*, institutions!inner(id, name, slug, country, city, '
            'logo_url, verification_status, tier)')
        .eq('is_active', true);

    if (_query.isNotEmpty) {
      // Matches the program name; institution name is handled by the separate
      // institution list, which keeps this a single indexable predicate.
      builder = builder.ilike('name', '%$_query%');
    }
    if (_levelFilter != null) builder = builder.eq('level', _levelFilter!);
    if (_fieldFilter != null) builder = builder.eq('field_of_study', _fieldFilter!);
    if (_countryFilter != null) {
      builder = builder.eq('institutions.country', _countryFilter!);
    }
    if (_scholarshipOnly) builder = builder.eq('scholarship_available', true);

    final rows = await builder
        .order('created_at', ascending: false)
        .range(offset, offset + _pageSize - 1);

    return (rows as List)
        .map((r) => Program.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Institution>> _fetchInstitutions() async {
    var builder = _service.client.from('institutions').select();
    if (_countryFilter != null) builder = builder.eq('country', _countryFilter!);
    if (_query.isNotEmpty) builder = builder.ilike('name', '%$_query%');

    final rows = await builder
        // Verified listings first: the badge is the point of the directory.
        .order('verification_status')
        .order('name')
        .limit(50);
    return (rows as List)
        .map((r) => Institution.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<Set<String>> _fetchSaved() async {
    final id = _service.userId;
    if (id == null) return {};
    final rows = await _service.client
        .from('student_interests')
        .select('program_id')
        .eq('profile_id', id)
        .eq('kind', 'saved');
    return (rows as List).map((r) => r['program_id'] as String).toSet();
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  Future<void> search(String query) async {
    if (_query == query) return;
    _query = query;
    await load();
  }

  Future<void> setFilters({
    String? level,
    String? field,
    String? country,
    bool? scholarshipOnly,
    bool clearLevel = false,
    bool clearField = false,
    bool clearCountry = false,
  }) async {
    if (clearLevel) {
      _levelFilter = null;
    } else if (level != null) {
      _levelFilter = level;
    }
    if (clearField) {
      _fieldFilter = null;
    } else if (field != null) {
      _fieldFilter = field;
    }
    if (clearCountry) {
      _countryFilter = null;
    } else if (country != null) {
      _countryFilter = country;
    }
    if (scholarshipOnly != null) _scholarshipOnly = scholarshipOnly;

    await load();
  }

  Future<void> clearFilters() async {
    _query = '';
    _levelFilter = null;
    _fieldFilter = null;
    _countryFilter = null;
    _scholarshipOnly = false;
    await load();
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  Future<Institution?> fetchInstitution(String id) async {
    try {
      final row = await _service.client
          .from('institutions')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Institution.fromMap(row);
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  /// The whole institution page in one call.
  ///
  /// `institution_prospectus` also narrows entry requirements to the student's
  /// own country server-side — from their passport, so nothing has to be passed
  /// — which is not something PostgREST can express as an embed.
  Future<Prospectus?> fetchProspectus(String institutionId) async {
    try {
      final result = await _service.client.rpc(
        'institution_prospectus',
        params: {'p_institution_id': institutionId},
      );
      if (result == null) return null;
      return Prospectus.fromJson((result as Map).cast<String, dynamic>());
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  Future<List<Program>> fetchInstitutionPrograms(String institutionId) async {
    try {
      final rows = await _service.client
          .from('programs')
          .select('*, institutions!inner(id, name, slug, country, city, '
              'logo_url, verification_status, tier)')
          .eq('institution_id', institutionId)
          .eq('is_active', true)
          .order('level')
          .order('name');
      return (rows as List)
          .map((r) => Program.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return [];
    }
  }

  Future<Program?> fetchProgram(String id) async {
    try {
      final row = await _service.client
          .from('programs')
          .select('*, institutions!inner(id, name, slug, country, city, '
              'logo_url, verification_status, tier, description, website)')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Program.fromMap(row);
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  /// Saves or unsaves a program. Optimistic, because a star that waits for a
  /// server round trip feels broken.
  Future<void> toggleSaved(String programId) async {
    final wasSaved = _savedProgramIds.contains(programId);
    _savedProgramIds = {..._savedProgramIds};
    wasSaved
        ? _savedProgramIds.remove(programId)
        : _savedProgramIds.add(programId);
    notifyListeners();

    try {
      if (wasSaved) {
        await _service.client
            .from('student_interests')
            .delete()
            .eq('profile_id', _service.userId!)
            .eq('program_id', programId)
            .eq('kind', 'saved');
      } else {
        await _service.client.from('student_interests').insert({
          'profile_id': _service.userId,
          'program_id': programId,
          'kind': 'saved',
        });
      }
    } catch (e) {
      // Put it back so the UI never claims something that did not happen.
      _savedProgramIds = {..._savedProgramIds};
      wasSaved
          ? _savedProgramIds.add(programId)
          : _savedProgramIds.remove(programId);
      _error = SupabaseService.describeError(e);
      notifyListeners();
    }
  }

  /// Signals interest to the institution. Pseudonymous until the student
  /// shares their passport, which is exactly how reverse admission works.
  Future<bool> requestInfo(String programId) async {
    try {
      await _service.client.from('student_interests').insert({
        'profile_id': _service.userId,
        'program_id': programId,
        'kind': 'requested_info',
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
