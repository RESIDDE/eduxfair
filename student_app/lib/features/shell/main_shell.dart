import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../messages/providers/messages_provider.dart';
import '../applications/providers/applications_provider.dart';
import '../matches/providers/matches_provider.dart';
import '../notifications/models/action_item.dart';
import '../notifications/providers/notifications_provider.dart';
import '../passport/providers/passport_provider.dart';
import 'floating_tab_shell.dart';

/// The student shell: five tabs under a floating glass capsule.
///
/// The capsule stays in `Scaffold.bottomNavigationBar` even though it floats,
/// because that slot is the channel the Scaffold uses to tell the five tab
/// screens how much room to leave at the bottom: it measures the bar and
/// publishes the result as the body's `MediaQuery.padding.bottom`. Moving the
/// bar into a `Stack` would look identical and throw that number away, leaving
/// every list back on a hardcoded guess.
///
/// The slot's height is therefore **pinned** at the expanded size, and the
/// capsule shrinks *inside* it. Animating the slot itself would republish the
/// body's `MediaQuery` on every frame, re-resolving the padding of every list
/// and re-running sliver layout mid-scroll.
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final unreadMessages = context.select<MessagesProvider, int>(
      (p) => p.unreadCount,
    );
    // The badge counts the standing to-dos as well as the unread
    // notifications, because the to-dos used to be cards pinned above the
    // feed and the badge is now the only thing that says they are waiting.
    final unreadNotifications = context.select<NotificationsProvider, int>(
          (p) => p.unreadCount,
        ) +
        studentActions(
          passport: context.watch<PassportProvider>(),
          matches: context.watch<MatchesProvider>(),
          applications: context.watch<ApplicationsProvider>(),
        ).length;

    return FloatingTabShell(
      navigationShell: navigationShell,
      badges: {3: unreadNotifications, 4: unreadMessages},
    );
  }
}
