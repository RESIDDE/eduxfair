// Renders the components to PNGs so they can actually be looked at.
//
// Every other test in this suite asserts about behaviour. None of them can see
// anything, and three bugs this project has shipped — a sign-in error rendered
// green, a logo stretched full-width, a post attributed to a blank handle —
// were invisible to all of them and obvious in a screenshot.
//
// Golden files are how a Flutter test produces pixels. These are written, not
// compared: run with `--update-goldens` and open `test/goldens/`.
//
// The filename deliberately does not end in `_test.dart`, so `flutter test`
// does not pick it up. Two reasons. A golden that must match byte-for-byte
// across machines and font versions is a maintenance tax that buys nothing
// here — the point is to look, not to diff. And `google_fonts` throws without
// a network, which would paint the whole suite red for a tool whose only job
// is to produce images.
//
//   flutter test test/visual_goldens.dart --update-goldens
//
// Fonts: widget tests have no network, so `google_fonts` cannot fetch Inter and
// text would render as placeholder boxes. The real Inter files cached by a
// previous device run are loaded instead, which is why these show actual
// letterforms and real line breaks.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/core/widgets/custom_button.dart';
import 'package:lekkside_connect/core/widgets/material_surface.dart';
import 'package:lekkside_connect/core/widgets/social_icons.dart';
import 'package:provider/provider.dart';

import 'package:lekkside_connect/features/auth/providers/auth_provider.dart';
import 'package:lekkside_connect/features/auth/screens/account_type_screen.dart';
import 'package:lekkside_connect/features/auth/screens/login_screen.dart';
import 'package:lekkside_connect/core/theme/theme_provider.dart';
import 'package:lekkside_connect/features/discover/models/institution.dart';
import 'package:lekkside_connect/features/passport/providers/passport_provider.dart';
import 'package:lekkside_connect/features/profile/screens/profile_screen.dart';
import 'package:lekkside_connect/features/discover/widgets/institution_tile.dart';
import 'package:lekkside_connect/features/social/models/post.dart';
import 'package:lekkside_connect/features/shell/widgets/floating_nav_bar.dart';
import 'package:lekkside_connect/features/social/widgets/post_card.dart';

/// Registers a real typeface so the goldens show letters instead of boxes.
///
/// `google_fonts` fetches over HTTP, which a widget test has no access to, so
/// its text falls back to the framework's placeholder font — solid rectangles.
/// Registering a font the machine already has and pointing the theme at it
/// gives readable output.
///
/// The typeface is therefore *not* Inter. Everything that governs layout —
/// size, weight, tracking, leading, colour — still comes from the real theme,
/// so these are honest for spacing, density, hierarchy and line breaks, and
/// not for the shape of the letterforms.
const goldenFont = 'GoldenSans';

Future<bool> loadRealFont() async {
  const candidates = [
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
    '/Library/Fonts/Arial.ttf',
  ];
  final path = candidates.firstWhere(
    (p) => File(p).existsSync(),
    orElse: () => '',
  );
  if (path.isEmpty) return false;

  final loader = FontLoader(goldenFont)
    ..addFont(Future.value(File(path).readAsBytesSync().buffer.asByteData()));
  await loader.load();
  return true;
}

Post fixture({
  bool liked = false,
  bool verified = true,
  int likes = 128,
  int mediaCount = 0,
  int? mediaWidth = 1600,
  int? mediaHeight = 900,
}) =>
    Post(
      id: 'p1',
      kind: 'announcement',
      body: 'Global Futures Scholarship closes in 14 days. Full tuition, ten '
          'awards, open to students across West Africa.',
      likeCount: likes,
      commentCount: 12,
      repostCount: 48,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      authorHandle: 'maplecrest',
      authorName: 'Maplecrest University',
      authorKind: 'institution',
      authorVerified: verified,
      authorCountry: 'CA',
      liked: liked,
      // The URLs 404 in a widget test, so these render as the card's error
      // fill. That is deliberate: what these goldens are for is the *box* —
      // the 16:9 crop and the full-bleed edges — not the photograph.
      media: [
        for (var i = 0; i < mediaCount; i++)
          PostMedia(
              storagePath: 'demo/$i.jpg',
              width: mediaWidth,
              height: mediaHeight),
      ],
      topics: const [
        PostTopic(kind: 'field', value: 'computer-science'),
        PostTopic(kind: 'country', value: 'CA'),
      ],
    );

