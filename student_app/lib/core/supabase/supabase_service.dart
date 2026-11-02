import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// Thin wrapper over the Supabase client.
///
/// Deliberately much smaller than consult_client's `ApiClient`: that one had to
/// manage a JWT in SharedPreferences and hand-roll request plumbing, whereas
/// `supabase_flutter` already persists and refreshes the session. So this exists
/// only to centralise three things — the current user, upload paths, and a
/// uniform way of turning Postgres errors into messages worth showing someone.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get client => Supabase.instance.client;

  // ── Session ───────────────────────────────────────────────────────────────

  User? get currentUser => client.auth.currentUser;
  String? get userId => currentUser?.id;

  /// The address the account signs in with. Lives on the auth session, not on
  /// `profiles`, which is why [AppUser] does not carry it.
  String? get userEmail => currentUser?.email;
  bool get isSignedIn => currentUser != null;

  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;

  // ── Storage paths ─────────────────────────────────────────────────────────
  //
  // The storage policies authorize on the FIRST path segment, and
  // `passport_documents.storage_path` has a CHECK constraint requiring the
  // owner's uuid there. Build every path through these so a policy violation
  // can never be a typo.

  String passportDocPath(String fileName) {
    final id = userId;
    if (id == null) throw StateError('not signed in');
    // Prefixed with a timestamp so re-uploading the same filename does not
    // collide, and the bucket stays browsable in upload order.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '$id/$stamp-${_sanitize(fileName)}';
  }

  String avatarPath(String fileName) {
    final id = userId;
    if (id == null) throw StateError('not signed in');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '$id/$stamp-${_sanitize(fileName)}';
  }

  String institutionLogoPath(String institutionId, String fileName) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '$institutionId/$stamp-${_sanitize(fileName)}';
  }

  String messageAttachmentPath(String conversationId, String fileName) {
    // Keyed on the conversation, not the uploader: both parties need to read it.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '$conversationId/$stamp-${_sanitize(fileName)}';
  }

  static String _sanitize(String fileName) =>
      fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  // ── Uploads ───────────────────────────────────────────────────────────────

  /// Uploads bytes and returns the stored path.
  ///
  /// Bytes rather than a `File` because this app also ships to web, where
  /// `file_picker` and `image_picker` give no filesystem path at all. Taking
  /// `Uint8List` is the one signature that works on all three platforms.
  Future<String> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String? contentType,
    bool upsert = false,
  }) async {
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: upsert),
        );
    return path;
  }

  /// A time-limited URL for a private object. Private buckets have no public
  /// URL at all, so documents must always be read through one of these.
  Future<String> signedUrl({
    required String bucket,
    required String path,
    Duration expiresIn = const Duration(hours: 1),
  }) =>
      client.storage.from(bucket).createSignedUrl(path, expiresIn.inSeconds);

  String publicUrl({required String bucket, required String path}) =>
      client.storage.from(bucket).getPublicUrl(path);

  Future<void> removeObject({required String bucket, required String path}) =>
      client.storage.from(bucket).remove([path]);

  // ── Edge Functions ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> invoke(
    String name, {
    Map<String, dynamic>? body,
  }) async {
    final res = await client.functions.invoke(name, body: body ?? const {});
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  // ── Errors ────────────────────────────────────────────────────────────────

  /// Turns a Supabase/Postgres error into something worth putting in front of a
  /// person.
  ///
  /// RLS denials arrive as bare "new row violates row-level security policy",
  /// which tells a student nothing. The guard triggers in the schema raise
  /// deliberately readable messages, so those are passed through as-is.
  static String describeError(Object error) {
    if (error is AuthException) {
      final msg = error.message;
      if (msg.contains('Invalid login credentials')) {
        return 'That email and password do not match.';
      }
      if (msg.contains('Email not confirmed')) {
        return 'Please confirm your email address first.';
      }
      if (msg.contains('User already registered')) {
        return 'An account with that email already exists.';
      }
      return msg;
    }

    if (error is PostgrestException) {
      // P0001 is raise_exception: our own guards, already written for humans.
      if (error.code == 'P0001') return error.message;

      switch (error.code) {
        case '23505': // unique_violation (and 23505 covers our partial indexes)
        case '23514': // check_violation
          return _friendlyConstraint(error.message);
        case '42501': // insufficient_privilege / RLS denial
          return 'You do not have access to that.';
        case 'PGRST116':
          return 'That record could not be found.';
      }

      if (error.message.contains('row-level security')) {
        return 'You do not have access to that.';
      }
      return error.message;
    }

    if (error is StorageException) {
      if (error.message.contains('exceeded the maximum allowed size')) {
        return 'That file is too large. The limit is 20 MB.';
      }
      if (error.message.contains('mime type')) {
        return 'That file type is not accepted. Use a PDF, JPG or PNG.';
      }
      return error.message;
    }

    if (error is FunctionException) {
      final details = error.details;
      if (details is Map) {
        final serverMsg = details['error'] ?? details['message'] ?? details['msg'];
        if (serverMsg is String && serverMsg.trim().isNotEmpty) {
          return serverMsg.trim();
        }
      } else if (details is String && details.trim().isNotEmpty) {
        return details.trim();
      }

      if (error.status == 429) {
        return 'Too many join attempts. Please wait a minute and try again.';
      }
      if (error.status == 403) {
        return 'You do not have access to this room.';
      }
      if (error.status == 503) {
        return 'Live video service is temporarily unavailable. Please try again shortly.';
      }
      if (error.reasonPhrase != null && error.reasonPhrase!.isNotEmpty) {
        return error.reasonPhrase!;
      }
    }

    final errStr = error.toString();
    if (errStr.contains('SocketException') ||
        errStr.contains('Failed host lookup') ||
        errStr.contains('Network is unreachable') ||
        errStr.contains('Connection refused')) {
      return 'Network connection error. Please check your internet connection.';
    }
    if (errStr.contains('LiveKit') || errStr.contains('livekit')) {
      return 'Could not connect to live video server. Please try again.';
    }

    if (kDebugMode) debugPrint('Unhandled error: $error');
    return 'Something went wrong. Please try again.';
  }

  static String _friendlyConstraint(String message) {
    if (message.contains('applications_one_live')) {
      return 'You already have an open application for this program.';
    }
    if (message.contains('passport_shares_one_live')) {
      return 'You have already shared your passport with this institution.';
    }
    if (message.contains('conversations_student_id_institution_id_key')) {
      return 'You already have a conversation with this institution.';
    }
    if (message.contains('fair_registrations')) {
      return 'You are already registered for this fair.';
    }
    if (message.contains('passport_grade_needs_scheme')) {
      return 'Please choose which grading scheme your grade is in.';
    }
    if (message.contains('passport_budget_order')) {
      return 'Your minimum budget cannot be higher than your maximum.';
    }
    return 'That value is not valid.';
  }
}
