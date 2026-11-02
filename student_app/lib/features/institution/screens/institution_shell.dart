import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/institution_provider.dart';

/// The institution bottom-nav shell.
///
/// Deliberately the same `StatefulShellRoute.indexedStack` pattern the student
/// shell uses, so each tab keeps its own stack and scroll position. Which shell
/// a person gets is decided by their role in the router — one app, two
/// experiences, rather than two apps.
class InstitutionShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const InstitutionShell({super.key, required this.navigationShell});

  void _onTap(int index) {
    // Tapping the current tab pops it to its root, as everywhere else.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final demand = context.select<InstitutionProvider, int>(
      (p) => p.demand.needsAttention,
    );

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            backgroundColor: Colors.transparent,
            elevation: 0,
            height: 68,
            // Icons alone, like the student shell and like X: five labels on
            // a phone forces each one to shrink or truncate, and the icons
            // already say it.
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Dashboard',
              ),
              const NavigationDestination(
                icon: Icon(Icons.apartment_outlined),
                selectedIcon: Icon(Icons.apartment_rounded),
                label: 'Our page',
              ),
              const NavigationDestination(
                icon: Icon(Icons.campaign_outlined),
                selectedIcon: Icon(Icons.campaign_rounded),
                label: 'Posts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.podcasts_outlined),
                selectedIcon: Icon(Icons.podcasts_rounded),
                label: 'Spaces',
              ),
              NavigationDestination(
                icon: demand > 0
                    ? Badge.count(
                        count: demand,
                        backgroundColor: colors.error,
                        child: const Icon(Icons.more_horiz_rounded),
                      )
                    : const Icon(Icons.more_horiz_rounded),
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
