import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Translucent chrome, with content passing underneath it.
///
/// Apple treats navigation bars, toolbars and sheets as a floating *material*
/// layer rather than an opaque strip that eats a fixed band of the screen. The
/// blur is what makes the layer read as glass sitting above the content, and
/// the content staying visible under it is what tells you the list continues.
///
/// Three details that are easy to miss and do most of the work:
///
///   * **Weight follows size.** A large surface reads as thicker — more blur,
///     deeper shadow — than a small chip. Passing [heavy] says which this is.
///   * **A bright top edge**, not a border. Real glass catches light along its
///     leading edge; a flat 1px grey line reads as a divider instead.
///   * **Saturation is raised** as well as blurred, because blurring alone
///     greys out the colour underneath and the material goes muddy.
///
/// Goes solid under Increase Contrast, dropping the blur entirely rather than
/// softening it — a weak blur is the worst of both.
///
/// Apple's own guidance also names Reduce Transparency as a separate signal.
/// Flutter does not surface it: `AccessibilityFeatures` carries `reduceMotion`,
/// `disableAnimations`, `boldText`, `highContrast`, `invertColors` and
/// `accessibleNavigation`, and nothing for transparency. Increase Contrast is
/// the closest real signal and is what people with low vision tend to turn on
/// alongside it, so it is what this reads. If Flutter adds the signal, it
/// belongs in [_opaque] next to this one.
class MaterialSurface extends StatelessWidget {
  final Widget child;

  /// Large structural chrome — a nav bar or a sheet — rather than a chip.
  final bool heavy;

  final BorderRadius? borderRadius;

  /// Which edge catches the light. A bottom bar is lit from above, a top bar
  /// from below, so the bright edge faces the content in both cases.
  final bool lightFromTop;

  const MaterialSurface({
    super.key,
    required this.child,
    this.heavy = true,
    this.borderRadius,
    this.lightFromTop = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final opaque = _opaque(context);

    final tint = colors.background.withValues(alpha: opaque ? 1.0 : 0.72);
    final edge = Border(
      top: lightFromTop
          ? BorderSide(
              color: dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.5),
            )
          : BorderSide.none,
      bottom: lightFromTop
          ? BorderSide.none
          : BorderSide(color: colors.divider.withValues(alpha: 0.6)),
    );

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        border: opaque ? null : edge,
        borderRadius: borderRadius,
      ),
      child: child,
    );

    if (opaque) return surface;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        // Bigger surfaces are thicker glass.
        filter: ImageFilter.blur(
          sigmaX: heavy ? 24 : 12,
          sigmaY: heavy ? 24 : 12,
        ),
        child: surface,
      ),
    );
  }

  /// Whether this surface should abandon translucency altogether.
  static bool _opaque(BuildContext context) =>
      MediaQuery.highContrastOf(context);
}
