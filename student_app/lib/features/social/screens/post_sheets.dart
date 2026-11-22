import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/post.dart';
import '../../passport/providers/passport_provider.dart';
import '../providers/feed_provider.dart';
import 'handle_sheet.dart';

/// The sheets and menus a post card opens.
///
/// Kept together because they are all small, all modal, and all operate on the
/// same provider — scattering them across five files would hide how little
/// each one does.

/// Makes sure the person has a handle before they say something in public.
///
/// `assert_can_write()` refuses a comment or a reshare from an account with no
/// handle, which is right — a reply with no name on it cannot be replied to.
/// But the app used to let them write the whole thing and then fail silently:
/// the sheet's spinner stopped and nothing else happened, which reads as the
/// button being broken.
///
/// Asked for up front instead, and only once. Liking, bookmarking and
/// following need no handle and are deliberately not gated.
Future<bool> _ensureHandle(BuildContext context) async {
  final passport = context.read<PassportProvider>();
  var handle = passport.handle;

  // Null may mean "not loaded yet" rather than "not claimed", and refusing on
  // the first reading would send someone to claim a handle they already have.
  handle ??= await passport.refreshHandle();
  if (handle != null) return true;

  if (!context.mounted) return false;
  final claimed = await openClaimHandleSheet(context);
  return claimed;
}

// ── Reply ───────────────────────────────────────────────────────────────────

Future<void> openReplySheet(
  BuildContext context,
  Post post, {
  PostComment? replyingTo,
}) async {
  if (!await _ensureHandle(context)) return;
  if (!context.mounted) return;

  final target = post.content;
  final isReplyingToComment = replyingTo != null;

  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ComposeSheet(
      title: isReplyingToComment
          ? 'Reply to @${replyingTo.authorHandle}'
          : 'Reply to @${target.authorHandle}',
      hint: isReplyingToComment ? 'Write your reply...' : 'Post your reply',
      quoted: target,
      quotedComment: replyingTo,
      initialText: (isReplyingToComment && replyingTo.parentId != null)
          ? '@${replyingTo.authorHandle} '
          : null,
      onSubmit: (body) => context.read<FeedProvider>().reply(
            target.id,
            body,
            parentId: replyingTo?.parentId ?? replyingTo?.id,
          ),
    ),
  );

  if (sent == true && context.mounted) {
    _toast(context, 'Reply posted.');
  }
}

// ── Repost ──────────────────────────────────────────────────────────────────

/// Reshare, or quote it with a comment — the two things the icon can mean.
Future<void> openRepostSheet(BuildContext context, Post post) async {
  if (!await _ensureHandle(context)) return;
  if (!context.mounted) return;

  final feed = context.read<FeedProvider>();

  // Already reshared: the obvious action is to undo it, with no menu.
  if (post.repostedByMe) {
    await feed.toggleRepost(post);
    if (context.mounted) _toast(context, 'Reshare removed.');
    return;
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: const Text('Reshare'),
            subtitle: const Text('Send this to your followers as it is'),
            onTap: () => Navigator.of(sheetContext).pop('repost'),
          ),
          ListTile(
            leading: const Icon(Icons.format_quote_rounded),
            title: const Text('Reshare with a comment'),
            subtitle: const Text('Add your own words above it'),
            onTap: () => Navigator.of(sheetContext).pop('quote'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return;

  if (choice == 'repost') {
    final ok = await feed.toggleRepost(post);
    if (context.mounted) {
      _toast(context, ok ? 'Reshared.' : feed.error ?? 'Could not reshare.',
          isError: !ok);
    }
    return;
  }

  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ComposeSheet(
      title: 'Reshare with a comment',
      hint: 'Add your thoughts',
      quoted: post.content,
      onSubmit: (body) => feed.toggleRepost(post, quote: body),
    ),
  );

  if (sent == true && context.mounted) _toast(context, 'Reshared.');
}

/// Likes or saves, and says so when it does not work.
///
/// `toggleLike` and `toggleBookmark` patch the card optimistically, put it back
/// when the write fails, and record the reason on the provider — which nothing
/// was reading. A blocked or restricted account saw the heart fill and empty
/// again with no explanation at all.
Future<void> engage(
  BuildContext context,
  Post post,
  Future<void> Function(Post) action,
) async {
  final feed = context.read<FeedProvider>();
  await action(post);
  if (!context.mounted || feed.error == null) return;
  _toast(context, feed.error!, isError: true);
  feed.clearError();
}

// ── Share ───────────────────────────────────────────────────────────────────

/// Copies a link to the post.
///
/// No native share sheet yet: that needs `share_plus`, and a copied link works
/// on all three platforms today including web.
Future<void> sharePost(BuildContext context, Post post) async {
  final target = post.content;
  final link = 'https://connect.educationfair.com.ng/post/${target.id}';

  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) _toast(context, 'Link copied.');
}

