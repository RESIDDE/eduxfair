import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/application.dart';
import '../providers/applications_provider.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ApplicationsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final provider = context.watch<ApplicationsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('My applications')),
      body: provider.loading && provider.applications.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.applications.isEmpty
              ? EmptyState(
                  icon: Icons.send_outlined,
                  title: 'No applications yet',
                  message: 'Start one from any program page. We will keep your '
                      'documents attached so you never upload twice.',
                  actionLabel: 'Browse programs',
                  onAction: () => context.go(AppConstants.routeDiscover),
                )
              : RefreshIndicator(
                  onRefresh: provider.load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      if (provider.active.isNotEmpty) ...[
                        Text('In progress', style: text.titleLarge),
                        const SizedBox(height: 12),
                        ...provider.active.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ApplicationCard(application: a),
                          ),
                        ),
                      ],
                      if (provider.closed.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Closed', style: text.titleLarge),
                        const SizedBox(height: 12),
                        ...provider.closed.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ApplicationCard(application: a),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class ApplicationCard extends StatelessWidget {
  final Application application;

  const ApplicationCard({super.key, required this.application});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final stageColor = application.isClosed
        ? colors.textLight
        : application.hasOffer
            ? colors.success
            : application.isDraft
                ? colors.textSecondary
                : colors.accent;

    return InkWell(
      onTap: () => context.push(
        '${AppConstants.routeApplicationDetail}/${application.id}',
      ),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: application.hasOffer ? colors.success : colors.border,
            width: application.hasOffer ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InstitutionAvatar(
                  logoUrl: application.institution?.logoUrl,
                  initials: application.institution?.initials ?? '?',
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.program?.name ?? 'Program',
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        application.institution?.name ?? '',
                        style: text.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: stageColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    application.stageLabel,
                    style: text.labelSmall?.copyWith(
                      color: stageColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (application.intake != null) ...[
                  const SizedBox(width: 8),
                  Text(application.intake!, style: text.bodySmall),
                ],
                const Spacer(),
                if (application.outstandingRequests.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.upload_file_rounded,
                          size: 14, color: colors.warning),
                      const SizedBox(width: 4),
                      Text(
                        '${application.outstandingRequests.length} needed',
                        style: text.labelSmall?.copyWith(color: colors.warning),
                      ),
                    ],
                  ),
              ],
            ),
            if (!application.isClosed) ...[
              const SizedBox(height: 12),
              LinearPercentIndicator(
                percent: application.progress,
                lineHeight: 5,
                padding: EdgeInsets.zero,
                barRadius: const Radius.circular(3),
                backgroundColor: colors.surfaceVariant,
                progressColor: stageColor,
                animation: true,
                animationDuration: 500,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
