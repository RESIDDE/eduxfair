import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';

/// A rounded-square button for the top chrome — the `+` and the avatar either
/// side of the wordmark.
///
/// Deliberately **not** a second [MaterialSurface]. These sit on top of the
/// glass header, and a `BackdropFilter` inside a `BackdropFilter` samples the
/// already-blurred layer rather than the content: it costs twice as much and
/// comes out muddy. A translucent tint over the glass gives the same raised
/// chip the reference shows, for one cheap draw.
class ChromeButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  /// The side of the square. The child is centred in it.
  final double size;

  const ChromeButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.size = 38,
  });

  /// The common case: a glyph.
  factory ChromeButton.icon({
    Key? key,
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    double size = 38,
  }) =>
      ChromeButton(
        key: key,
        onTap: onTap,
        tooltip: tooltip,
        size: size,
        child: Icon(icon, size: 22),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onTap,
          haptic: HapticKind.selection,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconTheme.merge(
              data: IconThemeData(color: colors.textPrimary),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
