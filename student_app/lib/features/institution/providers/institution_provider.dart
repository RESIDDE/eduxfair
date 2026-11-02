import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../discover/models/institution.dart';
import '../../discover/models/program.dart';
import '../../passport/models/field_of_study.dart';
import '../../discover/models/prospectus.dart';
import '../models/managed_institution.dart';

/// The institution the signed-in staff member works for.
///
/// One membership is the common case; the first is the active one until there
/// is a reason to build a switcher. Loaded once when an institution account
/// signs in, and the shell will not render until it resolves — every screen
/// below it needs the institution id.
class InstitutionProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  ManagedInstitution? _managed;
  InstitutionDemand _demand = const InstitutionDemand();

  bool _loading = false;
  bool _saving = false;
  String? _error;

  /// Whether a load has completed at least once. Without this, `needsSetup`
  /// would be true on the very first redirect — before anything had been
  /// fetched — and every institution would be sent to the setup screen.
  bool _loaded = false;

  InstitutionProvider() {
    _service.authChanges.listen(_onAuthChange);
    if (_service.isSignedIn) load();
  }

  void _onAuthChange(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
        load();
      case AuthChangeEvent.signedOut:
        _managed = null;
        _demand = const InstitutionDemand();
        _loaded = false;
        _error = null;
        notifyListeners();
      default:
        break;
    }
  }

  ManagedInstitution? get managed => _managed;
  Institution? get institution => _managed?.institution;
  String? get institutionId => _managed?.institution.id;

  /// The organisation's public handle, which `create_institution()` derives
  /// from its name. Read through `my_handle()` because `social_profiles` has no
  /// public select policy — the handle is public, the row behind it is not.
  ///
  /// The shell needs it to list what the organisation has actually posted:
  /// posts are addressed by handle, never by account id.
  String? get handle => _handle;
  InstitutionProfile? get profile => _managed?.profile;
  InstitutionDemand get demand => _demand;

  String? _handle;

  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;

  /// True once we know the account is staff with no institution yet. The shell
  /// sends them to setup rather than a dashboard with nothing to show.
  bool get needsSetup =>
      _loaded && !_loading && _managed == null && _error == null;

  /// The router has to wait rather than guess while this is false.
  bool get isResolved => _loaded && !_loading;

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final id = _service.userId;
      if (id == null) return;

      final membership = await _service.client
          .from('institution_members')
          .select('member_role, institution_id, institutions(*)')
          .eq('profile_id', id)
          .limit(1)
          .maybeSingle();

      if (membership == null) {
        _managed = null;
        return;
      }

      final institutionId = membership['institution_id'] as String;

      // Fetched together: the shell needs all three before it can render, and
      // three sequential round trips is a visible wait on mobile data.
      final results = await Future.wait([
        _service.client
            .from('institution_profiles')
            .select()
            .eq('institution_id', institutionId)
            .maybeSingle(),
        _service.client
            .from('institution_subscriptions')
            .select('tier, seats')
            .eq('institution_id', institutionId)
            .maybeSingle(),
      ]);

      final profileRow = results[0];
      final subscription = results[1];

      _managed = ManagedInstitution(
        institution: Institution.fromMap(
          (membership['institutions'] as Map).cast<String, dynamic>()),
        profile: InstitutionProfile.fromMap(profileRow ?? const {}),
        memberRole: membership['member_role'] as String? ?? 'admissions_officer',
        tier: subscription?['tier'] as String? ?? 'basic',
        seats: (subscription?['seats'] as num?)?.toInt() ?? 1,
      );

      await _loadDemand();
      _handle = await _fetchHandle();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  Future<String?> _fetchHandle() async {
    try {
      return await _service.client.rpc('my_handle') as String?;
    } catch (_) {
      // An institution created before handles were derived at signup may not
      // have one. That is a missing handle, not an error worth surfacing.
      return null;
    }
  }

  Future<void> _loadDemand() async {
    final id = institutionId;
    if (id == null) return;

    try {
      final result = await _service.client.rpc(
        'my_institution_demand',
        params: {'p_institution_id': id},
      );
      if (result != null) {
        _demand = InstitutionDemand.fromJson((result as Map).cast<String, dynamic>());
      }
    } catch (e) {
      // The dashboard degrades to zeroes rather than failing the whole shell.
      if (kDebugMode) debugPrint('demand load failed: $e');
    }
  }

  Future<void> refresh() => load();

  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Creates the institution and makes the caller its owner.
  ///
  /// Through `create_institution()` rather than a direct insert: RLS cannot let
  /// someone add a membership row for an institution they are not yet a member
  /// of, so the function does the listing, the ownership, the subscription and
  /// the verification request in one transaction.
  Future<bool> createInstitution({
    required String name,
    required String country,
    required String kind,
    String? city,
    String? website,
    String? emailDomain,
    String? description,
  }) async {
    _saving = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client.rpc('create_institution', params: {
        'p_name': name.trim(),
        'p_country': country,
        'p_website': website?.trim(),
        'p_email_domain': emailDomain?.trim(),
        'p_city': city?.trim(),
        'p_description': description?.trim(),
        // Decides whether the listing is about programs or visa routes, so it
        // is set at creation rather than defaulted and corrected later.
        'p_kind': kind,
      });
      await load();
      return _managed != null;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ── The prospectus ────────────────────────────────────────────────────────

  /// Saves part of the profile. Takes a patch rather than the whole row so a
  /// section can save without clobbering one being edited elsewhere.
  Future<bool> saveProfile(Map<String, dynamic> patch) async {
    final id = institutionId;
    if (id == null) return false;

    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _service.client
          .from('institution_profiles')
          .update(patch)
          .eq('institution_id', id)
          .select()
          .single();

      // Read back: completeness is recomputed by a trigger, so the local copy
      // would otherwise report a stale score.
      _managed = ManagedInstitution(
        institution: _managed!.institution,
        profile: InstitutionProfile.fromMap(row),
        memberRole: _managed!.memberRole,
        tier: _managed!.tier,
        seats: _managed!.seats,
      );
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Saves the institution record itself — name, country, domain.
  Future<bool> saveInstitution(Map<String, dynamic> patch) async {
    final id = institutionId;
    if (id == null) return false;

    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _service.client
          .from('institutions')
          .update(patch)
          .eq('id', id)
          .select()
          .single();

      _managed = ManagedInstitution(
        institution: Institution.fromMap(row),
        profile: _managed!.profile,
        memberRole: _managed!.memberRole,
        tier: _managed!.tier,
        seats: _managed!.seats,
      );
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Uploads a university logo to storage and saves the public URL.
  Future<bool> uploadLogo({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final id = institutionId;
    if (id == null) return false;

    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final path = _service.institutionLogoPath(id, fileName);
      await _service.uploadBytes(
        bucket: 'institution-logos',
        path: path,
        bytes: bytes,
        contentType: mimeType ?? 'image/jpeg',
        upsert: true,
      );
      final url = _service.publicUrl(bucket: 'institution-logos', path: path);
      return await saveInstitution({'logo_url': url});
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Clears the university logo.
  Future<bool> removeLogo() => saveInstitution({'logo_url': null});

  // ── Programs ──────────────────────────────────────────────────────────────
  //
  // Not a prospectus section: programs are what the matching engine reads, so
  // they have their own shape and their own consequence. Adding one makes an
  // institution discoverable; `refresh_matches_for_program()` scores it against
  // every eligible passport, which is why saving one asks the database to
  // recompute rather than waiting for a nightly sweep.

  List<Program> _programs = [];
  List<FieldOfStudy> _fields = [];
  bool _loadingPrograms = false;

  List<Program> get programs => _programs;
  List<FieldOfStudy> get fieldsOfStudy => _fields;
  bool get loadingPrograms => _loadingPrograms;

  /// A slug -> label map, for rendering a stored `field_of_study`.
  Map<String, String> get fieldLabels =>
      {for (final f in _fields) f.slug: f.label};

  Future<void> loadPrograms() async {
    final id = institutionId;
    if (id == null) return;

    _loadingPrograms = true;
    _error = null;
    notifyListeners();

    try {
      // The vocabulary is loaded with them: a program's field_of_study is a
      // foreign key into fields_of_study, and a typed-in subject silently makes
      // the program unmatchable. The picker must never be free text.
      final results = await Future.wait([
        _service.client
            .from('programs')
            .select()
            .eq('institution_id', id)
            .order('is_active', ascending: false)
            .order('created_at', ascending: false),
        if (_fields.isEmpty)
          _service.client.from('fields_of_study').select().order('sort_order'),
      ]);

      _programs = (results[0] as List)
          .map((r) => Program.fromMap(r as Map<String, dynamic>))
          .toList();
      if (results.length > 1) {
        _fields = (results[1] as List)
            .map((r) => FieldOfStudy.fromMap(r as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loadingPrograms = false;
      notifyListeners();
    }
  }

  Future<bool> saveProgram(Map<String, dynamic> values, {String? programId}) async {
    final id = institutionId;
    if (id == null) return false;

    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final row = programId == null
          ? await _service.client
              .from('programs')
              .insert({...values, 'institution_id': id})
              .select()
              .single()
          : await _service.client
              .from('programs')
              .update(values)
              .eq('id', programId)
              .select()
              .single();

      // Triggers already keep match_scores current (20251009000013), so this is
      // belt and braces for the first program an institution adds — the one
      // where an empty Matched students screen reads as a broken feature rather
      // than an empty one.
      try {
        await _service.client.rpc('refresh_matches_for_program',
            params: {'target': row['id']});
      } catch (_) {
        // Scoring is not the point of the save. A failure here leaves the
        // program saved and the triggers to catch up.
      }

      await loadPrograms();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Retiring a program rather than deleting it.
  ///
  /// `is_active = false` drops it out of discovery and matching while leaving
  /// every application that referenced it intact — a student's history should
  /// not change because an institution stopped offering something.
  Future<bool> setProgramActive(String programId, bool active) =>
      saveProgram({'is_active': active}, programId: programId);

  Future<bool> deleteProgram(String programId) async {
    _error = null;
    try {
      await _service.client.from('programs').delete().eq('id', programId);
      await loadPrograms();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  // ── The repeating prospectus sections ─────────────────────────────────────
  //
  // Six tables with the same shape — list, add, update, remove — so they share
  // one set of methods keyed on the table name rather than six near-identical
  // pairs.

  Future<List<Map<String, dynamic>>> listSection(String table) async {
    final id = institutionId;
    if (id == null) return [];

    try {
      final rows = await _service.client
          .from(table)
          .select()
          .eq('institution_id', id)
          .order('ord');
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return [];
    }
  }

  Future<bool> saveSectionRow(
    String table,
    Map<String, dynamic> values, {
    String? rowId,
  }) async {
    final id = institutionId;
    if (id == null) return false;

    _saving = true;
    _error = null;
    notifyListeners();

    try {
      if (rowId == null) {
        await _service.client
            .from(table)
            .insert({...values, 'institution_id': id});
      } else {
        await _service.client.from(table).update(values).eq('id', rowId);
      }
      await _refreshCompleteness();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteSectionRow(String table, String rowId) async {
    _error = null;
    try {
      await _service.client.from(table).delete().eq('id', rowId);
      await _refreshCompleteness();
      notifyListeners();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Child rows move the trigger-computed score, so the meter has to be reread.
  Future<void> _refreshCompleteness() async {
    final id = institutionId;
    if (id == null || _managed == null) return;

    final row = await _service.client
        .from('institution_profiles')
        .select()
        .eq('institution_id', id)
        .maybeSingle();

    if (row != null) {
      _managed = ManagedInstitution(
        institution: _managed!.institution,
        profile: InstitutionProfile.fromMap(row),
        memberRole: _managed!.memberRole,
        tier: _managed!.tier,
        seats: _managed!.seats,
      );
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
