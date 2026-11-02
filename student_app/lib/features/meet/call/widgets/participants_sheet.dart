import 'package:flutter/material.dart';

import '../../models/space.dart';
import '../call_provider.dart';

/// Who is in the room, and the host's controls.
///
/// Rows come from `space_roster` — the view with no profile_id column — so a
/// host can admit, mute and remove a listener they still cannot name. Every
/// action is one call to `space_moderate` through the Edge Function: the app
/// never talks to LiveKit for a privileged operation.
void showParticipantsSheet(BuildContext context, CallProvider call) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => _ParticipantsList(call: call, controller: controller),
    ),
  );
}

class _ParticipantsList extends StatefulWidget {
  final CallProvider call;
  final ScrollController controller;

  const _ParticipantsList({required this.call, required this.controller});

  @override
  State<_ParticipantsList> createState() => _ParticipantsListState();
}

class _ParticipantsListState extends State<_ParticipantsList> {
  @override
  void initState() {
    super.initState();
    widget.call.addListener(_onChange);
    widget.call.loadRoster();
  }

  @override
  void dispose() {
    widget.call.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;

    // Without moderation rights there is no roster to read, so the list is the
    // people actually connected — which is all an attendee needs.
    if (!call.canModerate || !call.isSpace) {
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.all(16),
        children: [
          const _Header('In the room'),
          for (final person in call.people)
            _Row(
              label: person.isLocal ? '${person.name} (you)' : person.name,
              sub: person.role,
              handUp: person.handRaised,
              muted: !person.micOn,
            ),
        ],
      );
    }

    final waiting = call.waitingRoom;
    final hands = call.hands;
    final rest = call.roster
        .where((r) => r.isIn && r.handRaisedAt == null)
        .toList();
    final liveByPid = {
      for (final p in call.people)
        if (p.participantId != null) p.participantId!: p,
    };

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.all(16),
      children: [
        _MuteEveryone(call: call),
        if (waiting.isNotEmpty) ...[
          _Header('Waiting to be let in · ${waiting.length}'),
          for (final entry in waiting)
            _Row(
              label: entry.label,
              sub: 'Asking to join',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => call.moderate(entry.participantId, 'admitted'),
                    child: const Text('Admit'),
                  ),
                  IconButton(
                    tooltip: 'Deny',
                    onPressed: () => call.moderate(entry.participantId, 'denied'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (hands.isNotEmpty) ...[
          _Header('Hands up · ${hands.length}'),
          for (final (index, entry) in hands.indexed)
            _Row(
              label: entry.label,
              sub: '${index + 1} in the queue',
              handUp: true,
              muted: !(liveByPid[entry.participantId]?.micOn ?? false),
              trailing: _Moderation(
                call: call,
                entry: entry,
                live: liveByPid[entry.participantId],
              ),
            ),
          const SizedBox(height: 8),
        ],
        _Header('In the room · ${rest.length}'),
        for (final entry in rest)
          _Row(
            label: entry.label,
            sub: switch (entry.role) {
              'listener' => 'Listening',
              'moderator' => 'Moderator',
              final role => role,
            },
            muted: !(liveByPid[entry.participantId]?.micOn ?? false),
            trailing: entry.role == 'host'
                ? null
                : _Moderation(
                    call: call,
                    entry: entry,
                    live: liveByPid[entry.participantId],
                  ),
          ),
      ],
    );
  }
}

/// "Mute everyone", with the confirmation an irreversible room-wide action
/// earns and the camera option folded into the same sheet rather than hidden
/// behind a second button.
class _MuteEveryone extends StatelessWidget {
  final CallProvider call;
  const _MuteEveryone({required this.call});

