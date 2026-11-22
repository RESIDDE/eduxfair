import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/dynamic_type.dart';
import '../../../core/widgets/material_surface.dart';
import '../../../core/widgets/pressable.dart';

/// The student nav bar: a glass capsule floating clear of the screen edges.
///
/// Pure presentation — it takes an index, a collapse factor and a badge map,
/// and knows nothing about go_router or any provider. That is what lets it be
/// rendered in a golden and reasoned about on its own; [MainShell] owns the
/// animation and the scroll policy that drives [collapse].
class FloatingNavBar extends StatelessWidget {
  /// Which tab is active.
  final int currentIndex;

  final ValueChanged<int> onTap;

  /// Unread counts by tab index. Absent means none.
  final Map<int, int> badges;

  /// 0 = expanded, 1 = compact.
  final double collapse;

  /// The tabs to draw. Defaults to the student shell's [items]; the
  /// institution shell passes its own, so both sides share one bar — the same
  /// material, the same press response, the same collapse — rather than two
  /// that drift apart.
  final List<(IconData, IconData, String)>? tabs;

  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.badges = const {},
    this.collapse = 0,
    this.tabs,
  });

  static const items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Feed'),
    (Icons.search_outlined, Icons.search_rounded, 'Search'),
    (Icons.podcasts_outlined, Icons.podcasts_rounded, 'Spaces'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded,
        'Notifications'),
    (Icons.mail_outline_rounded, Icons.mail_rounded, 'Messages'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = collapse.clamp(0.0, 1.0);
    final inset = lerpDouble(12, 72, t)!;
    final height = context.scaled(lerpDouble(AppChrome.navBarHeight, 44, t)!);
    final iconSize = lerpDouble(26, 22, t)!;
    final items = tabs ?? FloatingNavBar.items;

    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, AppChrome.navBarInset),
      child: MaterialSurface(
        borderRadius: BorderRadius.circular(999),
        shadow: true,
        // More opaque than the 0.72 default: this one floats over photographs,
        // and at 0.72 the icons disappear into whatever is behind them.
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
                    selected: currentIndex == i,
                    badge: badges[i] ?? 0,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
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
    // Under Increase Contrast a five-hue sweep is the wrong answer: several of
    // its stops fail contrast against both canvases, so the glyph goes solid,
    // like the surface behind it.
    final plain = MediaQuery.highContrastOf(context);

    Widget glyph = Icon(
      selected ? activeIcon : icon,
      size: iconSize,
      color: selected ? colors.textPrimary : colors.textLight,
    );

    if (selected && !plain) {
      // The one place the brand ramp appears in the chrome. `srcIn` keeps only
      // the glyph's alpha, so the shader supplies all of the colour.
      glyph = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => colors.brandGradient.createShader(rect),
        child: Icon(activeIcon, size: iconSize, color: Colors.white),
      );
    }

    // Outside the ShaderMask: inside it, the unread count would be painted in
    // the gradient too.
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
