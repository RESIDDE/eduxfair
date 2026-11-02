import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  /// One type scale, shared by both themes.
  ///
  /// Tracking and leading are **size-specific**, which is the part that was
  /// missing: a single letter-spacing value is wrong somewhere by definition.
  /// Apple's rule, from *The Details of UI Typography*, is that letters read
  /// too far apart as they grow and too tight as they shrink — so large text
  /// gets negative tracking and small text a little positive, with leading
  /// moving the other way: tight on headings, comfortable on body copy.
  ///
  /// Flutter's `letterSpacing` is in logical pixels rather than em, so each
  /// value below is the em figure multiplied out against its own size.
  static TextTheme _textTheme(AppThemeColors colors, TextTheme base) {
    TextStyle style(
      double size,
      FontWeight weight,
      Color colour, {
      required double tracking,
      required double leading,
    }) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: colour,
          letterSpacing: tracking,
          height: leading,
        );

    return GoogleFonts.interTextTheme(base).copyWith(
      // Display — tight leading, clearly negative tracking.
      displayLarge: style(40, FontWeight.w800, colors.textPrimary,
          tracking: -0.80, leading: 1.05),
      displayMedium: style(32, FontWeight.w700, colors.textPrimary,
          tracking: -0.64, leading: 1.08),
      displaySmall: style(28, FontWeight.w700, colors.textPrimary,
          tracking: -0.50, leading: 1.12),

      // Headline — still negative, leading opening up.
      headlineLarge: style(26, FontWeight.w700, colors.textPrimary,
          tracking: -0.40, leading: 1.18),
      headlineMedium: style(23, FontWeight.w800, colors.textPrimary,
          tracking: -0.30, leading: 1.22),
      // 20/w800 is X's section heading — "Today's News", a page title. The
      // weight is the whole character of it; at w600 the same words read as a
      // subheading.
      headlineSmall: style(20, FontWeight.w800, colors.textPrimary,
          tracking: -0.20, leading: 1.25),

      // Title — the hinge, where tracking crosses zero. A name is bold and
      // the same size as the text under it, which is what makes an X row read
      // as "who" then "what" rather than as a heading and a caption.
      titleLarge: style(17, FontWeight.w800, colors.textPrimary,
          tracking: -0.10, leading: 1.30),
      titleMedium: style(15, FontWeight.w700, colors.textPrimary,
          tracking: 0, leading: 1.33),
      titleSmall: style(13, FontWeight.w600, colors.textSecondary,
          tracking: 0.10, leading: 1.35),

      // Body — 15px, which is X's one reading size.
      //
      // X sets its timeline text at 20/15 = 1.333. This is 1.4, because
      // apple_design_test asserts body leading stays at or above that and the
      // difference is three quarters of a pixel per line: invisible next to
      // the readability rule it would be breaking to match exactly.
      bodyLarge: style(15, FontWeight.w400, colors.textPrimary,
          tracking: 0, leading: 1.40),
      bodyMedium: style(14, FontWeight.w400, colors.textSecondary,
          tracking: 0.05, leading: 1.45),
      bodySmall: style(13, FontWeight.w400, colors.textLight,
          tracking: 0.10, leading: 1.40),

      // Label — small and often all-caps, so positive tracking and tight
      // leading. labelLarge is a filled button's text, hence onAccent.
      labelLarge: style(15, FontWeight.w700, colors.onAccent,
          tracking: 0, leading: 1.20),
      labelMedium: style(12, FontWeight.w500, colors.textSecondary,
          tracking: 0.20, leading: 1.20),
      labelSmall: style(11, FontWeight.w500, colors.textLight,
          tracking: 0.30, leading: 1.20),
    );
  }

  // ── Light Theme ────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final colors = AppThemeColors.light;
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: Brightness.light,
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        surface: colors.background,
        onSurface: colors.textPrimary,
        error: colors.error,
      ),
      scaffoldBackgroundColor: colors.background,
      extensions: [colors],
      textTheme: _textTheme(colors, base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600, color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: colors.textPrimary, size: 22),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surfaceVariant,
          disabledForegroundColor: colors.textLight,
          // A minimum, not a fixed height: Material grows the button when
          // the label needs more room, so larger text is not clipped.
          minimumSize: const Size(double.infinity, 56),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surfaceVariant,
          disabledForegroundColor: colors.textLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accent,
          side: BorderSide(color: colors.accent, width: 1.5),
          // A minimum, not a fixed height: Material grows the button when
          // the label needs more room, so larger text is not clipped.
          minimumSize: const Size(double.infinity, 56),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: colors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: colors.textLight, fontSize: 14),
        errorStyle: GoogleFonts.inter(color: colors.error, fontSize: 12),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return colors.accent;
          return colors.textLight;
        }),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: colors.divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: colors.surface,
        contentTextStyle: GoogleFonts.inter(color: colors.textPrimary, fontSize: 14),
        elevation: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        selectedColor: colors.accent.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.accent.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.accent, size: 24);
          }
          return IconThemeData(color: colors.textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: colors.accent);
          }
          return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textSecondary);
        }),
        elevation: 8,
        surfaceTintColor: Colors.transparent,
        shadowColor: colors.border,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.accent;
          return colors.textLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.accent.withValues(alpha: 0.3);
          return colors.border;
        }),
      ),
    );
  }

  // ── Dark Theme — true black, accent inverted to white ─────────────────────
  static ThemeData get darkTheme {
    final colors = AppThemeColors.dark;
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: Brightness.dark,
        primary: colors.accent,
        onPrimary: colors.onAccent,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        surface: colors.background,
        onSurface: colors.textPrimary,
        error: colors.error,
      ),
      scaffoldBackgroundColor: colors.background, // pure black
      extensions: [colors],
      textTheme: _textTheme(colors, base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background, // true black app bar
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600, color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: colors.textPrimary, size: 22),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surfaceVariant,
          disabledForegroundColor: colors.textLight,
          // A minimum, not a fixed height: Material grows the button when
          // the label needs more room, so larger text is not clipped.
          minimumSize: const Size(double.infinity, 56),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surfaceVariant,
          disabledForegroundColor: colors.textLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.accent,
          side: BorderSide(color: colors.accent.withValues(alpha: 0.6), width: 1.5),
          // A minimum, not a fixed height: Material grows the button when
          // the label needs more room, so larger text is not clipped.
          minimumSize: const Size(double.infinity, 56),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: colors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: colors.textLight, fontSize: 14),
        errorStyle: GoogleFonts.inter(color: colors.error, fontSize: 12),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return colors.accent;
          return colors.textLight;
        }),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: colors.divider, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: colors.surface,
        contentTextStyle: GoogleFonts.inter(color: colors.textPrimary, fontSize: 14),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        selectedColor: colors.accent.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.background,
        indicatorColor: Colors.transparent, // no fill indicator
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.accent, size: 24);
          }
          return IconThemeData(color: colors.textLight, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: colors.accent);
          }
          return GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: colors.textLight);
        }),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.accent;
          return colors.textLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.accent.withValues(alpha: 0.3);
          return colors.border;
        }),
      ),
    );
  }
}
