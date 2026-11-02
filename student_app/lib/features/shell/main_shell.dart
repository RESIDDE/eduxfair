import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/dynamic_type.dart';
import '../../core/widgets/material_surface.dart';
import '../../core/widgets/pressable.dart';
import '../messages/providers/messages_provider.dart';
import '../notifications/providers/notifications_provider.dart';

/// The student bottom bar.
///
/// Five icons, no labels, as in the X reference — at this size a label under
/// each icon crowds the bar without telling anyone anything the icon does not.
/// Everything personal lives behind the avatar in the app bar instead, which is
/// what freed the slot for Notifications.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    // Tapping the current tab pops it back to its root.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {

    final unreadMessages = context.select<MessagesProvider, int>(
      (p) => p.unreadCount,
    );
    final unreadNotifications = context.select<NotificationsProvider, int>(
      (p) => p.unreadCount,
    );

    const items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home_rounded, 'Feed'),
      (Icons.search_outlined, Icons.search_rounded, 'Search'),
      (Icons.podcasts_outlined, Icons.podcasts_rounded, 'Spaces'),
      (Icons.notifications_none_rounded, Icons.notifications_rounded,
          'Notifications'),
      (Icons.mail_outline_rounded, Icons.mail_rounded, 'Messages'),
    ];

    return Scaffold(
      // The bar floats over the content rather than taking a strip out of it,
      // so a list reads as continuing underneath instead of stopping dead.
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: MaterialSurface(
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: context.scaled(52),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _Tab(
                      icon: items[i].$1,
                      activeIcon: items[i].$2,
                      label: items[i].$3,
                      selected: navigationShell.currentIndex == i,
                      badge: switch (i) {
                        3 => unreadNotifications,
                        4 => unreadMessages,
                        _ => 0,
                      },
                      onTap: () => _onTap(i),
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

class _Tab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = Icon(
      selected ? activeIcon : icon,
      size: 26,
      color: selected ? colors.textPrimary : colors.textLight,
    );

    return Semantics(
      // The icons carry no visible label, so the accessible one matters more
      // here than it would on a labelled bar.
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge unread' : label,
      child: Pressable(
        onTap: onTap,
        // Switching tabs is a selection, and the icon yields a little as it is
        // pressed — the acknowledgement arrives before the screen changes.
        scale: 0.88,
        haptic: HapticKind.selection,
        child: Center(
          child: badge > 0
              ? Badge.count(
                  count: badge,
                  backgroundColor: colors.accent,
                  textColor: context.colors.onAccent,
                  child: child,
                )
              : child,
        ),
      ),
    );
  }
}
