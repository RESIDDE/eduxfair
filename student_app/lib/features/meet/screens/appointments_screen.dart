import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/institution_avatar.dart';
import '../models/appointment.dart';
import '../providers/meet_provider.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MeetProvider>().load();
    });
  }

  Future<void> _cancel(Appointment appointment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this meeting?'),
        content: Text(
          'You will need to request a new time with '
          '${appointment.institution?.name ?? 'this institution'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Cancel meeting'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final provider = context.read<MeetProvider>();
    final ok = await provider.cancel(appointment);
    if (!mounted || ok) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(provider.error ?? 'Could not cancel.'),
        backgroundColor: context.colors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final provider = context.watch<MeetProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('My meetings')),
      body: provider.loading && provider.appointments.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.appointments.isEmpty
              ? const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No meetings yet',
                  message: 'Request a meeting from any institution or program '
                      'page, and it will appear here once they confirm a time.',
                )
              : RefreshIndicator(
                  onRefresh: provider.load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      if (provider.upcoming.isNotEmpty) ...[
                        Text('Upcoming', style: text.titleLarge),
                        const SizedBox(height: 12),
                        ...provider.upcoming.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AppointmentCard(
                              appointment: a,
                              onCancel: () => _cancel(a),
                            ),
                          ),
                        ),
                      ],
                      if (provider.past.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Past', style: text.titleLarge),
                        const SizedBox(height: 12),
                        ...provider.past.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AppointmentCard(appointment: a),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback? onCancel;

  const _AppointmentCard({required this.appointment, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final statusColor = appointment.isConfirmed
        ? colors.success
        : appointment.isRequested
            ? colors.warning
            : colors.textLight;

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
            children: [
              InstitutionAvatar(
                logoUrl: appointment.institution?.logoUrl,
                initials: appointment.institution?.initials ?? '?',
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.institution?.name ?? 'Institution',
                      style: text.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (appointment.programName != null)
                      Text(appointment.programName!, style: text.bodySmall),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  appointment.statusLabel,
                  style: text.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 15, color: colors.textLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  appointment.scheduledFor == null
                      ? 'Waiting for a time to be proposed'
                      : '${_formatDateTime(appointment.scheduledFor!)} · '
                          '${appointment.durationMin} min',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(_channelIcon, size: 15, color: colors.textLight),
              const SizedBox(width: 6),
              Text(appointment.channelLabel, style: text.bodySmall),
            ],
          ),

          if (appointment.notes != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                appointment.notes!,
                style: text.bodySmall?.copyWith(height: 1.45),
              ),
            ),
          ],

          if (appointment.canJoinNow) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              // Ours opens in the app; a link the institution pasted still
              // leaves it. Keeping url_launcher for those is what makes this an
              // additive change rather than a migration of live appointments.
              onPressed: () => appointment.isLekksideRoom
                  ? context.push(
                      '${AppConstants.routeCall}/appointment/${appointment.id}')
                  : launchUrl(
                      Uri.parse(appointment.meetingUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: Text(
                appointment.isLekksideRoom ? 'Join the call' : 'Join now',
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
                backgroundColor: colors.success,
              ),
            ),
          ] else if (appointment.isConfirmed &&
              appointment.meetingUrl != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.link_rounded, size: 15, color: colors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // Explains why the button is not live yet rather than
                    // leaving a dead link on screen.
                    'Your joining link opens 10 minutes before the meeting.',
                    style: text.bodySmall?.copyWith(color: colors.accent),
                  ),
                ),
              ],
            ),
          ],

          if (onCancel != null && !appointment.isComplete) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: colors.error),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData get _channelIcon => switch (appointment.channel) {
        'video' => Icons.videocam_outlined,
        'phone' => Icons.call_outlined,
        'in_person' => Icons.place_outlined,
        'chat' => Icons.forum_outlined,
        _ => Icons.event_outlined,
      };

  static String _formatDateTime(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour < 12 ? 'am' : 'pm';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}, '
        '$hour:$minute$period';
  }
}
