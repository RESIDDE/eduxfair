import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../models/field_of_study.dart';
import '../models/passport.dart';
import '../models/passport_document.dart';
import '../models/passport_share.dart';

/// Owns the student's passport, their documents and their consent grants.
///
/// Matching is recomputed by database triggers on every meaningful passport
/// change, so nothing here needs to kick it off — saving the passport is
/// enough, and `completeness` comes back already recalculated.
class PassportProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  Passport? _passport;
  List<PassportDocument> _documents = [];
  List<PassportShare> _shares = [];
  List<FieldOfStudy> _fields = [];

  bool _loading = false;
  bool _saving = false;
  String? _error;

  PassportProvider() {
    try {
      _service.authChanges.listen((state) {
        if (state.event == AuthChangeEvent.signedOut) {
          _passport = null;
          _documents = [];
          _shares = [];
          _fields = [];
          _handle = null;
          _error = null;
          _loading = false;
          notifyListeners();
        }
      });
    } catch (_) {
      // Uninitialized Supabase in pure unit tests
    }
  }

  /// The caller's public handle, or null if they have not claimed one.
  /// Read through `my_handle()` rather than from `social_profiles`, which has
  /// no public select policy — the handle is public, the row behind it is not.
  String? _handle;
  String? _bio;

  Passport? get passport => _passport;
  List<PassportDocument> get documents => _documents;

  /// Only live grants — a revoked share is history, not access.
  List<PassportShare> get activeShares =>
      _shares.where((s) => s.isActive).toList();
  List<PassportShare> get allShares => _shares;

  List<FieldOfStudy> get fields => _fields;
  String? get handle => _handle;

  /// The PUBLIC bio from `social_profiles`, not `passports.bio`. The two are
  /// different columns with different audiences: this one is on the handle
  /// profile for anyone, that one is passport data behind a share.
  String? get bio => _bio;
  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;

  int get completeness => _passport?.completeness ?? 0;
  bool get isMatchable => _passport?.isMatchable ?? false;

  /// How far through the "ready to be discovered" bar they are.
  double get completenessFraction => (completeness / 100).clamp(0.0, 1.0);

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Fetched together: the passport screen renders all four, and four
      // sequential round trips on a Lagos mobile connection is a visible wait.
      final results = await Future.wait([
        _fetchPassport(),
        _fetchDocuments(),
        _fetchShares(),
        _fetchFields(),
        _fetchHandle(),
      ]);

      _passport = results[0] as Passport?;
      _documents = results[1] as List<PassportDocument>;
      _shares = results[2] as List<PassportShare>;
      _fields = results[3] as List<FieldOfStudy>;
      _handle = results[4] as String?;
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Passport?> _fetchPassport() async {
    final id = _service.userId;
    if (id == null) return null;
    final row = await _service.client
        .from('student_passports')
        .select()
        .eq('profile_id', id)
        .maybeSingle();
    return row == null ? null : Passport.fromMap(row);
  }

  Future<List<PassportDocument>> _fetchDocuments() async {
    final id = _service.userId;
    if (id == null) return [];
    final rows = await _service.client
        .from('passport_documents')
        .select()
        .eq('profile_id', id)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => PassportDocument.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<PassportShare>> _fetchShares() async {
    final id = _service.userId;
    if (id == null) return [];
    final rows = await _service.client
        .from('passport_shares')
        .select('*, institutions(id, name, logo_url, country)')
        .eq('profile_id', id)
        .order('granted_at', ascending: false);
    return (rows as List)
        .map((r) => PassportShare.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<String?> _fetchHandle() async {
    try {
      final handle = await _service.client.rpc('my_handle') as String?;
      // The bio rides along with the handle: both come from social_profiles,
      // and every caller that wants one wants the other.
      if (handle != null) {
        final row = await _service.client
            .from('public_profiles')
            .select('bio')
            .eq('handle', handle)
            .maybeSingle();
        _bio = row?['bio'] as String?;
      }
      return handle;
    } catch (_) {
      // A missing handle is an ordinary state, not an error worth surfacing.
      return null;
    }
  }

  /// Sets or clears the public bio.
  ///
  /// Through `set_social_bio` rather than `claim_handle`, which coalesces a
  /// null onto the existing value — right for a rename, and wrong here, where
  /// clearing the field has to mean clearing the bio.
  Future<bool> saveBio(String? bio) async {
    _saving = true;
    _error = null;
    notifyListeners();

    try {
      _bio = await _service.client
          .rpc('set_social_bio', params: {'p_bio': bio}) as String?;
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Re-reads just the handle.
  ///
  /// `load()` fetches the passport, documents, shares and reference data — far
  /// too much for the one question "may this person reply yet?", which the feed
  /// needs to answer before opening a reply sheet.
  Future<String?> refreshHandle() async {
    _handle = await _fetchHandle();
    notifyListeners();
    return _handle;
  }

  /// Claims or renames the caller's public handle.
  ///
  /// A function rather than an insert, so the shape rules and the uniqueness
  /// check produce messages worth showing someone — `social_handle_shape` is
  /// not a sentence.
  Future<bool> claimHandle(String handle, String displayName) async {
    _saving = true;
    _error = null;
    notifyListeners();

    try {
      _handle = await _service.client.rpc('claim_handle', params: {
        'p_handle': handle,
        'p_display_name': displayName,
      }) as String?;
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<List<FieldOfStudy>> _fetchFields() async {
    final rows = await _service.client
        .from('fields_of_study')
        .select()
        .order('sort_order');
    return (rows as List)
        .map((r) => FieldOfStudy.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ── Saving ────────────────────────────────────────────────────────────────

  /// Creates or updates the passport.
  ///
  /// Upsert rather than insert-or-update branching, because a student reaching
  /// the edit screen may or may not already have a row and the distinction is
  /// not worth a round trip to discover.
  Future<bool> save(Passport updated) async {
    _saving = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _service.client
          .from('student_passports')
          .upsert(updated.toUpsertMap(), onConflict: 'profile_id')
          .select()
          .single();

      // Read back rather than trusting the local copy: completeness,
      // normalized_grade and english_band are all computed server-side.
      _passport = Passport.fromMap(row);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ── Documents ─────────────────────────────────────────────────────────────

  /// Uploads a document and records it.
  ///
  /// Takes bytes, not a path, because this app also runs on web where
  /// file_picker returns no filesystem path at all.
  Future<bool> uploadDocument({
    required String kind,
    required String fileName,
    required Uint8List bytes,
    String? mime,
  }) async {
    _saving = true;
    _error = null;
    notifyListeners();

    String? uploadedPath;
    try {
      final path = _service.passportDocPath(fileName);
      await _service.uploadBytes(
        bucket: AppConstants.bucketPassportDocs,
        path: path,
        bytes: bytes,
        contentType: mime,
      );
      uploadedPath = path;

      final row = await _service.client
          .from('passport_documents')
          .insert({
            'profile_id': _service.userId,
            'kind': kind,
            'storage_path': path,
            'file_name': fileName,
            'mime': mime,
            'size_bytes': bytes.length,
          })
          .select()
          .single();

      _documents = [PassportDocument.fromMap(row), ..._documents];

      // The documents trigger bumps completeness, so refresh the passport to
      // keep the progress meter honest.
      _passport = await _fetchPassport();
      return true;
    } catch (e) {
      // Don't leave an orphan object in the bucket if the row insert failed.
      if (uploadedPath != null) {
        try {
          await _service.removeObject(
            bucket: AppConstants.bucketPassportDocs,
            path: uploadedPath,
          );
        } catch (_) {
          // Best effort: the row is what matters, and a stray object is
          // recoverable by an admin sweep.
        }
      }
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> deleteDocument(PassportDocument doc) async {
    _error = null;
    try {
      // Row first: if this is denied, the file should still be there.
      await _service.client.from('passport_documents').delete().eq('id', doc.id);
      await _service.removeObject(
        bucket: AppConstants.bucketPassportDocs,
        path: doc.storagePath,
      );

      _documents = _documents.where((d) => d.id != doc.id).toList();
      _passport = await _fetchPassport();
      notifyListeners();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// A short-lived URL for viewing a document. The bucket is private, so there
  /// is no permanent URL to cache.
  Future<String?> documentUrl(PassportDocument doc) async {
    try {
      return await _service.signedUrl(
        bucket: AppConstants.bucketPassportDocs,
        path: doc.storagePath,
      );
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  /// Asks an admin to verify the passport. Only requests — the status itself is
  /// set by review, and `guard_self_verification()` enforces that.
  Future<bool> requestVerification() async {
    _error = null;
    try {
      await _service.client.from('verifications').insert({
        'subject_type': 'passport',
        'subject_id': _service.userId,
        'status': 'pending',
      });
      _passport = await _fetchPassport();
      notifyListeners();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  // ── Consent ───────────────────────────────────────────────────────────────

  Future<bool> grantShare(String institutionId, {String? reason}) async {
    _error = null;
    try {
      await _service.client.from('passport_shares').insert({
        'profile_id': _service.userId,
        'institution_id': institutionId,
        'reason': reason ?? 'You chose to share your passport',
      });
      _shares = await _fetchShares();
      notifyListeners();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Revokes access. A timestamp, not a delete, so the grant history survives —
  /// which matters if a student ever needs to show who saw their documents.
  Future<bool> revokeShare(PassportShare share) async {
    _error = null;
    try {
      await _service.client
          .from('passport_shares')
          .update({'revoked_at': DateTime.now().toIso8601String()})
          .eq('id', share.id);
      _shares = await _fetchShares();
      notifyListeners();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  String fieldLabel(String slug) =>
      _fields.firstWhere(
        (f) => f.slug == slug,
        orElse: () => FieldOfStudy(slug: slug, label: slug),
      ).label;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
