import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which of the two themes the app wears, and whether the phone decides.
///
/// The default is [ThemeMode.system] — a student reading requirements outdoors
/// and a student scrolling in bed want opposite things, and the phone already
/// knows which one it is. The override exists because Instagram offers one and
/// people look for it.
///
/// Persistence matches the pattern already used for `seen_onboarding`: a single
/// `SharedPreferences` key read on construction, rather than a service layer
/// for one string.
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  /// Whether the stored preference has been read yet.
  ///
  /// The first frame renders on the system theme regardless; if the stored
  /// choice differs, it arrives a frame or two later. That is a far better
  /// trade than blocking startup on a disk read, and it is why the splash
  /// screen exists.
  bool _loaded = false;
  bool get loaded => _loaded;

  ThemeProvider({bool autoLoad = true}) {
    if (autoLoad) load();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _decode(prefs.getString(_key));
    } catch (_) {
      // A preferences read that fails is not worth failing startup over; the
      // system theme is a correct answer, just not the remembered one.
      _mode = ThemeMode.system;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _encode(mode));
    } catch (_) {
      // The choice still applies to this session even if it cannot be stored.
    }
  }

  /// What the Appearance row shows as its current value.
  String get label => switch (_mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      };

  static ThemeMode _decode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}
