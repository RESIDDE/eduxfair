import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../institution/providers/institution_provider.dart';
import '../../passport/providers/passport_provider.dart';
import '../providers/feed_provider.dart';
import 'handle_sheet.dart';
import 'tag_sheet.dart';

/// Writing a post.
///
/// One composer for both audiences: a student posts as themselves, and staff
/// who belong to an institution get a switch to post as the organisation
/// instead, rather than needing a second screen.
class ComposerScreen extends StatefulWidget {
  const ComposerScreen({super.key});

  @override
  State<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends State<ComposerScreen> {
  final _body = TextEditingController();
  final _media = <({Uint8List bytes, String name, String? mime})>[];
  final _taggedUsers = <TaggedAccount>{};

  String _kind = 'update';
  String _replyPolicy = 'everyone';
  bool _asOrganisation = true;
  bool _sending = false;

  final _fields = <String>{};
  final _countries = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Staff need their institution resolved before the "posting as" switch
      // can appear. Without this the switch is simply absent when the provider
      // happens not to be loaded, and the post goes out under the staff
      // member's own name with nothing on screen having said so — which is
      // how a university's first post ended up filed as a person's.
      final auth = context.read<AuthProvider>();
      final institutions = context.read<InstitutionProvider>();
      if (auth.user?.isStudent == false && !institutions.isResolved) {
        await institutions.load();
        if (!mounted) return;
      }

      final passport = context.read<PassportProvider>();
      passport.load();

      // A student's own targets are a sensible default audience: the post is
      // usually about the thing they are looking for.
      final p = passport.passport;
      if (p != null) {
        setState(() {
          _fields.addAll(p.targetFields.take(2));
          _countries.addAll(p.targetCountries.take(2));
        });
      }
    });
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  /// Where a photo comes from.
  ///
  /// `file_picker` alone opens the Files app on iOS, which is not where
  /// anyone's photos are — so the gallery was effectively unreachable. Files
  /// stays as an option because a prospectus photo or a scanned flyer often
  /// does live there.
  Future<void> _addMedia() async {
    if (_media.length >= 4) {
      _toast('Four images is the limit for one post.');
      return;
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo library'),
              onTap: () => Navigator.of(sheetContext).pop('gallery'),
            ),
            // No camera in a browser tab.
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(sheetContext).pop('camera'),
              ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Files'),
              onTap: () => Navigator.of(sheetContext).pop('files'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    switch (source) {
      case 'gallery':
        await _addFromPhotos(multiple: true);
      case 'camera':
        await _addFromPhotos(multiple: false, camera: true);
      case 'files':
        await _addFromFiles();
    }
  }

  Future<void> _addFromPhotos({
    required bool multiple,
    bool camera = false,
  }) async {
    final picker = ImagePicker();
    final room = 4 - _media.length;

    try {
      final picked = <XFile>[];
      if (camera) {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          // Posted images are displayed at most a phone wide; full-resolution
          // originals are a slow upload on mobile data for no visible gain.
          maxWidth: 2048,
          imageQuality: 85,
        );
        if (shot != null) picked.add(shot);
      } else if (multiple) {
        picked.addAll(await picker.pickMultiImage(
          maxWidth: 2048,
          imageQuality: 85,
        ));
      }

      for (final file in picked.take(room)) {
        await _addBytes(await file.readAsBytes(), file.name);
      }
    } catch (e) {
      // A refused permission arrives here rather than as a null result.
      if (mounted) _toast('Could not open your photos: $e');
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _addFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
      allowMultiple: true,
      withData: true, // required on web, where there is no file path
    );

    if (result == null || !mounted) return;

    for (final file in result.files.take(4 - _media.length)) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      await _addBytes(bytes, file.name);
    }
    if (mounted) setState(() {});
  }

  Future<void> _addBytes(Uint8List bytes, String name) async {
    if (bytes.length > 10 * 1024 * 1024) {
      _toast('$name is larger than 10 MB.');
      return;
    }
    _media.add((
      bytes: bytes,
      name: name,
      mime: _mimeFor(name.split('.').last),
    ));
  }

  static String? _mimeFor(String? ext) => switch (ext?.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        _ => null,
      };

  Future<void> _post() async {
    setState(() => _sending = true);

    // Everything that needs a BuildContext is resolved before the await.
    // Reaching back through `context` after an async gap is how a disposed
    // element gets touched, and the failure mode is an assertion deep in the
    // framework rather than anything that names this screen.
    final feed = context.read<FeedProvider>();
    final institution = context.read<InstitutionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final errorColour = context.colors.error;
    final isStaff = context.read<AuthProvider>().user?.isStudent == false;
    final postAsOrg = _asOrganisation && institution.institutionId != null;

    // Refused rather than quietly downgraded. Staff who meant to post as the
    // organisation would otherwise discover the mistake only by reading the
    // byline on a post that is already out.
    if (isStaff && _asOrganisation && institution.institutionId == null) {
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: const Text(
            'Your institution has not loaded yet, so this would post under '
            'your own name. Try again in a moment.'),
        backgroundColor: errorColour,
      ));
      return;
    }

    final id = await feed.createPost(
      body: _body.text,
      kind: _kind,
      institutionId: postAsOrg ? institution.institutionId : null,
      replyPolicy: _replyPolicy,
      fields: _fields.toList(),
      countries: _countries.toList(),
      taggedHandles: _taggedUsers.map((u) => u.handle).toList(),
      media: _media,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (id == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(feed.error ?? 'Could not post.'),
        backgroundColor: errorColour,
      ));
      return;
    }

    // `context.pop()`, not `Navigator.pop()`. This screen is a GoRoute pushed
    // with `context.push`, and popping it straight off the Navigator leaves
    // go_router's own match list holding a route the Navigator no longer has.
    // The next time the router rebuilds it works from that stale list, which
    // is a route-lifecycle bug waiting for a trigger.
    router.pop(true);
  }

  Future<void> _openTagSheet() async {
    final selected = await showModalBottomSheet<Set<TaggedAccount>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => TagSheet(initiallySelected: _taggedUsers),
    );

    if (selected != null && mounted) {
      setState(() {
        _taggedUsers.clear();
        _taggedUsers.addAll(selected);
      });
    }
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? context.colors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final user = context.watch<AuthProvider>().user;
    final passport = context.watch<PassportProvider>();
    final institution = context.watch<InstitutionProvider>();
    final canPostAsOrg = institution.institutionId != null;

    final body = _body.text.trim();
    final canPost = body.isNotEmpty && !_sending;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 80,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton(
              onPressed: canPost ? _post : null,
              child: _sending
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.colors.onAccent),
                    )
                  : const Text('Post'),
            ),
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Who this goes out as. Staff default to the organisation, because
          // that is almost always what they mean.
          if (canPostAsOrg)
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(institution.institution?.name ?? 'Our institution',
                      overflow: TextOverflow.ellipsis),
                  icon: const Icon(Icons.apartment_rounded, size: 16),
                ),
                ButtonSegment(
                  value: false,
                  label: Text(user?.firstName ?? 'Me'),
                  icon: const Icon(Icons.person_rounded, size: 16),
                ),
              ],
              selected: {_asOrganisation},
              onSelectionChanged: (v) =>
                  setState(() => _asOrganisation = v.first),
            ),

          if (!canPostAsOrg && passport.handle == null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.warningLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Posts are signed with a handle, and this account does '
                    'not have one. New accounts are given one automatically, '
                    'so this only affects older ones.',
                    style: text.bodySmall?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => openClaimHandleSheet(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Choose a handle'),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),
          TextField(
            controller: _body,
            autofocus: true,
            minLines: 5,
            maxLines: 20,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            style: text.bodyLarge?.copyWith(height: 1.45),
            decoration: const InputDecoration(
              hintText: 'What do you want to say?',
              border: InputBorder.none,
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
          ),

          if (_media.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _media.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_media[i].bytes,
                          width: 96, height: 96, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _media.removeAt(i)),
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: const Icon(Icons.close_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_taggedUsers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tagged in _taggedUsers)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: colors.surfaceVariant,
                    avatar: Icon(
                      tagged.isInstitution
                          ? Icons.apartment_rounded
                          : Icons.person_rounded,
                      size: 14,
                      color: colors.accent,
                    ),
                    label: Text(
                      '@${tagged.handle}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    deleteIcon: const Icon(Icons.close_rounded, size: 14),
                    onDeleted: () =>
                        setState(() => _taggedUsers.remove(tagged)),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: 'Add a photo',
                onPressed: _media.length >= 4 ? null : _addMedia,
                icon: Icon(Icons.image_outlined, color: colors.accent),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: colors.accent,
                  side: BorderSide(color: colors.accent.withValues(alpha: 0.3)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: _openTagSheet,
                icon: const Icon(Icons.alternate_email_rounded, size: 16),
                label: Text(
                  _taggedUsers.isEmpty
                      ? 'Tag university or student'
                      : '${_taggedUsers.length} tagged',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Spacer(),
              Text('${body.length}/2000', style: text.labelSmall),
            ],
          ),

          Divider(color: colors.divider),
          const SizedBox(height: 8),

          Text('What kind of post?', style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const {
                'update': 'Update',
                'question': 'Question',
                'announcement': 'Announcement',
                'requirement': 'Requirements',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _kind == entry.key,
                  onSelected: (_) => setState(() => _kind = entry.key),
                ),
            ],
          ),

          const SizedBox(height: 16),
          Text('Who is it about?', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            // The tags are what put a post in front of the right students, so
            // the screen says so rather than leaving them looking decorative.
            'These decide whose feed it reaches.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final field in passport.fields.take(12))
                FilterChip(
                  label: Text(field.label),
                  selected: _fields.contains(field.slug),
                  onSelected: (on) => setState(() =>
                      on ? _fields.add(field.slug) : _fields.remove(field.slug)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in AppConstants.popularDestinations.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: _countries.contains(entry.key),
                  onSelected: (on) => setState(() => on
                      ? _countries.add(entry.key)
                      : _countries.remove(entry.key)),
                ),
            ],
          ),

          const SizedBox(height: 16),
          Text('Who can reply?', style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'everyone', label: Text('Everyone')),
              ButtonSegment(value: 'following', label: Text('People I follow')),
              ButtonSegment(value: 'verified', label: Text('Verified')),
            ],
            selected: {_replyPolicy},
            onSelectionChanged: (v) => setState(() => _replyPolicy = v.first),
          ),
        ],
      ),
    );
  }
}
