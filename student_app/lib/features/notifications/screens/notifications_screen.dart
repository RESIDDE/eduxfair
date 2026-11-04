import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_chrome.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../models/app_notification.dart';
import '../providers/notifications_provider.dart';
import '../models/action_item.dart';
import '../../applications/providers/applications_provider.dart';
import '../../matches/providers/matches_provider.dart';
import '../../passport/providers/passport_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsProvider>().load();
    });
  }

  Future<void> _open(AppNotification notification) async {
    final provider = context.read<NotificationsProvider>();
    await provider.markRead(notification);
    if (!mounted) return;

    final target = notification.deepLinkTarget;
    // `push`, so the arrow on the destination returns here. Replacing the
    // stack dropped someone into an application or a post with no route back
    // to the list they came from.
    if (target != null) context.push(target);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<NotificationsProvider>();

    // The standing to-dos that used to be cards pinned above the feed. They
    // live above the notifications because they are the ones that need doing
    // rather than reading, and the nav badge counts them alongside.
    final actions = studentActions(
      passport: context.watch<PassportProvider>(),
      matches: context.watch<MatchesProvider>(),
      applications: context.watch<ApplicationsProvider>(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (provider.hasUnread)
            TextButton(
              onPressed: provider.markAllRead,
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: provider.loading && provider.notifications.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.notifications.isEmpty && actions.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Nothing yet',
                  message: 'We will let you know when an institution reaches '
                      'out, a meeting is confirmed, or your application moves.',
                )
              : RefreshIndicator(
                  onRefresh: provider.load,
                  child: ListView(
                    padding: EdgeInsets.only(
                        top: 8,
                        bottom: AppChrome.navClearance(context, gap: 8)),
                    children: [
                      for (final action in actions)
                        _ActionCard(item: action),
                      if (actions.isNotEmpty && provider.notifications.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                          child: Text(
                            'Earlier',
                            style: text.labelMedium
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ..._notificationTiles(context, provider),
                    ],
                  ),
                ),
    );
  }

  /// The notifications themselves, as a flat list so the action cards can
  /// sit above them in the same scroll view.
  List<Widget> _notificationTiles(
    BuildContext context,
    NotificationsProvider provider,
  ) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final tiles = <Widget>[];

    for (var index = 0; index < provider.notifications.length; index++) {
      final notification = provider.notifications[index];
      tiles.add(ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: notification.isUnread
                ? colors.infoLight
                : colors.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _iconFor(notification.kind),
            size: 19,
            color:
                notification.isUnread ? colors.accent : colors.textLight,
          ),
        ),
        title: Text(
          notification.title,
          style: text.titleMedium?.copyWith(
            fontWeight:
                notification.isUnread ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        subtitle: notification.body == null
            ? null
            : Text(
                notification.body!,
                style: text.bodySmall?.copyWith(height: 1.4),
              ),
        trailing: Text(
          _relative(notification.createdAt),
          style: text.labelSmall?.copyWith(color: colors.textLight),
        ),
        onTap: () => _open(notification),
      ));

      if (index < provider.notifications.length - 1) {
        tiles.add(
          Divider(height: 1, color: colors.divider, indent: 68),
        );
      }
    }

    return tiles;
  }

  static IconData _iconFor(String kind) => switch (kind) {
        'institution_invited_you' => Icons.handshake_rounded,
        'institution_requested_access' => Icons.visibility_rounded,
        'appointment_requested' ||
        'appointment_confirmed' => Icons.event_available_rounded,
        'appointment_declined' => Icons.event_busy_rounded,
        'application_stage_changed' => Icons.move_up_rounded,
        'documents_requested' => Icons.upload_file_rounded,
        'passport_verified' => Icons.verified_rounded,
        'new_message' => Icons.forum_rounded,
        'post_tagged' => Icons.alternate_email_rounded,
        _ => Icons.notifications_rounded,
      };

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }
}

/// One standing to-do, in the tone its urgency deserves.
class _ActionCard extends StatelessWidget {
  final ActionItem item;

  const _ActionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final good = item.tone == ActionTone.good;
    final tint = good ? colors.success : colors.warning;
    final wash = good ? colors.successLight : colors.warningLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: wash,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => context.push(item.route),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, size: 20, color: tint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.title,
                        style: text.titleMedium?.copyWith(color: tint),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.body, style: text.bodySmall?.copyWith(height: 1.45)),
                const SizedBox(height: 10),
                Text(
                  item.actionLabel,
                  style: text.titleSmall?.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
