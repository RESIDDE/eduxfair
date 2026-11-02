import 'package:flutter/material.dart';

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color primary;
  final Color accent;

  /// What sits *on* an [accent] surface — text, icons, a spinner inside a
  /// filled button. The accent inverts between themes (black on light, white
  /// on dark), so nothing may hardcode white over it.
  final Color onAccent;

  /// A light foreground for use on a dark surface — the completeness bar over
  /// the passport hero. Light in *both* themes; it is not "a paler accent".
  final Color accentLight;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color textPrimary;
  final Color textSecondary;
  final Color textLight;
  final Color textOnDark;
  final Color success;
  final Color successLight;
  final Color warning;
  final Color warningLight;
  final Color error;
  final Color errorLight;
  final Color info;
  final Color infoLight;
  final Color border;
  final Color divider;
  final LinearGradient primaryGradient;
  final LinearGradient accentGradient;
  final LinearGradient heroGradient;

  const AppThemeColors({
    required this.primary,
    required this.accent,
    required this.onAccent,
    required this.accentLight,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.textPrimary,
    required this.textSecondary,
    required this.textLight,
    required this.textOnDark,
    required this.success,
    required this.successLight,
    required this.warning,
    required this.warningLight,
    required this.error,
    required this.errorLight,
    required this.info,
    required this.infoLight,
    required this.border,
    required this.divider,
    required this.primaryGradient,
    required this.accentGradient,
    required this.heroGradient,
  });

  @override
  AppThemeColors copyWith({
    Color? primary,
    Color? accent,
    Color? onAccent,
    Color? accentLight,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? textPrimary,
    Color? textSecondary,
    Color? textLight,
    Color? textOnDark,
    Color? success,
    Color? successLight,
    Color? warning,
    Color? warningLight,
    Color? error,
    Color? errorLight,
    Color? info,
    Color? infoLight,
    Color? border,
    Color? divider,
    LinearGradient? primaryGradient,
    LinearGradient? accentGradient,
    LinearGradient? heroGradient,
  }) {
    return AppThemeColors(
      primary: primary ?? this.primary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentLight: accentLight ?? this.accentLight,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textLight: textLight ?? this.textLight,
      textOnDark: textOnDark ?? this.textOnDark,
      success: success ?? this.success,
      successLight: successLight ?? this.successLight,
      warning: warning ?? this.warning,
      warningLight: warningLight ?? this.warningLight,
      error: error ?? this.error,
      errorLight: errorLight ?? this.errorLight,
      info: info ?? this.info,
      infoLight: infoLight ?? this.infoLight,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      accentGradient: accentGradient ?? this.accentGradient,
      heroGradient: heroGradient ?? this.heroGradient,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) {
      return this;
    }
    return AppThemeColors(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textLight: Color.lerp(textLight, other.textLight, t)!,
      textOnDark: Color.lerp(textOnDark, other.textOnDark, t)!,
      success: Color.lerp(success, other.success, t)!,
      successLight: Color.lerp(successLight, other.successLight, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningLight: Color.lerp(warningLight, other.warningLight, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorLight: Color.lerp(errorLight, other.errorLight, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoLight: Color.lerp(infoLight, other.infoLight, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      primaryGradient: primaryGradient, // Not interpolating gradients for simplicity
      accentGradient: accentGradient,
      heroGradient: heroGradient,
    );
  }

  // Pre-defined static themes

  /// Light theme — the default. Students spend most of their time in this app
  /// reading requirements and filling in a passport, often outdoors on a phone
  /// in strong daylight, so light is the right default here.
  ///
  /// Black is the action colour, as on X: a black button, a black tab
  /// indicator, a black compose button. Verification keeps its own green and
  /// deadlines their own amber, so a badge never competes with a button for
  /// meaning. Neutrals are true greys rather than blue-tinted, or the black
  /// reads as "very dark navy".
  static const AppThemeColors light = AppThemeColors(
    primary: Color(0xFF0F1419), // Near-black — headers, hero surfaces
    accent: Color(0xFF1D9BF0), // X's blue. Every action, both themes.
    onAccent: Color(0xFFFFFFFF),
    accentLight: Color(0xFFD6EBFB),
    background: Color(0xFFF7F9F9),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF2F4F5),
    textPrimary: Color(0xFF0F1419),
    textSecondary: Color(0xFF536471),
    textLight: Color(0xFF5F6D79), // 5.0:1 on the canvas — it carries '@handle · 2h'
    textOnDark: Color(0xFFFFFFFF),
    success: Color(0xFF0E9F6E), // Reserved for verified / approved
    successLight: Color(0xFFDEF7EC),
    warning: Color(0xFFF59E0B), // Scholarships, deadlines
    warningLight: Color(0xFFFEF3C7),
    error: Color(0xFFE02424),
    errorLight: Color(0xFFFDE8E8),
    info: Color(0xFF1D9BF0),
    infoLight: Color(0xFFE8F5FD),
    border: Color(0xFFE1E8ED),
    divider: Color(0xFFEFF3F4),
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0F1419), Color(0xFF2F3336)],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1D9BF0), Color(0xFF1A8CD8)],
    ),
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Color(0xE60F1419)],
    ),
  );

  /// Dark theme — follows the system setting. True black, X's "lights out".
  ///
  /// The accent does NOT invert. X's blue is the action colour in both
  /// themes — the compose button, a link, a selected tab — and it carries
  /// enough contrast on #000000 and on #FFFFFF alike. Only the canvas flips.
  /// Surfaces step up off black (#16181C, #202327) so a card still reads as a
  /// raised panel and document thumbnails keep their edges.
  static const AppThemeColors dark = AppThemeColors(
    primary: Color(0xFF16181C),
    accent: Color(0xFF1D9BF0), // X's blue, the same in both themes
    onAccent: Color(0xFFFFFFFF),
    accentLight: Color(0xFF8ECDF8),
    background: Color(0xFF000000),
    surface: Color(0xFF16181C),
    surfaceVariant: Color(0xFF202327),
    textPrimary: Color(0xFFE7E9EA),
    textSecondary: Color(0xFF71767B), // X's one secondary grey
    textLight: Color(0xFF71767B),
    textOnDark: Color(0xFFFFFFFF),
    success: Color(0xFF34D399),
    successLight: Color(0xFF0C2B22),
    warning: Color(0xFFFBBF24),
    warningLight: Color(0xFF2E2410),
    error: Color(0xFFF87171),
    errorLight: Color(0xFF2E1313),
    info: Color(0xFF1D9BF0),
    infoLight: Color(0xFF0B2638),
    border: Color(0xFF2F3336),
    divider: Color(0xFF2F3336), // X draws one hairline, not two weights
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF202327), Color(0xFF16181C)],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1D9BF0), Color(0xFF1A8CD8)],
    ),
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Color(0xFF000000)],
    ),
  );
}

extension AppThemeColorsExtension on BuildContext {
  AppThemeColors get colors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.light;
}
