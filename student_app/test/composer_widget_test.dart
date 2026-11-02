// Drives the composer as a real widget, to reproduce a crash seen on device:
//
//   'package:flutter/src/widgets/framework.dart': Failed assertion:
//   line 6281 pos 12: '_dependents.isEmpty': is not true
//
// Every other suite here exercises providers, which is why this got through:
// the bug is in the widget lifecycle, not in a query. The composer is pushed
// the way the app pushes it — through go_router, onto a root navigator, inside
// the real provider tree — because the crash is about how it comes *off* that
// stack again.
//
//   cd devserver   && npm start
//   cd student_app && flutter test test/composer_widget_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';
import 'package:lekkside_connect/features/social/screens/composer_screen.dart';

const studentEmail = 'chidi.okeke@example.com';
const demoPassword = 'Lekkside123!';

Future<bool> devServerIsRunning(String url) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final request = await client.getUrl(Uri.parse('$url/health'));
    final response = await request.close();
    await response.drain<void>();
    client.close();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

Future<({String url, String key})?> localConfig() async {
  final file = File('.env.local');
  if (!file.existsSync()) return null;
  String url = '', key = '';
  for (final line in await file.readAsLines()) {
    if (line.startsWith('SUPABASE_URL=')) {
      url = line.substring('SUPABASE_URL='.length).trim();
    } else if (line.startsWith('SUPABASE_ANON_KEY=')) {
      key = line.substring('SUPABASE_ANON_KEY='.length).trim();
    }
  }
  if (key.isEmpty) return null;
  final host = Uri.tryParse(url)?.host;
  if (host != 'localhost' && host != '127.0.0.1') return null;
  return (url: url, key: key);
}

void main() {
  late bool available;
  var skipReason = 'dev server unavailable';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});

    final config = await localConfig();
    if (config == null) {
      available = false;
      skipReason = 'student_app/.env.local must point at the local dev server';
      return;
    }
    available = await devServerIsRunning(config.url);
    if (!available) {
      skipReason = 'no dev server — run `npm start` in devserver/';
      return;
    }

    await Supabase.initialize(
      url: config.url,
      publishableKey: config.key,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      debug: false,
    );

    // A fresh author with a handle. Reusing the seeded student would hit
    // post_rate_limit() once enough runs accumulate, and a rate-limited post
    // leaves the spinner turning — which looks exactly like the crash being
    // investigated.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final auth = AuthProvider();
    final created = await auth.signUp(
      email: 'composer.$stamp@example.com',
      password: demoPassword,
      fullName: 'Composer Test',
      role: 'student',
    );
    if (!created) {
      available = false;
      skipReason = 'could not create a test author: ${auth.error}';
      return;
    }
    for (var i = 0; i < 40 && auth.user == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final passport = PassportProvider();
    await passport.load();
    await passport.claimHandle('composer${stamp % 100000000}', 'Composer Test');
  });

  /// The composer inside the app's real shape: global providers, go_router,
  /// and a route underneath it so there is something to pop back to.
  Widget harness(GlobalKey<NavigatorState> rootKey) {
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Center(child: Text('feed'))),
        ),
        GoRoute(
          path: '/compose',
          parentNavigatorKey: rootKey,
          builder: (_, __) => const ComposerScreen(),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PassportProvider()),
        ChangeNotifierProvider(create: (_) => InstitutionProvider()),
        ChangeNotifierProvider(create: (_) => FeedProvider()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
      ),
    );
  }

  group('the composer', () {
    setUp(() {
      if (!available) markTestSkipped(skipReason);
    });

    // The networked variant of this — tap Post, wait for the round trip, watch
    // it close — is deliberately absent. Driving a real request from a widget
    // test leaves a Dart timer alive (the HTTP client's), and the binding's
    // end-of-test invariant fails on it regardless of how it is drained, with
    // no seam to stub the Supabase client behind. It would be a red test about
    // the harness rather than the app.
    //
    // What is covered instead: the route lifecycle below, which is where the
    // '_dependents.isEmpty' assertion actually fires, and the posting flow
    // itself at provider level in devserver_integration_test.dart.

    testWidgets('closing with the back button is clean too', (tester) async {
      if (!available) return;

      final rootKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(harness(rootKey));
      await tester.pumpAndSettle();

      rootKey.currentContext!.push('/compose');
      await tester.pumpAndSettle();
      expect(find.byType(ComposerScreen), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ComposerScreen), findsNothing);
    });
  });
}
