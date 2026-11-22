// The legal pages open for everyone, from everywhere, without a red screen.
//
// The bug this guards: the policies sat in the router's set of "open" auth
// routes, and a signed-in person on an auth route is redirected to /feed. So a
// signed-in student tapping Terms in Profile had their `push` redirected to
// /feed — a second copy of the tab shell's page on the root Navigator, which
// trips `!keyReservation.contains(key)`. Staff hit the same thing through the
// redirect to /org. Every legal route, and the safety routes Profile links to,
// is pushed here for each kind of account.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/app.dart';
import 'package:lekkside_connect/core/constants/app_constants.dart';
import 'package:lekkside_connect/core/theme/theme_provider.dart';
import 'package:lekkside_connect/features/applications/providers/applications_provider.dart';
import 'package:lekkside_connect/features/auth/models/app_user.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/discover/providers/discover_provider.dart';
import 'package:lekkside_connect/features/fairs/providers/fairs_provider.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/institution/providers/org_desk_provider.dart';
import 'package:lekkside_connect/features/legal/screens/legal_document_screen.dart';
import 'package:lekkside_connect/features/matches/providers/matches_provider.dart';
import 'package:lekkside_connect/features/meet/providers/meet_provider.dart';
import 'package:lekkside_connect/features/meet/providers/spaces_provider.dart';
import 'package:lekkside_connect/features/messages/providers/messages_provider.dart';
import 'package:lekkside_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';

/// An [AuthProvider] whose session is whatever the test says it is.
class _FakeAuth extends AuthProvider {
  final AppUser? _fakeUser;
  _FakeAuth(this._fakeUser);

  @override
  AuthStatus get status =>
      _fakeUser == null ? AuthStatus.signedOut : AuthStatus.signedIn;
  @override
  bool get isSignedIn => _fakeUser != null;
  @override
  AppUser? get user => _fakeUser;
  @override
  String? get email => _fakeUser == null ? null : 'someone@example.com';
}

/// Staff whose institution has loaded, so the router sends them to /org.
class _FakeInstitutions extends InstitutionProvider {
  @override
  bool get isResolved => true;
  @override
  bool get needsSetup => false;
}

AppUser _user(String role, {bool verified = true}) => AppUser(
      id: 'u',
      role: role,
      fullName: 'Someone',
      isEmailVerified: verified,
      createdAt: DateTime(2026),
    );

Widget _app(AppUser? user) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(autoLoad: false)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth(user)),
        ChangeNotifierProvider(create: (_) => PassportProvider()),
        ChangeNotifierProvider(create: (_) => DiscoverProvider()),
        ChangeNotifierProvider(create: (_) => MatchesProvider()),
        ChangeNotifierProvider(create: (_) => MeetProvider()),
        ChangeNotifierProvider(create: (_) => SpacesProvider()),
        ChangeNotifierProvider(create: (_) => MessagesProvider()),
        ChangeNotifierProvider(create: (_) => ApplicationsProvider()),
        ChangeNotifierProvider(create: (_) => FairsProvider()),
        ChangeNotifierProvider<InstitutionProvider>(
            create: (_) => _FakeInstitutions()),
        ChangeNotifierProvider(create: (_) => OrgDeskProvider()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
      ],
      child: const EduxfairApp(),
    );

GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(Navigator).first));

const _legal = {
  AppConstants.routeTerms: 'Terms of Service',
  AppConstants.routePrivacy: 'Privacy Policy',
  AppConstants.routeGuidelines: 'Community Guidelines',
};

/// Drains every frame and timer the screens start, swallowing nothing.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Boots as [user], moves to [from], then pushes each legal page from there
/// and comes back — the path a real tap takes.
Future<void> _pushEachFrom(
  WidgetTester tester, {
  required AppUser? user,
  required String from,
}) async {
  await tester.pumpWidget(_app(user));
  await tester.pump(const Duration(seconds: 2)); // splash decides
  await _settle(tester);

  _router(tester).go(from);
  await _settle(tester);
  expect(tester.takeException(), isNull, reason: 'landing on $from');

  for (final entry in _legal.entries) {
    _router(tester).push(entry.key);
    await _settle(tester);

    expect(tester.takeException(), isNull,
        reason: '${entry.key} pushed from $from');
    expect(find.byType(LegalDocumentScreen), findsOneWidget,
        reason: '${entry.key} should be on screen, not redirected away');
    expect(find.text(entry.value), findsWidgets);

    _router(tester).pop();
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: 'back from ${entry.key}');
    expect(find.byType(LegalDocumentScreen), findsNothing);
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  testWidgets('signed out, from the sign-up form', (tester) async {
    await _pushEachFrom(tester, user: null, from: AppConstants.routeRegister);
  });

  testWidgets('signed-in student, from Profile', (tester) async {
    await _pushEachFrom(tester,
        user: _user('student'), from: AppConstants.routeProfile);
  });

  testWidgets('signed-in staff, from Profile', (tester) async {
    await _pushEachFrom(tester,
        user: _user('institution_member'), from: AppConstants.routeProfile);
  });

  testWidgets('unverified account held at /otp can still read them',
      (tester) async {
    await _pushEachFrom(tester,
        user: _user('student', verified: false), from: AppConstants.routeOtp);
  });

  testWidgets('the sign-up checkbox links open the right page', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    _router(tester).go(AppConstants.routeRegister);
    await _settle(tester);

    for (final title in _legal.values) {
      // The links are spans inside one Text.rich; tap the span by its text.
      final rich = find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().contains('I agree to the'));
      await tester.ensureVisible(rich);
      await _settle(tester);
      await tester.tapOnText(find.textRange.ofSubstring(title));
      await _settle(tester);

      expect(tester.takeException(), isNull, reason: 'tapping "$title"');
      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.text(title), findsWidgets);

      _router(tester).pop();
      await _settle(tester);
    }
  });

  testWidgets('staff can open Blocked accounts and Delete account from Profile',
      (tester) async {
    await tester.pumpWidget(_app(_user('institution_member')));
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    _router(tester).go(AppConstants.routeProfile);
    await _settle(tester);

    for (final route in [
      AppConstants.routeBlocked,
      AppConstants.routeDeleteAccount,
    ]) {
      _router(tester).push(route);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: route);
      expect(_router(tester).state.matchedLocation, route,
          reason: 'staff were being bounced to /org');
      _router(tester).pop();
      await _settle(tester);
    }
  });
}
