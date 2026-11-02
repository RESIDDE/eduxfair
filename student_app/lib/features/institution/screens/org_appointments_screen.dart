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
import '../../../core/widgets/empty_state.dart';
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
    final colors = context.colors;
    final pendingCount = _requested.length;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Meeting requests'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: _publishSlot,
            icon: const Icon(Icons.add_alarm_rounded),
            tooltip: 'Publish slot',
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              child: Row(
                children: [
                  const Text('Requested'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.warning,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: 'Upcoming (${_upcoming.length})'),
            Tab(text: 'Open slots (${_slots.where((s) => s['is_booked'] != true).length})'),
            Tab(text: 'History (${_history.length})'),
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
                      emptyTitle: 'No pending meeting requests',
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
                      emptyTitle: 'No appointment history',
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
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
    final text = Theme.of(context).textTheme;

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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_slots.length} published slot${_slots.length == 1 ? '' : 's'}',
                  style: text.labelLarge?.copyWith(color: colors.textSecondary),
                ),
                TextButton.icon(
                  onPressed: _publishSlot,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add slot'),
                ),
              ],
            ),
          ),
          ..._slots.map((slot) {
            final start = DateTime.parse(slot['starts_at'] as String).toLocal();
            final end = DateTime.parse(slot['ends_at'] as String).toLocal();
            final isBooked = slot['is_booked'] as bool? ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isBooked ? colors.accent : colors.success).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isBooked ? Icons.event_busy_rounded : Icons.event_available_rounded,
                      size: 20,
                      color: isBooked ? colors.accent : colors.success,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatDateTime(start),
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Until ${TimeOfDay.fromDateTime(end).format(context)} · ${isBooked ? 'Booked by student' : 'Open for booking'}',
                          style: text.bodySmall?.copyWith(
                            color: isBooked ? colors.accent : colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isBooked)
                    IconButton(
                      onPressed: () => _deleteSlot(slot['id'] as String),
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.textLight),
                      tooltip: 'Remove slot',
                    ),
                ],
              ),
            );
          }),
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

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student Name & Status
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colors.surfaceVariant,
                  child: Text(
                    appointment.studentName.isNotEmpty
                        ? appointment.studentName[0].toUpperCase()
                        : 'S',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appointment.studentName,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (appointment.programName != null)
                        Text(
                          appointment.programName!,
                          style: text.bodySmall?.copyWith(color: colors.textSecondary),
                        ),
                    ],
                  ),
                ),
                _StatusBadge(status: appointment.status, label: appointment.statusLabel),
              ],
            ),

            const SizedBox(height: 12),

            // Time & Channel Info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: colors.accent),
                  const SizedBox(width: 6),
                  Text(
                    appointment.scheduledFor != null
                        ? formatDateTime(appointment.scheduledFor!)
                        : 'Time requested by student',
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(
                    appointment.isLekksideRoom
                        ? Icons.videocam_rounded
                        : Icons.link_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${appointment.durationMin}m · ${appointment.isLekksideRoom ? 'In-app room' : 'External link'}',
                    style: text.labelSmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),

            if (appointment.studentMessage != null && appointment.studentMessage!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '“${appointment.studentMessage}”',
                style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: colors.textSecondary),
              ),
            ],

            if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Note: ${appointment.notes}',
                style: text.labelSmall?.copyWith(color: colors.textLight),
              ),
            ],

            const SizedBox(height: 14),

            // Action Buttons
            if (onConfirm != null) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isBusy ? null : onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(color: colors.error.withValues(alpha: 0.4)),
                        minimumSize: const Size(0, 42),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isBusy ? null : onConfirm,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42)),
                      child: const Text('Confirm time'),
                    ),
                  ),
                ],
              ),
            ] else if (appointment.isUpcoming) ...[
              Row(
                children: [
                  if (appointment.isLekksideRoom)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: appointment.canJoinNow
                            ? () => context.push('${AppConstants.routeCall}/appointment/${appointment.id}')
                            : null,
                        icon: const Icon(Icons.videocam_rounded, size: 18),
                        label: Text(appointment.canJoinNow ? 'Join video call' : 'Call opens 10m before'),
                        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42)),
                      ),
                    )
                  else if (appointment.meetingUrl != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(appointment.meetingUrl!)),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Open meeting link'),
                        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42)),
                      ),
                    ),
                  if (onCancel != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: isBusy ? null : onCancel,
                      icon: Icon(Icons.cancel_outlined, color: colors.error, size: 22),
                      tooltip: 'Cancel meeting',
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final String label;

  const _StatusBadge({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color bg;
    Color fg;

    switch (status) {
      case 'confirmed':
        bg = colors.successLight;
        fg = colors.success;
        break;
      case 'requested':
        bg = colors.warningLight;
        fg = colors.warning;
        break;
      case 'completed':
        bg = colors.infoLight;
        fg = colors.info;
        break;
      case 'declined':
      case 'cancelled':
        bg = colors.errorLight;
        fg = colors.error;
        break;
      default:
        bg = colors.surfaceVariant;
        fg = colors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
