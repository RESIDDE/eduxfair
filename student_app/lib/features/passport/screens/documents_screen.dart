import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../models/passport_document.dart';
import '../providers/passport_provider.dart';

/// Upload and manage passport documents.
///
/// Documents are uploaded once and attached to as many applications as needed —
/// the whole point of a "document-ready profile".
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PassportProvider>().load();
    });
  }

  Future<void> _pickAndUpload() async {
    final kind = await _chooseKind();
    if (kind == null || !mounted) return;

    // `withData: true` is essential: on web there is no file path at all, and
    // asking for bytes is the one approach that works on all three platforms.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'doc', 'docx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;

    if (bytes == null) {
      _toast('Could not read that file.', isError: true);
      return;
    }
    // Matches the bucket's own limit, so the student hears about it before
    // spending their data allowance on the upload.
    if (bytes.length > 20 * 1024 * 1024) {
      _toast('That file is larger than 20 MB.', isError: true);
      return;
    }

    final provider = context.read<PassportProvider>();
    final ok = await provider.uploadDocument(
      kind: kind,
      fileName: file.name,
      bytes: bytes,
      mime: _mimeFor(file.extension),
    );

    if (!mounted) return;
    _toast(ok
        ? 'Uploaded. It will be checked when you request verification.'
        : provider.error ?? 'Could not upload that file.',
        isError: !ok);
  }

  Future<String?> _chooseKind() => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'What kind of document?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...AppConstants.documentKinds.entries.map(
                (entry) => ListTile(
                  leading: Icon(_iconFor(entry.key)),
                  title: Text(entry.value),
                  onTap: () => Navigator.of(context).pop(entry.key),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _view(PassportDocument doc) async {
    final provider = context.read<PassportProvider>();
    final url = await provider.documentUrl(doc);
    if (!mounted) return;

    if (url == null) {
      _toast(provider.error ?? 'Could not open that document.', isError: true);
      return;
    }

    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _toast('Could not open that document.', isError: true);
    }
  }

  Future<void> _confirmDelete(PassportDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: Text(
          '${doc.fileName} will be removed. Any application you attached it '
          'to will no longer show it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<PassportProvider>();
    final ok = await provider.deleteDocument(doc);
    if (!mounted) return;
    if (!ok) {
      _toast(provider.error ?? 'Could not delete that document.', isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? context.colors.error : null,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  static String? _mimeFor(String? extension) => switch (extension?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'heic' => 'image/heic',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ => null,
      };

  static IconData _iconFor(String kind) => switch (kind) {
        'transcript' => Icons.description_outlined,
        'certificate' => Icons.workspace_premium_outlined,
        'passport_id' => Icons.badge_outlined,
        'english_test' => Icons.translate_rounded,
        'cv' => Icons.article_outlined,
        'recommendation' => Icons.mail_outline_rounded,
        'statement' => Icons.edit_note_rounded,
        'financial' => Icons.account_balance_outlined,
        _ => Icons.insert_drive_file_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<PassportProvider>();
    final documents = provider.documents;

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: provider.saving ? null : _pickAndUpload,
        icon: provider.saving
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: context.colors.onAccent,
                ),
              )
            : const Icon(Icons.upload_file_rounded),
        label: Text(provider.saving ? 'Uploading…' : 'Add document'),
      ),
      body: provider.loading && documents.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : documents.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_outlined,
                  title: 'No documents yet',
                  message: 'Upload your transcript, certificates and ID once. '
                      'You can then attach them to any application without '
                      'uploading again.',
                )
              : RefreshIndicator(
                  onRefresh: provider.load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.infoLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 18, color: colors.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Only you can see these until you share your '
                                'passport with an institution.',
                                style: text.bodySmall?.copyWith(height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...documents.map(
                        (doc) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DocumentTile(
                            document: doc,
                            onView: () => _view(doc),
                            onDelete: () => _confirmDelete(doc),
                            icon: _iconFor(doc.kind),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final PassportDocument document;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final IconData icon;

  const _DocumentTile({
    required this.document,
    required this.onView,
    required this.onDelete,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final (statusColor, statusLabel) = document.isVerified
        ? (colors.success, 'Verified')
        : document.isRejected
            ? (colors.error, 'Declined')
            : (colors.warning, 'Awaiting review');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(document.kindLabel, style: text.titleMedium),
                    Text(
                      '${document.fileName}  ·  ${document.sizeDisplay}',
                      style: text.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: text.labelSmall?.copyWith(color: statusColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open',
                onPressed: onView,
                icon: const Icon(Icons.open_in_new_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: colors.error),
              ),
            ],
          ),
          // A reviewer's note is the only way a student learns why a document
          // was declined, so it is shown rather than tucked away.
          if (document.isRejected && document.reviewNote != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.errorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                document.reviewNote!,
                style: text.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
