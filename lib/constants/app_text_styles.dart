// =============================================================================
// COMPATIBILITY LAYER: AppTextStyles
//
// Thin wrapper providing named typography tokens that delegate to
// GoogleFonts.poppins with HuddlColors.  All new code should use
// Theme.of(context).textTheme or GoogleFonts.poppins() directly.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // ── Headings ──────────────────────────────────────────────────────────────
  static TextStyle get h1 => GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.2,
        color: HuddlColors.textDark,
      );

  static TextStyle get h2 => GoogleFonts.poppins(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.3,
        color: HuddlColors.textDark,
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  static TextStyle get body1 => GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.47,
        color: HuddlColors.textDark,
      );

  static TextStyle get body2 => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.43,
        color: HuddlColors.textDark,
      );

  // ── Button ────────────────────────────────────────────────────────────────
  static TextStyle get button => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: Colors.white,
      );

  // ── Input fields ──────────────────────────────────────────────────────────
  static TextStyle get inputLabel => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: HuddlColors.textSecondary,
      );

  static TextStyle get inputHint => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: HuddlColors.textHint,
      );

  // ── Caption ───────────────────────────────────────────────────────────────
  static TextStyle get caption => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: HuddlColors.textHint,
      );
}
