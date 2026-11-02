import 'package:flutter/material.dart';

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color primary;
  final Color accent;

  /// What sits *on* an [accent] surface — text, icons, a spinner inside a
  /// filled button. Kept as its own token so nothing hardcodes white over it.
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

  /// The colour a floating surface casts.
  ///
  /// Every shadow in this app used to be a literal `Colors.black` at some
  /// alpha, which is the whole design on a white canvas and completely
  /// invisible on a black one. The glass nav bar floats over *content* rather
  /// than over the canvas, so it needs a shadow in both themes — a heavier one
  /// in dark, where it has to read against a bright photo.
  final Color shadow;

  final LinearGradient primaryGradient;
  final LinearGradient accentGradient;
  final LinearGradient heroGradient;

  /// Instagram's five-stop brand ramp.
  ///
  /// Identical in both themes, because it is an **accent** and never a
  /// surface: it appears on the active tab glyph, unread badges, avatar rings
  /// and the sign-in hero, and nowhere that text has to sit on top of it.
  /// Several of its stops fail contrast against both canvases, which is
  /// exactly why it is not allowed to become a background.
  final LinearGradient brandGradient;

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
    required this.shadow,
    required this.primaryGradient,
    required this.accentGradient,
    required this.heroGradient,
    required this.brandGradient,
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
    Color? shadow,
    LinearGradient? primaryGradient,
    LinearGradient? accentGradient,
    LinearGradient? heroGradient,
    LinearGradient? brandGradient,
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
      shadow: shadow ?? this.shadow,
      primaryGradient: primaryGradient ?? this.primaryGradient,
      accentGradient: accentGradient ?? this.accentGradient,
      heroGradient: heroGradient ?? this.heroGradient,
      brandGradient: brandGradient ?? this.brandGradient,
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
      shadow: Color.lerp(shadow, other.shadow, t)!,
      primaryGradient: primaryGradient, // Not interpolating gradients for simplicity
      accentGradient: accentGradient,
      heroGradient: heroGradient,
      brandGradient: brandGradient, // identical in both themes anyway
    );
  }

  /// Instagram's brand ramp, shared by both themes.
  ///
  /// Bottom-left to top-right is the orientation the glyph mark uses: yellow
  /// in the warm corner, indigo in the cool one.
  static const _brandGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [
      Color(0xFFFEDA75), // yellow
      Color(0xFFFA7E1E), // orange
      Color(0xFFD62976), // magenta
      Color(0xFF962FBF), // purple
      Color(0xFF4F5BD5), // indigo
    ],
  );

  // Pre-defined static themes

  /// Light theme — Instagram's white canvas.
  ///
  /// Blue `#0095F6` is the action colour in both themes: a filled button, a
  /// link, a Follow. The brand gradient is deliberately *not* the action
  /// colour — it decorates, and a control whose label has to stay legible
  /// cannot sit on a five-stop ramp.
  ///
  /// `textLight` is the one place this knowingly departs from Instagram.
  /// Theirs is `#8E8E8E`, which is 2.9:1 on white and fails WCAG AA for the
  /// small text it carries here (`@handle · 2h`). `#6B6B6B` is 4.8:1 and
  /// reads as the same grey.
  static const AppThemeColors light = AppThemeColors(
    primary: Color(0xFF000000),
    accent: Color(0xFF0095F6), // Instagram blue. Every action, both themes.
    onAccent: Color(0xFFFFFFFF),
    accentLight: Color(0xFFB2DFFC),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFEFEFEF), // Instagram's field and chip fill
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF737373),
    textLight: Color(0xFF6B6B6B), // 4.8:1 — it carries '@handle · 2h'
    textOnDark: Color(0xFFFFFFFF),
    success: Color(0xFF0E9F6E), // Reserved for verified / approved
    successLight: Color(0xFFDEF7EC),
    warning: Color(0xFFF59E0B), // Scholarships, deadlines
    warningLight: Color(0xFFFEF3C7),
    error: Color(0xFFED4956), // Instagram's like-red, and its error red
    errorLight: Color(0xFFFDECEE),
    info: Color(0xFF0095F6),
    infoLight: Color(0xFFE7F3FF),
    border: Color(0xFFDBDBDB),
    divider: Color(0xFFEFEFEF), // the lighter of the two weights
    shadow: Color(0x1F000000), // 12% — what a floating capsule casts on white
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF000000), Color(0xFF262626)],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0095F6), Color(0xFF0081DB)],
    ),
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Color(0xE6000000)],
    ),
    brandGradient: _brandGradient,
  );

  /// Dark theme — Instagram's black canvas.
  ///
  /// The accent does not invert: `#0095F6` carries enough contrast on
  /// `#000000` and `#FFFFFF` alike. Surfaces step up off black (`#121212`,
  /// `#262626`) so a card still reads as a raised panel.
  static const AppThemeColors dark = AppThemeColors(
    primary: Color(0xFF121212),
    accent: Color(0xFF0095F6), // Instagram blue, the same in both themes
    onAccent: Color(0xFFFFFFFF),
    accentLight: Color(0xFF8ECDF8),
    background: Color(0xFF000000),
    surface: Color(0xFF121212),
    surfaceVariant: Color(0xFF262626),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA8A8A8),
    textLight: Color(0xFF8E8E8E), // 6.5:1 on black — fine as Instagram ships it
    textOnDark: Color(0xFFFFFFFF),
    success: Color(0xFF34D399),
    successLight: Color(0xFF0C2B22),
    warning: Color(0xFFFBBF24),
    warningLight: Color(0xFF2E2410),
    error: Color(0xFFED4956),
    errorLight: Color(0xFF2E1313),
    info: Color(0xFF0095F6),
    infoLight: Color(0xFF0B2638),
    border: Color(0xFF363636),
    divider: Color(0xFF262626),
    // Heavier than light's: in dark the capsule's job is to read against a
    // bright photo, not against the canvas it is invisible on.
    shadow: Color(0x4D000000),
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF262626), Color(0xFF121212)],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0095F6), Color(0xFF0081DB)],
    ),
    heroGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Color(0xFF000000)],
    ),
    brandGradient: _brandGradient,
  );
}

extension AppThemeColorsExtension on BuildContext {
  AppThemeColors get colors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.light;
}
