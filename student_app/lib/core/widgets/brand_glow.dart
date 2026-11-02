import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A soft wash of the brand gradient, used behind the sign-in hero.
///
/// This is the gradient's one appearance as a *field* rather than as a line or
/// a glyph, and it is blurred past the point where any of its stops reads as a
/// colour you could put text on — which is the condition for using it this way
/// at all. Nothing is ever laid directly on top of it; the glass card in front
/// is what text sits on.
///
/// It also gives that card something to refract. Glass over a flat canvas is
/// just a tinted box.
///
/// Dropped entirely under Increase Contrast, for the same reason
/// [MaterialSurface] drops its blur: a washed-out gradient behind a
/// high-contrast interface is noise.
class BrandGlow extends StatelessWidget {
  final double size;
  final double opacity;

  const BrandGlow({super.key, this.size = 260, this.opacity = 0.40});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) {
      return SizedBox(width: size, height: size);
    }

    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: context.colors.brandGradient,
            ),
          ),
        ),
      ),
    );
  }
}
