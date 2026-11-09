import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_service.dart';
import '../models/app_user.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Owns the session and the signed-in person's profile row.
///
/// `supabase_flutter` already persists and refreshes the session, so this does
/// not store tokens. It listens to auth changes, keeps the matching `profiles`
/// row loaded, and exposes the operations the auth screens need.
class AuthProvider extends ChangeNotifier {
  final _service = SupabaseService.instance;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  AppUser? get user => _user;

  /// The signed-in address, for the one place that needs it: prefilling the
  /// email domain an institution is about to verify.
  String? get email => _service.userEmail;
  bool get busy => _busy;
  String? get error => _error;
  bool get isSignedIn => _status == AuthStatus.signedIn;

  AuthProvider() {
    _service.authChanges.listen(_onAuthChange);
    // Cover the case where a session was already restored before this provider
    // was constructed, which is the normal cold-start path.
    if (_service.isSignedIn) {
      _loadProfile();
    } else {
      _status = AuthStatus.signedOut;
    }
  }

  void _onAuthChange(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        _loadProfile();
      case AuthChangeEvent.signedOut:
        _user = null;
        _status = AuthStatus.signedOut;
        notifyListeners();
      default:
        break;
    }
  }

  /// Loads the `profiles` row for the current session.
  ///
  /// The row is created by the `on_auth_user_created` trigger, but a client can
  /// occasionally read before that commit is visible, so this retries briefly
  /// rather than dropping the user on an empty profile.
  Future<void> _loadProfile() async {
    final id = _service.userId;
    if (id == null) {
      _status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final row = await _service.client
            .from('profiles')
            .select()
            .eq('id', id)
            .maybeSingle();

        if (row != null) {
          _user = AppUser.fromMap(row);
          _status = AuthStatus.signedIn;
          notifyListeners();
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('profile load failed: $e');
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }

    // Signed in but no profile: treat as signed in so the app is usable, and
    // let the profile screen prompt for a name.
    _status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      _error = SupabaseService.describeError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ── Operations ────────────────────────────────────────────────────────────

  /// Creates an account in one of the two roles sign-up offers.
  ///
  /// [role] is read by `handle_new_user()`, which clamps anything it does not
  /// recognise to 'student' — so a client cannot talk its way into 'admin'.
  /// 'institution_member' *is* self-assignable by design: that is how an
  /// institution onboards itself. What it grants is the ability to create a
  /// listing, not any claim about the institution being real; the verified
  /// badge comes later, from domain verification.
  /// Creates an account via the custom backend edge function, bypassing Supabase's
  /// mailer rate limits, establishes the session, and dispatches a 6-digit OTP via Resend.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    String? country,
    String role = 'student',
    DateTime? dateOfBirth,
  }) =>
      _run(() async {
        assert(
          role == 'student' || role == 'institution_member',
          'signUp only offers the two roles the signup fork offers',
        );

        final res = await _service.invoke('send-auth-email', body: {
          'action': 'signup',
          'email': email.trim(),
          'password': password,
          'fullName': fullName.trim(),
          if (country != null) 'country': country,
          // Date only, no time: this is an age check, not an event.
          if (dateOfBirth != null)
            'dateOfBirth': dateOfBirth.toIso8601String().split('T').first,
          'role': role,
        });

        if (res['ok'] != true) {
          throw StateError(
            res['error'] as String? ?? 'Could not create your account.',
          );
        }

        // Establish session without triggering Supabase mailer
        await _service.client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
      });

  Future<bool> signIn({required String email, required String password}) =>
      _run(() async {
        await _service.client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        await _loadProfile();
      });

  /// Dispatches a custom 6-digit verification code to [email] via Resend.
  Future<bool> sendCustomOtp(String email) => _run(() async {
        final res = await _service.invoke('send-auth-email', body: {
          'action': 'send',
          'email': email.trim(),
          'actionType': 'signup',
        });
        if (res['ok'] != true) {
          throw StateError(
            res['error'] as String? ?? 'Could not send verification code.',
          );
        }
      });

  /// Verifies the entered 6-digit code against the custom OTP storage.
  /// On success, marks the profile verified and refreshes session state.
  Future<bool> verifyCustomOtp({
    required String email,
    required String code,
  }) =>
      _run(() async {
        final res = await _service.client.rpc(
          'verify_account_otp',
          params: {
            'p_email': email.trim(),
            'p_code': code.trim(),
          },
        );

        if (res is Map && res['ok'] == true) {
          await _loadProfile();
          if (_user != null) {
            _user = _user!.copyWith(isEmailVerified: true);
            notifyListeners();
          }
          return;
        }

        final errorMsg = (res is Map ? res['error'] as String? : null) ??
            'Invalid verification code.';
        throw StateError(errorMsg);
      });

  /// Backward-compatible aliases delegating to the custom OTP flow.
  Future<bool> sendEmailOtp(String email) => sendCustomOtp(email);

  Future<bool> verifyEmailOtp({required String email, required String token}) =>
      verifyCustomOtp(email: email, code: token);

  /// Dispatches a 6-digit password reset code to [email] via Resend.
  Future<bool> sendPasswordReset(String email) => _run(() async {
        final res = await _service.invoke('send-auth-email', body: {
          'action': 'send_recovery_otp',
          'email': email.trim(),
        });
        if (res['ok'] != true) {
          throw StateError(
            res['error'] as String? ?? 'Could not send password reset code.',
          );
        }
      });

  /// Verifies the 6-digit password reset code and sets a new password.
  Future<bool> resetPasswordWithOtp({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _run(() async {
        final res = await _service.invoke('send-auth-email', body: {
          'action': 'reset_password',
          'email': email.trim(),
          'code': code.trim(),
          'newPassword': newPassword,
        });
        if (res['ok'] != true) {
          throw StateError(
            res['error'] as String? ?? 'Could not reset password.',
          );
        }
      });

  Future<bool> updatePassword(String password) => _run(() async {
        await _service.client.auth.updateUser(UserAttributes(password: password));
      });

  Future<bool> updateProfile({
    String? fullName,
    String? phone,
    String? country,
    String? avatarUrl,
    bool clearAvatar = false,
  }) =>
      _run(() async {
        final id = _service.userId;
        if (id == null) throw StateError('not signed in');

        final patch = <String, dynamic>{
          if (fullName != null) 'full_name': fullName.trim(),
          if (phone != null) 'phone': phone.trim(),
          if (country != null) 'country': country,
          if (clearAvatar) 'avatar_url': null else if (avatarUrl != null) 'avatar_url': avatarUrl,
        };
        if (patch.isEmpty) return;

        await _service.client.from('profiles').update(patch).eq('id', id);
        _user = _user?.copyWith(
          fullName: fullName ?? _user?.fullName,
          phone: phone,
          country: country,
          avatarUrl: avatarUrl,
          clearAvatar: clearAvatar,
        );
      });

  Future<bool> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final id = _service.userId;
    if (id == null) throw StateError('not signed in');

    return _run(() async {
      final path = _service.avatarPath(fileName);
      await _service.uploadBytes(
        bucket: 'avatars',
        path: path,
        bytes: bytes,
        contentType: mimeType ?? 'image/jpeg',
        upsert: true,
      );
      final url = _service.publicUrl(bucket: 'avatars', path: path);
      await updateProfile(avatarUrl: url);
    });
  }

  Future<bool> removeAvatar() => updateProfile(clearAvatar: true);

  Future<void> signOut() async {
    await _service.client.auth.signOut();
    _user = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
