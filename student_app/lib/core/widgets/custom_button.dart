import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../utils/dynamic_type.dart';

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final Widget? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? width;
  final double height;
  final double borderRadius;

  const CustomButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.width,
    this.height = 54,
    this.borderRadius = 14,
  });

  const CustomButton.outlined({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.width,
    this.height = 54,
    this.borderRadius = 14,
  }) : isOutlined = true;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? (isOutlined ? Colors.transparent : context.colors.accent);
    // The accent inverts between themes — black on light, white on dark — so
    // the filled button's foreground has to come from the theme too.
    //
    // Disabled is its own case, and was wrong in both themes: the fill drops
    // to `border` while the label stayed `onAccent`, giving white-on-light-grey
    // in light and near-black-on-dark-grey in dark. Neither was readable.
    // `textLight` is the muted-but-legible colour the themes already use for
    // `disabledForegroundColor`.
    final disabled = onPressed == null || isLoading;
    final fg = foregroundColor ??
        (disabled
            ? context.colors.textLight
            : isOutlined
                ? context.colors.accent
                : context.colors.onAccent);

    final child = isLoading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: isOutlined ? context.colors.accent : context.colors.onAccent,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[icon!, SizedBox(width: 8)],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      side: isOutlined ? BorderSide(color: context.colors.border, width: 1.5) : BorderSide.none,
    );

    return SizedBox(
      width: width ?? double.infinity,
      // Grown with the reader's text size: a 54pt box around 22pt text clips.
      height: context.scaled(height),
      child: isOutlined
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: fg,
                side: BorderSide(color: context.colors.border, width: 1.5),
                shape: shape,
                padding: EdgeInsets.zero,
              ),
              child: child,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: disabled ? null : context.colors.accentGradient,
                color: disabled ? context.colors.surfaceVariant : null,
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: !disabled
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        )
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: isLoading ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
                  padding: EdgeInsets.zero,
                  minimumSize: Size(width ?? double.infinity, height),
                ),
                child: child,
              ),
            ),
    );
  }
}
