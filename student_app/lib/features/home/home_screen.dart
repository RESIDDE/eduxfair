import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/institution_avatar.dart';
import '../applications/providers/applications_provider.dart';
import '../auth/providers/auth_provider.dart';
import '../fairs/providers/fairs_provider.dart';
import '../matches/providers/matches_provider.dart';
import '../meet/providers/meet_provider.dart';
import '../notifications/providers/notifications_provider.dart';
import '../passport/providers/passport_provider.dart';

/// The home screen leads with whatever most needs the student's attention:
/// finishing their passport if it is incomplete, otherwise institutions that
/// have reached out, offers waiting, and the next fair.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame so the providers are mounted and a failure here
    // surfaces as an error state rather than an exception during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    final notifications = context.read<NotificationsProvider>();

    await Future.wait([
      context.read<PassportProvider>().load(),
      context.read<MatchesProvider>().load(),
      context.read<ApplicationsProvider>().load(),
      context.read<MeetProvider>().load(),
      context.read<FairsProvider>().load(),
      notifications.load(),
    ]);

    notifications.subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final user = context.watch<AuthProvider>().user;
    final passport = context.watch<PassportProvider>();
    final matches = context.watch<MatchesProvider>();
    final applications = context.watch<ApplicationsProvider>();
    final meet = context.watch<MeetProvider>();
    final fairs = context.watch<FairsProvider>();
    final unread = context.watch<NotificationsProvider>().unreadCount;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 108,
              backgroundColor: colors.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, ${user?.firstName ?? 'there'}',
                        style: text.headlineMedium,
                      ),
                      Text(AppConstants.appTagline, style: text.bodySmall),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () => context.push(AppConstants.routeNotifications),
                  icon: unread > 0
                      ? Badge.count(
                          count: unread,
                          backgroundColor: colors.error,
                          child: const Icon(Icons.notifications_outlined),
                        )
                      : const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  onPressed: () => context.push(AppConstants.routeProfile),
                  icon: const Icon(Icons.account_circle_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              sliver: SliverList.list(
                children: [
                  // The passport gates everything else: an incomplete one is
                  // not matched at all, so it leads until it is done.
                  if (!passport.isMatchable)
                    _PassportPrompt(
                      completeness: passport.completeness,
                      missing: passport.passport?.missingPieces ?? const [],
                    )
                  else
                    _PassportSummary(completeness: passport.completeness),

                  if (matches.invitations.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: 'Institutions are asking for you',
                      count: matches.invitationCount,
                      onSeeAll: () => context.go(AppConstants.routeMatches),
                    ),
                    const SizedBox(height: 12),
                    ...matches.invitations.take(2).map(
                          (invite) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _InvitationTile(
                              name: invite.institutionName,
                              logoUrl: invite.institutionLogoUrl,
                              programName: invite.programName,
                              note: invite.note,
                              verified: invite.institutionVerified,
                              onTap: () => context.go(AppConstants.routeMatches),
                            ),
                          ),
                        ),
                  ],

                  if (applications.offerCount > 0) ...[
                    const SizedBox(height: 24),
                    _ActionBanner(
                      icon: Icons.celebration_rounded,
                      background: colors.successLight,
                      foreground: colors.success,
                      title: applications.offerCount == 1
                          ? 'You have an offer'
                          : 'You have ${applications.offerCount} offers',
                      body: 'Review the terms and respond when you are ready.',
                      actionLabel: 'View',
                      onAction: () => context.push(AppConstants.routeApplications),
                    ),
                  ],

                  if (applications.outstandingRequestCount > 0) ...[
                    const SizedBox(height: 12),
                    _ActionBanner(
                      icon: Icons.upload_file_rounded,
                      background: colors.warningLight,
                      foreground: colors.warning,
                      title: 'Documents requested',
                      body: '${applications.outstandingRequestCount} '
                          'outstanding — your application is waiting on these.',
                      actionLabel: 'Upload',
                      onAction: () => context.push(AppConstants.routeApplications),
                    ),
                  ],

                  if (meet.upcoming.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: 'Upcoming meetings',
                      count: meet.upcoming.length,
                      onSeeAll: () =>
                          context.push(AppConstants.routeAppointments),
                    ),
                    const SizedBox(height: 12),
                    ...meet.upcoming.take(2).map(
                          (appointment) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AppointmentTile(
                              institutionName:
                                  appointment.institution?.name ?? 'Institution',
                              logoUrl: appointment.institution?.logoUrl,
                              when: appointment.scheduledFor,
                              statusLabel: appointment.statusLabel,
                              confirmed: appointment.isConfirmed,
                              onTap: () =>
                                  context.push(AppConstants.routeAppointments),
                            ),
                          ),
                        ),
                  ],

                  if (passport.isMatchable && matches.topMatches.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: 'Programs that match you',
                      count: matches.matchCount,
                      onSeeAll: () => context.go(AppConstants.routeMatches),
                    ),
                    const SizedBox(height: 12),
                    ...matches.topMatches.map(
                      (match) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _MatchPreviewTile(
                          programName: match.program?.name ?? 'Program',
                          institutionName:
                              match.program?.institution?.name ?? '',
                          logoUrl: match.program?.institution?.logoUrl,
                          score: match.score,
                          strengthLabel: match.strengthLabel,
                          hasScholarship: match.hasScholarship,
                          onTap: () => context.push(
                            '${AppConstants.routeProgram}/${match.programId}',
                          ),
                        ),
                      ),
                    ),
                  ],

                  // The fair is the thing that brought most students here, so
                  // it stays visible even when nothing else is happening.
                  if (fairs.currentRegistration != null) ...[
                    const SizedBox(height: 24),
                    _FairCard(
                      fairName:
                          fairs.currentRegistration!.fair?.name ?? 'Eduxfair',
                      location: fairs.currentRegistration!.fair?.location ?? '',
                      startsAt: fairs.currentRegistration!.fair?.startsAt,
                      isOnNow: fairs.currentRegistration!.fair?.isOnNow ?? false,
                      onTap: () => context.push(AppConstants.routeFairPassport),
                    ),
                  ] else if (fairs.upcomingFairs.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _ActionBanner(
                      icon: Icons.event_available_rounded,
                      background: colors.infoLight,
                      foreground: colors.info,
                      title: fairs.upcomingFairs.first.name,
                      body: 'Register to get your Fair Passport and skip the '
                          'queue at every booth.',
                      actionLabel: 'Register',
                      onAction: () => context.push(AppConstants.routeFairPassport),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _PassportPrompt extends StatelessWidget {
  final int completeness;
  final List<String> missing;

  const _PassportPrompt({required this.completeness, required this.missing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: colors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Finish your Education Passport',
                  style: text.titleLarge?.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // Explains the consequence rather than just nagging: below the
            // threshold, institutions genuinely cannot see this student.
            'Institutions can only find you once your passport is at '
            '${AppConstants.minCompletenessToMatch}%.',
            style: text.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          LinearPercentIndicator(
            percent: (completeness / 100).clamp(0.0, 1.0),
            lineHeight: 8,
            padding: EdgeInsets.zero,
            barRadius: const Radius.circular(4),
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            progressColor: colors.accentLight,
            animation: true,
            animationDuration: 600,
          ),
          const SizedBox(height: 8),
          Text(
            '$completeness% complete',
            style: text.labelMedium?.copyWith(color: Colors.white),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...missing.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.radio_button_unchecked,
                            size: 15,
                            color: Colors.white.withValues(alpha: 0.6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: text.bodySmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: colors.primary,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: () => context.push(AppConstants.routePassportEdit),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PassportSummary extends StatelessWidget {
  final int completeness;

  const _PassportSummary({required this.completeness});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => context.go(AppConstants.routePassport),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.successLight,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.verified_user_rounded,
                  color: colors.success, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your passport is live', style: text.titleMedium),
                  Text(
                    '$completeness% complete — institutions can find you',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textLight),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final VoidCallback onSeeAll;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          TextButton(
            onPressed: onSeeAll,
            child: Text(count > 0 ? 'See all $count' : 'See all'),
          ),
        ],
      );
}

class _ActionBanner extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _ActionBanner({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(color: foreground),
                ),
                const SizedBox(height: 2),
                Text(body, style: text.bodySmall?.copyWith(height: 1.4)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitationTile extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final String? programName;
  final String? note;
  final bool verified;
  final VoidCallback onTap;

  const _InvitationTile({
    required this.name,
    this.logoUrl,
    this.programName,
    this.note,
    required this.verified,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            InstitutionAvatar(
              logoUrl: logoUrl,
              initials: name.isEmpty ? '?' : name[0].toUpperCase(),
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: text.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.verified_rounded,
                            size: 15, color: colors.success),
                      ],
                    ],
                  ),
                  Text(
                    note ?? programName ?? 'Wants to hear from you',
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textLight),
          ],
        ),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  final String institutionName;
  final String? logoUrl;
  final DateTime? when;
  final String statusLabel;
  final bool confirmed;
  final VoidCallback onTap;

  const _AppointmentTile({
    required this.institutionName,
    this.logoUrl,
    this.when,
    required this.statusLabel,
    required this.confirmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            InstitutionAvatar(
              logoUrl: logoUrl,
              initials: institutionName.isEmpty
                  ? '?'
                  : institutionName[0].toUpperCase(),
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(institutionName,
                      style: text.titleMedium, overflow: TextOverflow.ellipsis),
                  Text(
                    when == null
                        ? statusLabel
                        : '${_formatDate(when!)} · $statusLabel',
                    style: text.bodySmall?.copyWith(
                      color: confirmed ? colors.success : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textLight),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour < 12 ? 'am' : 'pm';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $hour:$minute$period';
  }
}

class _MatchPreviewTile extends StatelessWidget {
  final String programName;
  final String institutionName;
  final String? logoUrl;
  final int score;
  final String strengthLabel;
  final bool hasScholarship;
  final VoidCallback onTap;

  const _MatchPreviewTile({
    required this.programName,
    required this.institutionName,
    this.logoUrl,
    required this.score,
    required this.strengthLabel,
    required this.hasScholarship,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            InstitutionAvatar(
              logoUrl: logoUrl,
              initials: institutionName.isEmpty
                  ? '?'
                  : institutionName[0].toUpperCase(),
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(programName,
                      style: text.titleMedium, overflow: TextOverflow.ellipsis),
                  Text(institutionName,
                      style: text.bodySmall, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.infoLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$score% · $strengthLabel',
                          style: text.labelSmall?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (hasScholarship) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.savings_rounded,
                            size: 14, color: colors.warning),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textLight),
          ],
        ),
      ),
    );
  }
}

class _FairCard extends StatelessWidget {
  final String fairName;
  final String location;
  final DateTime? startsAt;
  final bool isOnNow;
  final VoidCallback onTap;

  const _FairCard({
    required this.fairName,
    required this.location,
    this.startsAt,
    required this.isOnNow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.qr_code_2_rounded,
                  size: 30, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isOnNow) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: colors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'HAPPENING NOW',
                          style: text.labelSmall?.copyWith(
                            color: colors.success,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ] else
                        Text(
                          'YOUR FAIR PASSPORT',
                          style: text.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fairName,
                    style: text.titleMedium?.copyWith(color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location.isNotEmpty)
                    Text(
                      location,
                      style: text.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}
