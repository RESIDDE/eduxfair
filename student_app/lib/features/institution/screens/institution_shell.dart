import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../shell/floating_tab_shell.dart';
import '../providers/institution_provider.dart';

/// The institution shell.
///
/// The same floating glass capsule as the student shell — one component, so
/// the two sides of the app feel like one product. Which shell a person gets is
/// decided by their role in the router; each tab keeps its own stack and scroll
/// position, and tapping the current tab pops it back to its root.
class InstitutionShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const InstitutionShell({super.key, required this.navigationShell});

  /// Specific names, not umbrellas: each says what is behind it.
  static const tabs = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.apartment_outlined, Icons.apartment_rounded, 'Our page'),
    (Icons.dynamic_feed_outlined, Icons.dynamic_feed_rounded, 'Posts'),
    (Icons.podcasts_outlined, Icons.podcasts_rounded, 'Spaces'),
    (Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    // The badge sits on Home, because Home is where the list of what needs
    // doing lives — a count on a tab that does not show the items is a
    // number with nowhere to go.
    final attention = context.select<InstitutionProvider, int>(
      (p) => p.demand.needsAttention,
    );

    return FloatingTabShell(
      navigationShell: navigationShell,
      tabs: tabs,
      badges: {0: attention},
    );
  }
}
