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

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/core/widgets/custom_button.dart';
import 'package:lekkside_connect/core/widgets/material_surface.dart';
import 'package:lekkside_connect/features/discover/models/institution.dart';
import 'package:lekkside_connect/features/discover/widgets/institution_tile.dart';
import 'package:lekkside_connect/features/social/models/post.dart';
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
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(child: child),
        ),
      ),
    );

void main() {
  setUpAll(() async {
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
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
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
