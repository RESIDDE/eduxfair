import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/conversation.dart';
import '../providers/messages_provider.dart';
import '../widgets/voice_note.dart';

/// One thread, delivered live over Supabase Realtime.
class ChatScreen extends StatefulWidget {
  final String conversationId;

  /// What to put in the title bar.
  ///
  /// A student sees the institution's name, which the conversation itself
  /// carries. Staff see the student — and that is *not* on the conversation,
  /// because an unshared student has no name an institution may read. The
  /// inbox resolves it to a match token and passes it in here.
  final String? title;

  /// The other party's picture, when the caller already has one.
  ///
  /// Staff pass the student's, which `institution_inbox` only returns after a
  /// share. A student needs nothing here: the institution's logo comes off the
  /// conversation itself.
  final String? avatarUrl;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.title,
    this.avatarUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;

  /// The message the composer is currently answering, shown as a strip above
  /// the field so it cannot be forgotten about.
  Message? _replyingTo;

  /// The other party's public handle, when there is one to open.
  ///
  /// Only ever set for an institution. A student's handle is deliberately not
  /// reachable from a thread: `social_profiles` has no policy letting staff
  /// read a student's row, and linking the two would hand an institution the
  /// public identity the match token exists to withhold — even after a share,
  /// which grants their passport name and not their social presence.
  String? _otherHandle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final provider = context.read<MessagesProvider>();
      await provider.loadMessages(widget.conversationId);
      if (!mounted) return;
      provider.subscribe(widget.conversationId);
      await provider.markRead(widget.conversationId);
      _scrollToBottom();
      await _resolveOtherHandle(provider);
    });
  }

  /// Held so [dispose] can leave the channel: by then the element is
  /// deactivated and `context.read` on it throws — which it was doing, so the
  /// realtime subscription outlived every thread anyone opened.
  MessagesProvider? _messages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messages = context.read<MessagesProvider>();
  }

  @override
  void dispose() {
    // Leave the channel so the client is not kept awake by a thread nobody is
    // looking at.
    _messages?.unsubscribe();
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Finds the institution's handle, so its avatar can open its profile.
  ///
  /// One query when the thread opens. `public_profiles` carries
  /// `institution_id`, so this needs no new column and no new policy.
  Future<void> _resolveOtherHandle(MessagesProvider provider) async {
    final institutionId = provider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull
        ?.institutionId;
    if (institutionId == null) return;

    try {
      final row = await SupabaseService.instance.client
          .from('public_profiles')
          .select('handle')
          .eq('institution_id', institutionId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _otherHandle = row?['handle'] as String?);
    } catch (_) {
      // No handle is an ordinary state — an institution that has not claimed
      // one simply has no profile to open.
    }
  }

  Future<void> _send() async {
    final body = _input.text;
    if (body.trim().isEmpty) return;
    _input.clear();

    final provider = context.read<MessagesProvider>();
    final replyTo = _replyingTo;
    // Cleared before the round trip, so the strip does not sit there looking
    // like the next message will quote it too.
    setState(() => _replyingTo = null);

    final ok = await provider.send(
      conversationId: widget.conversationId,
      body: body,
      replyToId: replyTo?.id,
    );

    if (!mounted) return;
    if (ok) {
      _scrollToBottom();
    } else {
      // Put the text back rather than losing what they typed.
      _input.text = body;
      setState(() => _replyingTo = replyTo);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not send.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  bool _recording = false;

  /// Whether the mic replaces the send arrow right now.
  ///
  /// Not on the web: `record` hands back a blob URL rather than a file there,
  /// and `dart:io` cannot read one — so a mic button in a browser would record
  /// something it could never send. Staff record voice notes from the React
  /// console, which uses MediaRecorder directly and does not have this problem.
  bool get _canRecord => !kIsWeb && _input.text.trim().isEmpty;

  /// Offers the two things people actually attach, instead of one picker that
  /// opens a file browser when they wanted the camera roll.
  Future<void> _attachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.of(sheet).pop('photo'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.of(sheet).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              subtitle: const Text('PDF or Word, up to 20 MB'),
              onTap: () => Navigator.of(sheet).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'file') return _attach();
    await _sendImage(
      choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
  }

  /// Sends a picture as `kind: image`, which is what makes it render as one.
  Future<void> _sendImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // Resized on the way out: a modern phone camera produces 8 MB of JPEG
      // that nobody needs in a chat bubble, and the bucket caps at 20.
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final provider = context.read<MessagesProvider>();
    final ok = await provider.send(
      conversationId: widget.conversationId,
      attachment: bytes,
      attachmentName: picked.name,
      attachmentMime: _mimeFor(picked.name.split('.').last) ?? 'image/jpeg',
      kind: 'image',
    );
    if (!mounted) return;
    if (ok) {
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not send that picture.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  /// Uploads a finished recording as `kind: voice`.
  ///
  /// The duration comes from the recorder rather than the file, so a bubble
  /// can show its length before any audio has been fetched.
  Future<void> _sendVoiceNote(String path, int durationMs) async {
    setState(() => _recording = false);
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;

    final provider = context.read<MessagesProvider>();
    final ok = await provider.send(
      conversationId: widget.conversationId,
      attachment: bytes,
      attachmentName: 'voice-note.m4a',
      attachmentMime: 'audio/mp4',
      kind: 'voice',
      durationMs: durationMs,
    );
    if (!mounted) return;
    if (ok) {
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not send that voice note.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'doc',
        'docx',
      ],
      withData: true, // required on web, where there is no file path
    );

    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    if (bytes.length > 20 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('That file is larger than 20 MB.'),
          backgroundColor: context.colors.error,
        ),
      );
      return;
    }

    final provider = context.read<MessagesProvider>();
    final mime = _mimeFor(file.extension);
    final ok = await provider.send(
      conversationId: widget.conversationId,
      attachment: bytes,
      attachmentName: file.name,
      attachmentMime: mime,
      // A JPEG picked through the document browser is still a picture, and
      // should render as one. The kind follows the mime, not the entry point.
      kind: (mime ?? '').startsWith('image/') ? 'image' : 'file',
    );

    if (!mounted) return;
    if (ok) {
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not send that file.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  /// Everything you can do to one message, in one sheet.
  ///
  /// Reactions sit along the top because that is the one action people take
  /// without thinking; reply, forward and the two deletions are the rest. A
  /// long press used to open a delete-only menu, which made holding a message
  /// a destructive gesture and left nowhere to put the others.
  Future<void> _actions(Message message, bool isMine) async {
    if (message.isDeleted) return;
    final provider = context.read<MessagesProvider>();
    final me =
        SupabaseService.instance.userId ??
        context.read<AuthProvider>().user?.id;
    final mine = message.myReaction(me);

    final choice = await showModalBottomSheet<String>(
      context: context,
      // Scrollable and capped. A Column in a bottom sheet does not scroll when
      // it runs out of room — it clips — and this one grew a reaction row, a
      // reply, a forward and two deletions, which is taller than a sheet gets
      // on a short screen or at a large text size.
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheet).height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in MessagesProvider.reactionChoices)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(sheet).pop('react:$emoji'),
                          child: Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              // The one already given is marked, so a second tap
                              // reads as "take it back" rather than "set it again".
                              color: mine == emoji
                                  ? context.colors.accent.withValues(
                                      alpha: 0.18,
                                    )
                                  : null,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 8),
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () => Navigator.of(sheet).pop('reply'),
                ),
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('Forward'),
                  onTap: () => Navigator.of(sheet).pop('forward'),
                ),
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Delete for me'),
                  subtitle: const Text(
                    'Removes it from your view. Nobody else is told.',
                  ),
                  onTap: () => Navigator.of(sheet).pop('me'),
                ),
                if (isMine)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: context.colors.error,
                    ),
                    title: const Text('Delete for everyone'),
                    subtitle: const Text(
                      'Both sides see that a message was deleted.',
                    ),
                    onTap: () => Navigator.of(sheet).pop('everyone'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;

    if (choice.startsWith('react:')) {
      await provider.react(message, choice.substring(6));
      return;
    }
    if (choice == 'reply') {
      setState(() => _replyingTo = message);
      return;
    }
    if (choice == 'forward') {
      await _forward(message);
      return;
    }
    await _delete(message, forEveryone: choice == 'everyone');
  }

  Future<void> _delete(Message message, {required bool forEveryone}) async {
    final provider = context.read<MessagesProvider>();
    final ok = await provider.deleteMessage(message, forEveryone: forEveryone);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(provider.error ?? 'That message could not be deleted.'),
        backgroundColor: context.colors.error,
      ),
    );
  }

  /// Picks a thread to forward into, from the ones this person already has.
  Future<void> _forward(Message message) async {
    final provider = context.read<MessagesProvider>();
    final targets = provider.conversations
        .where((c) => c.id != widget.conversationId)
        .toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have no other conversation to forward this to.'),
        ),
      );
      return;
    }

    final target = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Forward to',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: targets.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(targets[i].title),
                  subtitle: targets[i].subject == null
                      ? null
                      : Text(
                          targets[i].subject!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => Navigator.of(sheet).pop(targets[i].id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;

    final ok = await provider.forward(message, target);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Forwarded.'
              : provider.error ?? 'That message could not be forwarded.',
        ),
        backgroundColor: ok ? null : context.colors.error,
      ),
    );
  }

  Future<void> _openAttachment(Message message) async {
    final provider = context.read<MessagesProvider>();
    final url = await provider.attachmentUrl(message);
    if (!mounted || url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static String? _mimeFor(String? ext) => switch (ext?.toLowerCase()) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final provider = context.watch<MessagesProvider>();
    final myId =
        SupabaseService.instance.userId ??
        context.watch<AuthProvider>().user?.id;

    final messages = provider.messagesFor(widget.conversationId);
    final conversation = provider.conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;

    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }

    final name = widget.title ?? conversation?.title ?? 'Conversation';
    final logo = conversation?.institution?.logoUrl ?? widget.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          // Tappable only when there is somewhere to go. A student's profile
          // is not reachable from a thread by design, so staff get the same
          // header without the link rather than a dead tap target.
          onTap: _otherHandle == null
              ? null
              : () => context.push('${AppConstants.routeHandle}/$_otherHandle'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logo != null || conversation?.institution != null)
                InstitutionAvatar(
                  logoUrl: logo,
                  initials: conversation?.institution?.initials ?? '?',
                  size: 32,
                )
              else
                UserAvatar(
                  avatarUrl: widget.avatarUrl,
                  initials: name.isEmpty ? '?' : name[0].toUpperCase(),
                  size: 32,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_otherHandle != null)
                      Text(
                        '@$_otherHandle',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colors.textLight),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Say hello. Ask about entry requirements, '
                        'scholarships, or anything you need to know.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMine = myId != null && message.senderId == myId;
                      // Group consecutive messages from the same sender.
                      final isFirstOfRun =
                          index == 0 ||
                          messages[index - 1].senderId != message.senderId;

                      return _Bubble(
                        message: message,
                        isMine: isMine,
                        myId: myId,
                        showTail: isFirstOfRun,
                        // Resolved from what is loaded; a quote whose original
                        // scrolled out of the window falls back to a label.
                        quoted: message.replyToId == null
                            ? null
                            : messages
                                  .where((m) => m.id == message.replyToId)
                                  .firstOrNull,
                        onOpenAttachment: () => _openAttachment(message),
                        onLongPress: () => _actions(message, isMine),
                        onReply: () => setState(() => _replyingTo = message),
                        onDelete: () => _actions(message, isMine),
                        onReact: (emoji) => context
                            .read<MessagesProvider>()
                            .react(message, emoji),
                      );
                    },
                  ),
          ),
          // A message log cannot be edited or deleted by anyone, which is what
          // makes it usable as evidence later; nothing in this UI implies it can.
          if (_replyingTo != null)
            _ReplyStrip(
              message: _replyingTo!,
              isMine: _replyingTo!.senderId == myId,
              onCancel: () => setState(() => _replyingTo = null),
            ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.divider)),
              ),
              child: _recording
                  ? VoiceRecorderBar(
                      onComplete: _sendVoiceNote,
                      onCancel: () => setState(() => _recording = false),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: provider.sending ? null : _attachMenu,
                          icon: const Icon(Icons.attach_file_rounded, size: 21),
                          tooltip: 'Attach a photo or file',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.send,
                            decoration: const InputDecoration(
                              hintText: 'Write a message',
                              isDense: true,
                            ),
                            // Swaps the mic for the send arrow on the first letter.
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Microphone until there is something to send, then send.
                        // One button, because two would mean the send button is
                        // disabled most of the time and the mic is in the way the
                        // rest of it.
                        IconButton.filled(
                          onPressed: provider.sending
                              ? null
                              : (_canRecord
                                    ? () => setState(() => _recording = true)
                                    : _send),
                          tooltip: _canRecord ? 'Record a voice note' : 'Send',
                          icon: provider.sending
                              ? SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: context.colors.onAccent,
                                  ),
                                )
                              : Icon(
                                  _canRecord
                                      ? Icons.mic_rounded
                                      : Icons.send_rounded,
                                  size: 19,
                                ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showTail;
  final String? myId;
  final Message? quoted;
  final VoidCallback onOpenAttachment;
  final VoidCallback onLongPress;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final void Function(String emoji) onReact;

  const _Bubble({
    required this.message,
    required this.isMine,
    required this.showTail,
    required this.myId,
    required this.quoted,
    required this.onOpenAttachment,
    required this.onLongPress,
    required this.onReply,
    required this.onDelete,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMine || !showTail ? 16 : 4),
      topRight: Radius.circular(!isMine || !showTail ? 16 : 4),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    final row = Padding(
      padding: EdgeInsets.only(top: showTail ? 10 : 3, bottom: 1),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.76,
            ),
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isMine ? colors.accent : colors.surfaceVariant,
                  borderRadius: radius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Like WhatsApp: a small italic label, and nothing about
                    // where it came from — naming that would name a
                    // conversation the reader is not on.
                    if (message.isForwarded && !message.isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.forward_rounded,
                              size: 13,
                              color: isMine
                                  ? context.colors.onAccent.withValues(
                                      alpha: 0.7,
                                    )
                                  : colors.textLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Forwarded',
                              style: text.labelSmall?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: isMine
                                    ? context.colors.onAccent.withValues(
                                        alpha: 0.75,
                                      )
                                    : colors.textLight,
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (message.replyToId != null && !message.isDeleted)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.15)
                              : colors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                            left: BorderSide(
                              width: 3,
                              color: isMine
                                  ? context.colors.onAccent
                                  : colors.accent,
                            ),
                          ),
                        ),
                        child: Text(
                          // Null when the original has scrolled out of the
                          // loaded window; the label beats an empty strip.
                          quoted?.quotedLabel ?? 'Message',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: isMine
                                ? context.colors.onAccent.withValues(
                                    alpha: 0.85,
                                  )
                                : colors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),

                    // A withdrawn message says so, and says nothing else.
                    if (message.isDeleted)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.do_not_disturb_on_outlined,
                            size: 15,
                            color: isMine
                                ? context.colors.onAccent.withValues(alpha: 0.7)
                                : colors.textLight,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'This message was deleted',
                            style: text.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: isMine
                                  ? context.colors.onAccent.withValues(
                                      alpha: 0.8,
                                    )
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    // Three attachments, three renderings. Before this every
                    // one of them was the same grey chip with a filename on it,
                    // so a photo someone sent looked exactly like a PDF.
                    else if (message.isVoice)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: message.body == null ? 0 : 8,
                        ),
                        child: VoiceNoteBubble(
                          message: message,
                          isMine: isMine,
                        ),
                      )
                    else if (message.isImage)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: message.body == null ? 0 : 8,
                        ),
                        child: _InlineImage(
                          message: message,
                          onOpen: onOpenAttachment,
                        ),
                      )
                    else if (message.hasAttachment)
                      InkWell(
                        onTap: onOpenAttachment,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: message.body == null ? 0 : 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.insert_drive_file_rounded,
                                size: 17,
                                color: isMine
                                    ? context.colors.onAccent
                                    : colors.accent,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  message.attachmentName,
                                  style: text.bodySmall?.copyWith(
                                    color: isMine
                                        ? context.colors.onAccent
                                        : colors.textPrimary,
                                    decoration: TextDecoration.underline,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (message.body != null && !message.isDeleted)
                      Text(
                        message.body!,
                        style: text.bodyMedium?.copyWith(
                          color: isMine
                              ? context.colors.onAccent
                              : colors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    if (message.hasReactions && !message.isDeleted) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final entry in message.reactions.entries)
                            InkWell(
                              onTap: () => onReact(entry.key),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isMine
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : colors.surface,
                                  borderRadius: BorderRadius.circular(999),
                                  // Yours is outlined, so you can tell at a
                                  // glance which of these you put there.
                                  border: entry.value.contains(myId)
                                      ? Border.all(
                                          color: isMine
                                              ? context.colors.onAccent
                                              : colors.accent,
                                          width: 1.2,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  entry.value.length > 1
                                      ? '${entry.key} ${entry.value.length}'
                                      : entry.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _time(message.createdAt),
                      style: text.labelSmall?.copyWith(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.7)
                            : colors.textLight,
                        fontSize: 10,
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

    // A tombstone has nothing left to reply to, forward or delete.
    if (message.isDeleted) return row;

    // Swipe right to reply, left to delete — and neither actually dismisses:
    // the message stays, so letting the widget animate away as well would be
    // two different disappearances for one action.
    return Dismissible(
      key: ValueKey('swipe-${message.id}'),
      // Deliberately generous. A chat bubble is a small target inside a
      // vertically scrolling list, and a short threshold turns every
      // imprecise scroll into a delete prompt.
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
        DismissDirection.endToStart: 0.34,
      },
      background: _SwipeHint(
        icon: Icons.reply_rounded,
        alignment: Alignment.centerLeft,
        color: colors.accent,
      ),
      secondaryBackground: _SwipeHint(
        icon: Icons.delete_outline_rounded,
        alignment: Alignment.centerRight,
        color: colors.error,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onReply();
        } else {
          onDelete();
        }
        return false;
      },
      child: row,
    );
  }

  static String _time(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour < 12 ? 'am' : 'pm';
    return '$hour:${d.minute.toString().padLeft(2, '0')}$period';
  }
}

/// A picture, in the thread rather than behind a download.
///
/// The bucket is private, so the URL has to be signed before anything can be
/// fetched — hence the FutureBuilder rather than a plain Image.network. Tapping
/// still opens the full-size original, because a chat bubble is not a viewer.
class _InlineImage extends StatefulWidget {
  final Message message;
  final VoidCallback onOpen;

  const _InlineImage({required this.message, required this.onOpen});

  @override
  State<_InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<_InlineImage> {
  late final Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = context.read<MessagesProvider>().attachmentUrl(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260, minWidth: 160),
        child: FutureBuilder<String?>(
          future: _url,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(
                height: 150,
                width: 200,
                color: colors.surfaceVariant,
                child: const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              );
            }
            final url = snapshot.data;
            if (url == null) {
              // A signed URL that could not be minted is still an attachment
              // worth offering, so this falls back rather than showing nothing.
              return InkWell(
                onTap: widget.onOpen,
                child: Container(
                  height: 90,
                  width: 200,
                  color: colors.surfaceVariant,
                  alignment: Alignment.center,
                  child: Text(
                    'Open picture',
                    style: TextStyle(color: colors.accent, fontSize: 12),
                  ),
                ),
              );
            }
            return InkWell(
              onTap: widget.onOpen,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 90,
                  width: 200,
                  color: colors.surfaceVariant,
                  alignment: Alignment.center,
                  child: Text(
                    widget.message.attachmentName,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The coloured hint that slides in behind a message as you drag it.
class _SwipeHint extends StatelessWidget {
  final IconData icon;
  final Alignment alignment;
  final Color color;

  const _SwipeHint({
    required this.icon,
    required this.alignment,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 26),
    child: Icon(icon, color: color, size: 20),
  );
}

/// What the composer is currently answering.
///
/// Above the field rather than inside it, so the quote cannot be scrolled out
/// of sight by a long message being typed underneath it.
class _ReplyStrip extends StatelessWidget {
  final Message message;
  final bool isMine;
  final VoidCallback onCancel;

  const _ReplyStrip({
    required this.message,
    required this.isMine,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMine ? 'Replying to yourself' : 'Replying',
                  style: text.labelSmall?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  message.quotedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Stop replying',
          ),
        ],
      ),
    );
  }
}
