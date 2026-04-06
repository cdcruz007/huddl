import 'package:flutter/material.dart';

// =============================================================================
// DESIGN-SYSTEM TOKENS — single source of truth
// =============================================================================
//
// USER PERSONAS (documented per audit recommendation #4):
//   1. "New-Parent Nadia" — First-time mum, 28-35, overwhelmed by travel
//      logistics, needs hand-holding checklists and reassurance from peers.
//   2. "Seasoned-Dad Sam" — Father of two, 32-40, confident traveller but
//      wants child-age-specific tips and community shortcuts.
//   3. "Expert-Grandparent Grace" — 55+, travels with grandchildren, wants
//      to share knowledge and earn badges — motivated by altruism.
//
// COMPETITOR ANALYSIS (documented per audit recommendation #4):
//   - Huckleberry: excellent age-aware UX but no community Q&A layer.
//   - Family Destinations Guide: strong editorial content but no
//     personalisation or interactive checklists.
//   - TripIt / PackPoint: good packing lists but not family-aware.
//   - Huddl differentiator: AI + real-parent community intelligence,
//     age-aware checklists, and gamified expert badges.
// =============================================================================

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
  static const Color yellowDark = Color(0xFFD4A017);
  static const Color yellow = Color(0xFFF3C54F);
  static const Color yellowMedium = Color(0xFFF7D97C);
  static const Color yellowSoft = Color(0xFFFBE8A6);
  static const Color yellowBackground = Color(0xFFFFF7C9);

  static const LinearGradient yellowGradient = LinearGradient(
    colors: [Color(0xFFF3C54F), Color(0xFFF7D97C)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF43464D);
  static const Color textPrimary = Color(0xFF262A35);
  static const Color textSecondary = Color(0xFF6C6C6C);
  /// WCAG-safe hint for decorative / non-essential text only (2.9:1).
  static const Color textHint = Color(0xFF949494);
  /// WCAG 4.5:1 tertiary — use for interactive hints, counts, timestamps
  /// that carry meaning (audit recommendation #2).
  static const Color textTertiary = Color(0xFF767676);      // 4.6:1 on white
  static const Color textLight = Color(0xFFB0B0B0);

  // ── Backgrounds (light mode) ────────────────────────────────────────────
  static const Color background = Color(0xFFF6F6F6);
  static const Color white = Color(0xFFFFFFFF);
  static const Color peachLight = Color(0xFFFFF3ED);
  static const Color peachVeryLight = Color(0xFFFFF8F0);
  static const Color yellowLight = Color(0xFFFFF7C9);
  static const Color surfaceLight = Color(0xFFFAFAFA);

  // ── Dark-mode tokens (audit recommendation #1 — #121212 base) ──────────
  static const Color darkBackground = Color(0xFF121212);     // Material dark base
  static const Color darkSurface = Color(0xFF1E1E1E);       // card / elevated surface
  static const Color darkSurfaceVariant = Color(0xFF2C2C2C); // input fields, secondary surfaces
  static const Color darkDivider = Color(0xFF3A3A3A);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);   // high-emphasis text on dark
  static const Color darkTextSecondary = Color(0xFFB0B0B0);  // medium-emphasis
  static const Color darkTextTertiary = Color(0xFF8A8A8A);   // low-emphasis (still 4.5:1 on #1E1E1E)
  static const Color darkInputBg = Color(0xFF2A2A2A);

  // Status
  static const Color error = Color(0xFFE53935);
  static const Color errorSoft = Color(0xFFFF7575);
  static const Color errorLight = Color(0xFFFFE9E9);
  static const Color success = Color(0xFF199A85);
  static const Color successGreen = Color(0xFF22C55E);
  static const Color successBg = Color(0xFFE6F5F3);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningDark = Color(0xFF78350F);

  // Interactive / Disabled
  static const Color disabled = Color(0xFFEEEEEE);
  static const Color disabledText = Color(0xFF9E9E9E);

  // Input fields
  static const Color inputBg = Color(0xFFF5F5F5);
  static const Color inputBorder = Color(0xFFDDDDDD);
  static const Color inputBorderLight = Color(0xFFE0E0E0);

  // Onboarding
  static const Color onboardingOrange = Color(0xFFFCA878);
  static const Color avatarBg = Color(0xFFFFF9D6);
  static const Color avatarIcon = Color(0xFFE8A87C);

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

  // AI feature gradient
  static const LinearGradient aiGradient = LinearGradient(
    colors: [Color(0xFF3580F0), Color(0xFF5B9DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color aiBlue = Color(0xFF3580F0);
  static const Color aiBlueLight = Color(0xFF5B9DFF);
}

// =============================================================================
// ADAPTIVE COLOUR HELPER — resolves light/dark tokens from BuildContext
// =============================================================================
/// Extension on [BuildContext] that returns the correct semantic color for the
/// current brightness.  Usage: `context.hc.surface`, `context.hc.textPrimary`.
///
/// This keeps all Travel screens theme-aware without touching every `const`
/// reference — screens can gradually migrate from `HuddlColors.white` to
/// `context.hc.surface` at their own pace.
extension HuddlAdaptive on BuildContext {
  _HuddlContextColors get hc => _HuddlContextColors(this);
}

class _HuddlContextColors {
  final BuildContext _ctx;
  const _HuddlContextColors(this._ctx);

  bool get _isDark => Theme.of(_ctx).brightness == Brightness.dark;

  // Surfaces
  Color get scaffold   => _isDark ? HuddlColors.darkBackground     : HuddlColors.background;
  Color get surface    => _isDark ? HuddlColors.darkSurface         : HuddlColors.white;
  Color get surfaceAlt => _isDark ? HuddlColors.darkSurfaceVariant  : HuddlColors.background;
  Color get inputBg    => _isDark ? HuddlColors.darkInputBg         : HuddlColors.inputBg;
  Color get divider    => _isDark ? HuddlColors.darkDivider         : HuddlColors.divider;

  // Text
  Color get textPrimary   => _isDark ? HuddlColors.darkTextPrimary   : HuddlColors.textDark;
  Color get textSecondary => _isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
  Color get textTertiary  => _isDark ? HuddlColors.darkTextTertiary  : HuddlColors.textTertiary;

  // Shadows (invisible in dark mode to avoid glow artefacts)
  Color get shadow => _isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.04);

  // Card border (subtle lift in dark mode)
  Border? get cardBorder => _isDark
      ? Border.all(color: HuddlColors.darkDivider, width: 0.5)
      : null;
}