// ── The overflow menu ───────────────────────────────────────────────────────

Future<void> openPostMenu(BuildContext context, Post post) async {
  final feed = context.read<FeedProvider>();
  final target = post.content;

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (post.isMine)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: context.colors.error),
              title: Text('Delete',
                  style: TextStyle(color: context.colors.error)),
              subtitle: const Text('This also removes every reshare of it'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.volume_off_rounded),
              title: Text('Mute @${target.authorHandle}'),
              subtitle: const Text('Hide them from your feed; their profile '
                  'stays readable'),
              onTap: () => Navigator.of(sheetContext).pop('mute'),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text('Block @${target.authorHandle}'),
              subtitle: const Text('You disappear from each other entirely'),
              onTap: () => Navigator.of(sheetContext).pop('block'),
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: context.colors.error),
              title: const Text('Report this post'),
              onTap: () => Navigator.of(sheetContext).pop('report'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case 'delete':
      final confirmed = await _confirm(
        context,
        title: 'Delete this post?',
        body: 'It will be removed, and so will every reshare of it.',
        action: 'Delete',
      );
      if (confirmed != true || !context.mounted) return;
      final ok = await feed.removePost(post);
      if (context.mounted) {
        _toast(context, ok ? 'Deleted.' : feed.error ?? 'Could not delete.',
            isError: !ok);
      }

    case 'mute':
      final ok = await feed.mute(target.authorHandle);
      if (context.mounted) {
        _toast(context,
            ok ? 'Muted @${target.authorHandle}.' : feed.error ?? 'Failed.',
            isError: !ok);
      }

    case 'block':
      final confirmed = await _confirm(
        context,
        title: 'Block @${target.authorHandle}?',
        body: 'Neither of you will see the other anywhere, and any follow '
            'between you is removed.',
        action: 'Block',
      );
      if (confirmed != true || !context.mounted) return;
      final ok = await feed.block(target.authorHandle);
      if (context.mounted) {
        _toast(context,
            ok ? 'Blocked @${target.authorHandle}.' : feed.error ?? 'Failed.',
            isError: !ok);
      }

    case 'report':
      await openReportSheet(context, subjectType: 'post', subjectId: target.id);
  }
}

// ── The comment overflow menu ──────────────────────────────────────────────

Future<void> openCommentMenu(
  BuildContext context, {
  required Post post,
  required PostComment comment,
  required VoidCallback onDeleted,
}) async {
  final feed = context.read<FeedProvider>();

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (comment.isMine)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: context.colors.error),
              title: Text('Delete comment',
                  style: TextStyle(color: context.colors.error)),
              subtitle: const Text('Remove your comment from this post'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.volume_off_rounded),
              title: Text('Mute @${comment.authorHandle}'),
              subtitle: const Text('Hide them from your feed'),
              onTap: () => Navigator.of(sheetContext).pop('mute'),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text('Block @${comment.authorHandle}'),
              subtitle: const Text('You disappear from each other entirely'),
              onTap: () => Navigator.of(sheetContext).pop('block'),
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: context.colors.error),
              title: const Text('Report this comment'),
              onTap: () => Navigator.of(sheetContext).pop('report'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case 'delete':
      final confirmed = await _confirm(
        context,
        title: 'Delete this comment?',
        body: 'It will be permanently removed from this post.',
        action: 'Delete',
      );
      if (confirmed != true || !context.mounted) return;
      final ok = await feed.removeComment(comment.id, post.id);
      if (context.mounted) {
        if (ok) {
          _toast(context, 'Comment deleted.');
          onDeleted();
        } else {
          _toast(context, feed.error ?? 'Could not delete comment.',
              isError: true);
        }
      }

    case 'mute':
      final ok = await feed.mute(comment.authorHandle);
      if (context.mounted) {
        _toast(
          context,
          ok ? 'Muted @${comment.authorHandle}.' : feed.error ?? 'Failed.',
          isError: !ok,
        );
      }

    case 'block':
      final confirmed = await _confirm(
        context,
        title: 'Block @${comment.authorHandle}?',
        body: 'Neither of you will see the other anywhere.',
        action: 'Block',
      );
      if (confirmed != true || !context.mounted) return;
      final ok = await feed.block(comment.authorHandle);
      if (context.mounted) {
        _toast(
          context,
          ok ? 'Blocked @${comment.authorHandle}.' : feed.error ?? 'Failed.',
          isError: !ok,
        );
      }

    case 'report':
      await openReportSheet(context,
          subjectType: 'comment', subjectId: comment.id);
  }
}


