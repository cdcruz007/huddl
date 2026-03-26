// ─── Typography & Spacing ───────────────────────────────────────────────────
import 'package:flutter/material.dart';

class AppTypography {
  // Display
  static const TextStyle display1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.2,
  );
  static const TextStyle display2 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.2,
  );
  static const TextStyle display3 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.2,
  );

  // Headings
  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.3,
  );
  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.3,
  );
  static const TextStyle h3 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.3,
  );
  static const TextStyle h4 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.3,
  );

  // Body
  static const TextStyle body1 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.47,
  );
  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
  );
  static const TextStyle body3 = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.46,
  );

  // Caption
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle tiny = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  // Labels
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle labelSm = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle labelLg = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // Button
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const TextStyle buttonSm = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 999;
}

class AppShadow {
  static const BoxShadow sm = BoxShadow(
    color: Color(0x0F000000),
    offset: Offset(0, 1),
    blurRadius: 4,
    spreadRadius: 0,
  );

  static const BoxShadow md = BoxShadow(
    color: Color(0x14000000),
    offset: Offset(0, 2),
    blurRadius: 12,
    spreadRadius: 0,
  );

  static const BoxShadow lg = BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0, 8),
    blurRadius: 32,
    spreadRadius: 0,
  );
}
