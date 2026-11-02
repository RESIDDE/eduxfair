import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/discover/models/institution.dart';
import 'package:lekkside_connect/features/institution/providers/institution_provider.dart';
import 'package:lekkside_connect/features/institution/screens/org_spaces_screen.dart';
import 'package:lekkside_connect/features/meet/models/space.dart';
import 'package:lekkside_connect/features/meet/providers/spaces_provider.dart';

class FakeSpaces extends SpacesProvider {
  final List<Space> _rows;
  FakeSpaces(this._rows);
  @override
  List<Space> get spaces => _rows;
  @override
  List<Space> get live => _rows.where((s) => s.isLive).toList();
  @override
  List<Space> get upcoming => _rows.where((s) => s.isScheduled).toList();
  @override
  List<Space> get past => _rows.where((s) => s.isOver).toList();
  @override
  bool get loading => false;
  @override
  void subscribe({String? institutionId}) {}
  @override
  void unsubscribe() {}
  @override
  Future<void> load({String? institutionId}) async {}
}

class FakeInstitution extends InstitutionProvider {
  @override
  Institution? get institution => const Institution(
        id: '5ed99fe6',
        name: 'Maplecrest',
        slug: 'maplecrest',
        country: 'CA',
        kind: 'university',
      );
}

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

  testWidgets('a live space renders its card on Live & Upcoming', (tester) async {
    final live = Space(
      id: 'abd69dd7',
      institutionId: '5ed99fe6',
      hostProfileId: 'h1',
      title: 'As',
      status: 'live',
      scheduledFor: DateTime.now(),
      durationMin: 45,
    );
    final ended = Space(
      id: 'cf71145b',
      institutionId: '5ed99fe6',
      hostProfileId: 'h1',
      title: 'Help',
      status: 'ended',
      scheduledFor: DateTime.now().subtract(const Duration(days: 3)),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SpacesProvider>(
              create: (_) => FakeSpaces([live, ended])),
          ChangeNotifierProvider<InstitutionProvider>(
              create: (_) => FakeInstitution()),
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const OrgSpacesScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The regression: the theme's outlined button is full-width, a Row lays
    // its children out unbounded, and the resulting infinite-width constraint
    // threw during layout — so the live card rendered as nothing at all while
    // the tab still showed its LIVE badge.
    expect(find.text('As'), findsOneWidget);
    expect(find.text('Join room'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
  });
}
