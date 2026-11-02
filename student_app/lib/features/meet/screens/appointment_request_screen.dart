import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../models/appointment.dart';
import '../providers/meet_provider.dart';

/// Requests a Meet Me appointment.
///
/// Phase 1 has no in-app video, so a confirmed video meeting arrives as a link
/// the institution supplies. The copy says so, rather than implying a call
/// will happen inside the app.
class AppointmentRequestScreen extends StatefulWidget {
  final String institutionId;
  final String? programId;

  const AppointmentRequestScreen({
    super.key,
    required this.institutionId,
    this.programId,
  });

  @override
  State<AppointmentRequestScreen> createState() =>
      _AppointmentRequestScreenState();
}

class _AppointmentRequestScreenState extends State<AppointmentRequestScreen> {
  final _message = TextEditingController();
  List<AvailabilitySlot> _slots = [];
  AvailabilitySlot? _selected;
  String _channel = 'video';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    final slots =
        await context.read<MeetProvider>().fetchSlots(widget.institutionId);
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final provider = context.read<MeetProvider>();
    // Resolved before the await, so nothing reaches back through a context
    // that may no longer be mounted.
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final errorColour = context.colors.error;

    final ok = await provider.request(
      institutionId: widget.institutionId,
      programId: widget.programId,
      slot: _selected,
      channel: _channel,
      message: _message.text.trim().isEmpty ? null : _message.text.trim(),
    );

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Request sent. You will hear back once they confirm.'
            : provider.error ?? 'Could not send your request.'),
        backgroundColor: ok ? null : errorColour,
      ),
    );
    // `context.pop()` rather than Navigator's, for the same reason as the
    // composer: this is a GoRoute, and popping it off the Navigator directly
    // leaves go_router's match list out of step with the real stack.
    if (ok) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final provider = context.watch<MeetProvider>();

    // Group open slots by day so a long list stays scannable.
    final byDay = <String, List<AvailabilitySlot>>{};
    for (final slot in _slots) {
      final key = _dayKey(slot.startsAt);
      byDay.putIfAbsent(key, () => []).add(slot);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Request a meeting')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                // Sets the expectation about what happens next, including the
                // passport share that requesting triggers.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.infoLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: colors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Requesting a meeting lets this institution see your '
                          'passport, so they can prepare. You can revoke that '
                          'at any time.',
                          style: text.bodySmall?.copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text('How would you like to meet?', style: text.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'video',
                      label: Text('Video'),
                      icon: Icon(Icons.videocam_outlined, size: 17),
                    ),
                    ButtonSegment(
                      value: 'phone',
                      label: Text('Phone'),
                      icon: Icon(Icons.call_outlined, size: 17),
                    ),
                    ButtonSegment(
                      value: 'in_person',
                      label: Text('In person'),
                      icon: Icon(Icons.place_outlined, size: 17),
                    ),
                  ],
                  selected: {_channel},
                  onSelectionChanged: (v) => setState(() => _channel = v.first),
                ),
                if (_channel == 'video') ...[
                  const SizedBox(height: 8),
                  Text(
                    'The institution will send a joining link once they '
                    'confirm.',
                    style: text.bodySmall,
                  ),
                ],

                const SizedBox(height: 24),
                Text('Pick a time', style: text.titleLarge),
                const SizedBox(height: 6),
                Text(
                  _slots.isEmpty
                      ? 'This institution has not published any open times. '
                          'Send a request and they will propose one.'
                      : 'Or send a request without a time and let them '
                          'propose one.',
                  style: text.bodySmall?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 14),

                ...byDay.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.key, style: text.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: entry.value.map((slot) {
                            final selected = _selected?.id == slot.id;
                            return ChoiceChip(
                              label: Text(_timeLabel(slot.startsAt)),
                              selected: selected,
                              showCheckmark: false,
                              onSelected: (_) => setState(
                                () => _selected = selected ? null : slot,
                              ),
                              backgroundColor: colors.surface,
                              selectedColor: colors.accent,
                              side: BorderSide(
                                color: selected ? colors.accent : colors.border,
                              ),
                              labelStyle: text.bodyMedium?.copyWith(
                                color: selected
                                    ? context.colors.onAccent
                                    : colors.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                CustomTextField(
                  controller: _message,
                  label: 'Anything you want them to know?',
                  hint: 'What you would like to discuss.',
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                ),

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: provider.busy ? null : _submit,
                  child: provider.busy
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: context.colors.onAccent,
                          ),
                        )
                      : Text(_selected == null
                          ? 'Send request'
                          : 'Request ${_timeLabel(_selected!.startsAt)}'),
                ),
              ],
            ),
    );
  }

  static String _dayKey(DateTime d) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  static String _timeLabel(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour < 12 ? 'am' : 'pm';
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute$period';
  }
}
