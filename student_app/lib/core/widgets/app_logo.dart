import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Renders the official Eduxfair application logo.
class EduxfairLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showWordmark;
  final TextStyle? wordmarkStyle;
  final bool isHorizontal;
  final double spacing;

  const EduxfairLogo({
    super.key,
    this.size = 64,
    this.borderRadius = 18,
    this.showWordmark = false,
    this.wordmarkStyle,
    this.isHorizontal = false,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final logoWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        AppConstants.appLogoPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );

    if (!showWordmark) {
      return logoWidget;
    }

    final effectiveStyle = wordmarkStyle ??
        Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            );

    final textWidget = Text(
      AppConstants.appName,
      style: effectiveStyle,
    );

    if (isHorizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logoWidget,
          SizedBox(width: spacing),
          textWidget,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logoWidget,
        SizedBox(height: spacing),
        textWidget,
      ],
    );
  }
}
