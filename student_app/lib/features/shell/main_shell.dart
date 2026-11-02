import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_chrome.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/dynamic_type.dart';
import '../../core/utils/motion.dart';
import '../../core/widgets/material_surface.dart';
import '../../core/widgets/pressable.dart';
import '../messages/providers/messages_provider.dart';
import '../notifications/providers/notifications_provider.dart';
import 'nav_scroll_policy.dart';

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

    const items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home_rounded, 'Feed'),
      (Icons.search_outlined, Icons.search_rounded, 'Search'),
      (Icons.podcasts_outlined, Icons.podcasts_rounded, 'Spaces'),
      (Icons.notifications_none_rounded, Icons.notifications_rounded,
          'Notifications'),
      (Icons.mail_outline_rounded, Icons.mail_rounded, 'Messages'),
    ];

    final slotHeight = AppChrome.navSlotHeight(context);
    _slotHeight = slotHeight;

    return Scaffold(
      // The list reads as continuing underneath the capsule rather than
      // stopping dead at it.
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
              builder: (context, _) {
                final t = _t.value;
                final inset = lerpDouble(12, 72, t)!;
                final height =
                    context.scaled(lerpDouble(AppChrome.navBarHeight, 44, t)!);
                final iconSize = lerpDouble(26, 22, t)!;

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                      inset, 0, inset, AppChrome.navBarInset),
                  child: MaterialSurface(
                    borderRadius: BorderRadius.circular(999),
                    shadow: true,
                    // More opaque than the 0.72 default: this one floats over
                    // photographs, and at 0.72 the icons disappear into
                    // whatever happens to be behind them.
                    tintAlpha: 0.82,
                    child: SizedBox(
                      height: height,
                      child: Row(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Expanded(
                              child: _Tab(
                                icon: items[i].$1,
                                activeIcon: items[i].$2,
                                label: items[i].$3,
                                iconSize: iconSize,
                                selected:
                                    widget.navigationShell.currentIndex == i,
                                badge: switch (i) {
                                  3 => unreadNotifications,
                                  4 => unreadMessages,
                                  _ => 0,
                                },
                                onTap: () => _onTap(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final int badge;
  final double iconSize;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A five-stop ramp has stops that fail contrast against both canvases, so
    // under Increase Contrast the glyph falls back to the flat colour.
    final plain = MediaQuery.highContrastOf(context);

    Widget glyph = Icon(
      selected ? activeIcon : icon,
      size: iconSize,
      color: selected ? colors.textPrimary : colors.textLight,
    );

    if (selected && !plain) {
      // The one place the brand ramp appears in the chrome. Masked onto the
      // glyph only — a gradient unread count is noise.
      glyph = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => colors.brandGradient.createShader(rect),
        child: Icon(activeIcon, size: iconSize, color: Colors.white),
      );
    }

    final content = badge > 0
        ? Badge.count(
            count: badge,
            backgroundColor: colors.error,
            textColor: colors.onAccent,
            child: glyph,
          )
        : glyph;

    return Semantics(
      // The icons carry no visible label, so the accessible one matters more
      // here than it would on a labelled bar.
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge unread' : label,
      child: Pressable(
        onTap: onTap,
        // Switching tabs is a selection, and the icon yields a little as it is
        // pressed — the acknowledgement arrives before the screen changes.
        scale: 0.88,
        haptic: HapticKind.selection,
        child: Center(
          child: Container(
            // Sized off the icon so the five pills can never overflow the
            // capsule at its narrowest.
            width: iconSize + 18,
            height: iconSize + 8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colors.surfaceVariant.withValues(alpha: 0.85)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
