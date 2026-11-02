// The post card's media box.
//
// The point of the Instagram redesign was to make the picture full-bleed and
// to stop it being as tall as Instagram's own. Both of those are geometry, and
// geometry is invisible in a golden when every tile renders as the same flat
// "image failed to load" fill — so they are asserted here instead.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lekkside_connect/core/theme/app_theme.dart';
import 'package:lekkside_connect/features/social/models/post.dart';
import 'package:lekkside_connect/features/social/widgets/post_card.dart';

Post withMedia(int count) => Post(
      id: 'p1',
      body: 'A caption.',
      createdAt: DateTime.now(),
      authorHandle: 'maplecrest',
      authorName: 'Maplecrest University',
      authorKind: 'institution',
      media: [
        for (var i = 0; i < count; i++)
          PostMedia(storagePath: 'demo/$i.jpg', width: 1600, height: 900),
      ],
    );

const _screen = Size(390, 844);

Future<void> pumpCard(WidgetTester tester, int mediaCount) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: ListView(children: [PostCard(post: withMedia(mediaCount))]),
    ),
  ));
  await tester.pump();
}

/// The media box — the one AspectRatio the card puts around its pictures.
Size mediaBox(WidgetTester tester) => tester.getSize(find.descendant(
      of: find.byType(PostCard),
      matching: find.byType(AspectRatio),
    ));

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

  testWidgets('media runs edge to edge — the old layout inset it behind an '
      'avatar gutter and lost 80pt of width', (tester) async {
    await pumpCard(tester, 1);
    expect(mediaBox(tester).width, _screen.width);
  });

  testWidgets('media is boxed at 16:9, not at the image\'s own ratio',
      (tester) async {
    await pumpCard(tester, 1);
    final box = mediaBox(tester);
    expect(box.width / box.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('and so takes well under half the screen, so the next post '
      'still peeks at the bottom edge', (tester) async {
    await pumpCard(tester, 1);
    expect(mediaBox(tester).height, lessThan(_screen.height * 0.45));
  });

  group('the mosaic', () {
    testWidgets('two images split the box down the middle', (tester) async {
      await pumpCard(tester, 2);
      final tiles = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .length;
      expect(tiles, 2);

      final sizes = find.byType(CachedNetworkImage);
      final a = tester.getSize(sizes.at(0));
      final b = tester.getSize(sizes.at(1));
      expect(a.width, closeTo(b.width, 0.5));
      expect(a.height, closeTo(mediaBox(tester).height, 0.5),
          reason: 'each is a full-height half');
    });

    testWidgets('three images are one large and two stacked — a 2x2 grid '
        'would leave an empty fourth cell, which it used to', (tester) async {
      await pumpCard(tester, 3);
      final tiles = find.byType(CachedNetworkImage);
      expect(tester.widgetList(tiles).length, 3);

      final box = mediaBox(tester);
      final big = tester.getSize(tiles.at(0));
      final top = tester.getSize(tiles.at(1));
      final bottom = tester.getSize(tiles.at(2));

      expect(big.height, closeTo(box.height, 0.5), reason: 'full height');
      expect(top.height, lessThan(big.height * 0.55));
      expect(bottom.height, closeTo(top.height, 0.5));
      expect(top.width, closeTo(big.width, 0.5));
    });

    testWidgets('four images make a 2x2', (tester) async {
      await pumpCard(tester, 4);
      expect(tester.widgetList(find.byType(CachedNetworkImage)).length, 4);
      final box = mediaBox(tester);
      for (var i = 0; i < 4; i++) {
        final tile = tester.getSize(find.byType(CachedNetworkImage).at(i));
        expect(tile.height, lessThan(box.height * 0.55));
        expect(tile.width, lessThan(box.width * 0.55));
      }
    });

    testWidgets('a fifth image is dropped rather than shrinking the rest',
        (tester) async {
      await pumpCard(tester, 5);
      expect(tester.widgetList(find.byType(CachedNetworkImage)).length, 4);
    });
  });
}
