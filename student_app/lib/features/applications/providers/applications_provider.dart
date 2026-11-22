import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/application.dart';

/// The student's applications and their progress.
///
/// Submitting writes a `passport_shares` row via a database trigger — applying
/// to an institution is an unambiguous request to be identified by it — so the
/// submit confirmation says so plainly.
class ApplicationsProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  List<Application> _applications = [];
  bool _loading = false;
  bool _busy = false;
  String? _error;

  List<Application> get applications => _applications;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _error;

  List<Application> get active =>
      _applications.where((a) => !a.isClosed).toList();
  List<Application> get closed =>
      _applications.where((a) => a.isClosed).toList();

  int get offerCount => _applications.where((a) => a.hasOffer).length;
  int get outstandingRequestCount => _applications
      .expand((a) => a.outstandingRequests)
      .length;

  static const String _selectWithJoins =
      '*, institutions!inner(id, name, slug, country, city, logo_url, '
      'verification_status, tier), '
      'programs!inner(*), '
      'application_events(id, from_stage, to_stage, note, created_at), '
      'application_document_requests(id, application_id, kind, note, '
      'fulfilled_at, created_at)';

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final id = _service.userId;
      if (id == null) return;

      final rows = await _service.client
          .from('applications')
          .select(_selectWithJoins)
          .eq('profile_id', id)
          .order('updated_at', ascending: false);

      _applications = (rows as List)
          .map((r) => Application.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Application?> fetchOne(String id) async {
    try {
      final row = await _service.client
          .from('applications')
          .select(_selectWithJoins)
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Application.fromMap(row);
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return null;
    }
  }

  /// Starts an application. Created as a draft so a student can attach
  /// documents and reread the requirements before committing.
  Future<String?> start({
    required String institutionId,
    required String programId,
    String? intake,
    String? note,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _service.client
          .from('applications')
          .insert({
            'profile_id': _service.userId,
            'institution_id': institutionId,
            'program_id': programId,
            'intake': intake,
            'stage': 'draft',
            'student_note': note,
          })
          .select('id')
          .single();

      await load();
      return row['id'] as String;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Moves an application to a new stage.
  ///
  /// Which stages a student may set is enforced server-side by
  /// `guard_application_stage()`, and it raises a readable message, so a
  /// refusal here surfaces as-is rather than being second-guessed client-side.
  Future<bool> setStage(Application application, String stage) async {
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await _service.client
          .from('applications')
          .update({'stage': stage})
          .eq('id', application.id);
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

  Future<bool> submit(Application application) =>
      setStage(application, 'submitted');

  Future<bool> acceptOffer(Application application) =>
      setStage(application, 'accepted');

  Future<bool> withdraw(Application application) =>
      setStage(application, 'withdrawn');

  Future<bool> updateNote(Application application, String note) async {
    _error = null;
    try {
      await _service.client
          .from('applications')
          .update({'student_note': note})
          .eq('id', application.id);
      await load();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Attaches a passport document to an application.
  ///
  /// A reference, not a copy: a transcript is uploaded once and attached to as
  /// many applications as needed.
  Future<bool> attachDocument({
    required String applicationId,
    required String documentId,
  }) async {
    _error = null;
    try {
      await _service.client.from('application_documents').insert({
        'application_id': applicationId,
        'document_id': documentId,
      });
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  Future<List<String>> attachedDocumentIds(String applicationId) async {
    try {
      final rows = await _service.client
          .from('application_documents')
          .select('document_id')
          .eq('application_id', applicationId);
      return (rows as List).map((r) => r['document_id'] as String).toList();
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return [];
    }
  }

  Future<bool> detachDocument({
    required String applicationId,
    required String documentId,
  }) async {
    _error = null;
    try {
      await _service.client
          .from('application_documents')
          .delete()
          .eq('application_id', applicationId)
          .eq('document_id', documentId);
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      notifyListeners();
      return false;
    }
  }

  /// Answers an institution's document request with one of the student's
  /// passport documents.
  ///
  /// One call to `fulfil_document_request`, which attaches the document to the
  /// application, marks the request sent and tells the institution — together,
  /// so a request can never read "sent" with nothing attached.
  Future<bool> fulfilRequest(DocumentRequest request, String documentId) async {
    _error = null;
    try {
      await _service.client.rpc('fulfil_document_request', params: {
        'p_request_id': request.id,
        'p_document_id': documentId,
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
