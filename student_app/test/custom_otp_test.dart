import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/core/constants/app_constants.dart';
import 'package:lekkside_connect/features/auth/models/app_user.dart';

void main() {
  group('Custom OTP configuration & constants', () {
    test('OTP length is standard 6 digits', () {
      expect(AppConstants.otpLength, 6);
    });
  });

  group('AppUser email verification state', () {
    test('defaults isEmailVerified to false if not set in map', () {
      final user = AppUser.fromMap({
        'id': 'u1',
        'role': 'student',
        'full_name': 'Jane Doe',
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(user.isEmailVerified, isFalse);
    });

    test('parses email_verified: true from profiles map', () {
      final user = AppUser.fromMap({
        'id': 'u2',
        'role': 'institution_member',
        'full_name': 'Oxford Admissions',
        'email_verified': true,
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(user.isEmailVerified, isTrue);
    });

    test('copyWith preserves or updates isEmailVerified', () {
      final user = AppUser(
        id: 'u3',
        role: 'student',
        fullName: 'Jane Doe',
        isEmailVerified: false,
        createdAt: DateTime(2026),
      );
      expect(user.isEmailVerified, isFalse);

      final verified = user.copyWith(isEmailVerified: true);
      expect(verified.isEmailVerified, isTrue);
      expect(verified.id, user.id);
      expect(verified.fullName, user.fullName);
    });
  });

  group('Custom OTP route guards', () {
    test('unverified students and staff must land on /otp', () {
      final student = AppUser(
        id: 'u4',
        role: 'student',
        fullName: 'Student Doe',
        isEmailVerified: false,
        createdAt: DateTime(2026),
      );
      expect(landingRouteFor(student), AppConstants.routeOtp);

      final staff = AppUser(
        id: 'u5',
        role: 'institution_member',
        fullName: 'Staff Member',
        isEmailVerified: false,
        createdAt: DateTime(2026),
      );
      expect(landingRouteFor(staff), AppConstants.routeOtp);
    });

    test('verified students land on /home and verified staff land on /org', () {
      final student = AppUser(
        id: 'u6',
        role: 'student',
        fullName: 'Student Doe',
        isEmailVerified: true,
        createdAt: DateTime(2026),
      );
      expect(landingRouteFor(student), AppConstants.routeHome);

      final staff = AppUser(
        id: 'u7',
        role: 'institution_member',
        fullName: 'Staff Member',
        isEmailVerified: true,
        createdAt: DateTime(2026),
      );
      expect(landingRouteFor(staff), AppConstants.routeOrgHome);
    });
  });
}
