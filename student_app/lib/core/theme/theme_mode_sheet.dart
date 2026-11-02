import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_colors.dart';
import 'theme_provider.dart';

/// Light / Dark / System, as a sheet.
///
/// `useRootNavigator: true` matters here: a sheet pushed on a tab's own
/// navigator sits *inside* the shell's scroll listener, so a tall one can
/// retract the nav bar behind it.
Future<void> showThemeModeSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _ThemeModeSheet(),
    );

class _ThemeModeSheet extends StatelessWidget {
  const _ThemeModeSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final theme = context.watch<ThemeProvider>();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Text('Appearance', style: text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'System follows your phone’s own light and dark setting.',
              style: text.bodyMedium,
            ),
          ),
          // RadioGroup rather than per-tile groupValue/onChanged, which are
          // deprecated as of 3.32.
          RadioGroup<ThemeMode>(
            groupValue: theme.mode,
            onChanged: (picked) {
              if (picked != null) context.read<ThemeProvider>().set(picked);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (mode, label, icon) in const [
                  (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
                  (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                  (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                ])
                  RadioListTile<ThemeMode>(
                    value: mode,
                    activeColor: colors.accent,
                    title: Text(label, style: text.bodyLarge),
                    secondary: Icon(icon, color: colors.textPrimary, size: 22),
                    controlAffinity: ListTileControlAffinity.trailing,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
