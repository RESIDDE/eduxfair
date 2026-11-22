import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/user_avatar.dart';

/// The small set of pieces every institution list is built from.
///
/// Before this, each screen drew its own chips, cards, banners and avatars, so
/// the pipeline, the inbox and the matched list each looked like a different
/// app. These follow the student side and Home: flat surfaces with a hairline,
/// colour kept for state, neutral everywhere else, and every tappable thing
/// answering on press.

/// A country code as a name: "NG" reads as noise, "Nigeria" does not.
String countryLabel(String? code) =>
    AppConstants.homeCountries[code] ??
    AppConstants.popularDestinations[code] ??
    code ??
    '';

/// A student's face once they have shared, and a padlock until then. The
/// avatar is withheld for the same reason the name is.
class StudentMark extends StatelessWidget {
  final bool isShared;
  final String? avatarUrl;
  final String initials;
  final double size;

  const StudentMark({
    super.key,
    required this.isShared,
    required this.initials,
    this.avatarUrl,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    if (isShared) {
      return UserAvatar(avatarUrl: avatarUrl, initials: initials, size: size);
    }
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.lock_outline_rounded,
          size: size * 0.42, color: colors.textSecondary),
    );
  }
}

/// A short fact about something — a grade band, a country, a count. Neutral
/// unless [tone] is given, and tone is for state only.
class OrgTag extends StatelessWidget {
  final String label;
  final Color? tone;
  final IconData? icon;

  const OrgTag(this.label, {super.key, this.tone, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = tone ?? colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone == null ? colors.surfaceVariant : fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// A group label, set like [SettingsSection]'s, with an optional count.
class OrgSectionLabel extends StatelessWidget {
  final String title;
  final int? count;
  final EdgeInsetsGeometry padding;

  const OrgSectionLabel(
    this.title, {
    super.key,
    this.count,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: colors.textSecondary);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Flexible(child: Text(title, style: style)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: style?.copyWith(color: colors.textLight)),
          ],
        ],
      ),
    );
  }
}

/// A rounded group of rows, separated by hairlines — the inset grouped list.
class OrgGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  const OrgGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, color: colors.divider, indent: 72),
          ],
        ],
      ),
    );
  }
}

/// One row in an [OrgGroup]: who, what, a few facts, and when.
class OrgRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final List<Widget> tags;
  final String? meta;
  final bool emphasised;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const OrgRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.tags = const [],
    this.meta,
    this.emphasised = false,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Pressable.surface(
      haptic: null,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: title,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight:
                                emphasised ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (meta != null) ...[
                        const SizedBox(width: 8),
                        Text(meta!,
                            style: text.labelSmall
                                ?.copyWith(color: colors.textLight)),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: emphasised
                            ? colors.textPrimary
                            : colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: tags),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: colors.textLight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A row of choices, one selected — inverted rather than tinted, like the
/// composer's.
class OrgFilterBar<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;

  const OrgFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (value, label) = options[i];
          final on = value == selected;
          return Pressable(
            onTap: () => onSelected(value),
            semanticLabel: label,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? colors.textPrimary : colors.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: on ? colors.background : colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A quiet notice above a list. [tone] colours only the leading mark.
class OrgNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color? tone;
  final EdgeInsetsGeometry margin;

  const OrgNotice({
    super.key,
    required this.icon,
    required this.message,
    this.tone,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone ?? colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(height: 1.4, color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One button shape for institution cards: filled in the text colour for the main
/// action, quiet for the rest, a ticked label once something is done.
class OrgPillButton extends StatelessWidget {
  final String label;
  final bool primary;
  final IconData? icon;
  final Color? tone;
  final VoidCallback? onTap;

  const OrgPillButton({
    super.key,
    required this.label,
    this.primary = false,
    this.icon,
    this.tone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = tone ?? (primary ? colors.background : colors.textPrimary);
    return Pressable(
      onTap: onTap,
      haptic: primary ? HapticKind.impact : HapticKind.selection,
      semanticLabel: label,
      child: Opacity(
        opacity: onTap == null && tone == null ? 0.5 : 1,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: primary ? colors.textPrimary : colors.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
