import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A student or user avatar, circular with fallback to initials.
///
/// Supports interactive editing with a camera overlay badge when [onEdit] is supplied,
/// and an animated loading spinner overlay during uploads when [isBusy] is true.
class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;
  final VoidCallback? onEdit;
  final bool isBusy;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.initials,
    this.size = 48,
    this.onEdit,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: colors.accentGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: text.titleMedium?.copyWith(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          color: colors.onAccent,
        ),
      ),
    );

    final url = avatarUrl;
    Widget avatarContent;
    if (url == null || url.trim().isEmpty) {
      avatarContent = fallback;
    } else {
      avatarContent = ClipOval(
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
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isBusy ? null : onEdit,
                child: avatarContent,
              ),
            ),
          ),
          if (isBusy)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
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
