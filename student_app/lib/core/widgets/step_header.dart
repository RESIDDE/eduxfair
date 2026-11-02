import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "STEP 1 OF 2" with a two-segment progress rule.
///
/// Shared by both halves of institution sign-up, which are two separate
/// screens reached by two different routes — the second one is also reachable
/// on its own, so without this the person has no way to tell whether they are
/// mid-flow or looking at an unexpected extra form.
class StepHeader extends StatelessWidget {
  final int step;
  final int of;
  final String label;

  const StepHeader({
    super.key,
    required this.step,
    required this.label,
    this.of = 2,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          'STEP $step OF $of',
          style: text.labelSmall?.copyWith(
            color: colors.textLight,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              for (var i = 1; i <= of; i++) ...[
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= step ? colors.accent : colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < of) const SizedBox(width: 5),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: text.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
