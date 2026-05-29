// =============================================================================
// HUDDL TYPE RAMP — 4 levels, used everywhere, no exceptions
//
// display  → screen titles, greeting headers, onboarding hero text
// heading  → section headers, card titles, modal titles
// body     → all paragraph text, descriptions, message content
// caption  → timestamps, counts, labels, badges, secondary metadata
//
// RULE 1: Never define fontSize inline anywhere in lib/screens/ or lib/widgets/
// RULE 2: Never use a font size not in this file (26, 17, 14, 12 only)
// RULE 3: Color goes on the text style call, never on the Text widget directly
// RULE 4: FontWeight only varies at body level (w400 default, w600 for emphasis)
//         Display is always w700. Heading is always w600. Caption is always w400.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';

// ignore_for_file: prefer_const_constructors

class HuddlText {
  HuddlText._();

  // ── DISPLAY — 26px / 700 / -0.5 tracking ─────────────────────────────────
  // Use for: screen greetings ("Good morning, Conrad"), onboarding heroes,
  // large numeric stats. Maximum one per screen.
  static TextStyle display({Color? color}) => GoogleFonts.poppins(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
        color: color ?? HuddlColors.nearBlack,
      );

  // ── HEADING — 17px / 600 / -0.2 tracking ─────────────────────────────────
  // Use for: section headers ("Your groups", "Meetups near you"),
  // card titles, bottom sheet titles, modal headers, list item names.
  static TextStyle heading({Color? color}) => GoogleFonts.poppins(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
        color: color ?? HuddlColors.nearBlack,
      );

  // ── BODY — 14px / 400 / 0 tracking ───────────────────────────────────────
  // Use for: all descriptive text, message content, card subtitles,
  // form helper text, notification body. Default text weight.
  // Updated 16px (was 14) per Figma styleguide — better legibility.
  static TextStyle body({Color? color, FontWeight? weight}) => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: weight ?? FontWeight.w400,
        height: 1.55,
        color: color ?? HuddlColors.textSecondary,
      );

  // ── CAPTION — 12px / 400 / 0.1 tracking ──────────────────────────────────
  // Use for: timestamps, member counts, distance labels, badge text,
  // tab labels, "See all" links, form character counts.
  // Updated 13px (was 12) per Figma styleguide — prevents sub-pixel artifacts.
  static TextStyle caption({Color? color, FontWeight? weight}) => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: weight ?? FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.4,
        color: color ?? HuddlColors.textTertiary,
      );

  // ── LABEL — 12px / 600 / 0.5 tracking — UPPERCASE only ───────────────────
  // Use for: category tags ("HEALTH & WELLNESS"), section dividers,
  // status chips, nav labels. Always uppercase at call site.
  static TextStyle label({Color? color}) => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.3,
        color: color ?? HuddlColors.textTertiary,
      );
}

// =============================================================================
// AppTextStyles — thin alias layer that delegates to HuddlText.
// Kept for backward compatibility with any remaining call sites.
// All new code should use HuddlText directly.
// =============================================================================
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get h1 => HuddlText.display();
  static TextStyle get h2 => HuddlText.heading();

  /// 16px / w400 / nearBlack — primary body copy on light backgrounds.
  static TextStyle get body1 => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: HuddlColors.nearBlack,
      );

  /// 16px / w400 / textSecondary — secondary body copy.
  static TextStyle get body2 => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        color: HuddlColors.textSecondary,
      );

  static TextStyle get button => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      );

  /// 13px / w400 / textTertiary — caption / metadata text.
  static TextStyle get caption => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.4,
        color: HuddlColors.textTertiary,
      );

  static TextStyle get inputLabel =>
      HuddlText.body(color: HuddlColors.textSecondary, weight: FontWeight.w500);
  static TextStyle get inputHint => HuddlText.body(color: HuddlColors.textHint);
}
