import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'call_provider.dart';
import 'widgets/call_chat_sheet.dart';
import 'widgets/call_controls_bar.dart';
import 'widgets/device_picker_sheet.dart';
import 'widgets/identify_consent_sheet.dart';
import 'widgets/participant_tile.dart';
import 'widgets/participants_sheet.dart';
import 'widgets/reactions_overlay.dart';

/// The room. One screen for students and staff; the role flips the controls.
///
/// This is the one screen that unlocks landscape and keeps the display awake —
/// a video grid in a single column wastes half the glass, and a call screen
/// that lets the phone sleep is a bug. Both are restored on the way out, so the
/// app-wide portrait lock in main.dart stays the default everywhere else.
///
/// Note for anyone testing this: video publishing does NOT work on the iOS
/// simulator. A black self-view there is the simulator, not a bug.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const _tileCap = 6;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final call = context.read<CallProvider>();
      await call.requestPermissions();
      await call.connect();
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _consent(CallProvider call) async {
    if (!call.isSpace) return;
    await showIdentifyConsent(
      context,
      institution: call.institutionName,
      onConfirm: call.identifyAndUpgrade,
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();

    return PopScope(
      // Leaving is a write — it stamps `left_at` — so the back gesture goes
      // through leave() rather than tearing the route down under it.
      canPop: call.phase == CallPhase.ended || call.phase == CallPhase.failed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) call.leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: switch (call.phase) {
            CallPhase.preflight ||
            CallPhase.connecting =>
              _Centred(child: _Busy(label: 'Joining the room')),
            CallPhase.waiting => const _Centred(
                child: _Message(
                  icon: Icons.hourglass_top_rounded,
                  title: 'Waiting for the host to let you in',
                  body: 'You will join automatically as soon as they do.',
                ),
              ),
            CallPhase.closed => _Centred(
                child: _Message(
                  icon: Icons.schedule_rounded,
                  // `opens_at` in the past means the window closed behind them,
                  // not that it has yet to open. Telling someone to wait for a
                  // session that finished an hour ago is the worse of the two.
                  title: call.opensInFuture
                      ? 'This room is not open yet'
                      : 'This room has closed',
                  body: call.opensInFuture
                      ? 'It opens ten minutes before the start.'
                      : 'The session is over. Ask the host if it is running again.',
                  actionLabel: 'Check again',
                  onAction: call.connect,
                ),
              ),
            CallPhase.failed => _Centred(
                child: _Message(
                  icon: Icons.wifi_off_rounded,
                  title: 'This room could not be opened',
                  body: call.error ?? 'Something went wrong.',
                  actionLabel: 'Try again',
                  onAction: call.connect,
                ),
              ),
            CallPhase.ended => _Centred(
                child: _Message(
                  icon: Icons.call_end_rounded,
                  title: 'You have left the room',
                  actionLabel: 'Done',
                  onAction: () => Navigator.of(context).maybePop(),
                ),
              ),
            CallPhase.live => _LiveView(
                call: call,
                tileCap: _tileCap,
                onConsent: () => _consent(call),
              ),
          },
        ),
      ),
    );
  }
}

class _LiveView extends StatelessWidget {
  final CallProvider call;
  final int tileCap;
  final VoidCallback onConsent;

  const _LiveView({
    required this.call,
    required this.tileCap,
    required this.onConsent,
  });

  @override
  Widget build(BuildContext context) {
    // People are already ranked by CallPerson.score, so the cap drops the
    // least interesting tiles rather than an arbitrary six.
    final visible = call.people.take(tileCap).toList();
    final overflow = call.people.length - visible.length;

    final sharer = call.people.where((p) => p.screenTrack != null).firstOrNull;
    final pinnedPerson = sharer ??
        (call.pinned == null
            ? null
            : visible.where((p) => p.identity == call.pinned).firstOrNull);

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Column(
      children: [
        _Header(call: call),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    if (pinnedPerson != null)
                      Expanded(
                        flex: 3,
                        child: ParticipantTile(
                          person: pinnedPerson,
                          screen: pinnedPerson.screenTrack != null,
                          onPin: sharer != null ? null : () => call.pin(null),
                        ),
                      ),
                    if (pinnedPerson != null) const SizedBox(height: 8),
                    Expanded(
                      flex: pinnedPerson != null ? 1 : 4,
                      child: pinnedPerson != null
                          ? ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: visible
                                  .where((p) => p != pinnedPerson)
                                  .length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (_, index) {
                                final others = visible
                                    .where((p) => p != pinnedPerson)
                                    .toList();
                                return AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: ParticipantTile(
                                    person: others[index],
                                    compact: true,
                                    onPin: () => call.pin(others[index].identity),
                                  ),
                                );
                              },
                            )
                          : GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _columns(
                                  visible.length,
                                  landscape: landscape,
                                ),
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: landscape ? 16 / 10 : 3 / 4,
                              ),
                              itemCount: visible.length,
                              itemBuilder: (_, index) => ParticipantTile(
                                person: visible[index],
                                onPin: () => call.pin(visible[index].identity),
                              ),
                            ),
                    ),
                    if (overflow > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'and $overflow more listening',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ReactionsOverlay(reactions: call.reactions),
              if (call.notices.isNotEmpty)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        for (final notice in call.notices)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              notice,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!call.canPublish && call.isSpace)
          _ListeningBanner(call: call, onConsent: onConsent),
        CallControlsBar(
          call: call,
          onNeedsConsent: onConsent,
          onShowPeople: () => showParticipantsSheet(context, call),
          onShowChat: () =>
              showCallChatSheet(context, call, onNeedsConsent: onConsent),
          onShowDevices: () => showDevicePickerSheet(context, call),
        ),
      ],
    );
  }

  static int _columns(int count, {required bool landscape}) {
    if (count <= 1) return 1;
    if (landscape) return count <= 2 ? 2 : 3;
    return count <= 2 ? 1 : 2;
  }
}

class _Header extends StatelessWidget {
  final CallProvider call;
  const _Header({required this.call});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: call.leave,
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Leave',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.grant?.title ?? 'Live room',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${call.institutionName} · ${call.people.length} here',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // isStaff, not canModerate: space_set_status() is institution-only,
          // so an appointed moderator pressing this would get a refusal from
          // the server rather than an ended session.
          if (call.isStaff)
            TextButton(
              onPressed: () => _confirmEnd(context, call),
              child: const Text(
                'End',
                style: TextStyle(color: Color(0xFFF87171)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, CallProvider call) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF16181C),
        title: const Text('End for everyone?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Everyone is disconnected and the session is marked as ended.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF87171),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('End'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await call.endForEveryone();
  }
}

class _ListeningBanner extends StatelessWidget {
  final CallProvider call;
  final VoidCallback onConsent;

  const _ListeningBanner({required this.call, required this.onConsent});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: const Color(0xFF16181C),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Listening as ${call.grant?.displayName ?? 'a student'}. '
                'Raise your hand to take part.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: onConsent,
              child: const Text(
                'Take part',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

class _Centred extends StatelessWidget {
  final Widget child;
  const _Centred({required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(28), child: child),
      );
}

class _Busy extends StatelessWidget {
  final String label;
  const _Busy({required this.label});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(label, style: const TextStyle(color: Colors.white54)),
        ],
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 42, color: Colors.white38),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      );
}
