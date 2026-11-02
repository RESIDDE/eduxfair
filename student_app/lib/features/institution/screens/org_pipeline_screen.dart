import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pressable.dart';
import '../models/pipeline.dart';
import '../providers/org_desk_provider.dart';

/// Every application to this institution, grouped by the stage it is at.
///
/// A list rather than a drag-and-drop board. Dragging a card between columns
/// is the obvious design and the wrong one on a phone: the stages do not fit
/// side by side, and a stage change here is a decision with a reason attached,
/// not a gesture you can make by accident.
class OrgPipelineScreen extends StatefulWidget {
  const OrgPipelineScreen({super.key});

  @override
  State<OrgPipelineScreen> createState() => _OrgPipelineScreenState();
}

class _OrgPipelineScreenState extends State<OrgPipelineScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OrgDeskProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final desk = context.watch<OrgDeskProvider>();
    final grouped = desk.byStage;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Pipeline'),
      ),
      body: desk.loading && desk.applications.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : desk.error != null && desk.applications.isEmpty
              ? ErrorState(message: desk.error!, onRetry: desk.load)
              : desk.applications.isEmpty
                  ? const EmptyState(
                      icon: Icons.workspaces_outline,
                      title: 'No applications yet',
                      message: 'When a student applies to one of your '
                          'programmes it lands here, and every move it makes '
                          'is recorded.',
                    )
                  : RefreshIndicator(
                      onRefresh: desk.load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
                        children: [
                          if (desk.needingAttention > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: colors.warningLight,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${desk.needingAttention} '
                                  '${desk.needingAttention == 1 ? 'application needs' : 'applications need'}'
                                  ' a look — newly submitted, or waiting on a '
                                  'document you asked for.',
                                  style: text.bodySmall?.copyWith(height: 1.4),
                                ),
                              ),
                            ),
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(2, 10, 2, 8),
                              child: Row(
                                children: [
                                  Text(stageLabel(entry.key),
                                      style: text.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: colors.textPrimary)),
                                  const SizedBox(width: 8),
                                  Text('${entry.value.length}',
                                      style: text.labelSmall),
                                ],
                              ),
                            ),
                            for (final application in entry.value)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ApplicationCard(entry: application),
                              ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final PipelineEntry entry;

  const _ApplicationCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Pressable.surface(
      haptic: null,
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openSheet(context, entry),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: entry.needsAttention ? colors.warning : colors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.displayName,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (!entry.isShared)
                  Icon(Icons.lock_outline_rounded,
                      size: 15, color: colors.textLight),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.programName}'
              '${entry.intake == null ? '' : ' · ${entry.intake}'}',
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (entry.gradeBand != null) _Chip(label: entry.gradeBand!),
                if (entry.englishBand != null)
                  _Chip(label: 'English ${entry.englishBand}'),
                if (entry.currentCountry != null)
                  _Chip(label: entry.currentCountry!),
                if (entry.documentCount > 0)
                  _Chip(label: '${entry.documentCount} docs'),
                if (entry.outstandingRequests > 0)
                  _Chip(
                    label: '${entry.outstandingRequests} awaited',
                    tone: colors.warning,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Updated ${formatRelative(entry.updatedAt)}',
                style: text.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? tone;

  const _Chip({required this.label, this.tone});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final colour = tone ?? colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: colour, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Everything you can do to one application, in one sheet.
Future<void> _openSheet(BuildContext context, PipelineEntry entry) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ApplicationSheet(entry: entry),
  );
}

class _ApplicationSheet extends StatelessWidget {
  final PipelineEntry entry;

  const _ApplicationSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final desk = context.watch<OrgDeskProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.displayName, style: text.headlineSmall),
            Text('${entry.programName} · ${stageLabel(entry.stage)}',
                style: text.bodySmall),
            if (!entry.isShared) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'This student has not shared their passport, so their name '
                  'and documents stay hidden. You can still review, request '
                  'documents and make an offer.',
                  style: text.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            ],
            if ((entry.studentNote ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Their note', style: text.titleSmall),
              const SizedBox(height: 4),
              Text(entry.studentNote!.trim(),
                  style: text.bodySmall?.copyWith(height: 1.45)),
            ],
            const SizedBox(height: 18),
            Text('Move to', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stage in pipelineStages)
                  if (stage != entry.stage)
                    ActionChip(
                      label: Text(stageLabel(stage)),
                      onPressed: desk.busy
                          ? null
                          : () => _move(context, entry, stage),
                    ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    desk.busy ? null : () => _askForDocument(context, entry),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Request a document'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the reason before moving, because the reason is the point.
Future<void> _move(
    BuildContext context, PipelineEntry entry, String stage) async {
  final controller = TextEditingController();
  final desk = context.read<OrgDeskProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Move to ${stageLabel(stage)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'This goes into the application’s history, which nobody can '
            'edit afterwards — including you.',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Why this decision was made',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Move'),
        ),
      ],
    ),
  );

  final note = controller.text;
  controller.dispose();
  if (confirmed != true) return;

  final ok = await desk.setStage(entry.applicationId, stage,
      note: note.trim().isEmpty ? null : note);

  if (ok) {
    navigator.pop();
    messenger.showSnackBar(
        SnackBar(content: Text('Moved to ${stageLabel(stage)}.')));
  } else {
    messenger.showSnackBar(SnackBar(
      content: Text(desk.error ?? 'Could not move that application.'),
    ));
    desk.clearError();
  }
}

Future<void> _askForDocument(BuildContext context, PipelineEntry entry) async {
  final desk = context.read<OrgDeskProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in AppConstants.documentKinds.entries)
            ListTile(
              title: Text(entry.value),
              onTap: () => Navigator.of(sheetContext).pop(entry.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (kind == null) return;

  final ok = await desk.requestDocument(entry.applicationId, kind);
  if (ok) {
    navigator.pop();
    messenger.showSnackBar(const SnackBar(
      content: Text('Asked for it. The student sees it on their application.'),
    ));
  } else {
    messenger.showSnackBar(
        SnackBar(content: Text(desk.error ?? 'Could not request that.')));
    desk.clearError();
  }
}