  Future<void> _confirm(BuildContext context) async {
    final includeVideo = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF16181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Mute everyone',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Everyone except the hosts and moderators is silenced. They '
                'can turn their own microphone back on, so this quiets the '
                'room rather than locking it.',
                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(sheet).pop(false),
                icon: const Icon(Icons.mic_off_rounded, size: 18),
                label: const Text('Mute microphones'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed: () => Navigator.of(sheet).pop(true),
                icon: const Icon(Icons.videocam_off_rounded, size: 18),
                label: const Text('Mute microphones and cameras'),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheet).pop(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (includeVideo == null) return;
    await call.muteEveryone(includeVideo: includeVideo);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            // The theme's outlined button is full-width with a 56px floor,
            // which is right for a form and wrong for a sheet header.
            minimumSize: const Size(0, 42),
          ),
          onPressed: () => _confirm(context),
          icon: const Icon(Icons.volume_off_rounded, size: 18),
          label: const Text('Mute everyone'),
        ),
      );
}

class _Moderation extends StatelessWidget {
  final CallProvider call;
  final SpaceRosterEntry entry;
  final CallPerson? live;

  const _Moderation({required this.call, required this.entry, this.live});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mute is one-way on a default LiveKit deployment: remote unmute is
        // refused unless enable_remote_unmute is set. So the pair is "mute" and
        // "ask them to unmute", not a toggle that half-works.
        if (live?.micOn ?? false)
          _Action(
            icon: Icons.mic_off_rounded,
            tooltip: 'Mute',
            onTap: () => call.moderate(entry.participantId, 'muted'),
          )
        else if (live != null)
          _Action(
            icon: Icons.volume_up_rounded,
            tooltip: 'Ask them to unmute',
            onTap: () => call.askToUnmute(live!.identity),
          ),
        // Cameras, unlike microphones, have no "ask them to turn it back on":
        // a camera the participant re-enables is one they chose to, and that
        // is the whole of the interaction.
        if (live?.cameraOn ?? false)
          _Action(
            icon: Icons.videocam_off_rounded,
            tooltip: 'Turn their camera off',
            onTap: () => call.moderate(entry.participantId, 'camera_muted'),
          ),
        if (entry.handRaisedAt != null)
          _Action(
            icon: Icons.back_hand_outlined,
            tooltip: 'Lower their hand',
            onTap: () => call.moderate(entry.participantId, 'hand_lowered'),
          ),
        if (entry.role == 'listener')
          _Action(
            icon: Icons.record_voice_over_rounded,
            tooltip: entry.isIdentified
                ? 'Give them the floor'
                : 'They have not shared their passport yet',
            enabled: entry.isIdentified,
            onTap: () => call.moderate(entry.participantId, 'promoted'),
          )
        else if (entry.role != 'moderator')
          _Action(
            icon: Icons.voice_over_off_rounded,
            tooltip: 'Take back the floor',
            onTap: () => call.moderate(entry.participantId, 'demoted'),
          ),

        // Appointing is staff-only, which is why this is gated on isStaff and
        // not on canModerate: an appointed moderator runs the room, not the
        // people who appointed them.
        if (call.isStaff && entry.role != 'host' && entry.role != 'cohost')
          entry.role == 'moderator'
              ? _Action(
                  icon: Icons.shield_rounded,
                  tooltip: 'Take back their moderator role',
                  onTap: () =>
                      call.moderate(entry.participantId, 'moderator_revoked'),
                )
              : _Action(
                  icon: Icons.shield_outlined,
                  tooltip: entry.isIdentified
                      ? 'Make them a moderator'
                      : 'They have not shared their passport yet',
                  enabled: entry.isIdentified,
                  onTap: () =>
                      call.moderate(entry.participantId, 'moderator_granted'),
                ),

        _Action(
          icon: Icons.person_remove_rounded,
          tooltip: 'Remove from the session',
          danger: true,
          onTap: () => call.moderate(entry.participantId, 'removed'),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final bool enabled;

  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 18),
        color: danger ? const Color(0xFFF87171) : Colors.white70,
        disabledColor: Colors.white24,
        visualDensity: VisualDensity.compact,
      );
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String sub;
  final bool handUp;
  final bool muted;
  final Widget? trailing;

  const _Row({
    required this.label,
    required this.sub,
    this.handUp = false,
    this.muted = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF202327),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (handUp)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.back_hand_rounded,
                              size: 13, color: Color(0xFFFBBF24)),
                        ),
                      if (muted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.mic_off_rounded,
                              size: 12, color: Colors.white38),
                        ),
                    ],
                  ),
                  Text(
                    sub,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
