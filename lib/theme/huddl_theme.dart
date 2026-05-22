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
      scaffoldBackgroundColor: HuddlColors.warmSand, // #F7F5F2 warm sand — Phase 1 spec
      colorScheme: const ColorScheme.light(
        primary: HuddlColors.primary,
        secondary: HuddlColors.teal,
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
        selectedItemColor: HuddlColors.nearBlack,   // Phase 1: near-black nav active state
        unselectedItemColor: HuddlColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showUnselectedLabels: true,
      ),
      inputDecorationTheme: _inputTheme(
        fillColor: HuddlColors.warmSand,  // warm sand fill matches scaffold
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
      datePickerTheme: _datePickerTheme(),
      timePickerTheme: _timePickerTheme(),
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
        secondary: HuddlColors.teal,
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

  // ── Date picker — Huddl brand (orange header, rounded corners) ────────────
  static DatePickerThemeData _datePickerTheme() {
    return DatePickerThemeData(
      // Dialog chrome
      backgroundColor: HuddlColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      shadowColor: Colors.black12,

      // Header band — brand orange
      headerBackgroundColor: HuddlColors.primary,
      headerForegroundColor: HuddlColors.white,
      headerHeadlineStyle: GoogleFonts.poppins(
        fontSize: 28, fontWeight: FontWeight.w700, color: HuddlColors.white),
      headerHelpStyle: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.white),

      // Day grid
      dayStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400),
      weekdayStyle: GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textTertiary),

      // Selected day — filled orange circle
      todayBorder: const BorderSide(color: HuddlColors.primary, width: 1.5),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.white;
        return HuddlColors.primary;
      }),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.white;
        if (states.contains(WidgetState.disabled)) return HuddlColors.textHint;
        return HuddlColors.textDark;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.primary;
        return Colors.transparent;
      }),

      // Year picker
      yearStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.white;
        if (states.contains(WidgetState.disabled)) return HuddlColors.textHint;
        return HuddlColors.textDark;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.primary;
        return Colors.transparent;
      }),

      // Range selection tint
      rangeSelectionBackgroundColor: HuddlColors.primary.withValues(alpha: 0.12),

      // Action buttons — text style
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: HuddlColors.textTertiary,
        textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: HuddlColors.primary,
        textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ── Time picker — Huddl brand (orange clock hand + dial) ─────────────────
  static TimePickerThemeData _timePickerTheme() {
    return TimePickerThemeData(
      // Dialog
      backgroundColor: HuddlColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,

      // Help text
      helpTextStyle: GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: HuddlColors.textTertiary, letterSpacing: 0.8),

      // Hour/minute entry boxes
      hourMinuteTextStyle: GoogleFonts.poppins(
        fontSize: 56, fontWeight: FontWeight.w300, color: HuddlColors.textDark),
      hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      hourMinuteColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return HuddlColors.primary.withValues(alpha: 0.12);
        }
        return HuddlColors.background;
      }),
      hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.primary;
        return HuddlColors.textDark;
      }),

      // AM/PM
      dayPeriodTextStyle: GoogleFonts.poppins(
        fontSize: 14, fontWeight: FontWeight.w600),
      dayPeriodBorderSide: const BorderSide(color: HuddlColors.divider),
      dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      dayPeriodColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return HuddlColors.primary.withValues(alpha: 0.12);
        }
        return Colors.transparent;
      }),
      dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.primary;
        return HuddlColors.textSecondary;
      }),

      // Dial
      dialHandColor: HuddlColors.primary,
      dialBackgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
      dialTextColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.white;
        return HuddlColors.textDark;
      }),
      entryModeIconColor: HuddlColors.primary,

      // Action buttons
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: HuddlColors.textTertiary,
        textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: HuddlColors.primary,
        textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}