// ── Report ──────────────────────────────────────────────────────────────────

const _reportReasons = <String, String>{
  'spam': 'Spam',
  'harassment': 'Harassment or bullying',
  'misinformation': 'False information',
  'impersonation': 'Pretending to be someone else',
  'inappropriate': 'Inappropriate content',
  'child_safety': 'A young person is at risk',
  'other': 'Something else',
};

/// The reason list, shared by every report in the app.
///
/// One list rather than one per surface, so a post, a comment and an account
/// are all reported against the same taxonomy — which is what makes the
/// moderation queue sortable.
/// Public so the chat screen reports against the same list.
Future<String?> pickReportReason(BuildContext context) => _pickReportReason(context);

Future<String?> _pickReportReason(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('What is wrong with it?',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'An Eduxfair reviewer reads every report. The person you '
                'report is never told who reported them.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ),
            ..._reportReasons.entries.map(
              (e) => ListTile(
                title: Text(e.value),
                // Child safety is routed ahead of everything else in the
                // queue, and saying so is part of why someone bothers to
                // report it.
                subtitle: e.key == 'child_safety'
                    ? const Text('Reviewed first, ahead of everything else')
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(e.key),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

Future<void> openReportSheet(
  BuildContext context, {
  required String subjectType,
  required String subjectId,
}) async {
  final reason = await _pickReportReason(context);
  if (reason == null || !context.mounted) return;

  final feed = context.read<FeedProvider>();
  final ok = await feed.report(
    subjectType: subjectType,
    subjectId: subjectId,
    reason: reason,
  );

  if (!context.mounted) return;
  _toast(
    context,
    ok
        ? 'Reported. Thank you — we will look at it.'
        : feed.error ?? 'Could not send that report.',
    isError: !ok,
  );
}

// ── Shared pieces ───────────────────────────────────────────────────────────

/// A text field over a quoted post or comment, used by reply and quote-reshare.
class _ComposeSheet extends StatefulWidget {
  final String title;
  final String hint;
  final Post? quoted;
  final PostComment? quotedComment;
  final String? initialText;
  final Future<bool> Function(String body) onSubmit;

  const _ComposeSheet({
    required this.title,
    required this.hint,
    this.quoted,
    this.quotedComment,
    this.initialText,
    required this.onSubmit,
  });

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  // Owned here, not by the caller.
  //
  // `showModalBottomSheet`'s future completes the moment the route is popped,
  // while the sheet is still on screen animating out — so a caller that
  // disposed the controller right after the await was pulling it out from
  // under a TextField that was still listening to it.
  late final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _controller.text = widget.initialText!;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final body = _controller.text.trim();

    return Padding(
      // So the keyboard never covers the field being typed into.
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: text.titleLarge),
              const SizedBox(height: 14),

              if (widget.quotedComment != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InstitutionAvatar(
                        logoUrl: widget.quotedComment!.authorAvatar,
                        initials: widget.quotedComment!.authorName.isEmpty
                            ? '?'
                            : widget.quotedComment!.authorName[0].toUpperCase(),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.quotedComment!.authorName,
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.quotedComment!.authorVerified) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.verified_rounded,
                                      size: 13, color: colors.success),
                                ],
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '@${widget.quotedComment!.authorHandle}',
                                    style: text.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.quotedComment!.body,
                              style: text.bodySmall?.copyWith(height: 1.4),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else if (widget.quoted != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InstitutionAvatar(
                        logoUrl: widget.quoted!.authorAvatar,
                        initials: widget.quoted!.authorName.isEmpty
                            ? '?'
                            : widget.quoted!.authorName[0].toUpperCase(),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.quoted!.authorName,
                                style: text.titleSmall),
                            if ((widget.quoted!.body ?? '').isNotEmpty)
                              Text(
                                widget.quoted!.body!,
                                style: text.bodySmall?.copyWith(height: 1.4),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 8),
              Row(
                children: [
                  Text('${body.length}/2000', style: text.labelSmall),
                  const Spacer(),
                  FilledButton(
                    onPressed: body.isEmpty || _sending
                        ? null
                        : () async {
                            setState(() => _sending = true);
                            final ok = await widget.onSubmit(body);
                            if (!context.mounted) return;
                            if (ok) {
                              Navigator.of(context).pop(true);
                            } else {
                              setState(() => _sending = false);
                              // Previously the spinner simply stopped, which
                              // looks exactly like a dead button. Rate limits,
                              // reply policies and restrictions all land here
                              // and each has something worth reading.
                              final feed = context.read<FeedProvider>();
                              _toast(
                                context,
                                feed.error ?? 'Could not post that.',
                                isError: true,
                              );
                              feed.clearError();
                            }
                          },
                    child: _sending
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.colors.onAccent),
                          )
                        : const Text('Post'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: Text(action),
          ),
        ],
      ),
    );

void _toast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? context.colors.error : null,
    ),
  );
}

