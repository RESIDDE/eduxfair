import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeline_tile/timeline_tile.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../passport/providers/passport_provider.dart';
import '../models/application.dart';
import '../providers/applications_provider.dart';

/// One application, its documents, and its full decision history.
class ApplicationDetailScreen extends StatefulWidget {
  final String applicationId;

  const ApplicationDetailScreen({super.key, required this.applicationId});

  @override
  State<ApplicationDetailScreen> createState() =>
      _ApplicationDetailScreenState();
}

class _ApplicationDetailScreenState extends State<ApplicationDetailScreen> {
  Application? _application;
  List<String> _attachedIds = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<ApplicationsProvider>();
    final application = await provider.fetchOne(widget.applicationId);
    final attached = await provider.attachedDocumentIds(widget.applicationId);
    if (!mounted) return;

    await context.read<PassportProvider>().load();
    if (!mounted) return;

    setState(() {
      _application = application;
      _attachedIds = attached;
      _loading = false;
    });
  }

  Future<void> _setStage(String stage) async {
    final application = _application;
    if (application == null) return;

    final label = AppConstants.applicationStages[stage] ?? stage;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label?'),
        content: Text(_confirmCopy(stage, application)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
            child: Text(label),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<ApplicationsProvider>();
    final ok = await provider.setStage(application, stage);
    if (!mounted) return;

    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated to $label.')),
      );
    } else {
      // The database guard raises a readable message, so it is shown as-is.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not update.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  static String _confirmCopy(String stage, Application application) {
    final institution = application.institution?.name ?? 'the institution';
    return switch (stage) {
      'submitted' =>
        'Your application goes to $institution, and they will be able to see '
            'your passport and attached documents. You can revoke that access '
            'later from your passport.',
      'accepted' =>
        'You are accepting the offer from $institution. Make sure you have '
            'read the conditions first.',
      'withdrawn' =>
        'This withdraws your application from $institution. You can apply '
            'again for a later intake.',
      _ => 'Continue?',
    };
  }

  Future<void> _manageDocuments() async {
    final application = _application;
    if (application == null) return;

    final passport = context.read<PassportProvider>();
    final provider = context.read<ApplicationsProvider>();

    if (passport.documents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload documents to your passport first.'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Attach documents',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  // Reassures the student that attaching is a reference, not a
                  // re-upload — the point of a document-ready profile.
                  'These stay in your passport. Attaching just links them to '
                  'this application.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              ),
              ...passport.documents.map((doc) {
                final attached = _attachedIds.contains(doc.id);
                return CheckboxListTile(
                  value: attached,
                  title: Text(doc.kindLabel),
                  subtitle: Text(doc.fileName, overflow: TextOverflow.ellipsis),
                  onChanged: (want) async {
                    final ok = want == true
                        ? await provider.attachDocument(
                            applicationId: application.id,
                            documentId: doc.id,
                          )
                        : await provider.detachDocument(
                            applicationId: application.id,
                            documentId: doc.id,
                          );
                    if (!ok) return;
                    setSheetState(() {
                      want == true
                          ? _attachedIds.add(doc.id)
                          : _attachedIds.remove(doc.id);
                    });
                    setState(() {});
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final application = _application;
    final provider = context.watch<ApplicationsProvider>();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (application == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: 'Not found', onRetry: _load),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Application')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InstitutionAvatar(
                logoUrl: application.institution?.logoUrl,
                initials: application.institution?.initials ?? '?',
                size: 54,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(application.program?.name ?? 'Program',
                        style: text.titleLarge),
                    Text(application.institution?.name ?? '',
                        style: text.bodySmall),
                    if (application.intake != null)
                      Text('Intake: ${application.intake}',
                          style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: application.hasOffer
                  ? colors.successLight
                  : colors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current stage',
                  style: text.labelMedium?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  application.stageLabel,
                  style: text.headlineSmall?.copyWith(
                    color: application.hasOffer ? colors.success : null,
                  ),
                ),
              ],
            ),
          ),

          // Outstanding document requests block the application, so they come
          // before anything else the student might do.
          if (application.outstandingRequests.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('They need from you', style: text.titleLarge),
            const SizedBox(height: 10),
            ...application.outstandingRequests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.warningLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.upload_file_rounded,
                          size: 18, color: colors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(request.kindLabel, style: text.titleSmall),
                            if (request.note != null)
                              Text(request.note!,
                                  style: text.bodySmall?.copyWith(height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Documents (${_attachedIds.length})',
                  style: text.titleLarge,
                ),
              ),
              TextButton(
                onPressed: _manageDocuments,
                child: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _attachedIds.isEmpty
                ? 'Nothing attached yet.'
                : '$_attachedCountLabel attached from your passport.',
            style: text.bodySmall,
          ),

          // The decision history. Append-only in the database — no role,
          // admin included, can rewrite it — which is what makes it worth
          // showing as the record of what happened.
          if (application.events.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('History', style: text.titleLarge),
            const SizedBox(height: 12),
            ...application.events.asMap().entries.map((entry) {
              final index = entry.key;
              final event = entry.value;
              final isLast = index == application.events.length - 1;

              return TimelineTile(
                isFirst: index == 0,
                isLast: isLast,
                alignment: TimelineAlign.start,
                indicatorStyle: IndicatorStyle(
                  width: 14,
                  color: isLast ? colors.accent : colors.border,
                  indicatorXY: 0.2,
                ),
                beforeLineStyle: LineStyle(color: colors.border, thickness: 1.5),
                afterLineStyle: LineStyle(color: colors.border, thickness: 1.5),
                endChild: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 0, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.stageLabel, style: text.titleSmall),
                      Text(
                        _formatDateTime(event.createdAt),
                        style: text.labelSmall?.copyWith(color: colors.textLight),
                      ),
                      if (event.note != null) ...[
                        const SizedBox(height: 4),
                        Text(event.note!,
                            style: text.bodySmall?.copyWith(height: 1.4)),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],

          if (application.availableActions.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...application.availableActions.map((stage) {
              final label = AppConstants.applicationStages[stage] ?? stage;
              final isPrimary = stage == 'submitted' || stage == 'accepted';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: isPrimary
                    ? ElevatedButton(
                        onPressed: provider.busy ? null : () => _setStage(stage),
                        child: Text(
                          stage == 'submitted' ? 'Submit application' : label,
                        ),
                      )
                    : OutlinedButton(
                        onPressed: provider.busy ? null : () => _setStage(stage),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.error,
                          side: BorderSide(color: colors.error),
                        ),
                        child: Text(label),
                      ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String get _attachedCountLabel =>
      _attachedIds.length == 1 ? '1 document' : '${_attachedIds.length} documents';

  static String _formatDateTime(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour < 12 ? 'am' : 'pm';
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '$hour:${d.minute.toString().padLeft(2, '0')}$period';
  }
}
