// University staff can follow any link without a red screen.
//
// The bug this guards: staff are kept out of student screens by a redirect,
// and that redirect sent them to their dashboard. For a `go` that is fine; for
// a `push` it put a second copy of the tab shell's page on the navigator — a
// duplicate page key, the red `keyReservation` screen. It bit when staff
// previewed their own page and tapped a programme. Programmes are now open to
// staff, and every other student-only link lands on an ordinary page instead.

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
import 'package:lekkside_connect/features/discover/screens/institution_screen.dart';
import 'package:lekkside_connect/features/discover/screens/program_screen.dart';
import 'package:lekkside_connect/features/institution/screens/org_students_only_screen.dart';
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


Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _bootStaff(WidgetTester tester) async {
  await tester.pumpWidget(_app(_user('institution_member')));
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
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

  testWidgets('staff preview their page and open a programme', (tester) async {
    await _bootStaff(tester);

    _router(tester).push('${AppConstants.routeInstitution}/inst-1');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(InstitutionScreen), findsOneWidget);

    _router(tester).push('${AppConstants.routeProgram}/prog-1');
    await _settle(tester);
    expect(tester.takeException(), isNull,
        reason: 'this was the red screen');
    expect(find.byType(ProgramScreen), findsOneWidget);

    _router(tester).pop();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(InstitutionScreen), findsOneWidget);
  });

  for (final route in [
    '${AppConstants.routeAppointmentRequest}?institution=inst-1',
    AppConstants.routeApplications,
    AppConstants.routePassport,
    AppConstants.routeSaved,
    AppConstants.routeMatches,
  ]) {
    testWidgets('a student-only link is a page, not a crash: $route',
        (tester) async {
      await _bootStaff(tester);
      _router(tester).push(route);
      await _settle(tester);

      expect(tester.takeException(), isNull, reason: route);
      expect(find.byType(OrgStudentsOnlyScreen), findsOneWidget);

      _router(tester).pop();
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(OrgStudentsOnlyScreen), findsNothing);
    });
  }

  testWidgets('a student still goes straight to a programme', (tester) async {
    await tester.pumpWidget(_app(_user('student')));
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    _router(tester).push('${AppConstants.routeProgram}/prog-1');
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(ProgramScreen), findsOneWidget);
  });
}
