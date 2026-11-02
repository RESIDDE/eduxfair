import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/surface.dart';
import '../../auth/providers/auth_provider.dart';
import '../../meet/models/space.dart';
import '../../meet/providers/spaces_provider.dart';
import '../providers/institution_provider.dart';

/// Live sessions, from the institution's side.
///
/// Media runs on LiveKit; the schedule, the waiting room and the in-room chat
/// run on Postgres and Supabase Realtime. The split is deliberate: LiveKit
/// carries what is transient, and anything a student might later dispute — what
/// was said in the chat, who was removed and why — lives in a table.
class OrgSpacesScreen extends StatefulWidget {
  const OrgSpacesScreen({super.key});

  @override
  State<OrgSpacesScreen> createState() => _OrgSpacesScreenState();
}

class _OrgSpacesScreenState extends State<OrgSpacesScreen> {
  String? _institutionId;

  /// Held so [dispose] can close the channel: by then the element is
  /// deactivated and `context.read` on it throws.
  SpacesProvider? _spaces;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spaces = context.read<SpacesProvider>();
    final id = context.watch<InstitutionProvider>().institution?.id;
    if (id != null && id != _institutionId) {
      _institutionId = id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final spaces = context.read<SpacesProvider>();
        spaces.load(institutionId: id);
        spaces.subscribe(institutionId: id);
      });
    }
  }

  @override
  void dispose() {
    _spaces?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<SpacesProvider>();
    final institution = context.watch<InstitutionProvider>().institution;
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final upcomingList = [...spaces.live, ...spaces.upcoming];
    final historyList = spaces.past;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Spaces'),
          bottom: TabBar(
            tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Live & Upcoming'),
                  if (spaces.live.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ] else if (spaces.upcoming.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${spaces.upcoming.length}',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('History'),
                  if (historyList.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.textSecondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${historyList.length}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: institution == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _schedule(context, institution.id),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedule'),
            ),
      body: Column(
        children: [
          if (spaces.error != null)
            Container(
              width: double.infinity,
              color: colors.errorLight,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      spaces.error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.error),
                    ),
                  ),
                  IconButton(
                    onPressed: spaces.clearError,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: colors.error,
                  ),
                ],
              ),
            ),
          Expanded(
            child: spaces.loading && spaces.spaces.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      // Tab 1: Live & Upcoming
                      RefreshIndicator(
                        onRefresh: () => spaces.load(institutionId: _institutionId),
                        child: upcomingList.isEmpty
                            ? ListView(
                                key: const PageStorageKey('org_spaces_upcoming_empty'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: const [
                                  SizedBox(height: 40),
                                  EmptyState(
                                    icon: Icons.podcasts_outlined,
                                    title: 'No upcoming sessions',
                                    message:
                                        'Schedule an admissions hour, scholarship Q&A '
                                        'or open day. Students will see it on their '
                                        'Spaces tab and drop in.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const PageStorageKey('org_spaces_upcoming_list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 96),
                                itemCount: upcomingList.length,
                                itemBuilder: (context, index) =>
                                    _OrgSpaceCard(space: upcomingList[index]),
                              ),
                      ),

                      // Tab 2: History
                      RefreshIndicator(
                        onRefresh: () => spaces.load(institutionId: _institutionId),
                        child: historyList.isEmpty
                            ? ListView(
                                key: const PageStorageKey('org_spaces_history_empty'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                children: const [
                                  SizedBox(height: 40),
                                  EmptyState(
                                    icon: Icons.history_rounded,
                                    title: 'No space history',
                                    message:
                                        'Ended live sessions and attendance '
                                        'statistics will appear here.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                key: const PageStorageKey('org_spaces_history_list'),
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 96),
                                itemCount: historyList.length,
                                itemBuilder: (context, index) =>
                                    _OrgSpaceCard(space: historyList[index]),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _schedule(BuildContext context, String institutionId) async {
    final hostId = context.read<AuthProvider>().user?.id;
    final verified =
        context.read<InstitutionProvider>().institution?.isVerified ?? false;
    if (hostId == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ScheduleSpaceSheet(
        institutionId: institutionId,
        hostProfileId: hostId,
        isVerified: verified,
      ),
    );
  }
}

/// A form-section label.
///
/// NOT textTheme.labelLarge: that is `onAccent`, a filled button's text colour,
/// which is white on the light theme and therefore invisible on a sheet.
TextStyle? _fieldLabel(BuildContext context) {
  final colors = Theme.of(context).extension<AppThemeColors>()!;
  return Theme.of(context)
      .textTheme
      .titleSmall
      ?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary);
}

class _OrgSpaceCard extends StatelessWidget {
  final Space space;
  const _OrgSpaceCard({required this.space});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final spaces = context.read<SpacesProvider>();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    space.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (space.isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.errorLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'LIVE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.error,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  )
                else if (space.isOver)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      space.statusLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${space.kindLabel} · ${formatDateTime(space.scheduledFor)} · '
              '${space.durationMin} min'
              '${space.requiresAdmission ? ' · waiting room' : ''}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            if (space.description != null &&
                space.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                space.description!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.textSecondary, height: 1.4),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (space.isLive) ...[
                  FilledButton.icon(
                    onPressed: () => context
                        .push('${AppConstants.routeCall}/space/${space.id}'),
                    icon: const Icon(Icons.videocam_rounded, size: 16),
                    label: const Text('Join room'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.error,
                      side:
                          BorderSide(color: colors.error.withValues(alpha: 0.5)),
                      // The theme's outlined button is full-width, which a Row
                      // lays out unbounded — that throws and the whole card
                      // renders as nothing.
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed:
                        spaces.busy ? null : () => _confirmEnd(context, space),
                    icon: const Icon(Icons.call_end_rounded, size: 16),
                    label: const Text('End session'),
                  ),
                ] else if (space.isScheduled) ...[
                  FilledButton.icon(
                    onPressed: spaces.busy
                        ? null
                        : () async {
                            final ok = await spaces.goLive(space);
                            if (ok && context.mounted) {
                              context.push(
                                  '${AppConstants.routeCall}/space/${space.id}');
                            }
                          },
                    icon: const Icon(Icons.podcasts_rounded, size: 16),
                    label: const Text('Go live'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: spaces.busy
                        ? null
                        : () => _confirmCancel(context, space),
                    child: const Text('Cancel'),
                  ),
                ],
              ],
            ),
            if (space.isOver) ...[
              _Attendance(spaceId: space.id),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.error,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: spaces.busy
                        ? null
                        : () => _confirmDelete(context, space),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, Space space) async {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End live session?'),
        content: const Text(
          'This will end the live session for all participants and move it to your Spaces History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep live'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final spaces = context.read<SpacesProvider>();
      final ok = await spaces.end(space);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Session ended and moved to History.'
                  : 'Failed to end session.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmCancel(BuildContext context, Space space) async {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel scheduled space?'),
        content: const Text(
          'Are you sure you want to cancel this scheduled space? Prospective students will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final spaces = context.read<SpacesProvider>();
      final ok = await spaces.cancel(space);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'Session cancelled.' : 'Failed to cancel session.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Space space) async {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete space?'),
        content: Text(
          'Are you sure you want to delete "${space.title}"? This will permanently remove it and its attendance history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final spaces = context.read<SpacesProvider>();
      final ok = await spaces.deleteSpace(space);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'Space deleted from history.' : 'Failed to delete space.',
            ),
          ),
        );
      }
    }
  }
}

/// How the session actually went.
///
/// Counted from `space_roster` rather than stored on the row: it is already
/// readable by this institution, and a denormalised count is one more thing
/// that can be wrong. The last figure is the one that matters — how many
/// listeners went on to share their passport.
class _Attendance extends StatefulWidget {
  final String spaceId;
  const _Attendance({required this.spaceId});

  @override
  State<_Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<_Attendance> {
  List<SpaceRosterEntry>? _roster;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await context
          .read<SpacesProvider>()
          .rosterFor(widget.spaceId);
      if (mounted) setState(() => _roster = rows);
    } catch (_) {
      if (mounted) setState(() => _roster = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final attended =
        roster?.where((r) => !r.isStaff && r.joinedAt != null).length ?? 0;
    final hands = roster?.where((r) => r.handRaisedAt != null).length ?? 0;
    final shared =
        roster?.where((r) => !r.isStaff && r.isIdentified).length ?? 0;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _Stat(label: 'attended', value: attended),
            _Stat(label: 'asked to speak', value: hands),
            _Stat(label: 'shared a passport', value: shared),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: Theme.of(context).textTheme.titleMedium),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ScheduleSpaceSheet extends StatefulWidget {
  final String institutionId;
  final String hostProfileId;
  final bool isVerified;

  const _ScheduleSpaceSheet({
    required this.institutionId,
    required this.hostProfileId,
    required this.isVerified,
  });

  @override
  State<_ScheduleSpaceSheet> createState() => _ScheduleSpaceSheetState();
}

class _ScheduleSpaceSheetState extends State<_ScheduleSpaceSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _kind = 'admissions_hour';
  DateTime? _when;
  int _duration = 45;
  late bool _waitingRoom = !widget.isVerified;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  /// What is still needed, or null when the form is ready.
  String? get _missing {
    if (_title.text.trim().isEmpty) return 'Give the session a title.';
    if (_when == null) return 'Pick when it starts.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppThemeColors>()!;
    final spaces = context.watch<SpacesProvider>();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Schedule a live session',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              maxLength: 120,
              // Without this the sheet never rebuilds as the title is typed, so
              // the Schedule button below — whose enabled test reads
              // `_title.text` — stays disabled however much you write.
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Computer Science admissions hour',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            Text('What is it for', style: _fieldLabel(context)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in AppConstants.spaceKinds.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _kind == entry.key,
                    // chipTheme.labelStyle carries no colour, so an unselected
                    // chip inherits one too pale to read. Both states are set
                    // here rather than leaning on the default.
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kind == entry.key
                          ? colors.accent
                          : colors.textPrimary,
                    ),
                    onSelected: (_) => setState(() => _kind = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppConstants.spaceKindBlurbs[_kind] ?? '',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _description,
              maxLines: 3,
              maxLength: 600,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Bring your questions about entry requirements.',
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_when == null
                  ? 'Pick a date and time'
                  : formatDateTime(_when!)),
              trailing: const Icon(Icons.calendar_today_rounded, size: 18),
              onTap: _pickWhen,
            ),
            Row(
              children: [
                Text('Minutes', style: _fieldLabel(context)),
                const SizedBox(width: 16),
                Expanded(
                  child: Slider(
                    value: _duration.toDouble(),
                    min: 15,
                    max: 180,
                    divisions: 11,
                    label: '$_duration',
                    onChanged: (v) => setState(() => _duration = v.round()),
                  ),
                ),
                Text('$_duration'),
              ],
            ),
            // Deliberately NOT a disabled SwitchListTile. Disabling one greys
            // out its title and subtitle together, which made the sentence
            // explaining why it is locked the hardest thing on the screen to
            // read. The switch alone is locked; the words stay legible.
            //
            // Forced on until the institution is verified by a trigger in the
            // schema, so this is honesty about a rule rather than the rule.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Let people in one at a time',
                          style: _fieldLabel(context)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (!widget.isVerified) ...[
                            Icon(Icons.lock_outline_rounded,
                                size: 13, color: colors.textSecondary),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              widget.isVerified
                                  ? 'Students wait until you admit them.'
                                  : 'Required until your institution is verified.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _waitingRoom,
                  onChanged: widget.isVerified
                      ? (v) => setState(() => _waitingRoom = v)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Students join to listen without sharing who they are. If one '
              'raises their hand, unmutes or writes in the chat, they are asked '
              'to share their Education Passport first — and then you see their '
              'name.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textLight, height: 1.45),
            ),
            const SizedBox(height: 20),
            if (_missing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _missing!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: spaces.busy || _missing != null
                    ? null
                    : () async {
                        final ok = await spaces.schedule(
                          institutionId: widget.institutionId,
                          hostProfileId: widget.hostProfileId,
                          title: _title.text,
                          description: _description.text.isEmpty
                              ? null
                              : _description.text,
                          kind: _kind,
                          scheduledFor: _when!,
                          durationMin: _duration,
                          requiresAdmission: _waitingRoom,
                        );
                        if (ok && context.mounted) Navigator.of(context).pop();
                      },
                child: spaces.busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('Schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    setState(() {
      _when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }
}
