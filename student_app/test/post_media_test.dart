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

Post withMedia(int count, {int? w = 1600, int? h = 900}) => Post(
      id: 'p1',
      body: 'A caption.',
      createdAt: DateTime.now(),
      authorHandle: 'maplecrest',
      authorName: 'Maplecrest University',
      authorKind: 'institution',
      media: [
        for (var i = 0; i < count; i++)
          PostMedia(storagePath: 'demo/$i.jpg', width: w, height: h),
      ],
    );

const _screen = Size(390, 844);

Future<void> pumpCard(
  WidgetTester tester,
  int mediaCount, {
  int? w = 1600,
  int? h = 900,
}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: ListView(
        children: [PostCard(post: withMedia(mediaCount, w: w, h: h))],
      ),
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

  group('nothing is cut', () {
    testWidgets('the box takes the picture\'s own shape, so there is nothing '
        'to crop', (tester) async {
      await pumpCard(tester, 1, w: 1600, h: 900);
      final box = mediaBox(tester);
      expect(box.width / box.height, closeTo(1600 / 900, 0.01));
    });

    testWidgets('a portrait poster gets a portrait box', (tester) async {
      await pumpCard(tester, 1, w: 1080, h: 1350);
      final box = mediaBox(tester);
      expect(box.width / box.height, closeTo(1080 / 1350, 0.01));
    });

    testWidgets('the picture is contained, never cropped — this is the bit '
        'that was cutting the edges off flyers', (tester) async {
      await pumpCard(tester, 1, w: 1080, h: 1350);
      final fits = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((i) => i.fit)
          .toList();
      expect(fits, contains(BoxFit.contain));
    });

    testWidgets('a very tall picture is letterboxed rather than cropped — and '
        'the letterbox is a blurred copy, not a grey bar', (tester) async {
      await pumpCard(tester, 1, w: 600, h: 1600);
      final box = mediaBox(tester);
      // Clamped, so one post cannot eat the whole viewport...
      expect(box.width / box.height, closeTo(0.68, 0.01));
      // ...but still contained, so the whole poster is visible.
      final images = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .toList();
      expect(images.map((i) => i.fit), containsAll([
        BoxFit.contain, // the picture
        BoxFit.cover, // the blurred fill behind it
      ]));
      expect(find.byType(ImageFiltered), findsOneWidget);
    });

    testWidgets('and 4:5 is only the fallback, for posts uploaded before '
        'dimensions were recorded', (tester) async {
      await pumpCard(tester, 1, w: null, h: null);
      final box = mediaBox(tester);
      expect(box.width / box.height, closeTo(4 / 5, 0.01));
    });
  });

  group('several pictures', () {
    testWidgets('swipe horizontally instead of being cropped into a grid',
        (tester) async {
      await pumpCard(tester, 3);
      expect(find.byType(PageView), findsOneWidget);
      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.childrenDelegate.estimatedChildCount, 3);
    });

    testWidgets('a single picture needs no pager', (tester) async {
      await pumpCard(tester, 1);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('every page is contained, so none of them is cut either',
        (tester) async {
      await pumpCard(tester, 2);
      final fits = tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .map((i) => i.fit)
          .toList();
      expect(fits, contains(BoxFit.contain));
    });

    testWidgets('the box keeps one shape across the whole carousel, so it '
        'does not resize as you swipe', (tester) async {
      await pumpCard(tester, 3, w: 1080, h: 1350);
      final box = mediaBox(tester);
      expect(box.width / box.height, closeTo(1080 / 1350, 0.01));
    });

    testWidgets('the carousel swallows its own scroll notifications, so '
        'swiping photos does not drive the nav bar', (tester) async {
      await pumpCard(tester, 3);
      final listener = tester.widget<NotificationListener<ScrollNotification>>(
        find
            .ancestor(
              of: find.byType(PageView),
              matching: find.byType(NotificationListener<ScrollNotification>),
            )
            .first,
      );
      expect(
        listener.onNotification!(ScrollEndNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: 0,
            maxScrollExtent: 2,
            pixels: 1,
            viewportDimension: 390,
            axisDirection: AxisDirection.right,
            devicePixelRatio: 3,
          ),
          context: tester.element(find.byType(PageView)),
        )),
        isTrue,
        reason: 'returning true stops it reaching the shell',
      );
    });
  });
}
