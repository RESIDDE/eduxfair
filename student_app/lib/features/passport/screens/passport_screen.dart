import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/verified_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/passport_provider.dart';

/// The Education Passport at a glance: how complete it is, what it says, and
/// who can see it.
class PassportScreen extends StatefulWidget {
  const PassportScreen({super.key});

  @override
  State<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends State<PassportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PassportProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<PassportProvider>();
    final user = context.watch<AuthProvider>().user;
    final passport = provider.passport;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Passport'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => context.push(AppConstants.routePassportEdit),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: provider.loading && passport == null
          ? const Center(child: CircularProgressIndicator())
          : provider.error != null && passport == null
              ? ErrorState(
                  message: provider.error!,
                  onRetry: () => provider.load(),
                )
              : passport == null
                  ? EmptyState(
                      icon: Icons.badge_outlined,
                      title: 'Build your passport',
                      message: 'Enter your qualifications once, and every '
                          'institution can see them with your permission.',
                      actionLabel: 'Get started',
                      onAction: () =>
                          context.push(AppConstants.routePassportEdit),
                    )
                  : RefreshIndicator(
                      onRefresh: provider.load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        children: [
                          // ── Completeness ─────────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.border),
                            ),
                            child: Row(
                              children: [
                                CircularPercentIndicator(
                                  radius: 38,
                                  lineWidth: 7,
                                  percent: provider.completenessFraction,
                                  animation: true,
                                  animationDuration: 700,
                                  circularStrokeCap: CircularStrokeCap.round,
                                  backgroundColor: colors.surfaceVariant,
                                  progressColor: provider.isMatchable
                                      ? colors.success
                                      : colors.warning,
                                  center: Text(
                                    '${provider.completeness}%',
                                    style: text.titleLarge,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        provider.isMatchable
                                            ? 'Visible to institutions'
                                            : 'Not yet discoverable',
                                        style: text.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        provider.isMatchable
                                            ? 'Institutions offering your '
                                                'programs can find your '
                                                'profile.'
                                            : 'Reach '
                                                '${AppConstants.minCompletenessToMatch}% '
                                                'so institutions can match '
                                                'with you.',
                                        style: text.bodySmall
                                            ?.copyWith(height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── What's missing ───────────────────────────────
                          if (passport.missingPieces.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.warningLight,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Still to add',
                                    style: text.titleSmall?.copyWith(
                                      color: colors.warning,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...passport.missingPieces.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Icon(Icons.add_circle_outline,
                                              size: 15,
                                              color: colors.warning),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(item,
                                                style: text.bodySmall),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextButton(
                                    onPressed: () => context
                                        .push(AppConstants.routePassportEdit),
                                    style: TextButton.styleFrom(
                                      foregroundColor: colors.warning,
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Complete my passport'),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // ── Verification ─────────────────────────────────
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Text('Verification',
                                    style: text.titleLarge),
                              ),
                              VerificationStatusChip(
                                status: passport.verificationStatus,
                                subject: VerifiedSubject.student,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            passport.isVerified
                                ? 'An Eduxfair reviewer checked your documents '
                                    'against the qualifications you entered.'
                                : passport.isPendingVerification
                                    ? 'Your documents are in the review queue.'
                                    : 'Upload your documents and request a '
                                        'review. Verified passports are shown '
                                        'first to institutions.',
                            style: text.bodySmall?.copyWith(height: 1.45),
                          ),
                          if (!passport.isVerified &&
                              !passport.isPendingVerification) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: provider.documents.isEmpty
                                  ? null
                                  : () async {
                                      final ok = await provider
                                          .requestVerification();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(ok
                                            ? 'Your passport is in the review '
                                                'queue.'
                                            : provider.error ??
                                                'Could not request review.'),
                                      ));
                                    },
                              child: Text(provider.documents.isEmpty
                                  ? 'Upload a document first'
                                  : 'Request verification'),
                            ),
                          ],

                          // ── Details ──────────────────────────────────────
                          const SizedBox(height: 24),
                          Text('Your details', style: text.titleLarge),
                          const SizedBox(height: 12),
                          _DetailCard(rows: [
                            _Row('Name', user?.fullName ?? '—'),
                            _Row(
                              'Date of birth',
                              passport.dateOfBirth == null
                                  ? 'Not added'
                                  : _formatDate(passport.dateOfBirth!),
                            ),
                            _Row(
                              'Nationality',
                              AppConstants.homeCountries[passport.nationality] ??
                                  passport.nationality ??
                                  'Not added',
                            ),
                            _Row(
                              'Currently in',
                              AppConstants
                                      .homeCountries[passport.currentCountry] ??
                                  passport.currentCountry ??
                                  'Not added',
                            ),
                          ]),

                          const SizedBox(height: 16),
                          Text('Academics', style: text.titleLarge),
                          const SizedBox(height: 12),
                          _DetailCard(rows: [
                            _Row('Highest qualification',
                                passport.highestQualification ?? 'Not added'),
                            _Row('Grade', passport.gradeDisplay),
                            if (passport.gradeScheme != null)
                              _Row('Grading scheme', passport.gradeSchemeLabel),
                            _Row('English test', passport.englishTestLabel),
                            if (passport.englishBand != null)
                              _Row(
                                'IELTS equivalent',
                                'Band ${passport.englishBand!
                                    .toStringAsFixed(1)}',
                              ),
                          ]),

                          const SizedBox(height: 16),
                          Text('What you are looking for',
                              style: text.titleLarge),
                          const SizedBox(height: 12),
                          _DetailCard(rows: [
                            _Row(
                              'Destinations',
                              passport.targetCountries.isEmpty
                                  ? 'Not chosen'
                                  : passport.targetCountries
                                      .map((c) =>
                                          AppConstants
                                              .popularDestinations[c] ??
                                          c)
                                      .join(', '),
                            ),
                            _Row(
                              'Study level',
                              passport.targetLevels.isEmpty
                                  ? 'Not chosen'
                                  : passport.targetLevels
                                      .map((l) =>
                                          AppConstants.studyLevels[l] ?? l)
                                      .join(', '),
                            ),
                            _Row(
                              'Fields',
                              passport.targetFields.isEmpty
                                  ? 'Not chosen'
                                  : passport.targetFields
                                      .map(provider.fieldLabel)
                                      .join(', '),
                            ),
                            _Row('Budget', passport.budgetDisplay),
                            _Row('Intake',
                                passport.intendedIntake ?? 'Not chosen'),
                          ]),

                          // ── Documents and sharing ────────────────────────
                          const SizedBox(height: 24),
                          _NavTile(
                            icon: Icons.folder_outlined,
                            title: 'Documents',
                            subtitle: provider.documents.isEmpty
                                ? 'No documents yet'
                                : '${provider.documents.length} uploaded',
                            onTap: () =>
                                context.push(AppConstants.routeDocuments),
                          ),
                          const SizedBox(height: 10),
                          _NavTile(
                            icon: Icons.visibility_outlined,
                            title: 'Who can see my passport',
                            subtitle: provider.activeShares.isEmpty
                                ? 'No institution can see your details'
                                : '${provider.activeShares.length} '
                                    'institution${provider.activeShares.length == 1 ? '' : 's'}',
                            onTap: () => context.push(AppConstants.routeSharing),
                          ),
                        ],
                      ),
                    ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _DetailCard extends StatelessWidget {
  final List<_Row> rows;
  const _DetailCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(rows[i].label, style: text.bodySmall),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].value,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1)
              Divider(height: 1, color: colors.divider, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  Text(subtitle, style: text.bodySmall),
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
