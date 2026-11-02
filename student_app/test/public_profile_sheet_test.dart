import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/screens/handle_sheet.dart';

/// The sheet grew a bio field and the save button went under the edge of the
/// screen, where nothing could reach it. A Column that overflows does not
/// scroll — it clips — so this pins the sheet at a real phone height and
/// insists the button is both present and hittable.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  testWidgets('the save button is reachable on a phone-sized screen',
      (tester) async {
    // A small handset, which is where a clipped sheet shows up first.
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PassportProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => openClaimHandleSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Titled "Choose your handle" for an account with none yet, and "Your
    // public profile" once it has one. Either way the bio and the button below
    // it are what this is about.
    expect(find.byType(TextFormField), findsNWidgets(2));

    final save = find.text('Save profile');
    expect(save, findsOneWidget, reason: 'the save button must exist');

    // The real assertion: not merely in the tree, but on screen and tappable.
    expect(save.hitTestable(), findsOneWidget,
        reason: 'the save button must be reachable, not clipped off the sheet');

    // And both fields above it are on screen, not just in the tree.
    expect(find.byType(TextFormField).hitTestable(), findsNWidgets(2),
        reason: 'the handle and bio fields must both be reachable');
  });
}
