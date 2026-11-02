import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A hairline of gradient around a surface.
///
/// Flutter has no gradient `BorderSide`, so this strokes one: a rounded rect
/// painted *over* the child's edge with the ramp as its shader.
///
/// The obvious shortcut — a gradient-filled box with a hairline of padding and
/// the surface laid on top — is wrong for anything translucent. The fill sits
/// directly behind the child, so a [MaterialSurface] in front of it blurs the
/// gradient rather than the page, and the card's interior turns into a
/// full-bleed wash with body text sitting on it. Stroking the ring leaves the
/// inside alone.
///
/// Under Increase Contrast the ramp becomes a plain border: several of its
/// stops sit too close to both canvases to read as an edge at 1.5px.
class GradientBorder extends StatelessWidget {
  final Widget child;
  final double radius;
  final double width;

  /// The ramp. Defaults to the brand gradient.
  final Gradient? gradient;

  /// What fills the inside. Leave null for a translucent child — a glass card
  /// needs the real page behind it, not a colour.
  final Color? fill;

  const GradientBorder({
    super.key,
    required this.child,
    this.radius = 24,
    this.width = 1.5,
    this.gradient,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final plain = MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);

    Widget inner = ClipRRect(borderRadius: shape, child: child);
    if (fill != null) {
      inner = DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: shape),
        child: inner,
      );
    }

    return CustomPaint(
      // Over the child, so the stroke is not half-swallowed by the clip.
      foregroundPainter: _RingPainter(
        gradient: plain ? null : (gradient ?? colors.brandGradient),
        solid: plain ? colors.border : null,
        radius: radius,
        width: width,
      ),
      child: inner,
    );
  }
}

class _RingPainter extends CustomPainter {
  final Gradient? gradient;
  final Color? solid;
  final double radius;
  final double width;

  _RingPainter({
    required this.gradient,
    required this.solid,
    required this.radius,
    required this.width,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Inset by half the stroke, or the outer half of it lands outside the box
    // and gets clipped by whatever is above.
    final ring = RRect.fromRectAndRadius(
      bounds.deflate(width / 2),
      Radius.circular(radius - width / 2),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;
    if (gradient != null) {
      paint.shader = gradient!.createShader(bounds);
    } else {
      paint.color = solid ?? const Color(0x00000000);
    }

    canvas.drawRRect(ring, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.gradient != gradient ||
      old.solid != solid ||
      old.radius != radius ||
      old.width != width;
}
