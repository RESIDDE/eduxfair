import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/theme/app_colors.dart';
import '../call_provider.dart';

/// One participant.
///
/// A call screen is the one place in this app that is dark whatever the system
/// theme says: video is the content, and a light chrome around it both washes
/// the picture out and glows in a dark room. So the colours here are literal
/// rather than from [AppThemeColors].
class ParticipantTile extends StatelessWidget {
  final CallPerson person;
  final bool screen;
  final bool compact;
  final VoidCallback? onPin;

  const ParticipantTile({
    super.key,
    required this.person,
    this.screen = false,
    this.compact = false,
    this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    final track = screen ? person.screenTrack : person.videoTrack;

    return GestureDetector(
      onTap: onPin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF16181C),
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          border: Border.all(
            color: person.isSpeaking ? Colors.white : const Color(0xFF2F3336),
            width: person.isSpeaking ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track != null)
                VideoTrackRenderer(
                  track,
                  // Contain for a shared screen — cropping someone's slides is
                  // worse than letterboxing them. The default mirrorMode is
                  // `auto`, which already flips a local camera and leaves a
                  // screen share alone, so a self-view reads the right way
                  // round without this widget knowing whose it is.
                  fit: screen ? VideoViewFit.contain : VideoViewFit.cover,
                )
              else
                _Initials(name: person.name, compact: compact),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            person.isLocal ? '${person.name} (you)' : person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 11 : 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (person.handRaised)
                          const Icon(Icons.back_hand_rounded,
                              size: 14, color: Color(0xFFFBBF24)),
                        if (!person.micOn)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.mic_off_rounded,
                                size: 14, color: Colors.white70),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // isModerator, not isStaff: an appointed moderator wears the
              // badge too, so the room can see who to ask.
              if (person.isModerator && !compact)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _Pill(label: person.role.toUpperCase()),
                ),
              if (screen)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.screen_share_rounded,
                      size: 16, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final bool compact;
  const _Initials({required this.name, required this.compact});

  @override
  Widget build(BuildContext context) {
    final cleaned = name.replaceAll('@', '').trim();
    final letter = cleaned.isEmpty ? '?' : cleaned[0].toUpperCase();
    return ColoredBox(
      color: const Color(0xFF202327),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white70,
            fontSize: compact ? 20 : 34,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
}
