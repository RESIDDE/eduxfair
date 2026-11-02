import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/social/providers/feed_provider.dart';
import 'package:lekkside_connect/features/social/screens/composer_screen.dart';

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

  testWidgets('ComposerScreen builds without error for student', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PassportProvider()),
          ChangeNotifierProvider(create: (_) => InstitutionProvider()),
          ChangeNotifierProvider(create: (_) => FeedProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const ComposerScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(ComposerScreen), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
  });
}
