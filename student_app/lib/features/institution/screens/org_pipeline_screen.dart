import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/settings_section.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/pressable.dart';
import '../models/pipeline.dart';
import '../providers/org_desk_provider.dart';
import '../widgets/org_ui.dart';

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
  /// Null for every stage; otherwise one stage.
  String? _stage;

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
    final desk = context.watch<OrgDeskProvider>();
    final grouped = desk.byStage;
    final shown = _stage == null
        ? grouped
        : {if (grouped[_stage] != null) _stage!: grouped[_stage]!};

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Applications'),
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
                        padding: const EdgeInsets.only(top: 4, bottom: 40),
                        children: [
                          // Stages as filters: an officer usually works one
                          // column at a time, and a long scroll through every
                          // stage hides the one they came for.
                          OrgFilterBar<String?>(
                            selected: _stage,
                            onSelected: (v) => setState(() => _stage = v),
                            options: [
                              (null, 'All ${desk.applications.length}'),
                              for (final e in grouped.entries)
                                (e.key, '${stageLabel(e.key)} ${e.value.length}'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (desk.needingAttention > 0)
                            OrgNotice(
                              icon: Icons.circle,
                              tone: colors.warning,
                              message: '${desk.needingAttention} '
                                  '${desk.needingAttention == 1 ? 'application needs' : 'applications need'}'
                                  ' a look — newly submitted, or waiting on a '
                                  'document you asked for.',
                            ),
                          for (final entry in shown.entries) ...[
                            OrgSectionLabel(stageLabel(entry.key),
                                count: entry.value.length),
                            OrgGroup(
                              children: [
                                for (final application in entry.value)
                                  _ApplicationRow(entry: application),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  final PipelineEntry entry;

  const _ApplicationRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final country = countryLabel(entry.currentCountry);

    return OrgRow(
      onTap: () => _openSheet(context, entry),
      leading: StudentMark(
        isShared: entry.isShared,
        avatarUrl: entry.sharedAvatarUrl,
        initials: entry.initials,
      ),
      title: entry.displayName,
      emphasised: entry.needsAttention || entry.stage == 'submitted',
      meta: formatRelative(entry.updatedAt),
      subtitle: '${entry.programName}'
          '${entry.intake == null ? '' : ' · ${entry.intake}'}',
      tags: [
        if (entry.outstandingRequests > 0)
          OrgTag(
            entry.outstandingRequests == 1
                ? 'Document awaited'
                : '${entry.outstandingRequests} documents awaited',
            tone: colors.warning,
            icon: Icons.schedule_rounded,
          ),
        if (entry.gradeBand != null) OrgTag(entry.gradeBand!),
        if (entry.englishBand != null) OrgTag('English ${entry.englishBand}'),
        if (country.isNotEmpty) OrgTag(country),
        if (entry.documentCount > 0)
          OrgTag(entry.documentCount == 1
              ? '1 document'
              : '${entry.documentCount} documents'),
      ],
    );
  }
}

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
    final note = (entry.studentNote ?? '').trim();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Row(
                children: [
                  StudentMark(
                    isShared: entry.isShared,
                    avatarUrl: entry.sharedAvatarUrl,
                    initials: entry.initials,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.displayName,
                            style: text.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          '${entry.programName}'
                          '${entry.intake == null ? '' : ' · ${entry.intake}'}',
                          style: text.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        OrgTag(stageLabel(entry.stage)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!entry.isShared)
              const OrgNotice(
                icon: Icons.lock_outline_rounded,
                margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
                message: 'They have not shared their passport, so their name '
                    'stays hidden. You can still review, request documents and '
                    'make an offer.',
              ),
            if (note.isNotEmpty) ...[
              const OrgSectionLabel('Their note'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(note,
                    style: text.bodyMedium?.copyWith(height: 1.45)),
              ),
            ],
            SettingsSection(
              rows: [
                SettingsRow(
                  icon: entry.isShared
                      ? Icons.badge_outlined
                      : Icons.folder_open_outlined,
                  label: entry.isShared
                      ? 'View passport & documents'
                      : 'View documents they sent',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(
                        '${AppConstants.routeOrgStudent}/${entry.token}');
                  },
                ),
                SettingsRow(
                  icon: Icons.upload_file_outlined,
                  label: 'Request a document',
                  value: entry.outstandingRequests > 0
                      ? '${entry.outstandingRequests} awaited'
                      : null,
                  onTap: desk.busy ? null : () => _askForDocument(context, entry),
                ),
              ],
            ),
            const OrgSectionLabel('Move to'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final stage in pipelineStages)
                    if (stage != entry.stage)
                      Pressable(
                        onTap: desk.busy
                            ? null
                            : () => _move(context, entry, stage),
                        semanticLabel: 'Move to ${stageLabel(stage)}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: colors.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            stageLabel(stage),
                            style: text.labelLarge?.copyWith(
                              color: stage == 'rejected'
                                  ? colors.error
                                  : colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                ],
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
