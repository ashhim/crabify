import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class CrabifyColors {
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF181818);
  static const Color surfaceRaised = Color(0xFF202020);
  static const Color surfaceMuted = Color(0xFF2A2A2A);
  static const Color topBar = Color(0xFF101010);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF7A7A7A);
  static const Color accent = Color(0xFF1DB954);
  static const Color accentSoft = Color(0xFF3DDC84);
  static const Color border = Color(0xFF2D2D2D);
  static const Color danger = Color(0xFFE85D75);
}

class CrabifyTheme {
  static ThemeData dark() {
    final baseTextTheme = GoogleFonts.montserratTextTheme(
      ThemeData.dark().textTheme,
    ).apply(
      bodyColor: CrabifyColors.textPrimary,
      displayColor: CrabifyColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: CrabifyColors.background,
      colorScheme: const ColorScheme.dark(
        primary: CrabifyColors.accent,
        secondary: CrabifyColors.accentSoft,
        surface: CrabifyColors.surface,
        error: CrabifyColors.danger,
      ),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: CrabifyColors.textSecondary,
          height: 1.45,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CrabifyColors.surfaceRaised,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: CrabifyColors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CrabifyColors.surfaceRaised,
        hintStyle: baseTextTheme.bodyMedium?.copyWith(
          color: CrabifyColors.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CrabifyColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CrabifyColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: CrabifyColors.accent),
        ),
      ),
      cardTheme: CardThemeData(
        color: CrabifyColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerTheme: const DividerThemeData(color: CrabifyColors.border),
      sliderTheme: SliderThemeData(
        activeTrackColor: CrabifyColors.textPrimary,
        inactiveTrackColor: CrabifyColors.surfaceMuted,
        thumbColor: CrabifyColors.textPrimary,
        overlayColor: CrabifyColors.textPrimary.withValues(alpha: 0.15),
        trackHeight: 3,
      ),
    );
  }
}
