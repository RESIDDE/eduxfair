// Where a signed-in person lands, and why it has to be one rule.
//
// The bug this guards: the splash sent everyone to /home, which resolves to
// /feed inside the STUDENT shell. An institution account painted a frame of
// the student feed on every cold start before the router moved it to /org.

import 'package:flutter_test/flutter_test.dart';
import 'package:lekkside_connect/core/constants/app_constants.dart';
import 'package:lekkside_connect/features/auth/models/app_user.dart';

AppUser _user(String role, {bool isEmailVerified = true}) => AppUser(
      id: 'u',
      role: role,
      fullName: 'Someone',
      isEmailVerified: isEmailVerified,
      createdAt: DateTime(2026),
    );

void main() {
  group('landingRouteFor', () {
    test('unverified users are routed to /otp', () {
      expect(
        landingRouteFor(_user('student', isEmailVerified: false)),
        AppConstants.routeOtp,
      );
      expect(
        landingRouteFor(_user('institution_member', isEmailVerified: false)),
        AppConstants.routeOtp,
      );
    });

    test('a verified student lands in the student shell', () {
      expect(landingRouteFor(_user('student')), AppConstants.routeHome);
    });

    test('verified institution staff land in the org shell, never via /feed', () {
      expect(landingRouteFor(_user('institution_member')),
          AppConstants.routeOrgHome);
    });

    // Neither has a shell of its own, and the router's `!isStudent` test puts
    // them in /org — so this must agree or the two disagree on arrival.
    test('educators and admins follow staff', () {
      expect(landingRouteFor(_user('educator')), AppConstants.routeOrgHome);
      expect(landingRouteFor(_user('admin')), AppConstants.routeOrgHome);
    });

    test('no profile falls back to the student side', () {
      // The one branch that must not throw: AuthProvider gives up after three
      // attempts and leaves `user` null while still signed in.
      expect(landingRouteFor(null), AppConstants.routeHome);
    });
  });

  group('AppUser.isStaff', () {
    test('is the exact complement of isStudent', () {
      for (final role in ['student', 'institution_member', 'educator', 'admin']) {
        final user = _user(role);
        expect(user.isStaff, !user.isStudent, reason: role);
      }
    });
  });
}
