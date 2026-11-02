import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One row in a settings list.
///
/// A data class rather than a widget so a section can draw its own separators
/// and corner radii, which it cannot do if it is handed opaque children.
class SettingsRow {
  final IconData icon;
  final String label;

  /// A short value shown at the end of the row — "Dark", "82%", a count.
  final String? value;

  /// A control in place of the chevron. Takes precedence over [value]'s
  /// chevron, for rows that toggle rather than navigate.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// For a destructive or otherwise marked row.
  final Color? tint;

  const SettingsRow({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.tint,
  });
}

/// A titled group of settings rows.
///
/// Replaces three near-identical private copies of this — `_Group`/`_Tile` in
/// `profile_screen.dart` and again in `org_more_screen.dart`, and `_Item` in
/// `app_drawer.dart`. All three could only put a `String` at the end of a row,
/// which is exactly what stopped a control from going in one.
class SettingsSection extends StatelessWidget {
  final String? title;
  final List<SettingsRow> rows;

  const SettingsSection({super.key, this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(
              title!,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        for (var i = 0; i < rows.length; i++) ...[
          _Row(row: rows[i]),
          if (i < rows.length - 1)
            Divider(
              height: 1,
              color: colors.divider,
              // Inset to the label, so the separators line up with the text
              // rather than cutting under the glyphs.
              indent: 56,
              endIndent: 0,
            ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final SettingsRow row;

  const _Row({required this.row});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    // Instagram's settings rows carry monochrome glyphs. A column of blue
    // icons reads as a column of links.
    final tint = row.tint ?? colors.textPrimary;

    return InkWell(
      onTap: row.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(row.icon, size: 22, color: tint),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                row.label,
                style: text.bodyLarge?.copyWith(
                  color: row.tint ?? colors.textPrimary,
                ),
              ),
            ),
            if (row.trailing != null)
              row.trailing!
            else ...[
              if (row.value != null)
                Text(
                  row.value!,
                  style: text.bodyMedium?.copyWith(color: colors.textLight),
                ),
              if (row.onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: colors.textLight),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
