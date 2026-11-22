import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/moderation/content_filter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/user_avatar.dart';
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

  /// A refusal. One button, because there is nothing to negotiate.
  Future<void> _showFilterRefusal(String message) async {
    final colors = context.colors;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.block_rounded, color: colors.error),
        title: const Text('This cannot be posted'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Edit it'),
          ),
        ],
      ),
    );
  }

  /// A warning the author can overrule.
  ///
  /// Kept as a choice rather than a refusal because context decides: a
  /// student quoting the abuse they received is not the student sending it,
  /// and a filter that cannot tell them apart should not be the one deciding.
  Future<bool> _confirmDespiteWarning(String message) async {
    final colors = context.colors;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: colors.warning),
        title: const Text('Have another look'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Edit it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Post anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _post() async {
    // Guideline 1.2 asks for objectionable material to be filtered "from
    // being posted" — so this runs before the upload, not after it. A
    // refusal here costs one retyped sentence; the same refusal server-side
    // would already have uploaded the images.
    final verdict = ContentFilter.check(_body.text);
    if (verdict.isBlocked) {
      await _showFilterRefusal(verdict.message!);
      return;
    }
    if (verdict.needsReview && !await _confirmDespiteWarning(verdict.message!)) {
      return;
    }
    // Both branches above can await a dialog, and everything below this line
    // reads from `context`.
    if (!mounted) return;

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

  // ── Choices that open sheets ───────────────────────────────────────────

  Future<void> _pickReplyPolicy() async {
    final picked = await _showOptionSheet<String>(
      title: 'Who can reply?',
      subtitle: 'Anyone can still read the post. This only limits replies.',
      selected: _replyPolicy,
      options: [
        for (final p in _replyPolicies)
          _Option(
              value: p.value,
              title: p.title,
              detail: p.detail,
              leading: _OptionIcon(p.icon)),
      ],
    );
    if (picked != null && mounted) setState(() => _replyPolicy = picked);
  }

  Future<void> _pickIdentity() async {
    final user = context.read<AuthProvider>().user;
    final institution = context.read<InstitutionProvider>();
    final orgName = institution.institution?.name ?? 'Our institution';

    final picked = await _showOptionSheet<bool>(
      title: 'Post as',
      subtitle: 'The name your post goes out under.',
      selected: _asOrganisation,
      options: [
        _Option(
          value: true,
          title: orgName,
          detail: institution.handle == null
              ? 'Your institution'
              : '@${institution.handle} · your institution',
          leading: InstitutionAvatar(
            logoUrl: institution.institution?.logoUrl,
            initials: _initialsOf(orgName),
            size: 40,
          ),
        ),
        _Option(
          value: false,
          title: user?.fullName ?? 'Me',
          detail: 'Yourself',
          leading: UserAvatar(
            avatarUrl: user?.avatarUrl,
            initials: user?.initials ?? '?',
            size: 40,
          ),
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _asOrganisation = picked);
  }

  Future<T?> _showOptionSheet<T>({
    required String title,
    required String subtitle,
    required T selected,
    required List<_Option<T>> options,
  }) =>
      showModalBottomSheet<T>(
        context: context,
        useRootNavigator: true,
        builder: (sheetContext) {
          final colors = sheetContext.colors;
          final text = Theme.of(sheetContext).textTheme;
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                  child: Text(title,
                      style: text.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(subtitle,
                      style:
                          text.bodyMedium?.copyWith(color: colors.textLight)),
                ),
                for (final option in options)
                  Pressable.surface(
                    onTap: () =>
                        Navigator.of(sheetContext).pop(option.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          option.leading,
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(option.title,
                                    style: text.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(option.detail,
                                    style: text.bodySmall?.copyWith(
                                        color: colors.textLight)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _Check(on: option.value == selected),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      );

  /// Fields and destinations, in a sheet of their own.
  ///
  /// They used to be two walls of chips in the middle of the composer, which
  /// made a two-line post look like a form. They matter — they decide whose
  /// feed the post reaches — so the composer keeps a one-line summary and the
  /// choosing happens here.
  Future<void> _pickAudience() async {
    final passport = context.read<PassportProvider>();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          final colors = sheetContext.colors;
          final text = Theme.of(sheetContext).textTheme;

          void toggle(Set<String> set, String key) {
            setSheet(() => set.contains(key) ? set.remove(key) : set.add(key));
            setState(() {});
          }

          final count = _fields.length + _countries.length;

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Audience',
                              style: text.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        if (count > 0)
                          TextButton(
                            onPressed: () {
                              setSheet(() {
                                _fields.clear();
                                _countries.clear();
                              });
                              setState(() {});
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: colors.textSecondary,
                              textStyle: text.bodyLarge,
                            ),
                            child: const Text('Clear'),
                          ),
                        TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.textPrimary,
                            textStyle: text.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Your post is shown first to students interested in '
                      'what you pick here. Pick nothing and it goes to '
                      'everyone.',
                      style: text.bodyMedium
                          ?.copyWith(color: colors.textLight, height: 1.4),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      children: [
                        _SectionLabel('Fields of study'),
                        const SizedBox(height: 10),
                        if (passport.fields.isEmpty)
                          Text('Loading fields…',
                              style: text.bodySmall
                                  ?.copyWith(color: colors.textLight))
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final field in passport.fields)
                                _ChoicePill(
                                  label: field.label,
                                  selected: _fields.contains(field.slug),
                                  onTap: () => toggle(_fields, field.slug),
                                ),
                            ],
                          ),
                        const SizedBox(height: 24),
                        _SectionLabel('Study destinations'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry
                                in AppConstants.popularDestinations.entries)
                              _ChoicePill(
                                label: entry.value,
                                selected: _countries.contains(entry.key),
                                onTap: () => toggle(_countries, entry.key),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _initialsOf(String name) {
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  String _audienceSummary(PassportProvider passport) {
    final labels = <String>[
      for (final slug in _fields)
        passport.fields
                .where((f) => f.slug == slug)
                .map((f) => f.label)
                .firstOrNull ??
            slug,
      for (final code in _countries)
        AppConstants.popularDestinations[code] ?? code,
    ];
    if (labels.isEmpty) return 'Everyone — add topics to reach the right students';
    if (labels.length <= 3) return labels.join(', ');
    return '${labels.take(2).join(', ')} and ${labels.length - 2} more';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final user = context.watch<AuthProvider>().user;
    final passport = context.watch<PassportProvider>();
    final institution = context.watch<InstitutionProvider>();
    final canPostAsOrg = institution.institutionId != null;
    final asOrg = canPostAsOrg && _asOrganisation;

    final body = _body.text.trim();
    final canPost = body.isNotEmpty && !_sending;

    final orgName = institution.institution?.name ?? 'Our institution';
    final displayName = asOrg ? orgName : (user?.fullName ?? 'You');
    final handle = asOrg ? institution.handle : passport.handle;
    final reply = _replyPolicies.firstWhere((p) => p.value == _replyPolicy);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('New post',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        leadingWidth: 88,
        leading: TextButton(
          onPressed: () => context.pop(),
          style: TextButton.styleFrom(
            foregroundColor: colors.textPrimary,
            textStyle: text.bodyLarge,
          ),
          child: const Text('Cancel'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _PostButton(
              enabled: canPost,
              sending: _sending,
              onTap: _post,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: colors.divider),
        ),
      ),

      // A column rather than a bare list so the toolbar rides on top of the
      // keyboard, where the thumb already is.
      body: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (!canPostAsOrg && passport.handle == null) ...[
                  _HandleNotice(
                      onChoose: () => openClaimHandleSheet(context)),
                  const SizedBox(height: 16),
                ],

                // ── Who is writing, and who can answer ──────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    asOrg
                        ? InstitutionAvatar(
                            logoUrl: institution.institution?.logoUrl,
                            initials: _initialsOf(orgName),
                            size: 44,
                          )
                        : UserAvatar(
                            avatarUrl: user?.avatarUrl,
                            initials: user?.initials ?? '?',
                            size: 44,
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: displayName,
                                style: text.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (handle != null)
                                TextSpan(
                                  text: '  @$handle',
                                  style: text.bodyMedium
                                      ?.copyWith(color: colors.textLight),
                                ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          // Who can reply sits here, under the name and above
                          // the words — decided before writing, the way every
                          // social app now asks it, not found at the bottom
                          // after the post is done.
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (canPostAsOrg)
                                _MenuPill(
                                  icon: asOrg
                                      ? Icons.apartment_rounded
                                      : Icons.person_rounded,
                                  label: asOrg ? 'As institution' : 'As you',
                                  onTap: _pickIdentity,
                                ),
                              _MenuPill(
                                icon: reply.icon,
                                label: reply.pill,
                                onTap: _pickReplyPolicy,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // ── The post itself ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(left: 56, top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _body,
                        autofocus: true,
                        minLines: 4,
                        maxLines: null,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        style: text.bodyLarge?.copyWith(height: 1.45),
                        cursorColor: colors.textPrimary,
                        decoration: InputDecoration(
                          hintText: switch (_kind) {
                            'question' => 'What do you want to ask?',
                            'announcement' => 'What are you announcing?',
                            'requirement' => 'What do applicants need?',
                            _ => 'What’s new?',
                          },
                          hintStyle: text.bodyLarge
                              ?.copyWith(color: colors.textLight),
                          filled: false,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_media.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 132,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _media.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) => _MediaThumb(
                              bytes: _media[i].bytes,
                              onRemove: () =>
                                  setState(() => _media.removeAt(i)),
                            ),
                          ),
                        ),
                      ],
                      if (_taggedUsers.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tagged in _taggedUsers)
                              _TagPill(
                                tagged: tagged,
                                onRemove: () => setState(
                                    () => _taggedUsers.remove(tagged)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Details ─────────────────────────────────────────────
                _SectionLabel('Post type'),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final kind in _kinds) ...[
                        _ChoicePill(
                          icon: kind.icon,
                          label: kind.label,
                          selected: _kind == kind.value,
                          onTap: () => setState(() => _kind = kind.value),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _SectionLabel('Who is this about?'),
                const SizedBox(height: 10),
                Pressable.surface(
                  onTap: _pickAudience,
                  semanticLabel: 'Audience',
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.track_changes_rounded,
                              size: 19, color: colors.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _fields.isEmpty && _countries.isEmpty
                                    ? 'Audience'
                                    : 'Shown to students interested in',
                                style: text.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _audienceSummary(passport),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                    color: colors.textLight, height: 1.35),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: colors.textLight),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Toolbar ─────────────────────────────────────────────────────
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(top: BorderSide(color: colors.divider)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Add a photo',
                      onPressed: _media.length >= 4 ? null : _addMedia,
                      icon: Icon(Icons.image_outlined,
                          color: _media.length >= 4
                              ? colors.textLight
                              : colors.textPrimary),
                    ),
                    IconButton(
                      tooltip: 'Tag university or student',
                      onPressed: _openTagSheet,
                      icon: Badge(
                        isLabelVisible: _taggedUsers.isNotEmpty,
                        label: Text('${_taggedUsers.length}'),
                        backgroundColor: colors.textPrimary,
                        textColor: colors.background,
                        child: Icon(Icons.alternate_email_rounded,
                            color: colors.textPrimary),
                      ),
                    ),
                    if (_media.isNotEmpty)
                      Text('${_media.length}/4',
                          style: text.labelSmall
                              ?.copyWith(color: colors.textLight)),
                    const Spacer(),
                    _LengthRing(length: _body.text.length, max: 2000),
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

// ── Static choices ───────────────────────────────────────────────────────

const _kinds = [
  (value: 'update', label: 'Update', icon: Icons.edit_note_rounded),
  (value: 'question', label: 'Question', icon: Icons.help_outline_rounded),
  (value: 'announcement', label: 'Announcement', icon: Icons.campaign_outlined),
  (value: 'requirement', label: 'Requirements', icon: Icons.checklist_rounded),
];

const _replyPolicies = [
  (
    value: 'everyone',
    title: 'Everyone',
    pill: 'Everyone can reply',
    detail: 'Anyone who can see the post.',
    icon: Icons.public_rounded,
  ),
  (
    value: 'following',
    title: 'People you follow',
    pill: 'People you follow',
    detail: 'Only accounts you follow can reply.',
    icon: Icons.people_alt_outlined,
  ),
  (
    value: 'verified',
    title: 'Verified accounts',
    pill: 'Verified only',
    detail: 'Only accounts with a verified badge can reply.',
    icon: Icons.verified_outlined,
  ),
];

// ── Small pieces ─────────────────────────────────────────────────────────

class _Option<T> {
  final T value;
  final String title;
  final String detail;
  final Widget leading;
  const _Option({
    required this.value,
    required this.title,
    required this.detail,
    required this.leading,
  });
}

class _OptionIcon extends StatelessWidget {
  final IconData icon;
  const _OptionIcon(this.icon);

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.colors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: context.colors.textPrimary),
      );
}

/// A filled tick when chosen, an empty ring when not.
class _Check extends StatelessWidget {
  final bool on;
  const _Check({required this.on});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? colors.textPrimary : Colors.transparent,
        border: Border.all(
            color: on ? colors.textPrimary : colors.border, width: 1.5),
      ),
      child: on
          ? Icon(Icons.check_rounded, size: 15, color: colors.background)
          : null,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      );
}

/// The Post button: a pill in the text colour, so it reads as the one thing
/// to do on the screen without borrowing the link blue.
class _PostButton extends StatelessWidget {
  final bool enabled;
  final bool sending;
  final VoidCallback onTap;
  const _PostButton({
    required this.enabled,
    required this.sending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: enabled ? onTap : null,
      haptic: HapticKind.impact,
      semanticLabel: 'Post',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled || sending ? colors.textPrimary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: sending
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.background),
              )
            : Text(
                'Post',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: enabled ? colors.background : colors.textLight,
                ),
              ),
      ),
    );
  }
}

/// A small outlined pill that opens a menu.
class _MenuPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: colors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 16, color: colors.textLight),
          ],
        ),
      ),
    );
  }
}