Widget frame(Widget child, ThemeData theme, {double textScale = 1.0}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // Same sizes, weights, tracking and leading; a typeface that is actually
      // present.
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: goldenFont),
        primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: goldenFont),
      ),
      // copyWith, not a fresh MediaQueryData: building one from scratch zeroes
      // `size`, and anything that sizes itself against the screen — the post
      // card caps its media at 45% of the height — then collapses to nothing.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: SafeArea(child: child),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A post with media builds its URLs through SupabaseService, which asserts
    // the client is initialized. Nothing here talks to it — a dummy project is
    // enough to get a storage URL back.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://dummy.supabase.co',
      publishableKey: 'dummy-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );

    // The real Inter files are registered with the engine below, under the
    // same family name google_fonts asks for — so the glyphs are there.
    // google_fonts does not know that and will still try to fetch, which has
    // no network in a widget test. Its failure is harmless and its exception
    // would fail every test, so that one error is swallowed and nothing else.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exception.toString();
      if (text.contains('Failed to load font') ||
          text.contains('allowRuntimeFetching')) {
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    final ok = await loadRealFont();
    if (!ok) debugPrint('No system typeface found — expect placeholder boxes.');
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget child, {
    required ThemeData theme,
    Size size = const Size(390, 500),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(frame(child, theme, textScale: textScale));
    // pumpAndSettle drives timers and animations but does not wait for an
    // image to decode, so the first shot of a screen with Image.asset in it
    // catches an empty box. runAsync lets the real load finish.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  // The nav capsule floats over content, so these are shot over a stand-in
  // for a bright photo — a capsule looks fine over flat grey and illegible
  // over a picture, which is the case that matters.
  Widget navOver(Widget bar) => Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE9B949), Color(0xFF9B59B6)],
                ),
              ),
            ),
          ),
          bar,
        ],
      );

  // The theme getters call google_fonts, which reads the asset bundle, so
  // they cannot be evaluated in a loop header — that runs before the test
  // binding exists. Resolve them inside the test body.
  for (final name in ['light', 'dark']) {
    testWidgets('nav bar — $name, expanded', (tester) async {
      final theme =
          name == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
      await shoot(
        tester,
        'nav_bar_${name}_expanded',
        navOver(FloatingNavBar(
          currentIndex: 0,
          onTap: (_) {},
          badges: const {3: 4, 4: 12},
        )),
        theme: theme,
        size: const Size(390, 140),
      );
    });

    testWidgets('nav bar — $name, collapsed', (tester) async {
      final theme =
          name == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
      await shoot(
        tester,
        'nav_bar_${name}_collapsed',
        navOver(FloatingNavBar(
          currentIndex: 0,
          onTap: (_) {},
          badges: const {3: 4, 4: 12},
          collapse: 1,
        )),
        theme: theme,
        size: const Size(390, 140),
      );
    });
  }

  for (final name in ['light', 'dark']) {
    testWidgets('sign in — $name', (tester) async {
      final theme =
          name == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
      await shoot(
        tester,
        'login_$name',
        ChangeNotifierProvider(
          create: (_) => AuthProvider(),
          child: const LoginScreen(),
        ),
        theme: theme,
        size: const Size(390, 844),
      );
    });
  }

  for (final name in ['light', 'dark']) {
    testWidgets('settings — $name', (tester) async {
      final theme =
          name == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
      await shoot(
        tester,
        'settings_$name',
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => PassportProvider()),
            ChangeNotifierProvider(
                create: (_) => ThemeProvider(autoLoad: false)),
          ],
          child: const ProfileScreen(),
        ),
        theme: theme,
        size: const Size(390, 900),
      );
    });
  }

  testWidgets('post glyphs — outline and filled, large', (tester) async {
    await shoot(
      tester,
      'social_icons',
      Builder(builder: (context) {
        final colour = Theme.of(context).textTheme.bodyLarge!.color!;
        Widget row(double size, bool filled) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final g in SocialGlyph.values)
                    SocialIcon(g,
                        size: size,
                        color: colour,
                        filled: filled &&
                            (g == SocialGlyph.heart ||
                                g == SocialGlyph.bookmark)),
                ],
              ),
            );
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [row(48, false), row(48, true), row(22, false)],
          ),
        );
      }),
      theme: AppTheme.lightTheme,
      size: const Size(390, 260),
    );
  });

  for (final name in ['light', 'dark']) {
    testWidgets('choose an account type — $name', (tester) async {
      final theme =
          name == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
      await shoot(
        tester,
        'account_type_$name',
        const AccountTypeScreen(),
        theme: theme,
        size: const Size(390, 1000),
      );
    });
  }

  testWidgets('post card — light', (tester) async {
    await shoot(tester, 'post_card_light', PostCard(post: fixture()),
        theme: AppTheme.lightTheme, size: const Size(390, 330));
  });

  testWidgets('post card — header, long and short names', (tester) async {
    await shoot(
      tester,
      'post_card_headers',
      Column(children: [
        PostCard(post: fixture()),
        PostCard(
          post: Post(
            id: 'p2',
            body: 'Applications for September close on Friday.',
            createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
            authorHandle: 'mit',
            authorName: 'MIT',
            authorKind: 'institution',
            authorVerified: true,
            likeCount: 3,
          ),
        ),
        PostCard(
          post: Post(
            id: 'p3',
            body: 'Thanks — that answered it.',
            createdAt: DateTime.now().subtract(const Duration(days: 2)),
            authorHandle: 'amara_okonkwo_jr',
            authorName: 'Amara Okonkwo',
            likeCount: 1,
          ),
        ),
      ]),
      theme: AppTheme.lightTheme,
      size: const Size(390, 420),
    );
  });

  testWidgets('post card — dark', (tester) async {
    await shoot(tester, 'post_card_dark', PostCard(post: fixture(liked: true)),
        theme: AppTheme.darkTheme, size: const Size(390, 330));
  });

  testWidgets('post card — largest text', (tester) async {
    await shoot(tester, 'post_card_large_text', PostCard(post: fixture()),
        theme: AppTheme.lightTheme,
        size: const Size(390, 560),
        textScale: 1.6);
  });

  testWidgets('post card — one image, 16:9 and full bleed', (tester) async {
    await shoot(
      tester,
      'post_card_media_one',
      PostCard(
          post: fixture(
              mediaCount: 1,
              liked: true,
              mediaWidth: 1080,
              mediaHeight: 1350)),
      theme: AppTheme.lightTheme,
      size: const Size(390, 780),
    );
  });

  testWidgets('post card — three images, no empty cell', (tester) async {
    await shoot(
      tester,
      'post_card_media_three',
      PostCard(post: fixture(mediaCount: 3)),
      theme: AppTheme.darkTheme,
      size: const Size(390, 720),
    );
  });

  testWidgets('type scale — light', (tester) async {
    await shoot(
      tester,
      'type_scale_light',
      Builder(builder: (context) {
        final t = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Education', style: t.displaySmall),
              Text('Find your course', style: t.headlineSmall),
              Text('Maplecrest University', style: t.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Entry requirements are shown in your own country’s terms, '
                'so you can tell at a glance whether you qualify.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text('CLOSES IN 14 DAYS', style: t.labelSmall),
            ],
          ),
        );
      }),
      theme: AppTheme.lightTheme,
      size: const Size(390, 300),
    );
  });

  testWidgets('buttons — light and dark', (tester) async {
    Widget row(ThemeData theme) => Theme(
          data: theme,
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CustomButton(label: 'Create account', onPressed: _noop),
                  SizedBox(height: 12),
                  CustomButton.outlined(label: 'Sign in', onPressed: _noop),
                  SizedBox(height: 12),
                  CustomButton(label: 'Disabled'),
                ],
              ),
            ),
          ),
        );

    await shoot(
      tester,
      'buttons',
      Column(children: [
        Expanded(child: row(AppTheme.lightTheme)),
        Expanded(child: row(AppTheme.darkTheme)),
      ]),
      theme: AppTheme.lightTheme,
      size: const Size(390, 440),
    );
  });

  testWidgets('institution tiles — the Discover tab that was missing',
      (tester) async {
    Institution inst(String name, String kind, String country, String? city,
            {bool verified = true, String? about}) =>
        Institution(
          id: name,
          name: name,
          slug: name.toLowerCase(),
          country: country,
          city: city,
          kind: kind,
          verificationStatus: verified ? 'verified' : 'unverified',
          tier: 'basic',
          description: about,
        );

    await shoot(
      tester,
      'institution_tiles',
      Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          InstitutionTile(
            institution: inst('Maplecrest University', 'university', 'CA',
                'Toronto',
                about: 'A research university with strong engineering and '
                    'computer science faculties, and scholarships open to '
                    'West African students.'),
          ),
          const SizedBox(height: 10),
          InstitutionTile(
            institution: inst('High Commission of Canada', 'embassy', 'CA',
                'Lagos',
                about: 'Visa guidance and study-permit requirements.'),
          ),
          const SizedBox(height: 10),
          InstitutionTile(
            institution: inst('Northgate College London', 'college', 'GB',
                'London',
                verified: false),
          ),
        ]),
      ),
      theme: AppTheme.lightTheme,
      size: const Size(390, 420),
    );
  });

  testWidgets('translucent chrome over content', (tester) async {
    await shoot(
      tester,
      'material_surface',
      Stack(children: [
        ListView(
          children: List.generate(
            12,
            (i) => PostCard(post: fixture(likes: i * 7)),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: MaterialSurface(
            child: SizedBox(
              height: 64,
              child: Center(child: Text('Glass bar over the feed')),
            ),
          ),
        ),
      ]),
      theme: AppTheme.darkTheme,
      size: const Size(390, 420),
    );
  });
}

void _noop() {}
