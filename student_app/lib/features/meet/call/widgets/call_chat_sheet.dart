import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_service.dart';
import '../../models/space.dart';
import '../call_provider.dart';

/// In-room chat, over Postgres rather than LiveKit.
///
/// LiveKit text streams are not persisted and reach only the clients connected
/// when the stream opens, so a student arriving ten minutes into an admissions
/// hour would find an empty panel. Keeping chat in a table makes ordering,
/// history and persistence one mechanism instead of three.
///
/// A Space uses `space_messages`. An appointment uses the `messages` thread the
/// two of them already have, so what was typed during the call is in the inbox
/// where they will look for it — and the 1:1 case adds no schema at all.
void showCallChatSheet(
  BuildContext context,
  CallProvider call, {
  required VoidCallback onNeedsConsent,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _CallChat(call: call, onNeedsConsent: onNeedsConsent),
      ),
    ),
  );
}

class _CallChat extends StatefulWidget {
  final CallProvider call;
  final VoidCallback onNeedsConsent;

  const _CallChat({required this.call, required this.onNeedsConsent});

  @override
  State<_CallChat> createState() => _CallChatState();
}

class _CallChatState extends State<_CallChat> {
  final _service = SupabaseService.instance;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<SpaceMessage> _messages = [];
  RealtimeChannel? _channel;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  bool get _isSpace => widget.call.isSpace;
  String get _table => _isSpace ? 'space_messages' : 'messages';
  String get _key => _isSpace ? 'space_id' : 'conversation_id';
  String? get _chatId =>
      _isSpace ? widget.call.id : widget.call.grant?.conversationId;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _service.client.removeChannel(channel);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chatId = _chatId;
    if (chatId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      var query = _service.client.from(_table).select().eq(_key, chatId);
      if (_isSpace) query = query.isFilter('deleted_at', null);
      final rows = await query.order('created_at').limit(400);
      if (!mounted) return;
      setState(() {
        _messages = (rows as List)
            .map((r) => SpaceMessage.fromMap(r as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseService.describeError(e);
        _loading = false;
      });
    }
  }

  void _subscribe() {
    final chatId = _chatId;
    if (chatId == null) return;
    _channel = _service.client
        .channel('$_table:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: _key,
            value: chatId,
          ),
          callback: (payload) {
            final message = SpaceMessage.fromMap(payload.newRecord);
            if (!mounted) return;
            // De-duplicate: the sender already appended this optimistically.
            if (_messages.any((m) => m.id == message.id)) return;
            setState(() => _messages = [..._messages, message]);
            _toBottom();
          },
        )
        .subscribe();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// Names are resolved from the roster by participant id, which is why a chat
  /// row does not carry one.
  String _nameFor(SpaceMessage message) {
    if (!_isSpace) {
      return message.senderId == _service.userId ? 'You' : 'Them';
    }
    if (message.participantId == widget.call.grant?.participantId) return 'You';
    final row = widget.call.roster
        .where((r) => r.participantId == message.participantId)
        .firstOrNull;
    return row?.label ?? 'Someone';
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    // Posting in the chat identifies a student, so the consent sheet comes
    // first. The insert policy refuses a listener anyway — this is so they are
    // asked rather than rejected.
    if (!widget.call.canPublish) {
      Navigator.of(context).pop();
      widget.onNeedsConsent();
      return;
    }

    final chatId = _chatId;
    if (chatId == null) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final row = await _service.client
          .from(_table)
          .insert(_isSpace
              ? {
                  'space_id': chatId,
                  'participant_id': widget.call.grant?.participantId,
                  'body': text,
                }
              : {
                  'conversation_id': chatId,
                  'sender_id': _service.userId,
                  'body': text,
                })
          .select()
          .single();

      if (!mounted) return;
      final message = SpaceMessage.fromMap(row);
      setState(() {
        if (!_messages.any((m) => m.id == message.id)) {
          _messages = [..._messages, message];
        }
        _input.clear();
      });
      _toBottom();
    } catch (e) {
      if (mounted) setState(() => _error = SupabaseService.describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (_, index) {
                        final message = _messages[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _nameFor(message),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    TimeOfDay.fromDateTime(message.createdAt)
                                        .format(context),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                message.body,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 1000,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: widget.call.canPublish
                        ? 'Write a message'
                        : 'Share your passport to join in',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF202327),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
