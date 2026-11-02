import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/pressable.dart';
import '../models/post.dart';
import '../providers/feed_provider.dart';
import '../widgets/post_card.dart';
import 'post_sheets.dart';

/// One post and its replies in threaded conversation view.
///
/// Top-level comments are grouped with their nested replies, connected
/// by sleek thread lines and complete with inline reply actions,
/// comment likes, and author highlights.
class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  List<PostComment> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final feed = context.read<FeedProvider>();
    final post = await feed.postById(widget.postId);
    final comments = await feed.comments(widget.postId);

    if (!mounted) return;
    setState(() {
      _post = post;
      _comments = comments;
      _loading = false;
    });
  }

  void _toggleCommentLike(PostComment comment) async {
    final index = _comments.indexWhere((c) => c.id == comment.id);
    if (index == -1) return;

    final wasLiked = comment.liked;
    final newCount = (comment.likeCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);

    setState(() {
      _comments[index] = comment.copyWith(liked: !wasLiked, likeCount: newCount);
    });

    final feed = context.read<FeedProvider>();
    final ok = await feed.toggleCommentLike(comment);
    if (!ok && mounted) {
      setState(() {
        _comments[index] = comment;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final feed = context.read<FeedProvider>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final post = _post;
    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post')),
        body: const EmptyState(
          icon: Icons.highlight_off_rounded,
          title: 'This post is gone',
          message: 'It may have been deleted, or you may not be able to see it.',
        ),
      );
    }

    // Separate root comments and group their child replies
    final rootComments = _comments
        .where((c) =>
            c.parentId == null ||
            !_comments.any((parent) => parent.id == c.parentId))
        .toList();

    final repliesByParent = <String, List<PostComment>>{};
    for (final c in _comments) {
      if (c.parentId != null && _comments.any((p) => p.id == c.parentId)) {
        repliesByParent.putIfAbsent(c.parentId!, () => []).add(c);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            PostCard(
              post: post,
              expanded: true,
              onAuthorTap: (h) => context.push('${AppConstants.routeHandle}/$h'),
              onLike: (p) async {
                await engage(context, p, feed.toggleLike);
                _load();
              },
              onBookmark: (p) async {
                await engage(context, p, feed.toggleBookmark);
                _load();
              },
              onReply: (p) async {
                await openReplySheet(context, p);
                _load();
              },
              onRepost: (p) async {
                await openRepostSheet(context, p);
                _load();
              },
              onShare: (p) => sharePost(context, p),
              onMore: (p) async {
                await openPostMenu(context, p);
                if (mounted) _load();
              },
            ),

            // Replies header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.divider.withValues(alpha: 0.5)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'Replies',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_comments.length}',
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_comments.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 38,
                      color: colors.textSecondary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text('No replies yet', style: text.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      post.replyPolicy == 'everyone'
                          ? 'Be the first to reply to this post.'
                          : 'The author has limited who can reply.',
                      style: text.bodySmall?.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...rootComments.map((rootComment) {
                final replies = repliesByParent[rootComment.id] ?? const [];
                return _CommentThread(
                  post: post,
                  comment: rootComment,
                  replies: replies,
                  onReplyToComment: (targetComment) async {
                    await openReplySheet(context, post, replyingTo: targetComment);
                    _load();
                  },
                  onToggleLike: _toggleCommentLike,
                  onAuthorTap: (handle) =>
                      context.push('${AppConstants.routeHandle}/$handle'),
                  onCommentDeleted: _load,
                );
              }),

            const SizedBox(height: 90),
          ],
        ),
      ),

      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border(top: BorderSide(color: colors.divider)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: InkWell(
            onTap: () async {
              await openReplySheet(context, post);
              _load();
            },
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.divider.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 17,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Post your reply...',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 15,
                      color: colors.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A top-level comment card and its attached replies thread.
class _CommentThread extends StatefulWidget {
  final Post post;
  final PostComment comment;
  final List<PostComment> replies;
  final void Function(PostComment) onReplyToComment;
  final void Function(PostComment) onToggleLike;
  final void Function(String handle) onAuthorTap;
  final VoidCallback onCommentDeleted;

  const _CommentThread({
    required this.post,
    required this.comment,
    required this.replies,
    required this.onReplyToComment,
    required this.onToggleLike,
    required this.onAuthorTap,
    required this.onCommentDeleted,
  });

  @override
  State<_CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<_CommentThread> {
  bool _showReplies = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasReplies = widget.replies.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider.withValues(alpha: 0.6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top-level comment
          _CommentItem(
            post: widget.post,
            comment: widget.comment,
            isReply: false,
            hasRepliesBelow: hasReplies && _showReplies,
            onReplyTap: () => widget.onReplyToComment(widget.comment),
            onLikeTap: () => widget.onToggleLike(widget.comment),
            onAuthorTap: () => widget.onAuthorTap(widget.comment.authorHandle),
            onDeleted: widget.onCommentDeleted,
          ),

          // Replies list if any
          if (hasReplies) ...[
            if (!_showReplies)
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: 12),
                child: GestureDetector(
                  onTap: () => setState(() => _showReplies = true),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 1.5,
                        color: colors.divider,
                        margin: const EdgeInsets.only(right: 8),
                      ),
                      Text(
                        'View ${widget.replies.length} ${widget.replies.length == 1 ? 'reply' : 'replies'}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ...widget.replies.asMap().entries.map((entry) {
                final index = entry.key;
                final reply = entry.value;
                final isLast = index == widget.replies.length - 1;

                return _CommentItem(
                  post: widget.post,
                  comment: reply,
                  isReply: true,
                  isLastReply: isLast,
                  onReplyTap: () => widget.onReplyToComment(reply),
                  onLikeTap: () => widget.onToggleLike(reply),
                  onAuthorTap: () => widget.onAuthorTap(reply.authorHandle),
                  onDeleted: widget.onCommentDeleted,
                );
              }),
            ],
          ],
        ],
      ),
    );
  }
}

