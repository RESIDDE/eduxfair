import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_colors.dart';
import '../models/conversation.dart';
import '../providers/messages_provider.dart';

/// Plays one voice note.
///
/// The URL is signed on demand rather than at list build: a thread can hold a
/// hundred of these, and signing every one to render a row nobody pressed
/// would be a hundred requests for the one they do.
class VoiceNoteBubble extends StatefulWidget {
  final Message message;
  final bool isMine;

  const VoiceNoteBubble({super.key, required this.message, required this.isMine});

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  AudioPlayer? _player;
  bool _preparing = false;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positions;
  StreamSubscription<PlayerState>? _states;

  @override
  void dispose() {
    _positions?.cancel();
    _states?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final existing = _player;
    if (existing != null) {
      if (existing.playing) {
        await existing.pause();
      } else {
        // A finished clip rewinds rather than refusing to start, which is what
        // pressing play on something that has ended obviously means.
        if (existing.position >= (existing.duration ?? Duration.zero)) {
          await existing.seek(Duration.zero);
        }
        await existing.play();
      }
      if (mounted) setState(() {});
      return;
    }

    setState(() => _preparing = true);
    try {
      final url =
          await context.read<MessagesProvider>().attachmentUrl(widget.message);
      if (!mounted || url == null) return;

      final player = AudioPlayer();
      await player.setUrl(url);
      _positions = player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _states = player.playerStateStream.listen((_) {
        if (mounted) setState(() {});
      });
      _player = player;
      await player.play();
    } catch (e) {
      if (kDebugMode) debugPrint('voice note playback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That voice note could not be played.')),
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = widget.isMine ? colors.onAccent : colors.textPrimary;
    final total = _player?.duration ?? widget.message.duration ?? Duration.zero;
    final playing = _player?.playing ?? false;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _preparing ? null : _toggle,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _preparing
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 26,
                    color: fg,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 118,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: fg.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                // Counts up while playing and shows the length at rest, which
                // is the one number that is useful at each moment.
                playing || _position > Duration.zero
                    ? _label(_position)
                    : widget.message.durationLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.85),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _label(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

/// The composer's recorder: hold-free, with an explicit stop and a cancel.
///
/// Not press-and-hold. A thirty-second answer about entry requirements is a
/// long time to keep a thumb down, and a hold gesture that slips cancels the
/// recording with nothing to show for it.
class VoiceRecorderBar extends StatefulWidget {
  final void Function(String path, int durationMs) onComplete;
  final VoidCallback onCancel;

  const VoiceRecorderBar({
    super.key,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _recorder = AudioRecorder();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _started = false;
  String? _path;

  /// Two minutes. Long enough for a real answer, short enough that a pocket
  /// recording does not become a twenty-megabyte upload.
  static const _limit = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        widget.onCancel();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Allow microphone access to record a voice note.'),
            ),
          );
        }
        return;
      }

      // `path` is required and handed straight to the native recorder, so it
      // has to be somewhere real — an empty string here recorded to nothing
      // and stopped with no file to send.
      final dir = await getTemporaryDirectory();
      _path =
          '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';

      // AAC in an m4a: the format both phones encode natively, and the one the
      // storage bucket accepts as audio/mp4.
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: _path!,
      );
      if (!mounted) return;
      setState(() => _started = true);

      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(milliseconds: 200));
        if (_elapsed >= _limit) _stop();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('recording failed to start: $e');
      widget.onCancel();
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    if (path == null || _elapsed.inMilliseconds < 700) {
      // Under about a second is a slip, not a message.
      widget.onCancel();
      return;
    }
    widget.onComplete(path, _elapsed.inMilliseconds);
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await _recorder.stop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        IconButton(
          onPressed: _cancel,
          icon: Icon(Icons.delete_outline_rounded, color: colors.error),
          tooltip: 'Discard',
        ),
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: colors.error, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          _started
              ? '${_elapsed.inMinutes}:'
                  '${_elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}'
              : 'Starting…',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        Text(
          'Recording',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: _started ? _stop : null,
          icon: const Icon(Icons.send_rounded, size: 19),
          tooltip: 'Send',
        ),
      ],
    );
  }
}
