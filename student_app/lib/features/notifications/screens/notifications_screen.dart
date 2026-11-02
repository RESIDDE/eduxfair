import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../models/app_notification.dart';
import '../providers/notifications_provider.dart';

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
          : provider.notifications.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Nothing yet',
                  message: 'We will let you know when an institution reaches '
                      'out, a meeting is confirmed, or your application moves.',
                )
              : RefreshIndicator(
                  onRefresh: provider.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: provider.notifications.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: colors.divider, indent: 68),
                    itemBuilder: (context, index) {
                      final notification = provider.notifications[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
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
                            color: notification.isUnread
                                ? colors.accent
                                : colors.textLight,
                          ),
                        ),
                        title: Text(
                          notification.title,
                          style: text.titleMedium?.copyWith(
                            fontWeight: notification.isUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
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
                          style: text.labelSmall
                              ?.copyWith(color: colors.textLight),
                        ),
                        onTap: () => _open(notification),
                      );
                    },
                  ),
                ),
    );
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
