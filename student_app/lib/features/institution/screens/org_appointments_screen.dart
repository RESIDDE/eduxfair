import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/chrome_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../widgets/org_ui.dart';
import '../models/org_appointment.dart';
import '../providers/institution_provider.dart';

/// Meeting requests and appointment scheduling for admissions staff.
///
/// Staff confirm requests, launch LiveKit video rooms, and publish availability slots.
class OrgAppointmentsScreen extends StatefulWidget {
  const OrgAppointmentsScreen({super.key});

  @override
  State<OrgAppointmentsScreen> createState() => _OrgAppointmentsScreenState();
}

class _OrgAppointmentsScreenState extends State<OrgAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService.instance;

  late TabController _tabController;
  bool _loading = true;
  String? _error;
  List<OrgAppointment> _appointments = [];
  List<Map<String, dynamic>> _slots = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final institutionId = context.read<InstitutionProvider>().institutionId;
    if (institutionId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.client
            .from('appointments')
            .select(
              'id, status, scheduled_for, duration_min, channel, meeting_url, '
              'meeting_mode, student_message, notes, student_id, '
              'student:profiles!student_id(id, full_name), programs(id, name), created_at',
            )
            .eq('institution_id', institutionId)
            .order('scheduled_for', ascending: true, nullsFirst: true),
        _service.client
            .from('availability_slots')
            .select()
            .eq('institution_id', institutionId)
            .gte('starts_at', DateTime.now().toIso8601String())
            .order('starts_at'),
      ]);

      if (!mounted) return;
      setState(() {
        _appointments = (results[0] as List)
            .map((r) => OrgAppointment.fromMap((r as Map).cast<String, dynamic>()))
            .toList();
        _slots = (results[1] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = SupabaseService.describeError(e);
        _loading = false;
      });
    }
  }

  List<OrgAppointment> get _requested =>
      _appointments.where((a) => a.isRequested).toList();

  List<OrgAppointment> get _upcoming =>
      _appointments.where((a) => a.isUpcoming).toList();

  List<OrgAppointment> get _history => _appointments
      .where((a) => !a.isRequested && !a.isUpcoming)
      .toList();

  Future<void> _confirmAppointment(OrgAppointment appointment) async {
    DateTime selectedDate = appointment.scheduledFor ?? DateTime.now().add(const Duration(days: 1));
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(selectedDate);
    int duration = appointment.durationMin;
    String mode = appointment.meetingMode;
    final urlController = TextEditingController(text: appointment.meetingUrl ?? '');
    final notesController = TextEditingController(text: appointment.notes ?? '');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = ctx.colors;
            final text = Theme.of(ctx).textTheme;

            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Confirm appointment', style: text.titleLarge),
                    Text(
                      'Meeting with ${appointment.studentName}',
                      style: text.bodySmall?.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 18),

                    // Date & Time Picker Row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 90)),
                              );
                              if (picked != null) {
                                setSheetState(() => selectedDate = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(formatDayMonth(selectedDate)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setSheetState(() => selectedTime = picked);
                              }
                            },
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            label: Text(selectedTime.format(ctx)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Duration Selector
                    Text('Duration', style: text.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [15, 30, 45, 60].map((d) {
                        final isSel = duration == d;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$d min'),
                            selected: isSel,
                            onSelected: (_) => setSheetState(() => duration = d),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 16),

                    // Mode: Lekkside Room vs External Link
                    Text('Meeting room', style: text.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('In-App Video'),
                            avatar: const Icon(Icons.videocam_rounded, size: 16),
                            selected: mode == 'lekkside_room',
                            onSelected: (_) => setSheetState(() => mode = 'lekkside_room'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('External link'),
                            avatar: const Icon(Icons.link_rounded, size: 16),
                            selected: mode == 'external_link',
                            onSelected: (_) => setSheetState(() => mode = 'external_link'),
                          ),
                        ),
                      ],
                    ),

                    if (mode == 'external_link') ...[
                      const SizedBox(height: 14),
                      CustomTextField(
                        controller: urlController,
                        label: 'Meeting URL',
                        hint: 'https://meet.google.com/... or Zoom link',
                      ),
                    ],

                    const SizedBox(height: 14),
                    CustomTextField(
                      controller: notesController,
                      label: 'Admissions note (optional)',
                      hint: 'Preparation notes or agenda for the student...',
                      maxLines: 2,
                    ),

                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Confirm meeting'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final finalDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    ).toUtc();

    setState(() => _busy = true);
    try {
      await _service.client.from('appointments').update({
        'status': 'confirmed',
        'scheduled_for': finalDateTime.toIso8601String(),
        'duration_min': duration,
        'meeting_mode': mode,
        'meeting_url': mode == 'external_link' ? urlController.text.trim() : null,
        'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      }).eq('id', appointment.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment confirmed.'), backgroundColor: Colors.green),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SupabaseService.describeError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateStatus(OrgAppointment appointment, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${status == 'declined' ? 'Decline' : 'Cancel'} appointment?'),
        content: Text('Are you sure you want to ${status == 'declined' ? 'decline' : 'cancel'} this meeting with ${appointment.studentName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.error),
            child: Text(status == 'declined' ? 'Decline' : 'Cancel meeting'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _service.client
          .from('appointments')
          .update({'status': status})
          .eq('id', appointment.id);

      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SupabaseService.describeError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishSlot() async {
    final institutionId = context.read<InstitutionProvider>().institutionId;
    final userId = _service.userId;
    if (institutionId == null || userId == null) return;

    DateTime slotDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 30);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = ctx.colors;
            final text = Theme.of(ctx).textTheme;

            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Publish availability slot', style: text.titleLarge),
                  Text(
                    'Students can instantly book this slot from your institution page.',
                    style: text.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: slotDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (picked != null) setSheetState(() => slotDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(formatDate(slotDate)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: startTime,
                            );
                            if (picked != null) setSheetState(() => startTime = picked);
                          },
                          icon: const Icon(Icons.access_time_rounded, size: 16),
                          label: Text('Starts: ${startTime.format(ctx)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: endTime,
                            );
                            if (picked != null) setSheetState(() => endTime = picked);
                          },
                          icon: const Icon(Icons.access_time_filled_rounded, size: 16),
                          label: Text('Ends: ${endTime.format(ctx)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Publish slot'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final startUtc = DateTime(
      slotDate.year,
      slotDate.month,
      slotDate.day,
      startTime.hour,
      startTime.minute,
    ).toUtc();

    final endUtc = DateTime(
      slotDate.year,
      slotDate.month,
      slotDate.day,
      endTime.hour,
      endTime.minute,
    ).toUtc();

    setState(() => _busy = true);
    try {
      await _service.client.from('availability_slots').insert({
        'institution_id': institutionId,
        'host_profile_id': userId,
        'starts_at': startUtc.toIso8601String(),
        'ends_at': endUtc.toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Availability slot published.'), backgroundColor: Colors.green),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SupabaseService.describeError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSlot(String slotId) async {
    setState(() => _busy = true);
    try {
      await _service.client.from('availability_slots').delete().eq('id', slotId);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SupabaseService.describeError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _requested.length;

    final freeSlots = _slots.where((s) => s['is_booked'] != true).length;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Meetings'),
        actions: [
          // Adding a free time sits top-right, like every other "add" in the
          // app. Refresh is a pull on the list, as everywhere else.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ChromeButton.icon(
              icon: Icons.add_rounded,
              tooltip: 'Add a time you are free',
              onTap: _publishSlot,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: pendingCount > 0 ? 'Requests  $pendingCount' : 'Requests'),
            Tab(text: _upcoming.isEmpty ? 'Upcoming' : 'Upcoming  ${_upcoming.length}'),
            Tab(text: freeSlots == 0 ? 'Free times' : 'Free times  $freeSlots'),
            const Tab(text: 'Past'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Requested
                    _buildAppointmentList(
                      appointments: _requested,
                      emptyTitle: 'No requests waiting',
                      emptyMessage: 'When students request a Meet Me appointment with your admissions staff, they will appear here for confirmation.',
                      isRequestedTab: true,
                    ),

                    // Tab 2: Upcoming
                    _buildAppointmentList(
                      appointments: _upcoming,
                      emptyTitle: 'No upcoming meetings',
                      emptyMessage: 'Confirmed video appointments will appear here with a direct link to join when the meeting window opens.',
                      isUpcomingTab: true,
                    ),

                    // Tab 3: Open Slots
                    _buildSlotsList(),

                    // Tab 4: History
                    _buildAppointmentList(
                      appointments: _history,
                      emptyTitle: 'No past meetings',
                      emptyMessage: 'Completed and past meetings are stored here.',
                    ),
                  ],
                ),
    );
  }

  Widget _buildAppointmentList({
    required List<OrgAppointment> appointments,
    required String emptyTitle,
    required String emptyMessage,
    bool isRequestedTab = false,
    bool isUpcomingTab = false,
  }) {
    if (appointments.isEmpty) {
      return EmptyState(
        icon: Icons.event_available_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        itemCount: appointments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final appt = appointments[index];
          return _AppointmentCard(
            appointment: appt,
            onConfirm: isRequestedTab ? () => _confirmAppointment(appt) : null,
            onDecline: isRequestedTab ? () => _updateStatus(appt, 'declined') : null,
            onCancel: isUpcomingTab ? () => _updateStatus(appt, 'cancelled') : null,
            isBusy: _busy,
          );
        },
      ),
    );
  }

  Widget _buildSlotsList() {
    final colors = context.colors;

    if (_slots.isEmpty) {
      return EmptyState(
        icon: Icons.calendar_today_outlined,
        title: 'No availability published',
        message: 'Publish open time slots so prospective students can book 1:1 admissions meetings with you.',
        actionLabel: 'Publish slot',
        onAction: _publishSlot,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 40),
        children: [
          OrgSectionLabel('Times students can book', count: _slots.length),
          OrgGroup(
            children: [
              for (final slot in _slots)
                Builder(builder: (context) {
                  final start =
                      DateTime.parse(slot['starts_at'] as String).toLocal();
                  final end =
                      DateTime.parse(slot['ends_at'] as String).toLocal();
                  final isBooked = slot['is_booked'] as bool? ?? false;
                  return OrgRow(
                    leading: _DateTile(date: start),
                    title: '${TimeOfDay.fromDateTime(start).format(context)} – '
                        '${TimeOfDay.fromDateTime(end).format(context)}',
                    subtitle: _weekday(start),
                    tags: [
                      isBooked
                          ? OrgTag('Booked', tone: colors.accent)
                          : const OrgTag('Open'),
                    ],
                    trailing: isBooked
                        ? null
                        : IconButton(
                            onPressed: () => _deleteSlot(slot['id'] as String),
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 20, color: colors.textLight),
                            tooltip: 'Remove this time',
                          ),
                  );
                }),
            ],
          ),
          const OrgNotice(
            icon: Icons.info_outline_rounded,
            margin: EdgeInsets.fromLTRB(16, 14, 16, 0),
            message: 'Students see open times on your page and can book one '
                'for a one-to-one meeting. Booked times can only be released '
                'by cancelling the meeting.',
          ),
        ],
      ),
    );
  }
}

String _weekday(DateTime d) {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
    'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// A calendar leaf: month above, day below — the shape iOS uses for a date,
/// so it is read before it is parsed.
class _DateTile extends StatelessWidget {
  final DateTime? date;
  const _DateTile({required this.date});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG',
      'SEP', 'OCT', 'NOV', 'DEC'];
    final d = date;
    return Container(
      width: 46,
      height: 50,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: d == null
          ? Icon(Icons.schedule_rounded, color: colors.textSecondary, size: 20)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(months[d.month - 1],
                    style: text.labelSmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.4)),
                Text('${d.day}',
                    style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700, height: 1.05)),
              ],
            ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final OrgAppointment appointment;
  final VoidCallback? onConfirm;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;
  final bool isBusy;

  const _AppointmentCard({
    required this.appointment,
    this.onConfirm,
    this.onDecline,
    this.onCancel,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final when = appointment.scheduledFor;
    final statusTone = switch (appointment.status) {
      'requested' => colors.warning,
      'confirmed' => colors.success,
      'declined' || 'cancelled' || 'no_show' => colors.error,
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateTile(date: when),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      when == null
                          ? 'Time to be agreed'
                          : '${_weekday(when)} · ${TimeOfDay.fromDateTime(when).format(context)}',
                      style: text.bodySmall?.copyWith(color: colors.textPrimary),
                    ),
                    Text(
                      [
                        '${appointment.durationMin} min',
                        appointment.isLekksideRoom ? 'In-app video' : 'External link',
                        if (appointment.programName != null) appointment.programName!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OrgTag(appointment.statusLabel, tone: statusTone),
            ],
          ),
          if (appointment.studentMessage != null &&
              appointment.studentMessage!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                appointment.studentMessage!,
                style: text.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ],
          if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Note: ${appointment.notes}',
              style: text.labelSmall?.copyWith(color: colors.textLight),
            ),
          ],
          if (onConfirm != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OrgPillButton(
                    label: 'Decline',
                    tone: colors.error,
                    onTap: isBusy ? null : onDecline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OrgPillButton(
                    label: 'Confirm',
                    primary: true,
                    onTap: isBusy ? null : onConfirm,
                  ),
                ),
              ],
            ),
          ] else if (appointment.isUpcoming) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (appointment.isLekksideRoom)
                  Expanded(
                    child: OrgPillButton(
                      label: appointment.canJoinNow
                          ? 'Join video call'
                          : 'Opens 10 min before',
                      icon: Icons.videocam_rounded,
                      primary: appointment.canJoinNow,
                      onTap: appointment.canJoinNow
                          ? () => context.push(
                              '${AppConstants.routeCall}/appointment/${appointment.id}')
                          : null,
                    ),
                  )
                else if (appointment.meetingUrl != null)
                  Expanded(
                    child: OrgPillButton(
                      label: 'Open meeting link',
                      icon: Icons.open_in_new_rounded,
                      primary: true,
                      onTap: () => launchUrl(Uri.parse(appointment.meetingUrl!)),
                    ),
                  ),
                if (onCancel != null) ...[
                  const SizedBox(width: 8),
                  OrgPillButton(
                    label: 'Cancel',
                    tone: colors.error,
                    onTap: isBusy ? null : onCancel,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
