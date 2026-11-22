import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../passport/providers/passport_provider.dart';
import '../models/match_card.dart';
import '../providers/matches_provider.dart';

/// Reverse admission, from the student's side: institutions that asked for
/// them, and programs that match their passport — each with its reasoning.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MatchesProvider>().load();
      context.read<PassportProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MatchesProvider>();
    final passport = context.watch<PassportProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              text: provider.invitationCount > 0
                  ? 'Asking for you (${provider.invitationCount})'
                  : 'Asking for you',
            ),
            Tab(
              text: provider.matchCount > 0
                  ? 'Your matches (${provider.matchCount})'
                  : 'Your matches',
            ),
          ],
        ),
      ),
      body: provider.loading &&
              provider.matches.isEmpty &&
              provider.invitations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _InvitationsTab(provider: provider),
                _MatchesTab(provider: provider, passportReady: passport.isMatchable),
              ],
            ),
    );
  }
}

class _InvitationsTab extends StatelessWidget {
  final MatchesProvider provider;

  const _InvitationsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    if (provider.invitations.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          children: const [
            SizedBox(height: 40),
            EmptyState(
              icon: Icons.handshake_outlined,
              title: 'No invitations yet',
              message: 'When an institution sees that your profile matches '
                  'one of their programs, they can ask to hear from you. '
                  'They only learn who you are if you share your passport.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.successLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 18, color: colors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These institutions reached out to you. They matched your '
                    'anonymous profile — they do not have your name or '
                    'documents unless you share them.',
                    style: text.bodySmall?.copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...provider.invitations.map(
            (invite) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _InvitationCard(invitation: invite),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final Invitation invitation;

  const _InvitationCard({required this.invitation});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final passport = context.read<PassportProvider>();

    final alreadyShared = passport.activeShares
        .any((s) => s.institutionId == invitation.institutionId);

    return Container(
      padding: const EdgeInsets.all(16),
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
              InstitutionAvatar(
                logoUrl: invitation.institutionLogoUrl,
                initials: invitation.institutionName.isEmpty
                    ? '?'
                    : invitation.institutionName[0].toUpperCase(),
                size: 46,
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
                            invitation.institutionName,
                            style: text.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (invitation.institutionVerified) ...[
                          const SizedBox(width: 5),
                          Icon(Icons.verified_rounded,
                              size: 15, color: colors.success),
                        ],
                      ],
                    ),
                    if (invitation.programName != null)
                      Text(invitation.programName!, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (invitation.note != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                invitation.note!,
                style: text.bodyMedium?.copyWith(height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (invitation.programId != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push(
                      '${AppConstants.routeProgram}/${invitation.programId}',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('View program'),
                  ),
                ),
              if (invitation.programId != null) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: alreadyShared
                      ? () => context.push(
                            '${AppConstants.routeInstitution}/${invitation.institutionId}',
                          )
                      : () => _offerToShare(context, invitation),
                  child: Text(alreadyShared ? 'Open' : 'Share my passport'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Makes the consequence explicit before granting access. This is the moment
  /// a student stops being anonymous, so it should never be a one-tap accident.
  Future<void> _offerToShare(
      BuildContext context, Invitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Share with ${invitation.institutionName}?'),
        content: const Text(
          'They will be able to see your name, contact details, grades and any '
          'documents you have uploaded.\n\n'
          'You can revoke this at any time from your passport.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Share'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final passport = context.read<PassportProvider>();
    final ok = await passport.grantShare(
      invitation.institutionId,
      reason: 'You accepted an invitation from ${invitation.institutionName}',
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '${invitation.institutionName} can now see your passport.'
            : passport.error ?? 'Could not share your passport.'),
        backgroundColor: ok ? null : context.colors.error,
      ),
    );
  }
}

class _MatchesTab extends StatelessWidget {
  final MatchesProvider provider;
  final bool passportReady;

  const _MatchesTab({required this.provider, required this.passportReady});

  @override
  Widget build(BuildContext context) {
    if (!passportReady) {
      return EmptyState(
        icon: Icons.badge_outlined,
        title: 'Finish your passport first',
        message: 'Matching needs to know what you are looking for. Reach '
            '${AppConstants.minCompletenessToMatch}% and your matches will '
            'appear here.',
        actionLabel: 'Continue my passport',
        onAction: () => context.push(AppConstants.routePassportEdit),
      );
    }

    if (provider.matches.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          children: [
            const SizedBox(height: 40),
            EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matches yet',
              message: 'Nothing meets your criteria right now. Widening your '
                  'destinations or fields usually helps — or browse the '
                  'directory directly.',
              actionLabel: 'Browse programs',
              onAction: () => context.go(AppConstants.routeDiscover),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: provider.matches
            .map((match) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MatchCardTile(match: match),
                ))
            .toList(),
      ),
    );
  }
}

class _MatchCardTile extends StatelessWidget {
  final MatchCard match;

  const _MatchCardTile({required this.match});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final program = match.program;
    final institution = program?.institution;

    return InkWell(
      onTap: () =>
          context.push('${AppConstants.routeProgram}/${match.programId}'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InstitutionAvatar(
                  logoUrl: institution?.logoUrl,
                  initials: institution?.initials ?? '?',
                  size: 46,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        program?.name ?? 'Program',
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              institution?.name ?? '',
                              style: text.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (institution?.isVerified ?? false) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded,
                                size: 13, color: colors.success),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The score, shown as a figure rather than a vague label, so
                // the student can compare matches against each other.
                Column(
                  children: [
                    Text(
                      '${match.score}',
                      style: text.headlineSmall?.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('match',
                        style: text.labelSmall
                            ?.copyWith(color: colors.textLight)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Chip(
                  label: match.strengthLabel,
                  color: colors.accent,
                  background: colors.infoLight,
                ),
                if (program != null) ...[
                  const SizedBox(width: 6),
                  _Chip(
                    label: program.levelLabel,
                    color: colors.textSecondary,
                    background: colors.surfaceVariant,
                  ),
                ],
                if (match.hasScholarship) ...[
                  const SizedBox(width: 6),
                  _Chip(
                    label: 'Scholarships',
                    color: colors.warning,
                    background: colors.warningLight,
                    icon: Icons.savings_rounded,
                  ),
                ],
              ],
            ),

            // The reasoning. This is what makes the score trustworthy rather
            // than a number the student has to take on faith.
            if (match.rankedReasons.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: colors.divider),
              const SizedBox(height: 12),
              Text(
                'Why this matched',
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 8),
              ...match.rankedReasons.take(4).map(
                    (reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            reason.isHighlight
                                ? Icons.savings_rounded
                                : Icons.check_circle_rounded,
                            size: 14,
                            color: reason.isHighlight
                                ? colors.warning
                                : colors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reason.detail,
                              style: text.bodySmall?.copyWith(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],

            if (program != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: 14, color: colors.textLight),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(program.tuitionDisplay, style: text.bodySmall),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      );
}
