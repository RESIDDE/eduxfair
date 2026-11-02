import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import 'pressable.dart';

/// A back arrow that always goes somewhere.
///
/// Flutter's `BackButton` calls `Navigator.maybePop()`, which does exactly
/// nothing when there is nothing to pop — and with go_router that is common:
/// `context.go` *replaces* the stack, so any screen reached that way shows an
/// arrow that silently ignores every tap. Four auth screens were in that state.
///
/// This pops when it can and navigates to [fallback] when it cannot, so the
/// arrow is never decorative. Apple's wayfinding rule is that every screen
/// answers "how do I get out of here?"; an arrow that lies is worse than no
/// arrow, because the person stops looking for another way.
///
/// Not for tab roots. The five bottom tabs and the organisation's shell tabs
/// are the top of their stacks — there is genuinely nowhere back to, and an
/// arrow there would invent a hierarchy that does not exist.
class AppBackButton extends StatelessWidget {
  /// Where to go when the stack is empty. Defaults to the feed, which is the
  /// app's home for a student.
  final String fallback;

  final String? tooltip;

  const AppBackButton({
    super.key,
    this.fallback = AppConstants.routeFeed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      // Scaled down a little more than a standard control: it is a lone icon,
      // so the squeeze has to be visible at that size.
      scale: 0.86,
      semanticLabel: tooltip ?? 'Back',
      onTap: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(fallback);
        }
      },
      child: const Center(
        child: Icon(Icons.arrow_back_rounded, size: 22),
      ),
    );
  }
}
