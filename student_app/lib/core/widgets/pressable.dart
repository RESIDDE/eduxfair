import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/motion.dart';

/// A tap target that answers the instant it is touched.
///
/// Apple's first rule of fluid interfaces is response: the highlight belongs on
/// pointer-*down*, not on release. Material's ink ripple does fire on down, but
/// it reads as a spreading stain on the surface rather than the control itself
/// yielding — and it says nothing on a surface that already has a colour.
///
/// This presses the control itself: a small scale-down that starts on touch,
/// springs back on release, and cancels if the finger slides away. The scale is
/// deliberately slight — 0.97 by default, less for large surfaces — because the
/// point is acknowledgement, not animation.
///
/// Haptics follow Apple's three rules for multimodal feedback: fire on the
/// *causal* event, on the same frame as the visual, and only where they earn
/// their place. The default is `selectionClick`, the lightest tick iOS offers;
/// anything heavier is reserved for commits and is passed in explicitly.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far the control yields. Large surfaces need less: the same ratio on a
  /// full-width card is a lurch, on a 24pt icon it is invisible.
  final double scale;

  /// The tick played on press. Null for none — use it for anything that fires
  /// repeatedly, like scrolling through a list of chips.
  final HapticKind? haptic;

  final BorderRadius? borderRadius;
  final String? semanticLabel;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = HapticKind.selection,
    this.borderRadius,
    this.semanticLabel,
  });

  /// For cards and other large surfaces, where a 3% squeeze is too much.
  const Pressable.surface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = HapticKind.selection,
    this.borderRadius,
    this.semanticLabel,
  }) : scale = 0.99;

  @override
  State<Pressable> createState() => _PressableState();
}

enum HapticKind {
  /// The lightest tick: selecting, toggling, moving between options.
  selection,

  /// A committed action — sending, posting, confirming.
  impact,

  /// Something finished or failed. Used sparingly.
  notify,
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Not a duration in the usual sense: the spring below decides when it
    // settles. This is the bound Flutter needs for an unbounded simulation.
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 220),
  );

  // Critically damped on the way down so the press reads as firm and still,
  // with a little bounce on release — the finger lifting is the momentum that
  // earns it. Apple's own values for a reposition are damping 1.0 / response
  // 0.4; a press is smaller and faster than that.
  late final Animation<double> _scale = _controller.drive(
    Tween<double>(begin: 1, end: widget.scale).chain(
      CurveTween(curve: Curves.easeOutCubic),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _press() {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _controller.forward();
    switch (widget.haptic) {
      case HapticKind.selection:
        HapticFeedback.selectionClick();
      case HapticKind.impact:
        HapticFeedback.lightImpact();
      case HapticKind.notify:
        HapticFeedback.mediumImpact();
      case null:
        break;
    }
  }

  void _release() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;

    Widget content = widget.child;

    // With Reduce Motion on, the control still responds — it just does not
    // move. Reduced motion means a gentler equivalent, never no feedback.
    if (!reduceMotion(context)) {
      content = AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: content,
      );
    }

    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      // `Listener`, not `GestureDetector.onTapDown`.
      //
      // This is the whole point of the widget, and it is easy to get wrong:
      // `onTapDown` does not fire when the finger lands. The tap recognizer
      // holds it until it wins the gesture arena or `kPressTimeout` — 100ms —
      // elapses, whichever comes first. Inside a scrollable it is always the
      // timeout, because the scroll recognizer is competing. A hundred
      // milliseconds is exactly the latency that makes directness "fall off a
      // cliff"; a control built on `onTapDown` feels dead for the first tenth
      // of a second of every press.
      //
      // Raw pointer events have no such delay, so the response is wired to
      // them, and the tap *semantics* — what counts as a tap, when it is
      // cancelled — stay with the GestureDetector underneath where they
      // belong.
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: enabled ? (_) => _press() : null,
        onPointerUp: enabled ? (_) => _release() : null,
        onPointerCancel: enabled ? (_) => _release() : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Sliding off cancels, and the control returns — Apple's
          // cancel-by-dragging-away. Flutter's own slop gives the ~10pt of
          // hysteresis before a tap becomes a drag.
          onTapCancel: enabled ? _release : null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: content,
        ),
      ),
    );
  }
}
