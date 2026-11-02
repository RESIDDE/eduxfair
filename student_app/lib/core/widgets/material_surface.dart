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
/// Four details that are easy to miss and do most of the work:
///
///   * **Weight follows size.** A large surface reads as thicker — more blur,
///     deeper shadow — than a small chip. Passing [heavy] says which this is.
///   * **A bright top edge**, not a border. Real glass catches light along its
///     leading edge; a flat 1px grey line reads as a divider instead.
///   * **Saturation is raised** as well as blurred, because blurring alone
///     greys out the colour underneath and the material goes muddy. This is
///     done with a *composed* filter so there is still exactly one
///     [BackdropFilter] in the tree.
///   * **A floating surface casts a shadow.** Chrome pinned to an edge does
///     not need one; a capsule floating over a list does, or it reads as a
///     sticker lying flat on the content. Opt in with [shadow].
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

  /// How opaque the tint is, 0–1. Defaults to 0.72.
  ///
  /// A bar that floats over photographs needs to be more opaque than one over
  /// a mostly-text list, or its icons disappear into whatever is behind them.
  final double? tintAlpha;

  /// Whether to cast a shadow, for a surface that floats free of any edge.
  final bool shadow;

  const MaterialSurface({
    super.key,
    required this.child,
    this.heavy = true,
    this.borderRadius,
    this.lightFromTop = true,
    this.tintAlpha,
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final opaque = _opaque(context);

    final tint =
        colors.background.withValues(alpha: opaque ? 1.0 : (tintAlpha ?? 0.72));
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

    if (opaque) return _withShadow(context, surface);

    return _withShadow(
      context,
      ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          // One filter, composed: blur the backdrop, then pull the colour back
          // up. Two nested BackdropFilters would sample the backdrop twice and
          // cost twice as much for the same picture.
          filter: ImageFilter.compose(
            outer: _saturate(1.6),
            // Bigger surfaces are thicker glass.
            inner: ImageFilter.blur(
              sigmaX: heavy ? 24 : 12,
              sigmaY: heavy ? 24 : 12,
            ),
          ),
          child: surface,
        ),
      ),
    );
  }

  Widget _withShadow(BuildContext context, Widget surface) {
    if (!shadow) return surface;
    return DecoratedBox(
      // Outside the clip: a shadow drawn inside one is clipped away. No colour
      // here, or it would paint over the blur.
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            blurRadius: heavy ? 24 : 12,
            offset: Offset(0, heavy ? 8 : 4),
          ),
        ],
      ),
      child: surface,
    );
  }

  /// A saturation matrix, as `ColorFilter.matrix` wants it.
  ///
  /// `ColorFilter` implements `ImageFilter`, which is what lets it be the
  /// outer half of an `ImageFilter.compose`. Luminance weights are Rec. 709,
  /// matching how the engine understands sRGB.
  static ColorFilter _saturate(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    return ColorFilter.matrix(<double>[
      lr + s * (1 - lr), lg * (1 - s),      lb * (1 - s),      0, 0,
      lr * (1 - s),      lg + s * (1 - lg), lb * (1 - s),      0, 0,
      lr * (1 - s),      lg * (1 - s),      lb + s * (1 - lb), 0, 0,
      0,                 0,                 0,                 1, 0,
    ]);
  }

  /// Whether this surface should abandon translucency altogether.
  static bool _opaque(BuildContext context) =>
      MediaQuery.highContrastOf(context);
}
