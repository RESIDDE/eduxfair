// The app actually starts, and the theme actually follows the phone.
//
// Nothing pumped the real `EduxfairApp` before this, so the provider list, the
// router built in initState and the system-overlay wrapper were all unverified
// by the suite — a missing provider is a runtime crash on launch, not an
// analyzer error.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/app.dart';
import 'package:lekkside_connect/core/theme/theme_provider.dart';
import 'package:lekkside_connect/features/applications/providers/applications_provider.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/discover/providers/discover_provider.dart';
import 'package:lekkside_connect/features/fairs/providers/fairs_provider.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/institution/providers/org_desk_provider.dart';
import 'package:lekkside_connect/features/matches/providers/matches_provider.dart';
import 'package:lekkside_connect/features/meet/providers/meet_provider.dart';
import 'package:lekkside_connect/features/meet/providers/spaces_provider.dart';
import 'package:lekkside_connect/features/messages/providers/messages_provider.dart';
import 'package:lekkside_connect/features/notifications/providers/notifications_provider.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';

/// The same provider list `main.dart` installs. If one is missing here the
/// test fails the same way the app would.
Widget app() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(autoLoad: false)),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PassportProvider()),
        ChangeNotifierProvider(create: (_) => DiscoverProvider()),
        ChangeNotifierProvider(create: (_) => MatchesProvider()),
        ChangeNotifierProvider(create: (_) => MeetProvider()),
        ChangeNotifierProvider(create: (_) => SpacesProvider()),
        ChangeNotifierProvider(create: (_) => MessagesProvider()),
        ChangeNotifierProvider(create: (_) => ApplicationsProvider()),
        ChangeNotifierProvider(create: (_) => FairsProvider()),
        ChangeNotifierProvider(create: (_) => InstitutionProvider()),
        ChangeNotifierProvider(create: (_) => OrgDeskProvider()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
      ],
      child: const EduxfairApp(),
    );

/// Pumps the app with the platform reporting [brightness].
Future<void> boot(WidgetTester tester, Brightness brightness) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  await tester.pumpWidget(app());
  // The splash deliberately waits before deciding where to send anyone.
  await tester.pump(const Duration(seconds: 2));
}

ThemeData themeOf(WidgetTester tester) => Theme.of(
      tester.element(find.byType(Scaffold).first),
    );

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

  testWidgets('it boots without throwing', (tester) async {
    await boot(tester, Brightness.light);
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  group('the theme follows the phone', () {
    testWidgets('a light phone gets the light canvas', (tester) async {
      await boot(tester, Brightness.light);
      expect(themeOf(tester).brightness, Brightness.light);
      expect(themeOf(tester).scaffoldBackgroundColor,
          const Color(0xFFFFFFFF));
    });

    testWidgets('a dark phone gets the black one', (tester) async {
      await boot(tester, Brightness.dark);
      expect(themeOf(tester).brightness, Brightness.dark);
      expect(themeOf(tester).scaffoldBackgroundColor,
          const Color(0xFF000000));
    });

    testWidgets('and the app was previously pinned to dark, so this is the '
        'regression that matters', (tester) async {
      await boot(tester, Brightness.light);
      expect(themeOf(tester).brightness, isNot(Brightness.dark));
    });
  });

  group('the override beats the phone', () {
    testWidgets('choosing Dark on a light phone darkens the app',
        (tester) async {
      await boot(tester, Brightness.light);
      final context = tester.element(find.byType(MaterialApp));
      await context.read<ThemeProvider>().set(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(themeOf(tester).brightness, Brightness.dark);
    });

    testWidgets('choosing Light on a dark phone lightens it', (tester) async {
      await boot(tester, Brightness.dark);
      final context = tester.element(find.byType(MaterialApp));
      await context.read<ThemeProvider>().set(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(themeOf(tester).brightness, Brightness.light);
    });
  });

  group('ThemeProvider persistence', () {
    test('defaults to following the system', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider(autoLoad: false);
      await provider.load();
      expect(provider.mode, ThemeMode.system);
      expect(provider.label, 'System');
    });

    test('a stored choice survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeProvider(autoLoad: false).set(ThemeMode.dark);

      final next = ThemeProvider(autoLoad: false);
      await next.load();
      expect(next.mode, ThemeMode.dark);
      expect(next.label, 'Dark');
    });

    test('an unrecognised stored value falls back to system rather than '
        'failing to start', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'chartreuse'});
      final provider = ThemeProvider(autoLoad: false);
      await provider.load();
      expect(provider.mode, ThemeMode.system);
    });
  });
}
