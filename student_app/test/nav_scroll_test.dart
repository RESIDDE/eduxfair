// The floating nav bar's hide/show policy, pinned down.
//
// This is the part of the redesign most likely to break in a way nobody
// notices until it ships: a bar that retracts on a sideways tab swipe, or that
// hides on a two-item list and never comes back. `navBarIntentFor` is pure, so
// every branch is reachable here without a router or a single provider.

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lekkside_connect/features/shell/nav_scroll_policy.dart';

const _viewport = 800.0;
const _slot = 100.0;

ScrollMetrics _vertical({
  double pixels = 400,
  double maxScrollExtent = 5000,
  double viewportDimension = _viewport,
}) =>
    FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: maxScrollExtent,
      pixels: pixels,
      viewportDimension: viewportDimension,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );

/// What a TabBarView / PageView reports — the signal that a *tab* changed,
/// rather than a chip row having been flung.
PageMetrics _page() => PageMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 2,
      pixels: 1,
      viewportDimension: 390,
      axisDirection: AxisDirection.right,
      viewportFraction: 1,
      devicePixelRatio: 3,
    );

/// A horizontal list that is not a pager — Discover's chip row.
ScrollMetrics _chips() => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 600,
      pixels: 120,
      viewportDimension: 390,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 3,
    );

NavBarIntent intent(ScrollNotification n) => navBarIntentFor(
      n,
      viewportHeight: _viewport,
      slotHeight: _slot,
    );

/// `ScrollNotification.context` is non-nullable, and only a pumped tree can
/// produce one. It is never read by the policy — it exists for the
/// framework's own diagnostics — so any live context will do.
Future<BuildContext> ctxOf(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(Builder(builder: (context) {
    captured = context;
    return const SizedBox.shrink();
  }));
  return captured;
}

void main() {
  group('reading direction', () {
    testWidgets('scrolling down collapses the bar', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _vertical(), context: c, direction: ScrollDirection.reverse)),
        NavBarIntent.collapse,
      );
    });

    testWidgets('scrolling back up reveals it', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _vertical(), context: c, direction: ScrollDirection.forward)),
        NavBarIntent.reveal,
      );
    });

    testWidgets('idle holds — a settled fling must not pop it back up, and a mouse '
        'wheel emits idle between every tick', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _vertical(), context: c, direction: ScrollDirection.idle)),
        NavBarIntent.hold,
      );
    });
  });

  group('horizontal scrollables', () {
    testWidgets('a sideways drag on a pager does not collapse the bar', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _page(), context: c, direction: ScrollDirection.reverse)),
        NavBarIntent.hold,
      );
    });

    testWidgets('a flung chip row does not collapse it either', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _chips(), context: c, direction: ScrollDirection.reverse)),
        NavBarIntent.hold,
      );
    });

    testWidgets('settling on a new tab reveals it, because that tab kept its own '
        'offset and may be mid-list', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(ScrollEndNotification(metrics: _page(), context: c)),
        NavBarIntent.reveal,
      );
    });

    testWidgets('but a chip row settling is not a tab change', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(ScrollEndNotification(metrics: _chips(), context: c)),
        NavBarIntent.hold,
      );
    });
  });

  group('lists that cannot really scroll', () {
    testWidgets('a list shorter than the viewport never hides the bar', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _vertical(maxScrollExtent: 0),
            context: c,
            direction: ScrollDirection.reverse)),
        NavBarIntent.reveal,
      );
    });

    testWidgets('nor does one that scrolls by less than the bar is tall — otherwise '
        'the chrome flickers', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _vertical(maxScrollExtent: _slot - 1, pixels: 10),
            context: c,
            direction: ScrollDirection.reverse)),
        NavBarIntent.reveal,
      );
    });
  });

  group('resting states', () {
    testWidgets('coming to rest at the top reveals', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(ScrollEndNotification(metrics: _vertical(pixels: 0), context: c)),
        NavBarIntent.reveal,
      );
    });

    testWidgets('coming to rest at the bottom reveals, so the reserved strip is not '
        'left as dead space', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(ScrollEndNotification(
            metrics: _vertical(pixels: 5000), context: c)),
        NavBarIntent.reveal,
      );
    });

    testWidgets('coming to rest mid-list changes nothing', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(ScrollEndNotification(metrics: _vertical(), context: c)),
        NavBarIntent.hold,
      );
    });
  });

  group('nested scrollables', () {
    testWidgets('a short rail inside a card is not "the thing being read"', (tester) async {
      final c = await ctxOf(tester);
      expect(
        intent(UserScrollNotification(
            metrics: _vertical(viewportDimension: 120),
            context: c,
            direction: ScrollDirection.reverse)),
        NavBarIntent.hold,
      );
    });
  });
}
