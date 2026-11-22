import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_chrome.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/chrome_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/material_surface.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/settings_section.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../../passport/providers/passport_provider.dart';
import '../providers/institution_provider.dart';

/// Home, for an institution.
///
/// Ordered the way an admissions officer's morning goes: what needs me, then
/// how things stand, then what I might do next. The same chrome as the student
/// feed — glass header, the institution's mark where a student's avatar sits,
/// one `+` — so the two sides of the app are recognisably one product.
///
/// Deliberately plain. It used to open on a gradient banner with a sparkle
/// icon; numbers are now in the text colour on flat cards, and colour is kept
/// for state — something waiting, something wrong — where it means something.
class OrgDashboardScreen extends StatefulWidget {
  const OrgDashboardScreen({super.key});

  @override
  State<OrgDashboardScreen> createState() => _OrgDashboardScreenState();
}

class _OrgDashboardScreenState extends State<OrgDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InstitutionProvider>().refresh();
      context.read<PassportProvider>().load();
    });
  }

  static String _greeting(DateTime now) => switch (now.hour) {
    < 12 => 'Good morning',
    < 17 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<InstitutionProvider>();
    final managed = provider.managed;
    final user = context.watch<AuthProvider>().user;

    if (provider.loading && managed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (managed == null) {
      return Scaffold(
        body: ErrorState(
          message: provider.error ?? 'Could not load your institution.',
          onRetry: provider.refresh,
        ),
      );
    }

    final demand = provider.demand;
    final fieldLabel = context.read<PassportProvider>().fieldLabel;
    final institution = managed.institution;

    final attention = <SettingsRow>[
      if (demand.unreadConversations > 0)
        SettingsRow(
          icon: Icons.forum_outlined,
          label: demand.unreadConversations == 1
              ? 'An unread conversation'
              : 'Unread conversations',
          value: '${demand.unreadConversations}',
          onTap: () => context.push(AppConstants.routeOrgInbox),
        ),
      if (demand.pendingAppointments > 0)
        SettingsRow(
          icon: Icons.event_available_outlined,
          label: demand.pendingAppointments == 1
              ? 'A student is waiting for a time'
              : 'Students waiting for a time',
          value: '${demand.pendingAppointments}',
          onTap: () => context.push(AppConstants.routeOrgAppointments),
        ),
      if (!managed.isVerified)
        SettingsRow(
          icon: Icons.verified_outlined,
          label: institution.verificationStatus == 'pending'
              ? 'Verification in review'
              : 'Get verified',
          value: institution.verificationStatus == 'pending'
              ? null
              : 'Shown first',
          onTap: () => context.push(AppConstants.routeOrgSettings),
        ),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const MaterialSurface(
          lightFromTop: false,
          child: SizedBox.expand(),
        ),
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leadingWidth: 60,
        leading: Center(
          child: ChromeButton(
            tooltip: 'Our page',
            onTap: () => context.go(AppConstants.routeOrgProfile),
            child: InstitutionAvatar(
              logoUrl: institution.logoUrl,
              initials: institution.initials,
              size: 30,
            ),
          ),
        ),
        centerTitle: true,
        title: Text(
          AppConstants.appName,
          style: text.headlineSmall?.copyWith(color: colors.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChromeButton.icon(
              icon: Icons.add_rounded,
              tooltip: 'New post',
              onTap: () => context.push(AppConstants.routeCompose),
            ),
          ),
        ],
      ),
      // A Builder, because the padding to clear the glass header is published
      // by this Scaffold to its body — read from the screen's own context it
      // is the padding from *outside* the Scaffold, and the greeting slid
      // under the header.
      body: Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: provider.refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 16,
              bottom: AppChrome.navClearance(context),
            ),
            children: [
              // ── Greeting ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting(DateTime.now())}, ${user?.firstName ?? 'there'}',
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            institution.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyLarge?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        if (managed.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(
                            subject: VerifiedSubject.institution,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Needs your attention ─────────────────────────────────────
              SettingsSection(
                title: 'Needs your attention',
                rows: attention.isEmpty
                    ? [
                        SettingsRow(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'You’re all caught up',
                          tint: colors.success,
                        ),
                      ]
                    : attention,
              ),

              // ── At a glance ──────────────────────────────────────────────
              const _Heading('At a glance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: 2,
                  // Zero, explicitly: a vertical grid otherwise pads itself
                  // with the screen's insets, which opened a gap the height of
                  // the header above it and the tab bar below.
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: [
                    _StatTile(
                      icon: Icons.person_search_outlined,
                      value: demand.matchedStudents,
                      label: 'Matched students',
                      onTap: () => context.push(AppConstants.routeOrgStudents),
                    ),
                    _StatTile(
                      icon: Icons.workspaces_outline,
                      value: demand.openApplications,
                      label: 'Applications',
                      onTap: () => context.push(AppConstants.routeOrgPipeline),
                    ),
                    _StatTile(
                      icon: Icons.badge_outlined,
                      value: demand.sharedPassports,
                      label: 'Passports shared',
                      onTap: () => context.push(AppConstants.routeOrgPipeline),
                    ),
                    _StatTile(
                      icon: Icons.people_outline_rounded,
                      value: demand.followers,
                      label: 'Followers',
                      onTap: () => context.push(AppConstants.routeOrgFollowers),
                    ),
                  ],
                ),
              ),

              // ── Shortcuts ────────────────────────────────────────────────
              const _Heading('Shortcuts'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Shortcut(
                      icon: Icons.edit_outlined,
                      label: 'Write a post',
                      onTap: () => context.push(AppConstants.routeCompose),
                    ),
                    _Shortcut(
                      icon: Icons.podcasts_outlined,
                      label: 'Host a Space',
                      onTap: () => context.go(AppConstants.routeOrgSpaces),
                    ),
                    if (!managed.isEmbassy)
                      _Shortcut(
                        icon: Icons.school_outlined,
                        label: 'Programmes',
                        onTap: () =>
                            context.push(AppConstants.routeOrgPrograms),
                      ),
                    _Shortcut(
                      icon: Icons.group_outlined,
                      label: 'Team',
                      onTap: () => context.push(AppConstants.routeOrgTeam),
                    ),
                  ],
                ),
              ),

              // ── Our page ─────────────────────────────────────────────────
              if (managed.completeness < 100) ...[
                const _Heading('Our page'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CompletenessCard(
                    completeness: managed.completeness,
                    missing: managed.missingPieces,
                  ),
                ),
              ],

              // ── Demand ───────────────────────────────────────────────────
              if (demand.topFields.isNotEmpty) ...[
                const _Heading('What matched students want to study'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Card(
                    child: Column(
                      children: [
                        for (final f in demand.topFields)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: _FieldBar(
                              label: fieldLabel(f.field),
                              students: f.students,
                              max: demand.topFields.first.students,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────────

/// A section label, set like the ones in [SettingsSection] so the page reads
/// as one list of groups.
class _Heading extends StatelessWidget {
  final String label;
  const _Heading(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 26, 16, 10),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: context.colors.textSecondary),
    ),
  );
}

/// A flat card: surface colour, hairline border. Glass is for chrome only.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.colors.border),
    ),
    child: child,
  );
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final VoidCallback onTap;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Pressable.surface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      semanticLabel: '$label: $value',
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: colors.textSecondary),
                const Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textLight,
                ),
              ],
            ),
            const Spacer(),
            Text(
              formatThousands(value),
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round button with its name underneath — the shape iOS uses for quick
/// actions, so its meaning is familiar before it is read.
class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Shortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
              child: Icon(icon, size: 23, color: colors.textPrimary),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletenessCard extends StatelessWidget {
  final int completeness;
  final List<String> missing;

  const _CompletenessCard({required this.completeness, required this.missing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Pressable.surface(
      onTap: () => context.go(AppConstants.routeOrgProfile),
      borderRadius: BorderRadius.circular(18),
      semanticLabel: 'Our page is $completeness percent complete',
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$completeness% complete',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Finish it',
                  style: text.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textLight,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (completeness / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.surfaceVariant,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Students compare institutions on cost, entry requirements and '
              'deadlines. Pages that answer those get opened.',
              style: text.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final item in missing.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle_outlined,
                        size: 14,
                        color: colors.textLight,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item, style: text.bodySmall)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldBar extends StatelessWidget {
  final String label;
  final int students;
  final int max;

  const _FieldBar({
    required this.label,
    required this.students,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: text.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              formatThousands(students),
              style: text.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: max == 0 ? 0 : students / max,
            minHeight: 6,
            backgroundColor: colors.surfaceVariant,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