// ── The account overflow menu ──────────────────────────────────────────────

/// Report, mute or block a person, from their profile.
///
/// Guideline 1.2 asks for a way to report offensive content and to block
/// abusive users. Posts and comments already had both; an account did not, so
/// the only way to act on someone who was harassing you in several places was
/// to find one of their posts first.
Future<void> openAccountMenu(
  BuildContext context, {
  required String handle,
  required bool isSelf,
}) async {
  if (isSelf) return;

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.volume_off_rounded),
            title: Text('Mute @$handle'),
            subtitle: const Text('They disappear from your feed.'),
            onTap: () => Navigator.of(sheetContext).pop('mute'),
          ),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: Text('Block @$handle'),
            subtitle: const Text(
                'Neither of you sees the other anywhere, and any follow '
                'between you is removed.'),
            onTap: () => Navigator.of(sheetContext).pop('block'),
          ),
          ListTile(
            leading: Icon(Icons.flag_outlined,
                color: Theme.of(sheetContext).colorScheme.error),
            title: const Text('Report this account'),
            onTap: () => Navigator.of(sheetContext).pop('report'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;
  final feed = context.read<FeedProvider>();

  switch (action) {
    case 'mute':
      final ok = await feed.moderateHandle(handle, 'mute');
      if (context.mounted) {
        _toast(context, ok ? 'Muted @$handle.' : feed.error ?? 'Failed.',
            isError: !ok);
      }

    case 'block':
      final confirmed = await _confirm(
        context,
        title: 'Block @$handle?',
        body: 'Neither of you will see the other anywhere, and any follow '
            'between you is removed. You can undo this in Settings → '
            'Blocked accounts.',
        action: 'Block',
      );
      if (confirmed != true || !context.mounted) return;
      final ok = await feed.moderateHandle(handle, 'block');
      if (context.mounted) {
        _toast(context, ok ? 'Blocked @$handle.' : feed.error ?? 'Failed.',
            isError: !ok);
      }

    case 'report':
      await openAccountReportSheet(context, handle: handle);
  }
}

/// The same reason list as every other report, filed against an account.
///
/// Goes through `report_handle` rather than the generic path because the
/// client has no profile id to name — `social_profiles.profile_id` is never
/// exposed by a public view, so the handle is resolved inside the database.
Future<void> openAccountReportSheet(
  BuildContext context, {
  required String handle,
}) async {
  final reason = await _pickReportReason(context);
  if (reason == null || !context.mounted) return;

  try {
    await SupabaseService.instance.client.rpc(
      'report_handle',
      params: {'p_handle': handle, 'p_reason': reason},
    );
    if (context.mounted) {
      _toast(context,
          'Reported. Someone will look at it — thank you for telling us.');
    }
  } catch (e) {
    if (context.mounted) {
      _toast(context, SupabaseService.describeError(e), isError: true);
    }
  }
}
