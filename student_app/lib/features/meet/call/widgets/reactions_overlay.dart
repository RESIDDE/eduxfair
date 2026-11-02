import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../call_provider.dart';

/// Reactions float up and remove themselves.
///
/// Wrapped in IgnorePointer: a reaction drifting across the controls must never
/// be the thing that swallows a tap on Leave.
class ReactionsOverlay extends StatelessWidget {
  final List<FloatingReaction> reactions;
  const ReactionsOverlay({super.key, required this.reactions});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final (index, reaction) in reactions.indexed)
            Positioned(
              left: 24 + ((index * 53) % 220),
              bottom: 24,
              child: Text(
                reaction.emoji,
                style: const TextStyle(fontSize: 34),
              )
                  .animate()
                  .fadeIn(duration: 200.ms)
                  .moveY(begin: 0, end: -300, duration: 3.seconds, curve: Curves.easeOut)
                  .fadeOut(delay: 2.2.seconds, duration: 800.ms),
            ),
        ],
      ),
    );
  }
}
