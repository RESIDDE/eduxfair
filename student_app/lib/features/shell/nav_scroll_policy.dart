import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// What a scroll notification should do to the floating nav bar.
enum NavBarIntent {
  /// Bring the bar back to full size.
  reveal,

  /// Shrink it out of the way.
  collapse,

  /// Leave it as it is.
  hold,
}

/// Decides what a single [ScrollNotification] means for the nav bar.
///
/// Pure on purpose. This is the one genuinely fragile part of the floating bar
/// — the difference between "gets out of the way while you read" and "vanishes
/// when you swipe sideways and never comes back" is four guards that are easy
/// to get subtly wrong and impossible to eyeball. Keeping it a function of its
/// arguments means `test/nav_scroll_test.dart` can cover every branch without
/// standing up a router, five providers and a shell.
NavBarIntent navBarIntentFor(
  ScrollNotification n, {
  required double viewportHeight,
  required double slotHeight,
}) {
  final m = n.metrics;

  // The feed and Conversations each wrap their lists in a horizontal
  // TabBarView, and Discover has a horizontal chip row. All three emit
  // notifications indistinguishable from a list's, so without this a sideways
  // swipe would retract the bar.
  if (m.axis == Axis.horizontal) {
    // Landing on a new tab is a new reading context, and because every tab
    // keeps its own scroll offset alive, the one you land on may be mid-list.
    // PageMetrics is what tells a tab swipe apart from a flung chip row.
    if (n is ScrollEndNotification && m is PageMetrics) return NavBarIntent.reveal;
    return NavBarIntent.hold;
  }

  // Only the scrollable that owns most of the screen counts as "the thing
  // being read". Excludes short rails nested inside cards.
  if (viewportHeight > 0 && m.viewportDimension < viewportHeight * 0.6) {
    return NavBarIntent.hold;
  }

  // A list that barely scrolls never takes the chrome away. The threshold is
  // one bar height rather than literally zero, so a list that scrolls by a few
  // pixels does not flicker it.
  if (m.maxScrollExtent <= slotHeight) return NavBarIntent.reveal;

  // The two resting states, checked before direction so that the end of a
  // downward fling that lands at the bottom still reveals. At the top the bar
  // is always present; at the bottom there is no further reading gesture and
  // the reserved strip would read as dead space. This is also the net under
  // `jumpTo`, whose idle event carries stale metrics, and under a
  // pull-to-refresh.
  if (n is ScrollEndNotification &&
      (m.extentBefore <= 8 || m.extentAfter <= 8)) {
    return NavBarIntent.reveal;
  }

  if (n is UserScrollNotification) {
    return switch (n.direction) {
      ScrollDirection.reverse => NavBarIntent.collapse, // reading onwards
      ScrollDirection.forward => NavBarIntent.reveal, // coming back up
      // A settled fling, or one notch of a mouse wheel — which emits idle
      // between every tick and would otherwise strobe the bar.
      ScrollDirection.idle => NavBarIntent.hold,
    };
  }

  return NavBarIntent.hold;
}
