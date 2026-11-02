import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/theme_provider.dart';
import 'features/applications/providers/applications_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/discover/providers/discover_provider.dart';
import 'features/fairs/providers/fairs_provider.dart';
import 'features/institution/providers/institution_provider.dart';
import 'features/institution/providers/org_desk_provider.dart';
import 'features/matches/providers/matches_provider.dart';
import 'features/meet/providers/meet_provider.dart';
import 'features/meet/providers/spaces_provider.dart';
import 'features/messages/providers/messages_provider.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/passport/providers/passport_provider.dart';
import 'features/social/providers/feed_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  if (!AppConstants.isConfigured) {
    // Failing here with a clear message beats a stack trace from deep inside
    // the Supabase client on the first query.
    runApp(const _ConfigurationError());
    return;
  }

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    // `publishableKey` replaces the deprecated `anonKey`; it is the same value
    // from the project API settings and is safe in a client, since RLS is what
    // protects the data.
    publishableKey: AppConstants.supabaseAnonKey,
  );

  // Portrait only. The passport wizard and document lists are built for a
  // single column; landscape would need its own layout and does not earn one.
  //
  // The ONE exception is the call screen, which unlocks landscape itself and
  // restores this on the way out — a video grid in a single column wastes half
  // the glass.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
    ),
  );
}

/// Shown when .env is missing or empty, which is the most likely first-run
/// problem for anyone picking this repo up.
class _ConfigurationError extends StatelessWidget {
  const _ConfigurationError();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.settings_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Supabase is not configured',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add SUPABASE_URL and SUPABASE_ANON_KEY to '
                    'student_app/.env, then restart.\n\n'
                    'See .env.example for the template.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
