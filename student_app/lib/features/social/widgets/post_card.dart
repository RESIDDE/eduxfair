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
/// Laid out like Instagram: a header strip, then full-bleed media, then the
/// action row, then the caption. The media is edge-to-edge rather than inset
/// behind an avatar gutter, which is the whole reason for the change — in the
/// old X-style layout the picture only ever got about 308 of a 390pt phone's
/// width.
///
/// Media is boxed at **4:5** rather than at the image's own ratio — the
/// reference's portrait crop. Used by every feed, the profile and the detail
/// screen, so the anatomy is defined once.
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
    final hasMedia = content.media.isNotEmpty;
    final hasBody = (content.body ?? '').trim().isNotEmpty;

    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
      child: PostActions(
        post: post,
        onReply: onReply,
        onLike: onLike,
        onRepost: onRepost,
        onBookmark: onBookmark,
        onShare: onShare,
      ),
    );

    // Everything that hangs off a post but is not its picture or its words.
    // Inset to the text column; only the media goes edge to edge.
    final extras = <Widget>[
      if (content.tags.isNotEmpty) _Tags(tags: content.tags),
      if (content.linkUrl != null) _LinkPreview(url: content.linkUrl!),
      if (post.isQuote)
        _QuotedPost(
          post: post.reposted!,
          onTap: () => onAuthorTap?.call(post.reposted!.authorHandle),
        ),
      if (content.showsKindChip || content.topics.isNotEmpty)
        _Chips(post: content),
    ];

    return Pressable.surface(
      onTap: expanded ? null : onTap,
      haptic: null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        padding: const EdgeInsets.only(bottom: 10),
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

            // ── Header strip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => onAuthorTap?.call(content.authorHandle),
                    child: InstitutionAvatar(
                      logoUrl: content.authorAvatar,
                      initials: _initials(content.authorName),
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Header(
                      post: content,
                      onAuthorTap: onAuthorTap,
                      onMore: onMore == null ? null : () => onMore!(post),
                    ),
                  ),
                ],
              ),
            ),

            if (hasMedia) ...[
              // The one full-bleed element.
              _Media(media: content.media),
              actions,
              if (hasBody)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
                  child: _Caption(
                    handle: content.authorHandle,
                    body: content.body!,
                    expanded: expanded,
                  ),
                ),
            ] else if (hasBody)
              // No picture to put them under, so the words lead and the
              // actions close the card, as they did before.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Text(
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
              ),

            for (final extra in extras)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: extra,
              ),

            if (!hasMedia) actions,
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
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
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

    Widget tile(PostMedia m) => CachedNetworkImage(
          imageUrl: url(m),
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              ColoredBox(color: context.colors.surfaceVariant),
        );

    final shown = media.take(4).toList();

    return ConstrainedBox(
      // 4:5 of a full-bleed card is about 58% of a phone screen, so the cap
      // has to sit above that or it would crop the ratio back off. It is here
      // for web and tablet widths, where 4:5 of a 900pt column would be twice
      // the height of the window.
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.68),
      child: AspectRatio(
        // Instagram's portrait crop.
        aspectRatio: 4 / 5,
        child: switch (shown.length) {
          1 => tile(shown.first),
          // Two across, each a tall half.
          2 => Row(children: [
              Expanded(child: tile(shown[0])),
              const SizedBox(width: 2),
              Expanded(child: tile(shown[1])),
            ]),
          // One large, two stacked. A 2x2 grid for three images leaves an
          // empty cell, which is what this used to do.
          3 => Row(children: [
              Expanded(child: tile(shown[0])),
              const SizedBox(width: 2),
              Expanded(
                child: Column(children: [
                  Expanded(child: tile(shown[1])),
                  const SizedBox(height: 2),
                  Expanded(child: tile(shown[2])),
                ]),
              ),
            ]),
          _ => Row(children: [
              Expanded(
                child: Column(children: [
                  Expanded(child: tile(shown[0])),
                  const SizedBox(height: 2),
                  Expanded(child: tile(shown[2])),
                ]),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(children: [
                  Expanded(child: tile(shown[1])),
                  const SizedBox(height: 2),
                  Expanded(child: tile(shown[3])),
                ]),
              ),
            ]),
        },
      ),
    );
  }
}

/// The caption, as Instagram sets it: the author's handle in bold, then the
/// words, running straight on from it.
class _Caption extends StatelessWidget {
  final String handle;
  final String body;
  final bool expanded;

  const _Caption({
    required this.handle,
    required this.body,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final span = TextSpan(children: [
      TextSpan(
        text: '$handle  ',
        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      TextSpan(text: body, style: text.bodyLarge),
    ]);

    if (expanded) return Text.rich(span);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured rather than guessed from a character count, so "more" only
        // appears when there actually is more.
        final painter = TextPainter(
          text: span,
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final truncated = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(span, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (truncated)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'more',
                  // Tapping the card already opens the post, so this is a
                  // signpost rather than its own control.
                  style: text.bodySmall?.copyWith(color: colors.textLight),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The @handles a post tags.
class _Tags extends StatelessWidget {
  final List<PostTag> tags;

  const _Tags({required this.tags});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final tag in tags)
          InkWell(
            onTap: () =>
                context.push('${AppConstants.routeHandle}/${tag.handle}'),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: colors.accent.withValues(alpha: 0.25)),
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
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
      ],
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
