import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../supabase/supabase_service.dart';
import '../theme/app_colors.dart';

/// Opens a stored file inside the app.
///
/// Passports, application documents and chat attachments used to open in the
/// browser or another app, which took a student out of the app to look at
/// their own transcript, and took an admissions officer out of it to read
/// one they had been sent. This is the one viewer all of them use.
///
/// The file is read through Supabase storage with the signed-in user's own
/// session, so the same access rules apply as everywhere else — a university
/// sees a document only if the student shared or sent it.
Future<void> openDocument(
  BuildContext context, {
  required String bucket,
  required String path,
  required String fileName,
  String? title,
  String? mime,
}) =>
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(
          bucket: bucket,
          path: path,
          fileName: fileName,
          title: title,
          mime: mime,
        ),
      ),
    );

enum _Kind { pdf, image, word, other }

class DocumentViewerScreen extends StatefulWidget {
  final String bucket;
  final String path;
  final String fileName;
  final String? title;
  final String? mime;

  const DocumentViewerScreen({
    super.key,
    required this.bucket,
    required this.path,
    required this.fileName,
    this.title,
    this.mime,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  WebViewController? _web;

  _Kind get _kind {
    final mime = (widget.mime ?? '').toLowerCase();
    final ext = widget.fileName.split('.').last.toLowerCase();
    if (mime == 'application/pdf' || ext == 'pdf') return _Kind.pdf;
    if (mime.startsWith('image/') ||
        const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'].contains(ext)) {
      return _Kind.image;
    }
    if (mime.contains('word') || ext == 'doc' || ext == 'docx') return _Kind.word;
    return _Kind.other;
  }

  /// iOS draws Word documents itself (WKWebView uses the same renderer as
  /// Quick Look). Android and the web have nothing equivalent built in.
  bool get _canShowWordHere =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _bytes = null;
      _error = null;
    });
    try {
      final bytes = await SupabaseService.instance.client.storage
          .from(widget.bucket)
          .download(widget.path);
      if (!mounted) return;

      if (_kind == _Kind.word && _canShowWordHere) {
        // WKWebView renders a Word file from a local file URL, so it is
        // written to the app's own temporary folder first. Nothing leaves the
        // device, and the OS clears the folder.
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_'
            '${widget.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
        await file.writeAsBytes(bytes, flush: true);
        final controller = WebViewController();
        await controller.loadFile(file.path);
        if (!mounted) return;
        setState(() {
          _web = controller;
          _bytes = bytes;
        });
        return;
      }

      setState(() => _bytes = bytes);
    } catch (e) {
      // Plain words, not the storage service's JSON. The usual causes are the
      // file having been deleted, or access having been withdrawn.
      if (mounted) {
        setState(() => _error = 'It may have been deleted, or you may no '
            'longer have access to it. Check your connection and try again.');
      }
      debugPrint('document viewer: $e');
    }
  }

  /// For the one case the app cannot draw — a Word file off iOS — and only
  /// when the person asks.
  Future<void> _openElsewhere() async {
    try {
      final url = await SupabaseService.instance.signedUrl(
        bucket: widget.bucket,
        path: widget.path,
        expiresIn: const Duration(minutes: 10),
      );
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(SupabaseService.describeError(e)),
        backgroundColor: context.colors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final isImage = _kind == _Kind.image;

    return Scaffold(
      // Photos sit on black, like Photos does; documents on the page colour.
      backgroundColor: isImage ? Colors.black : colors.background,
      appBar: AppBar(
        backgroundColor: isImage ? Colors.black : null,
        foregroundColor: isImage ? Colors.white : null,
        // The theme's icon colour is dark; on the photo viewer's black it
        // vanished, and with it the only way back.
        iconTheme: isImage ? const IconThemeData(color: Colors.white) : null,
        // Plain Navigator back: this page is pushed imperatively, outside
        // the router's own stack.
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title ?? widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isImage ? Colors.white : null,
              ),
            ),
            if (widget.title != null)
              Text(
                widget.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: isImage ? Colors.white70 : colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
      body: _error != null
          ? _Message(
              icon: Icons.error_outline_rounded,
              title: 'This document could not be opened',
              detail: _error!,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : _bytes == null
              ? Center(
                  child: CircularProgressIndicator(
                      color: isImage ? Colors.white : null),
                )
              : switch (_kind) {
                  _Kind.pdf => PdfViewer.data(
                      _bytes!,
                      sourceName: widget.path,
                      params: PdfViewerParams(
                        backgroundColor: colors.surfaceVariant,
                        margin: 10,
                        errorBannerBuilder: (context, error, _, __) => _Message(
                          icon: Icons.error_outline_rounded,
                          title: 'This PDF could not be read',
                          detail: '$error',
                        ),
                      ),
                    ),
                  // Pinch to zoom and drag to pan, as in Photos.
                  _Kind.image => InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: Image.memory(
                          _bytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const _Message(
                            icon: Icons.broken_image_outlined,
                            title: 'This image could not be shown',
                            detail: 'It may be in a format this device cannot '
                                'read.',
                            light: true,
                          ),
                        ),
                      ),
                    ),
                  _Kind.word when _web != null =>
                    WebViewWidget(controller: _web!),
                  _ => _Message(
                      icon: Icons.description_outlined,
                      title: widget.fileName,
                      detail: 'Word documents can be previewed inside the app '
                          'on iPhone and iPad. On this device it opens in '
                          'another app instead.',
                      actionLabel: 'Open in another app',
                      onAction: _openElsewhere,
                    ),
                },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool light;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 44, color: light ? Colors.white70 : colors.textSecondary),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: light ? Colors.white : null)),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                    color: light ? Colors.white70 : colors.textSecondary,
                    height: 1.45)),
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.background,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
