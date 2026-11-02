import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The five glyphs under a post, drawn rather than taken from a font.
///
/// Material's nearest equivalents are the wrong shape and the wrong weight for
/// this design: `favorite_border_rounded` is a fat, soft heart,
/// `mode_comment_outlined` is a square bubble with no tail, and
/// `send_outlined` is a solid-ish plane. The reference's row is a set of thin,
/// even-stroked outlines at a single weight, which is most of what makes it
/// read the way it does — so these are paths on a 24x24 grid with one stroke
/// width between them.
///
/// They are drawn to match the *style* of the reference, not copied from its
/// asset files: these are the ordinary glyphs the shapes are made of — a
/// heart, a speech bubble, two repeat arrows, a paper plane, a bookmark — and
/// nobody's trademarked artwork is reproduced here.
enum SocialGlyph { heart, comment, reshare, send, bookmark }

class SocialIcon extends StatelessWidget {
  final SocialGlyph glyph;
  final double size;
  final Color color;

  /// Heart and bookmark fill when they are on. The other three have no
  /// on-state — resharing and sending are things you did, not states you are
  /// in, and the reference leaves them outlined too.
  final bool filled;

  const SocialIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _GlyphPainter(glyph: glyph, color: color, filled: filled),
          isComplex: false,
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  final SocialGlyph glyph;
  final Color color;
  final bool filled;

  _GlyphPainter({
    required this.glyph,
    required this.color,
    required this.filled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is authored against 24x24 and scaled, so one stroke
    // width governs the whole set at any size.
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;

    switch (glyph) {
      case SocialGlyph.heart:
        final path = _heart();
        canvas.drawPath(path, filled ? fill : stroke);
      case SocialGlyph.bookmark:
        final path = _bookmark();
        canvas.drawPath(path, filled ? fill : stroke);
      case SocialGlyph.comment:
        canvas.drawPath(_comment(), stroke);
      case SocialGlyph.reshare:
        canvas.drawPath(_reshare(), stroke);
      case SocialGlyph.send:
        canvas.drawPath(_send(), stroke);
    }

    canvas.restore();
  }

  /// Two lobes meeting at a point, with the dip at the top centred.
  Path _heart() => Path()
    ..moveTo(12, 20.8)
    ..cubicTo(12, 20.8, 3.1, 14.6, 3.1, 8.75)
    ..cubicTo(3.1, 5.6, 5.45, 3.4, 8.15, 3.4)
    ..cubicTo(10.05, 3.4, 11.35, 4.55, 12, 5.75)
    ..cubicTo(12.65, 4.55, 13.95, 3.4, 15.85, 3.4)
    ..cubicTo(18.55, 3.4, 20.9, 5.6, 20.9, 8.75)
    ..cubicTo(20.9, 14.6, 12, 20.8, 12, 20.8)
    ..close();

  /// A round bubble with a tail at the lower left — the gap in the ring is
  /// where the tail joins, so the outline is one continuous stroke.
  Path _comment() {
    const centre = Offset(12.4, 10.9);
    const radius = 8.5;
    // Leave a wedge open at the lower left for the tail to meet.
    const gapStart = 125 * math.pi / 180; // lower-left, going clockwise
    const gapEnd = 168 * math.pi / 180;

    final ring = Rect.fromCircle(center: centre, radius: radius);
    final path = Path()
      ..addArc(ring, gapEnd, 2 * math.pi - (gapEnd - gapStart));

    // The tail: out to a point, then back to where the ring resumes.
    final from = Offset(
      centre.dx + radius * math.cos(gapStart),
      centre.dy + radius * math.sin(gapStart),
    );
    final to = Offset(
      centre.dx + radius * math.cos(gapEnd),
      centre.dy + radius * math.sin(gapEnd),
    );
    path
      ..moveTo(from.dx, from.dy)
      ..lineTo(3.1, 21.2)
      ..lineTo(to.dx, to.dy);
    return path;
  }

  /// Two arrows chasing each other — the repeat glyph, squared off.
  Path _reshare() => Path()
    // Upper arrow: runs left to right along the top, then turns down.
    ..moveTo(4.6, 12.1)
    ..lineTo(4.6, 9.4)
    ..quadraticBezierTo(4.6, 7.3, 6.7, 7.3)
    ..lineTo(17.9, 7.3)
    ..moveTo(14.9, 4.5)
    ..lineTo(18.1, 7.3)
    ..lineTo(14.9, 10.1)
    // Lower arrow: right to left along the bottom, then turns up.
    ..moveTo(19.4, 11.9)
    ..lineTo(19.4, 14.6)
    ..quadraticBezierTo(19.4, 16.7, 17.3, 16.7)
    ..lineTo(6.1, 16.7)
    ..moveTo(9.1, 13.9)
    ..lineTo(5.9, 16.7)
    ..lineTo(9.1, 19.5);

  /// A paper plane: the outline, plus the fold that gives it a near wing.
  Path _send() => Path()
    ..moveTo(21.3, 3.1)
    ..lineTo(2.4, 10.3)
    ..lineTo(10.6, 13.5)
    ..lineTo(13.7, 21.2)
    ..close()
    ..moveTo(21.3, 3.1)
    ..lineTo(10.6, 13.5);

  /// A ribbon with a notch cut out of the bottom.
  Path _bookmark() => Path()
    ..moveTo(5.6, 3.4)
    ..lineTo(18.4, 3.4)
    ..lineTo(18.4, 20.6)
    ..lineTo(12, 15.3)
    ..lineTo(5.6, 20.6)
    ..close();

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.filled != filled;
}
