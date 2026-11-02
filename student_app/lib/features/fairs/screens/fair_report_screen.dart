import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/fair.dart';
import '../providers/fairs_provider.dart';

/// "Your Education Fair Report" — what the student actually got out of the day.
///
/// Assembled by the `fair_report` SQL function in a single call, so the whole
/// screen loads on one round trip rather than six.
class FairReportScreen extends StatefulWidget {
  final String fairId;

  const FairReportScreen({super.key, required this.fairId});

  @override
  State<FairReportScreen> createState() => _FairReportScreenState();
}

class _FairReportScreenState extends State<FairReportScreen> {
  FairReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<FairsProvider>();
    final report = await provider.fetchReport(widget.fairId);
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
      _error = report == null ? provider.error : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final report = _report;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (report == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: _error ?? 'Could not load your report.',
          onRetry: _load,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fair report')),
      body: report.isEmpty
          ? const EmptyState(
              icon: Icons.qr_code_2_rounded,
              title: 'Nothing recorded yet',
              message: 'Once you connect at a booth, your report will show '
                  'every institution you met and every program that matched.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(report.fairName, style: text.headlineSmall),
                const SizedBox(height: 20),

                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    _Stat(
                      value: '${report.institutionsMet}',
                      label: report.institutionsMet == 1
                          ? 'institution met'
                          : 'institutions met',
                      color: colors.accent,
                      background: colors.infoLight,
                    ),
                    _Stat(
                      value: '${report.programsMatched}',
                      label: 'programs matched',
                      color: colors.success,
                      background: colors.successLight,
                    ),
                    _Stat(
                      value: '${report.followUpsRequested}',
                      label: 'follow-ups requested',
                      color: colors.accent,
                      background: colors.infoLight,
                    ),
                    _Stat(
                      value: '${report.scholarshipDiscussions}',
                      label: 'scholarship talks',
                      color: colors.warning,
                      background: colors.warningLight,
                    ),
                  ],
                ),

                if (report.applicationsStarted > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.successLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.send_rounded, size: 20, color: colors.success),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${report.applicationsStarted} application'
                            '${report.applicationsStarted == 1 ? '' : 's'} '
                            'started with institutions from this fair.',
                            style: text.bodyMedium?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Text('Who you met', style: text.titleLarge),
                const SizedBox(height: 12),
                ...report.visits.map(
                  (visit) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
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
                            logoUrl: visit.institutionLogoUrl,
                            initials: visit.institutionName.isEmpty
                                ? '?'
                                : visit.institutionName[0].toUpperCase(),
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(visit.institutionName,
                                    style: text.titleMedium,
                                    overflow: TextOverflow.ellipsis),
                                if (visit.programInterest != null)
                                  Text(visit.programInterest!,
                                      style: text.bodySmall),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (visit.followUpRequested)
                                      _Tag(
                                        label: 'Follow-up requested',
                                        color: colors.accent,
                                        background: colors.infoLight,
                                      ),
                                    if (visit.scholarshipDiscussed)
                                      _Tag(
                                        label: 'Scholarship discussed',
                                        color: colors.warning,
                                        background: colors.warningLight,
                                      ),
                                    _Tag(
                                      label: '${visit.interestLevel} interest',
                                      color: colors.textSecondary,
                                      background: colors.surfaceVariant,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color background;

  const _Stat({
    required this.value,
    required this.label,
    required this.color,
    required this.background,
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: text.displaySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: text.bodySmall?.copyWith(height: 1.3)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _Tag({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      );
}
