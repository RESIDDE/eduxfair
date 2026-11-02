import 'package:flutter/material.dart';

import '../../models/room_protocol.dart';
import '../call_provider.dart';

/// The control bar.
///
/// A listener's buttons are NOT hidden. Pressing one opens the consent sheet,
/// which is the only way to get a publishing token — so an empty-handed
/// listener never wonders where the microphone went.
class CallControlsBar extends StatefulWidget {
  final CallProvider call;
  final VoidCallback onNeedsConsent;
  final VoidCallback onShowPeople;
  final VoidCallback onShowChat;
  final VoidCallback onShowDevices;

  const CallControlsBar({
    super.key,
    required this.call,
    required this.onNeedsConsent,
    required this.onShowPeople,
    required this.onShowChat,
    required this.onShowDevices,
  });

  @override
  State<CallControlsBar> createState() => _CallControlsBarState();
}

class _CallControlsBarState extends State<CallControlsBar> {
  bool _showReactions = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final badge = call.canModerate
        ? call.waitingRoom.length + call.hands.length
        : 0;

    void guarded(VoidCallback action) =>
        call.canPublish ? action() : widget.onNeedsConsent();

    return Container(
      color: Colors.black,
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        8 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showReactions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final emoji in RoomProtocol.reactions)
                    IconButton(
                      onPressed: () {
                        call.react(emoji);
                        setState(() => _showReactions = false);
                      },
                      icon: Text(emoji, style: const TextStyle(fontSize: 22)),
                      tooltip: 'React $emoji',
                    ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Control(
                  icon: call.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                  label: call.micEnabled ? 'Mute' : 'Unmute',
                  highlight: call.askedToUnmute && !call.micEnabled,
                  onTap: () => guarded(() => call.setMicrophone(!call.micEnabled)),
                ),
                _Control(
                  icon: call.cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: call.cameraEnabled ? 'Camera off' : 'Camera on',
                  onTap: () => guarded(() => call.setCamera(!call.cameraEnabled)),
                ),
                if (call.cameraEnabled)
                  _Control(
                    icon: Icons.flip_camera_ios_rounded,
                    label: 'Flip camera',
                    onTap: call.flipCamera,
                  ),
                if (call.grant?.canScreenShare ?? false)
                  _Control(
                    icon: Icons.screen_share_rounded,
                    label: call.screenShareEnabled ? 'Stop sharing' : 'Share screen',
                    active: call.screenShareEnabled,
                    onTap: () => call.setScreenShare(!call.screenShareEnabled),
                  ),
                _Control(
                  icon: Icons.back_hand_rounded,
                  label: call.handRaised ? 'Lower hand' : 'Raise hand',
                  active: call.handRaised,
                  onTap: () => guarded(() => call.raiseHand(!call.handRaised)),
                ),
                _Control(
                  icon: Icons.add_reaction_outlined,
                  label: 'React',
                  onTap: () => guarded(
                      () => setState(() => _showReactions = !_showReactions)),
                ),
                _Control(
                  icon: Icons.people_alt_rounded,
                  label: 'Participants',
                  badge: badge,
                  onTap: widget.onShowPeople,
                ),
                _Control(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chat',
                  onTap: widget.onShowChat,
                ),
                _Control(
                  icon: Icons.tune_rounded,
                  label: 'Devices',
                  onTap: widget.onShowDevices,
                ),
                _Control(
                  icon: Icons.call_end_rounded,
                  label: 'Leave',
                  danger: true,
                  onTap: call.leave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
  final bool highlight;
  final int badge;

  const _Control({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.highlight = false,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFF87171)
        : active
            ? Colors.white
            : Colors.white12;
    final foreground = danger
        ? Colors.white
        : active
            ? Colors.black
            : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    border: highlight
                        ? Border.all(color: const Color(0xFFFBBF24), width: 2)
                        : null,
                  ),
                  child: Icon(icon, color: foreground, size: 22),
                ),
                if (badge > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF87171),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