/// A single comment or reply item with avatar, metadata, body and actions.
class _CommentItem extends StatelessWidget {
  final Post post;
  final PostComment comment;
  final bool isReply;
  final bool hasRepliesBelow;
  final bool isLastReply;
  final VoidCallback onReplyTap;
  final VoidCallback onLikeTap;
  final VoidCallback onAuthorTap;
  final VoidCallback onDeleted;

  const _CommentItem({
    required this.post,
    required this.comment,
    required this.isReply,
    this.hasRepliesBelow = false,
    this.isLastReply = false,
    required this.onReplyTap,
    required this.onLikeTap,
    required this.onAuthorTap,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final isPostAuthor = comment.authorHandle.toLowerCase() ==
        post.content.authorHandle.toLowerCase();

    final avatarSize = isReply ? 28.0 : 34.0;
    final leftPadding = isReply ? 44.0 : 16.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(leftPadding, isReply ? 8 : 12, 16, isReply ? 8 : 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Subtle vertical thread line connecting parent to replies
          if (hasRepliesBelow)
            Positioned(
              left: 17,
              top: 36,
              bottom: -16,
              child: Container(
                width: 1.5,
                color: colors.divider,
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onAuthorTap,
                child: InstitutionAvatar(
                  logoUrl: comment.authorAvatar,
                  initials: comment.authorName.isEmpty
                      ? '?'
                      : comment.authorName[0].toUpperCase(),
                  size: avatarSize,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author metadata row
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onAuthorTap,
                            child: Text(
                              comment.authorName,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: isReply ? 13 : 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (comment.authorVerified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            size: 13,
                            color: colors.success,
                          ),
                        ],
                        if (isPostAuthor) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Author',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Flexible(
                          child: GestureDetector(
                            onTap: onAuthorTap,
                            child: Text(
                              '@${comment.authorHandle}',
                              style: text.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                fontSize: isReply ? 12 : 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Text(
                          ' · ${formatRelative(comment.createdAt)}',
                          style: text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: isReply ? 12 : 13,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 3),

                    // Comment body
                    SelectableText(
                      comment.body,
                      style: (isReply ? text.bodySmall : text.bodyMedium)?.copyWith(
                        height: 1.42,
                        color: colors.textPrimary,
                        fontSize: isReply ? 13.5 : 14.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Actions row: Reply, Like, and More options
                    Row(
                      children: [
                        // Reply action button
                        Pressable(
                          onTap: onReplyTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.reply_rounded,
                                  size: 14,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Reply',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 14),

                        // Like action button
                        Pressable(
                          onTap: onLikeTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  comment.liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 15,
                                  color: comment.liked
                                      ? colors.error
                                      : colors.textSecondary,
                                ),
                                if (comment.likeCount > 0) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '${comment.likeCount}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: comment.liked
                                          ? colors.error
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        const Spacer(),

                        // More overflow menu
                        Pressable(
                          onTap: () => openCommentMenu(
                            context,
                            post: post,
                            comment: comment,
                            onDeleted: onDeleted,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              size: 16,
                              color: colors.textSecondary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
