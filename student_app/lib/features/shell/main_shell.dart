import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_chrome.dart';
import '../../core/utils/motion.dart';
import '../messages/providers/messages_provider.dart';
import '../notifications/providers/notifications_provider.dart';
import 'nav_scroll_policy.dart';
import 'widgets/floating_nav_bar.dart';

/// The student shell: five tabs under a floating glass capsule.
///
/// The capsule stays in `Scaffold.bottomNavigationBar` even though it floats,
/// because that slot is the channel the Scaffold uses to tell the five tab
/// screens how much room to leave at the bottom: it measures the bar and
/// publishes the result as the body's `MediaQuery.padding.bottom`. Moving the
/// bar into a `Stack` would look identical and throw that number away, leaving
/// every list back on a hardcoded guess.
///
/// The slot's height is therefore **pinned** at the expanded size, and the
/// capsule shrinks *inside* it. Animating the slot itself would republish the
/// body's `MediaQuery` on every frame, re-resolving the padding of every list
/// and re-running sliver layout mid-scroll.
class MainShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  /// 0 = expanded, 1 = compact.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 200),
  );

  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );

  /// Read in [build] rather than in the scroll callback: looking up an
  /// inherited widget outside of build registers a dependency at the wrong
  /// time.
  bool _reduceMotion = false;
  double _viewportHeight = 0;
  double _slotHeight = 0;

  @override
  void didUpdateWidget(MainShell old) {
    super.didUpdateWidget(old);
    // Each tab keeps its own scroll offset alive (AutomaticKeepAliveClientMixin),
    // so switching tabs emits no scroll notification at all and the bar would
    // keep whatever state the tab you left had put it in.
    if (old.navigationShell.currentIndex != widget.navigationShell.currentIndex) {
      _reveal();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_controller.value == 0) return;
    _reduceMotion ? _controller.value = 0 : _controller.animateTo(0);
  }

  void _collapse() {
    // Under Reduce Motion the bar simply stays out. Chrome that hides is a
    // convenience, not a function, and a capsule that teleports away and back
    // on every direction change is worse than one that never moves. Nothing
    // reflows when it stays put, because the slot is pinned either way.
    if (_reduceMotion || _controller.value == 1) return;
    _controller.animateTo(1);
  }

  bool _onScroll(ScrollNotification n) {
    switch (navBarIntentFor(
      n,
      viewportHeight: _viewportHeight,
      slotHeight: _slotHeight,
    )) {
      case NavBarIntent.reveal:
        _reveal();
      case NavBarIntent.collapse:
        _collapse();
      case NavBarIntent.hold:
        break;
    }
    // Never swallow: the feed and Discover listen for pagination, and
    // RefreshIndicator needs the overscroll.
    return false;
  }

  void _onTap(int index) {
    _reveal(); // a tap always brings the bar back
    // Tapping the current tab pops it back to its root.
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = reduceMotion(context);
    _viewportHeight = MediaQuery.sizeOf(context).height;

    final unreadMessages = context.select<MessagesProvider, int>(
      (p) => p.unreadCount,
    );
    final unreadNotifications = context.select<NotificationsProvider, int>(
      (p) => p.unreadCount,
    );

    final slotHeight = AppChrome.navSlotHeight(context);
    _slotHeight = slotHeight;

    return Scaffold(
      // The list reads as continuing underneath the capsule rather than
      // stopping dead at it — and this is also what makes the Scaffold
      // publish the bar's height to the body (see the class comment).
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          // Pinned. The capsule shrinks inside this box, never the box itself
          // — see the note on AppChrome.navSlotHeight.
          height: slotHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) => FloatingNavBar(
                currentIndex: widget.navigationShell.currentIndex,
                onTap: _onTap,
                badges: {3: unreadNotifications, 4: unreadMessages},
                collapse: _t.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
