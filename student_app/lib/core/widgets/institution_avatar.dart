import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// An institution logo, falling back to initials.
///
/// Many listings will have no logo for a long while — institutions upload one
/// when they get round to it — so the fallback has to look deliberate rather
/// than broken.
///
/// Circular, like [UserAvatar]. This used to be a rounded square to set an
/// institution apart from a person, but the post card draws every author with
/// it regardless of kind, so the distinction only ever showed up as two
/// different avatar shapes in one feed.
class InstitutionAvatar extends StatelessWidget {
  final String? logoUrl;
  final String initials;
  final double size;
  final VoidCallback? onEdit;
  final bool isBusy;

  const InstitutionAvatar({
    super.key,
    this.logoUrl,
    required this.initials,
    this.size = 48,
    this.onEdit,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = size / 2;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.border),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );

    final url = logoUrl;
    Widget avatarContent;
    if (url == null || url.isEmpty) {
      avatarContent = fallback;
    } else {
      avatarContent = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        ),
      );
    }

    if (onEdit == null && !isBusy) {
      return avatarContent;
    }

    final badgeSize = (size * 0.36).clamp(22.0, 32.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(radius),
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: isBusy ? null : onEdit,
                child: avatarContent,
              ),
            ),
          ),
          if (isBusy)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(radius),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: size * 0.35,
                  height: size * 0.35,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ),
          if (onEdit != null && !isBusy)
            Positioned(
              right: -2,
              bottom: -2,
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.photo_camera_rounded,
                    size: badgeSize * 0.55,
                    color: colors.onAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
