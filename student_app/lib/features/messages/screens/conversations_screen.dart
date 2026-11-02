import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/conversation.dart';
import '../providers/messages_provider.dart';

/// The inbox: two tabs, a search box, and per-thread pinning.
///
/// Archived threads are a tab rather than a filter toggle, because the whole
/// point of archiving is that the thread stops appearing where you normally
/// look — a toggle people have to remember to turn off is the same list with
/// extra steps.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _search = TextEditingController();

  /// Typing is not a search. The name half filters locally on every keystroke;
  /// only the message-body half waits, so the server sees one query per pause
  /// rather than one per letter.
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MessagesProvider>().loadConversations();
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
      if (mounted) context.read<MessagesProvider>().search(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    context.read<MessagesProvider>().clearSearch();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final provider = context.watch<MessagesProvider>();
    final archivedCount = provider.archivedCount;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Messages'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Chats'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Archived'),
                    if (archivedCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.textSecondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$archivedCount',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
                  hintText: 'Search names and messages',
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
            if (provider.searching)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: provider.loading && provider.conversations.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : provider.error != null && provider.conversations.isEmpty
                      ? ErrorState(
                          message: provider.error!,
                          onRetry: provider.loadConversations,
                        )
                      : TabBarView(
                          children: [
                            _ThreadList(
                              key: const PageStorageKey('chats'),
                              rows: provider.inbox,
                              archivedTab: false,
                              searching: _search.text.trim().isNotEmpty,
                              hasAny: provider.conversations
                                  .any((c) => !c.isArchived),
                            ),
                            _ThreadList(
                              key: const PageStorageKey('archived'),
                              rows: provider.archived,
                              archivedTab: true,
                              searching: _search.text.trim().isNotEmpty,
                              hasAny: archivedCount > 0,
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
  final List<Conversation> rows;
  final bool archivedTab;
  final bool searching;
  final bool hasAny;

  const _ThreadList({
    super.key,
    required this.rows,
    required this.archivedTab,
    required this.searching,
    required this.hasAny,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final provider = context.read<MessagesProvider>();

    if (rows.isEmpty) {
      // Three different nothings, and conflating them is how an empty list
      // reads as a broken one.
      final empty = searching
          ? const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matched',
              message: 'Search looks at who you are talking to and at what '
                  'has been said in the thread.',
            )
          : archivedTab
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Nothing archived',
                  message: 'Archiving a thread moves it off your Chats tab '
                      'without deleting anything. It comes straight back if '
                      'someone replies to it.',
                )
              : EmptyState(
                  icon: Icons.forum_outlined,
                  title: hasAny ? 'Nothing here' : 'No conversations yet',
                  message: 'Ask a question from any institution or program '
                      'page and the thread will appear here.',
                  actionLabel: 'Browse institutions',
                  onAction: () => context.go(AppConstants.routeDiscover),
                );

      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [const SizedBox(height: 24), empty],
      );
    }

    return RefreshIndicator(
      onRefresh: provider.loadConversations,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: AppChrome.navClearance(context)),
        itemCount: rows.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: colors.divider, indent: 76),
        itemBuilder: (context, index) =>
            _ThreadTile(conversation: rows[index], archivedTab: archivedTab),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final Conversation conversation;
  final bool archivedTab;

  const _ThreadTile({required this.conversation, required this.archivedTab});

  Future<void> _actions(BuildContext context) async {
    final provider = context.read<MessagesProvider>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(conversation.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined),
              title: Text(conversation.isPinned ? 'Unpin' : 'Pin to the top'),
              onTap: () {
                Navigator.of(sheet).pop();
                provider.setConversationState(conversation.id,
                    pinned: !conversation.isPinned);
              },
            ),
            ListTile(
              leading: Icon(conversation.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              title: Text(conversation.isArchived ? 'Unarchive' : 'Archive'),
              subtitle: Text(
                conversation.isArchived
                    ? 'Puts it back on your Chats tab.'
                    : 'Moves it off Chats. Nothing is deleted, and only you '
                        'see the change.',
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                provider.setConversationState(conversation.id,
                    archived: !conversation.isArchived);
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
    final provider = context.watch<MessagesProvider>();

    // The matching line beats the latest one while a search is running: being
    // shown the thread without being shown why is the thing that makes search
    // results feel arbitrary.
    final match = provider.matchFor(conversation.id);
    final preview = (provider.query.trim().isNotEmpty && match != null)
        ? match
        : conversation.lastMessageBody ??
            conversation.subject ??
            'No messages yet';

    return Dismissible(
      key: ValueKey(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: colors.surfaceVariant,
        child: Icon(
          conversation.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          color: colors.textSecondary,
        ),
      ),
      // Never actually dismissed: the row moves to the other tab, and letting
      // the widget animate away as well would be two different disappearances
      // for one action.
      confirmDismiss: (_) async {
        await provider.setConversationState(conversation.id,
            archived: !conversation.isArchived);
        return false;
      },
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: InstitutionAvatar(
          logoUrl: conversation.institution?.logoUrl,
          initials: conversation.institution?.initials ?? '?',
          size: 44,
        ),
        title: Row(
          children: [
            if (conversation.isPinned) ...[
              Icon(Icons.push_pin_rounded, size: 13, color: colors.textLight),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                conversation.title,
                style: text.titleMedium?.copyWith(
                  fontWeight:
                      conversation.hasUnread ? FontWeight.w700 : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (conversation.institution?.isVerified ?? false)
              Icon(Icons.verified_rounded, size: 14, color: colors.success),
          ],
        ),
        subtitle: Text(
          preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(
            color: conversation.hasUnread
                ? colors.textPrimary
                : colors.textSecondary,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (conversation.lastMessageAt != null)
              Text(
                _relative(conversation.lastMessageAt!),
                style: text.labelSmall?.copyWith(color: colors.textLight),
              ),
            if (conversation.hasUnread) ...[
              const SizedBox(height: 6),
              Container(
                width: 9,
                height: 9,
                decoration:
                    BoxDecoration(color: colors.accent, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        onTap: () =>
            context.push('${AppConstants.routeChat}/${conversation.id}'),
        onLongPress: () => _actions(context),
      ),
    );
  }

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}
