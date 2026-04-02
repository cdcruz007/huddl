import 'package:flutter/material.dart';

class HuddlColors {
  // Primary
  static const Color primary = Color(0xFFFF975C);
  static const Color primaryLight = Color(0xFFFFAD7F);
  static const Color primaryDark = Color(0xFFFF8A47);

  // Secondary / Accent
  static const Color teal = Color(0xFF199A85);
  static const Color blue = Color(0xFF3580F0);
  static const Color lightBlue = Color(0xFF5B9DFF);
  static const Color paleBlue = Color(0xFF82B4FF);
  static const Color blueBackground = Color(0xFFEDF4FF);

  // Category accent palette (non-status, for tags / badges / avatars)
  static const Color accentAmber = Color(0xFFF3C54F);       // yellow family – warm gold (style-guide primary yellow)
  static const Color accentCoral = Color(0xFFF69F72);       // orange-pink family
  static const Color accentSky   = Color(0xFF78B0FF);       // blue gradient end
  static const Color accentSlate = Color(0xFF7C7C7C);       // neutral secondary text

  // Yellow / Amber family (from style guide — #FFF3C54F)
  // Use these tokens consistently for: Free badges, date cards, food/nutrition tags,
  // marketplace "Preloved" items, milestone celebrations, Walk/Social meetup categories.
  static const Color yellowDark = Color(0xFFD4A017);        // darkest yellow — strong icon tints, active text
  static const Color yellow = Color(0xFFF3C54F);            // primary yellow — badges, toggles, active dots (= accentAmber)
  static const Color yellowMedium = Color(0xFFF7D97C);      // medium yellow — softer badges, avatar accents
  static const Color yellowSoft = Color(0xFFFBE8A6);        // light yellow — card backgrounds, icon bgs
  static const Color yellowBackground = Color(0xFFFFF7C9);  // yellow bg — highlight backgrounds, banners

  // Yellow gradient
  static const LinearGradient yellowGradient = LinearGradient(
    colors: [Color(0xFFF3C54F), Color(0xFFF7D97C)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Text
  static const Color textDark = Color(0xFF43464D);
  static const Color textPrimary = Color(0xFF262A35);
  static const Color textSecondary = Color(0xFF6C6C6C);
  static const Color textHint = Color(0xFF949494);
  static const Color textLight = Color(0xFFB0B0B0);

  // Backgrounds
  static const Color background = Color(0xFFF6F6F6);
  static const Color white = Color(0xFFFFFFFF);
  static const Color peachLight = Color(0xFFFFF3ED);
  static const Color peachVeryLight = Color(0xFFFFF8F0);
  static const Color yellowLight = Color(0xFFFFF7C9);
  static const Color surfaceLight = Color(0xFFFAFAFA);

  // Status
  static const Color error = Color(0xFFFF7575);
  static const Color errorLight = Color(0xFFFFE9E9);
  static const Color success = Color(0xFF199A85);

  // Grayscale
  static const Color gray100 = Color(0xFFF6F6F6);
  static const Color gray200 = Color(0xFFE8E8E8);
  static const Color gray300 = Color(0xFFD4D4D4);
  static const Color gray400 = Color(0xFFB0B0B0);
  static const Color gray500 = Color(0xFF949494);
  static const Color gray600 = Color(0xFF6C6C6C);
  static const Color gray700 = Color(0xFF4A4A4A);
  static const Color gray800 = Color(0xFF2D2D2D);
  static const Color gray900 = Color(0xFF1A1A1A);

  // Divider
  static const Color divider = Color(0xFFE8E8E8);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFFF975C), Color(0xFFFFAD7F)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF0E6), Color(0xFFFFF8F0), Color(0xFFFFFFFF)],
  );
}
