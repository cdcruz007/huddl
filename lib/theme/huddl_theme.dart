import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'huddl_colors.dart';

class HuddlTheme {
  // ========================================================================
  // LIGHT THEME
  // ========================================================================
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: HuddlColors.white,
      colorScheme: const ColorScheme.light(
        primary: HuddlColors.primary,
        secondary: HuddlColors.blue,
        surface: HuddlColors.white,
        error: HuddlColors.error,
        onPrimary: HuddlColors.white,
        onSecondary: HuddlColors.white,
        onSurface: HuddlColors.textDark,
        onError: HuddlColors.white,
      ),
      textTheme: _lightTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: HuddlColors.textDark),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: HuddlColors.textDark,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: HuddlColors.white,
        selectedItemColor: HuddlColors.primary,
        unselectedItemColor: HuddlColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showUnselectedLabels: true,
      ),
      inputDecorationTheme: _inputTheme(
        fillColor: HuddlColors.background,
        hintColor: HuddlColors.textHint,
        labelColor: HuddlColors.textSecondary,
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      cardTheme: CardThemeData(
        color: HuddlColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: _chipTheme(bgColor: HuddlColors.background),
      dividerTheme: const DividerThemeData(
        color: HuddlColors.divider,
        thickness: 1,
        space: 0,
      ),
      tabBarTheme: _tabBarTheme(),
    );
  }

  // ========================================================================
  // DARK THEME  (#121212 base per audit recommendation)
  // ========================================================================
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HuddlColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: HuddlColors.primary,
        secondary: HuddlColors.blue,
        surface: HuddlColors.darkSurface,
        error: HuddlColors.errorSoft,
        onPrimary: HuddlColors.white,
        onSecondary: HuddlColors.white,
        onSurface: HuddlColors.darkTextPrimary,
        onError: HuddlColors.white,
      ),
      textTheme: _darkTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: HuddlColors.darkSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: HuddlColors.darkTextPrimary),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: HuddlColors.darkTextPrimary,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: HuddlColors.darkSurface,
        selectedItemColor: HuddlColors.primary,
        unselectedItemColor: HuddlColors.darkTextTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
      ),
      inputDecorationTheme: _inputTheme(
        fillColor: HuddlColors.darkInputBg,
        hintColor: HuddlColors.darkTextTertiary,
        labelColor: HuddlColors.darkTextSecondary,
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      cardTheme: CardThemeData(
        color: HuddlColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HuddlColors.darkDivider, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: _chipTheme(bgColor: HuddlColors.darkSurfaceVariant),
      dividerTheme: const DividerThemeData(
        color: HuddlColors.darkDivider,
        thickness: 1,
        space: 0,
      ),
      tabBarTheme: _tabBarTheme(),
    );
  }

  // ========================================================================
  // Shared helpers (DRY)
  // ========================================================================

  static TextTheme _lightTextTheme() => GoogleFonts.poppinsTextTheme().copyWith(
    headlineLarge:  GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w600, color: HuddlColors.textDark, height: 1.3),
    headlineMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600, color: HuddlColors.textDark, height: 1.3),
    headlineSmall:  GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: HuddlColors.textDark, height: 1.3),
    titleLarge:     GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500, color: HuddlColors.textPrimary, height: 1.4),
    titleMedium:    GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark, height: 1.4),
    titleSmall:     GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.4),
    bodyLarge:      GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: HuddlColors.textDark, height: 1.5),
    bodyMedium:     GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: HuddlColors.textSecondary, height: 1.5),
    bodySmall:      GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: HuddlColors.textTertiary, height: 1.4),
    labelLarge:     GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: HuddlColors.white, height: 1.4),
    labelMedium:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.4),
    labelSmall:     GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w400, color: HuddlColors.textTertiary, height: 1.4),
  );

  static TextTheme _darkTextTheme() => GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
    headlineLarge:  GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w600, color: HuddlColors.darkTextPrimary, height: 1.3),
    headlineMedium: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600, color: HuddlColors.darkTextPrimary, height: 1.3),
    headlineSmall:  GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: HuddlColors.darkTextPrimary, height: 1.3),
    titleLarge:     GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500, color: HuddlColors.darkTextPrimary, height: 1.4),
    titleMedium:    GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.darkTextPrimary, height: 1.4),
    titleSmall:     GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.darkTextPrimary, height: 1.4),
    bodyLarge:      GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w400, color: HuddlColors.darkTextPrimary, height: 1.5),
    bodyMedium:     GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: HuddlColors.darkTextSecondary, height: 1.5),
    bodySmall:      GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: HuddlColors.darkTextTertiary, height: 1.4),
    labelLarge:     GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: HuddlColors.white, height: 1.4),
    labelMedium:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.darkTextPrimary, height: 1.4),
    labelSmall:     GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w400, color: HuddlColors.darkTextTertiary, height: 1.4),
  );

  static InputDecorationTheme _inputTheme({
    required Color fillColor,
    required Color hintColor,
    required Color labelColor,
  }) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: HuddlColors.error, width: 1)),
      hintStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: hintColor),
      labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400, color: labelColor),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ChipThemeData _chipTheme({required Color bgColor}) {
    return ChipThemeData(
      backgroundColor: bgColor,
      selectedColor: HuddlColors.primary,
      labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }

  static TabBarThemeData _tabBarTheme() {
    return TabBarThemeData(
      labelColor: HuddlColors.primary,
      unselectedLabelColor: HuddlColors.textHint,
      labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400),
      indicatorColor: HuddlColors.primary,
      indicatorSize: TabBarIndicatorSize.label,
    );
  }
}