/// A pill you switch on and off. Chosen is inverted — text colour behind,
/// background colour in front — rather than tinted blue.
class _ChoicePill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? colors.background : colors.textPrimary;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(icon == null ? 14 : 12, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected ? colors.textPrimary : colors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  final Uint8List bytes;
  final VoidCallback onRemove;
  const _MediaThumb({required this.bytes, required this.onRemove});

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(bytes,
                width: 106, height: 132, fit: BoxFit.cover),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Pressable(
              onTap: onRemove,
              semanticLabel: 'Remove photo',
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      );
}

class _TagPill extends StatelessWidget {
  final TaggedAccount tagged;
  final VoidCallback onRemove;
  const _TagPill({required this.tagged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tagged.isInstitution
                ? Icons.apartment_rounded
                : Icons.person_rounded,
            size: 13,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            '@${tagged.handle}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
          ),
          Pressable(
            onTap: onRemove,
            semanticLabel: 'Remove @${tagged.handle}',
            child: Padding(
              padding: const EdgeInsets.all(4),
              child:
                  Icon(Icons.close_rounded, size: 14, color: colors.textLight),
            ),
          ),
        ],
      ),
    );
  }
}

/// How much of the 2000 characters is used, as a ring that only starts
/// counting out loud near the end.
class _LengthRing extends StatelessWidget {
  final int length;
  final int max;
  const _LengthRing({required this.length, required this.max});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final left = max - length;
    final colour = left <= 0
        ? colors.error
        : left <= 200
            ? colors.warning
            : colors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (left <= 200)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('$left',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colour, fontWeight: FontWeight.w600)),
          ),
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            value: (length / max).clamp(0.0, 1.0),
            strokeWidth: 2.5,
            backgroundColor: colors.divider,
            color: colour,
          ),
        ),
      ],
    );
  }
}

/// Shown only to the older accounts that have no handle to sign a post with.
class _HandleNotice extends StatelessWidget {
  final VoidCallback onChoose;
  const _HandleNotice({required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.warningLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.alternate_email_rounded, color: colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Posts are signed with a handle, and this account does not '
              'have one yet.',
              style: text.bodySmall?.copyWith(height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onChoose,
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              textStyle:
                  text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            child: const Text('Choose'),
          ),
        ],
      ),
    );
  }
}
