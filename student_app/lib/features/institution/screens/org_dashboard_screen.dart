import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../passport/providers/passport_provider.dart';
import '../providers/institution_provider.dart';

/// What an institution sees first.
///
/// Leads with the number that makes the platform worth paying for — how many
/// students currently match what they teach — then what is waiting on a person,
/// then the nudge to finish their page. Everything here is pseudonymous or
/// aggregate; identities require a passport share.
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
      // The field vocabulary labels the demand breakdown.
      context.read<PassportProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<InstitutionProvider>();
    final managed = provider.managed;

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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: provider.refresh,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 96,
              backgroundColor: colors.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                title: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InstitutionAvatar(
                        logoUrl: managed.institution.logoUrl,
                        initials: managed.institution.initials,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          managed.institution.name,
                          style: text.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  onPressed: () => context.push(AppConstants.routeOrgSettings),
                  icon: const Icon(Icons.settings_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              sliver: SliverList.list(
                children: [
                  if (!managed.isVerified) ...[
                    _VerifyBanner(status: managed.institution.verificationStatus),
                    const SizedBox(height: 16),
                  ],

                  // The headline: students looking for what you offer.
                  Container(
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
                            const Icon(Icons.auto_awesome_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 9),
                            Text(
                              'STUDENTS LOOKING FOR WHAT YOU OFFER',
                              style: text.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          formatThousands(demand.matchedStudents),
                          style: text.displayLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'They match one of your programs on destination, '
                          'level, field and entry requirements. You can invite '
                          'them before they apply — they stay anonymous until '
                          'they choose to share.',
                          style: text.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: colors.primary,
                              minimumSize: const Size(double.infinity, 46),
                            ),
                            onPressed: () =>
                                context.push(AppConstants.routeOrgStudents),
                            child: const Text('Browse matched students'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          value: demand.sharedPassports,
                          label: 'Passports',
                          color: colors.success,
                          background: colors.successLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          value: demand.openApplications,
                          label: 'Applications',
                          color: colors.accent,
                          background: colors.infoLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          value: demand.followers,
                          label: 'Followers',
                          color: colors.primary,
                          background: colors.primary.withValues(alpha: 0.1),
                          onTap: () => context.push(AppConstants.routeOrgFollowers),
                        ),
                      ),
                    ],
                  ),

                  // What is waiting on a person, only when something is.
                  if (demand.pendingAppointments > 0) ...[
                    const SizedBox(height: 12),
                    _ActionRow(
                      icon: Icons.event_available_rounded,
                      color: colors.warning,
                      background: colors.warningLight,
                      title: demand.pendingAppointments == 1
                          ? '1 student is waiting for a time'
                          : '${demand.pendingAppointments} students are waiting '
                              'for a time',
                      onTap: () =>
                          context.push(AppConstants.routeOrgAppointments),
                    ),
                  ],
                  if (demand.unreadConversations > 0) ...[
                    const SizedBox(height: 10),
                    _ActionRow(
                      icon: Icons.forum_rounded,
                      color: colors.accent,
                      background: colors.infoLight,
                      title: demand.unreadConversations == 1
                          ? '1 unread conversation'
                          : '${demand.unreadConversations} unread conversations',
                      onTap: () => context.push(AppConstants.routeOrgInbox),
                    ),
                  ],

                  // Finish your page — same nudge a student gets on theirs.
                  if (managed.completeness < 70) ...[
                    const SizedBox(height: 20),
                    _CompletenessCard(
                      completeness: managed.completeness,
                      missing: managed.missingPieces,
                    ),
                  ],

                  if (demand.topFields.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('What they want to study', style: text.titleLarge),
                    const SizedBox(height: 12),
                    ...demand.topFields.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FieldBar(
                          label: fieldLabel(f.field),
                          students: f.students,
                          max: demand.topFields.first.students,
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
    );
  }
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _VerifyBanner extends StatelessWidget {
  final String status;

  const _VerifyBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warningLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: colors.warning),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VerificationStatusChip(
                  status: status,
                  subject: VerifiedSubject.institution,
                ),
                const SizedBox(height: 7),
                Text(
                  'Students are shown verified institutions first. Verify your '
                  'email domain from Settings.',
                  style: text.bodySmall?.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final Color background;
  final VoidCallback? onTap;

  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    required this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatThousands(value),
                style: text.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: text.bodySmall?.copyWith(height: 1.2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: color),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      );
}

class _CompletenessCard extends StatelessWidget {
  final int completeness;
  final List<String> missing;

  const _CompletenessCard({required this.completeness, required this.missing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Your page is $completeness% complete',
                    style: text.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // The consequence, not a nag: students skip pages that do not
            // answer what they are deciding on.
            'Students compare institutions on cost, entry requirements and '
            'deadlines. Pages that answer those get opened.',
            style: text.bodySmall?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 14),
          LinearPercentIndicator(
            percent: (completeness / 100).clamp(0.0, 1.0),
            lineHeight: 7,
            padding: EdgeInsets.zero,
            barRadius: const Radius.circular(4),
            backgroundColor: colors.surfaceVariant,
            progressColor:
                completeness >= 70 ? colors.success : colors.warning,
            animation: true,
            animationDuration: 600,
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...missing.take(3).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.radio_button_unchecked,
                            size: 14, color: colors.textLight),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item, style: text.bodySmall)),
                      ],
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go(AppConstants.routeOrgProfile),
              child: const Text('Finish our page'),
            ),
          ),
        ],
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
              child: Text(label,
                  style: text.bodyMedium, overflow: TextOverflow.ellipsis),
            ),
            Text(formatThousands(students), style: text.titleSmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: max == 0 ? 0 : students / max,
            minHeight: 6,
            backgroundColor: colors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(colors.accent),
          ),
        ),
      ],
    );
  }
}
