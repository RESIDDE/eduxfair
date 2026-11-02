import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';
import '../models/post.dart';
import 'post_actions.dart';

/// One post in a feed.
///
/// Laid out like the X reference: avatar in a left gutter, everything else in a
/// column beside it, and a single row of actions underneath. Used by every
/// feed, the profile and the detail screen, so the anatomy is defined once.
class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  final void Function(String handle)? onAuthorTap;
  final void Function(Post post)? onReply;
  final void Function(Post post)? onLike;
  final void Function(Post post)? onRepost;
  final void Function(Post post)? onBookmark;
  final void Function(Post post)? onShare;
  final void Function(Post post)? onMore;

  /// The detail screen renders the body larger and drops the tap target.
  final bool expanded;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onAuthorTap,
    this.onReply,
    this.onLike,
    this.onRepost,
    this.onBookmark,
    this.onShare,
    this.onMore,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // A plain reshare shows the original with a line above saying who shared
    // it; a quote is its own post with the original embedded below.
    final content = post.content;

    return Pressable.surface(
      onTap: expanded ? null : onTap,
      haptic: null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.isRepost && !post.isQuote)
              _ContextLine(
                icon: Icons.repeat_rounded,
                text: '${post.authorName} reshared',
              ),
            if (post.isPinned)
              const _ContextLine(icon: Icons.push_pin_rounded, text: 'Pinned'),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => onAuthorTap?.call(content.authorHandle),
                  child: InstitutionAvatar(
                    logoUrl: content.authorAvatar,
                    initials: _initials(content.authorName),
                    size: 42,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        post: content,
                        onAuthorTap: onAuthorTap,
                        onMore: onMore == null ? null : () => onMore!(post),
                      ),

                      if ((content.body ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          content.body!,
                          style: expanded
                              ? Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(height: 1.45)
                              : Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(height: 1.4),
                        ),
                      ],

                      if (content.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in content.tags)
                              InkWell(
                                onTap: () => context.push(
                                    '${AppConstants.routeHandle}/${tag.handle}'),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        colors.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          colors.accent.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        tag.isInstitution
                                            ? Icons.apartment_rounded
                                            : Icons.person_rounded,
                                        size: 13,
                                        color: colors.accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '@${tag.handle}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],

                      if (content.media.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Media(media: content.media),
                      ],

                      if (content.linkUrl != null) ...[
                        const SizedBox(height: 10),
                        _LinkPreview(url: content.linkUrl!),
                      ],

                      // A quote shows the original in a bordered card below.
                      if (post.isQuote) ...[
                        const SizedBox(height: 10),
                        _QuotedPost(
                          post: post.reposted!,
                          onTap: () =>
                              onAuthorTap?.call(post.reposted!.authorHandle),
                        ),
                      ],

                      if (content.showsKindChip || content.topics.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _Chips(post: content),
                      ],

                      PostActions(
                        post: post,
                        onReply: onReply,
                        onLike: onLike,
                        onRepost: onRepost,
                        onBookmark: onBookmark,
                        onShare: onShare,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'))
        .where((p) => p.length > 2)
        .toList();
    if (parts.isEmpty) return name.isEmpty ? '?' : name[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Post post;
  final void Function(String handle)? onAuthorTap;
  final VoidCallback? onMore;

  const _Header({required this.post, this.onAuthorTap, this.onMore});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        // Who gives up space first, in order: the handle, then the name.
        // Never the tick, and never the time.
        //
        // Two loose Flexibles with equal flex each get *half* the free width,
        // so "Maplecrest University" and "@maplecrest" both ellipsised — to
        // "Maple…" and "@maple…" — on a 390pt phone with room to spare.
        // Weighting them 3:1 gives the name the room it needs while the handle
        // keeps enough to stay recognisable.
        //
        // The badge sits between them as a fixed child rather than inside
        // either text, so truncation can never eat it: it is the one mark on
        // the card that says this institution is who it claims to be.
        Flexible(
          flex: 3,
          child: GestureDetector(
            onTap: () => onAuthorTap?.call(post.authorHandle),
            child: Text(
              post.authorName,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (post.authorVerified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(
            subject: post.isOrganisation
                ? VerifiedSubject.institution
                : VerifiedSubject.student,
            compact: true,
          ),
        ],
        const SizedBox(width: 5),
        Flexible(
          child: GestureDetector(
            onTap: () => onAuthorTap?.call(post.authorHandle),
            child: Text(
              '@${post.authorHandle}',
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Kept outside the ellipsis budget: when a post was written is never
        // the thing worth dropping.
        Text(' · ${formatRelative(post.createdAt)}', style: text.bodySmall),
        const Spacer(),
        if (onMore != null)
          GestureDetector(
            onTap: onMore,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              // A small icon needs a real tap target around it.
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.more_horiz_rounded,
                  size: 18, color: colors.textLight),
            ),
          ),
      ],
    );
  }
}

class _ContextLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ContextLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      // Indented to sit above the body column, not the avatar gutter.
      padding: const EdgeInsets.only(left: 38, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: colors.textLight),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Media ───────────────────────────────────────────────────────────────────

class _Media extends StatelessWidget {
  final List<PostMedia> media;

  const _Media({required this.media});

  @override
  Widget build(BuildContext context) {
    final service = SupabaseService.instance;
    String url(PostMedia m) => service.publicUrl(
          bucket: AppConstants.bucketPostMedia,
          path: m.storagePath,
        );

    if (media.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: media.first.aspectRatio,
          child: CachedNetworkImage(
            imageUrl: url(media.first),
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                Container(color: context.colors.surfaceVariant),
          ),
        ),
      );
    }

    // Two across, square-ish, as the reference does for multiples.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: media
            .take(4)
            .map((m) => CachedNetworkImage(
                  imageUrl: url(m),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: context.colors.surfaceVariant),
                ))
            .toList(),
      ),
    );
  }
}

class _LinkPreview extends StatelessWidget {
  final String url;

  const _LinkPreview({required this.url});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final host = Uri.tryParse(url)?.host ?? url;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              host,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.open_in_new_rounded, size: 14, color: colors.textLight),
        ],
      ),
    );
  }
}

class _QuotedPost extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;

  const _QuotedPost({required this.post, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Pressable.surface(
      onTap: onTap,
      haptic: null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InstitutionAvatar(
                  logoUrl: post.authorAvatar,
                  initials: post.authorName.isEmpty
                      ? '?'
                      : post.authorName[0].toUpperCase(),
                  size: 20,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    post.authorName,
                    style: text.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (post.authorVerified) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.verified_rounded,
                      size: 12, color: colors.success),
                ],
                const SizedBox(width: 5),
                Text('@${post.authorHandle}', style: text.labelSmall),
              ],
            ),
            if ((post.body ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                post.body!,
                style: text.bodySmall?.copyWith(height: 1.4),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  final Post post;

  const _Chips({required this.post});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    Widget chip(String label, Color fg, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: text.labelSmall
                ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (post.showsKindChip)
          chip(
            post.kindLabel,
            post.kind == 'announcement' ? colors.warning : colors.accent,
            post.kind == 'announcement' ? colors.warningLight : colors.infoLight,
          ),
        ...post.topics
            .where((t) => t.isCountry)
            .map((t) => chip(
                t.countryLabel, colors.textSecondary, colors.surfaceVariant)),
      ],
    );
  }
}
