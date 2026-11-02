import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/pressable.dart';
import '../models/post.dart';

/// The row under every post: like, reply, repost and share together on the
/// left, save pushed to the right.
///
/// No view count. It would need an impressions table and a write on every
/// scroll, for a number that flatters the poster and tells a student nothing
/// about whether a scholarship is worth applying for.
class PostActions extends StatelessWidget {
  final Post post;
  final void Function(Post)? onReply;
  final void Function(Post)? onLike;
  final void Function(Post)? onRepost;
  final void Function(Post)? onBookmark;
  final void Function(Post)? onShare;

  const PostActions({
    super.key,
    required this.post,
    this.onReply,
    this.onLike,
    this.onRepost,
    this.onBookmark,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Counts come from the original when this is a plain reshare, so the
    // numbers on a reshared card match the ones on the post itself.
    final counted = post.content;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          // Instagram's order, and its asymmetry: the four that act on the
          // post sit together on the left with their counts beside them, and
          // saving — which acts on *your* account rather than on the post — is
          // pushed to the far right.
          _Action(
            icon: post.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            count: counted.likeCount,
            active: post.liked,
            activeColor: colors.error,
            tooltip: 'Like',
            onTap: onLike == null ? null : () => onLike!(post),
          ),
          _Action(
            icon: Icons.mode_comment_outlined,
            count: counted.commentCount,
            tooltip: 'Reply',
            onTap: onReply == null ? null : () => onReply!(post),
          ),
          _Action(
            icon: Icons.repeat_rounded,
            count: counted.repostCount,
            active: post.repostedByMe,
            activeColor: colors.success,
            tooltip: post.repostedByMe ? 'Undo reshare' : 'Reshare',
            onTap: onRepost == null ? null : () => onRepost!(post),
          ),
          _Action(
            icon: Icons.send_outlined,
            tooltip: 'Share',
            onTap: onShare == null ? null : () => onShare!(post),
          ),
          const Spacer(),
          _Action(
            icon: post.bookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            active: post.bookmarked,
            activeColor: colors.accent,
            tooltip: post.bookmarked ? 'Saved' : 'Save',
            onTap: onBookmark == null ? null : () => onBookmark!(post),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatefulWidget {
  final IconData icon;
  final int? count;
  final bool active;
  final Color? activeColor;
  final String tooltip;
  final VoidCallback? onTap;

  const _Action({
    required this.icon,
    this.count,
    this.active = false,
    this.activeColor,
    required this.tooltip,
    this.onTap,
  });

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action>
    with SingleTickerProviderStateMixin {
  // A like is a small achievement, and Apple reserves overshoot for moments
  // that carried momentum. Turning one *on* gets a brief swell; turning it off
  // does not, because taking something back should not celebrate.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _swell = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.28), weight: 35),
    TweenSequenceItem(
      tween: Tween(begin: 1.28, end: 1.0)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut));

  @override
  void didUpdateWidget(_Action old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final colour =
        widget.active ? (widget.activeColor ?? colors.accent) : colors.textLight;

    return Pressable(
      onTap: widget.onTap,
      // The row is five targets side by side; a scale on each would fight the
      // icon's own swell, so the press shows as the tick alone.
      scale: 1,
      haptic: HapticKind.selection,
      semanticLabel: widget.count == null
          ? widget.tooltip
          : '${widget.tooltip}, ${widget.count}',
      child: Padding(
        // Generous vertical padding: these sit close together and a small
        // icon alone is below the minimum comfortable tap target.
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _swell,
              // Colour crossfades rather than cutting, so the state change
              // reads as the control responding rather than a repaint.
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: colour),
                duration: reduceMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                builder: (_, value, __) =>
                    Icon(widget.icon, size: 17, color: value ?? colour),
              ),
            ),
            if (widget.count != null && widget.count! > 0) ...[
              const SizedBox(width: 6),
              Text(
                _compact(widget.count!),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colour),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// `1.2K`, `48` — the row has five items and no space for a full number.
  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}K';
    if (n < 1000000) return '${(n / 1000).round()}K';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}
