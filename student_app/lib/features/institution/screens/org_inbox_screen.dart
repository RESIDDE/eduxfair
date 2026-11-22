import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pressable.dart';
import '../../messages/screens/chat_screen.dart';
import '../models/pipeline.dart';
import '../providers/org_desk_provider.dart';
import '../widgets/org_ui.dart';

/// The institution's side of messaging.
///
/// Students are listed by their match token until they share a passport. That
/// is not a limitation to work around — it is the same guarantee the match
/// cards make, and it means an admissions officer can hold a whole
/// conversation with someone whose identity they have not been given.
class OrgInboxScreen extends StatefulWidget {
  const OrgInboxScreen({super.key});

  @override
  State<OrgInboxScreen> createState() => _OrgInboxScreenState();
}

class _OrgInboxScreenState extends State<OrgInboxScreen> {
  final _search = TextEditingController();

  /// Typing is not a search. The name half filters locally on every keystroke;
  /// only the message-body half waits, so the server sees one query per pause
  /// rather than one per letter.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OrgDeskProvider>().load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) context.read<OrgDeskProvider>().searchInbox(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    context.read<OrgDeskProvider>().clearInboxSearch();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final desk = context.watch<OrgDeskProvider>();
    final archivedCount = desk.archivedCount;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('Inbox'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Open'),
              Tab(text: archivedCount > 0 ? 'Archived  $archivedCount' : 'Archived'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search students and messages',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: _clear,
                          tooltip: 'Clear',
                        ),
                  isDense: true,
                ),
              ),
            ),
            if (desk.inboxSearching)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: desk.loading && desk.threads.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : desk.error != null && desk.threads.isEmpty
                  ? ErrorState(message: desk.error!, onRetry: desk.load)
                  : TabBarView(
                      children: [
                        _ThreadList(
                          key: const PageStorageKey('org_inbox_open'),
                          rows: desk.inbox,
                          archivedTab: false,
                          searching: _search.text.trim().isNotEmpty,
                        ),
                        _ThreadList(
                          key: const PageStorageKey('org_inbox_archived'),
                          rows: desk.archivedThreads,
                          archivedTab: true,
                          searching: _search.text.trim().isNotEmpty,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadList extends StatelessWidget {
  final List<InboxThread> rows;
  final bool archivedTab;
  final bool searching;

  const _ThreadList({
    super.key,
    required this.rows,
    required this.archivedTab,
    required this.searching,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final desk = context.read<OrgDeskProvider>();

    if (rows.isEmpty) {
      // Three different nothings, and conflating them is how an empty list
      // reads as a broken one.
      final empty = searching
          ? const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matched',
              message:
                  'Search looks at the student and at what has been said '
                  'in the thread.',
            )
          : archivedTab
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Nothing archived',
              message:
                  'Archiving moves a thread off your Open tab without '
                  'deleting anything, and only you see the change.',
            )
          : const EmptyState(
              icon: Icons.forum_outlined,
              title: 'No messages yet',
              message:
                  'When a student writes to you, or replies to an '
                  'invitation, the conversation appears here.',
            );

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 24), empty],
      );
    }

    return RefreshIndicator(
      onRefresh: desk.load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: colors.divider,
          indent: 78,
        ),
        itemBuilder: (_, i) => _Thread(thread: rows[i]),
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  final InboxThread thread;

  const _Thread({required this.thread});

  Future<void> _actions(BuildContext context, InboxThread thread) async {
    final desk = context.read<OrgDeskProvider>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(thread.isShared
                  ? Icons.badge_outlined
                  : Icons.folder_open_outlined),
              title: Text(thread.isShared
                  ? 'View passport & documents'
                  : 'View documents they sent'),
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('${AppConstants.routeOrgStudent}/${thread.token}');
              },
            ),
            ListTile(
              leading: Icon(
                thread.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
              title: Text(thread.isPinned ? 'Unpin' : 'Pin to the top'),
              onTap: () {
                Navigator.of(sheet).pop();
                desk.setThreadState(
                  thread.conversationId,
                  pinned: !thread.isPinned,
                );
              },
            ),
            ListTile(
              leading: Icon(
                thread.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(thread.isArchived ? 'Unarchive' : 'Archive'),
              subtitle: Text(
                thread.isArchived
                    ? 'Puts it back on your Open tab.'
                    : 'Moves it off Open. Nothing is deleted, and your '
                          'colleagues keep their own view.',
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                desk.setThreadState(
                  thread.conversationId,
                  archived: !thread.isArchived,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final desk = context.watch<OrgDeskProvider>();
    final match = desk.inboxMatchFor(thread.conversationId);
    // The matching line beats the latest one while a search is running: being
    // shown a thread without being shown why is what makes results feel
    // arbitrary.
    final preview = (desk.inboxQuery.trim().isNotEmpty && match != null)
        ? match
        : thread.lastMessageBody ?? 'No messages yet';

    // The same row as the student's Messages list: a round face (or the
    // padlock), the name, one line of the last message, the time and an
    // unread dot — and a swipe to archive.
    return Dismissible(
      key: ValueKey(thread.conversationId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: colors.surfaceVariant,
        child: Icon(
          thread.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          color: colors.textSecondary,
        ),
      ),
      // The row moves to the other tab rather than animating away, so the
      // dismissal itself is always declined.
      confirmDismiss: (_) async {
        await context
            .read<OrgDeskProvider>()
            .setThreadState(thread.conversationId, archived: !thread.isArchived);
        return false;
      },
      child: Pressable.surface(
        haptic: null,
        onLongPress: () => _actions(context, thread),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: thread.conversationId,
                title: thread.displayName,
                // Null until they share, like the name beside it.
                avatarUrl: thread.sharedAvatarUrl,
              ),
            ),
          );
          if (context.mounted) {
            context.read<OrgDeskProvider>().load();
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              StudentMark(
                isShared: thread.isShared,
                avatarUrl: thread.sharedAvatarUrl,
                initials: thread.initials,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (thread.isPinned) ...[
                          Icon(Icons.push_pin_rounded,
                              size: 13, color: colors.textLight),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            thread.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              fontWeight: thread.hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((thread.subject ?? '').isNotEmpty)
                      Text(
                        thread.subject!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: thread.hasUnread
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(thread.when,
                      style: text.labelSmall?.copyWith(color: colors.textLight)),
                  const SizedBox(height: 6),
                  if (thread.hasUnread)
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${thread.unreadCount}',
                        style: text.labelSmall?.copyWith(
                          color: colors.onAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
