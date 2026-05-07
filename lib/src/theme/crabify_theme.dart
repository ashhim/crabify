import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class CrabifyColors {
  static const Color goldPrimary = Color(0xFFF8B740);
  static const Color goldSecondary = Color(0xFFF29F1A);
  static const Color goldSoft = Color(0xFFFFD27A);
  static const Color background = Color(0xFF050505);
  static const Color surface = Color(0xFF0D0D0D);
  static const Color surfaceRaised = Color(0xFF151515);
  static const Color surfaceMuted = Color(0xFF222222);
  static const Color surfaceHighlight = Color(0xFF1B150E);
  static const Color surfaceHighlightStrong = Color(0xFF261A0A);
  static const Color topBar = Color(0xFF090909);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFD7D0C2);
  static const Color textMuted = Color(0xFF8E8577);
  static const Color accent = goldPrimary;
  static const Color accentSoft = goldSoft;
  static const Color accentSecondary = goldSecondary;
  static const Color border = Color(0xFF342612);
  static const Color danger = Color(0xFFFF9C6B);
  static const Color dangerSoft = Color(0xFFFFC7A8);
  static const Color heroGradientStart = Color(0xFF392409);
  static const Color heroGradientMid = Color(0xFF16110B);
  static const Color heroGradientDeep = Color(0xFF0A0907);
  static const Color likedGradientStart = Color(0xFF5A3400);
  static const Color likedGradientMid = Color(0xFF241506);
  static const Color bannerSurface = Color(0xFF1A130B);
  static const Color chipSelected = Color(0xFFF8B740);
  static const Color chipBackground = Color(0xFF17120C);
  static const Color iconSurface = Color(0xFF120F0B);
  static const Color goldGlow = Color(0x33F8B740);
  static const Color summaryLiked = Color(0xFF433013);
  static const Color summaryDownloads = Color(0xFF5A3B09);
  static const Color summaryImported = Color(0xFF6A4208);
  static const Color summaryUploads = Color(0xFF4A3311);
  static const Color summaryArtists = Color(0xFF302313);
  static const Color summaryRecent = Color(0xFF594312);
  static const Color searchTileA = Color(0xFF5A3702);
  static const Color searchTileB = Color(0xFF453006);
  static const Color searchTileC = Color(0xFF33240C);
  static const Color searchTileD = Color(0xFF6A4208);
  static const Color searchTileE = Color(0xFF2A1D08);
  static const Color searchTileF = Color(0xFF49320A);
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
        onPrimary: Colors.black,
        primaryContainer: CrabifyColors.accent,
        onPrimaryContainer: Colors.black,
        secondary: CrabifyColors.accentSecondary,
        onSecondary: Colors.black,
        secondaryContainer: CrabifyColors.surfaceHighlightStrong,
        onSecondaryContainer: CrabifyColors.accentSoft,
        surface: CrabifyColors.surface,
        onSurface: CrabifyColors.textPrimary,
        outline: CrabifyColors.border,
        surfaceTint: CrabifyColors.accentSecondary,
        error: CrabifyColors.danger,
      ),
      canvasColor: CrabifyColors.background,
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
      appBarTheme: AppBarTheme(
        backgroundColor: CrabifyColors.topBar,
        foregroundColor: CrabifyColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: baseTextTheme.titleMedium?.copyWith(
          color: CrabifyColors.textPrimary,
          fontWeight: FontWeight.w800,
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
        prefixIconColor: CrabifyColors.accentSoft,
        suffixIconColor: CrabifyColors.textMuted,
        labelStyle: baseTextTheme.bodyMedium?.copyWith(
          color: CrabifyColors.textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: CrabifyColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CrabifyColors.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: CrabifyColors.surfaceMuted,
          disabledForegroundColor: CrabifyColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CrabifyColors.accentSoft,
          disabledForegroundColor: CrabifyColors.textMuted,
          side: const BorderSide(color: CrabifyColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CrabifyColors.accentSoft,
          disabledForegroundColor: CrabifyColors.textMuted,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: CrabifyColors.textPrimary,
          disabledForegroundColor: CrabifyColors.textMuted,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CrabifyColors.chipBackground,
        disabledColor: CrabifyColors.surfaceMuted,
        selectedColor: CrabifyColors.chipSelected,
        secondarySelectedColor: CrabifyColors.chipSelected,
        checkmarkColor: Colors.black,
        side: const BorderSide(color: CrabifyColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: baseTextTheme.bodyMedium?.copyWith(
              color: CrabifyColors.textPrimary,
              fontWeight: FontWeight.w600,
            ) ??
            const TextStyle(color: Colors.white),
        secondaryLabelStyle: baseTextTheme.bodyMedium?.copyWith(
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ) ??
            const TextStyle(color: Colors.black),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        brightness: Brightness.dark,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CrabifyColors.accent,
        linearTrackColor: CrabifyColors.surfaceMuted,
        circularTrackColor: CrabifyColors.surfaceMuted,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return CrabifyColors.accent;
          }
          return CrabifyColors.surfaceRaised;
        }),
        checkColor: WidgetStateProperty.all<Color>(Colors.black),
        side: const BorderSide(color: CrabifyColors.border),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return CrabifyColors.accent;
          }
          return CrabifyColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return CrabifyColors.accent.withValues(alpha: 0.4);
          }
          return CrabifyColors.surfaceMuted;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: CrabifyColors.textPrimary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CrabifyColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: CrabifyColors.border),
      sliderTheme: SliderThemeData(
        activeTrackColor: CrabifyColors.accent,
        inactiveTrackColor: CrabifyColors.surfaceMuted,
        thumbColor: CrabifyColors.accentSoft,
        overlayColor: CrabifyColors.accent.withValues(alpha: 0.18),
        trackHeight: 3,
      ),
    );
  }
}
