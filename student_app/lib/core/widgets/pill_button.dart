import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';

/// The app's button shape: a capsule, filled in the text colour for the one
/// main action on a screen, a quiet grey for the rest.
///
/// Black-on-white in light mode and white-on-black in dark — the main action
/// is the most contrasting thing on the page without borrowing the link blue.
class PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool primary;
  final bool busy;
  final double height;
  final VoidCallback? onTap;

  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.primary = false,
    this.busy = false,
    this.height = 48,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = primary ? colors.background : colors.textPrimary;
    final enabled = onTap != null && !busy;

    return Pressable(
      onTap: enabled ? onTap : null,
      haptic: primary ? HapticKind.impact : HapticKind.selection,
      semanticLabel: label,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: onTap == null ? 0.45 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: primary ? colors.textPrimary : colors.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                )
              else ...[
                if (icon != null) ...[
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
