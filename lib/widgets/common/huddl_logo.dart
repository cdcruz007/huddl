import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// =============================================================================
// HUDDL LOGO WIDGETS — single source of truth for all logo usage
//
// HuddlLogomark   → H-mark only SVG (official brand asset, two-tone orange).
//                   Used on onboarding data-entry screens, biometric lock,
//                   verification, login OTP.
//
// HuddlLockup     → Full brand SVG: H-mark + "huddl" text side by side
//                   (official asset, orange mark + #43464D text).
//                   Used on splash screen and login screen.
//
// HuddlAppBarLogo → Compact adaptive PNG for home screen app bar only.
//                   Switches logo_huddl.png / logo_huddl_dark.png.
//
// USAGE:
//   Onboarding data-entry  → HuddlLogomark(size: 40)
//   Splash screen          → HuddlLockup(height: 52)
//   Login screen           → HuddlLockup(height: 44)
//   Home app bar           → HuddlAppBarLogo(height: 28)
// =============================================================================

/// Official H-mark SVG — two-tone orange brand asset.
/// viewBox 107×150 → aspect ratio 0.713 (taller than wide).
/// Do NOT apply a colorFilter — the SVG has its own two-tone fills.
class HuddlLogomark extends StatelessWidget {
  /// Rendered height in logical pixels. Width is derived from aspect ratio.
  final double size;

  const HuddlLogomark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    // viewBox is 107×150 — width = height * (107/150)
    final double w = size * (107 / 150);
    return SvgPicture.asset(
      'assets/icons/huddl_logomark.svg',
      width: w,
      height: size,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => SizedBox(width: w, height: size),
    );
  }
}

/// Official full-brand SVG: H-mark + "huddl" text.
/// viewBox 559×150 → aspect ratio 3.727 (wide).
/// Scales uniformly by [height]; width is derived from aspect ratio.
/// Text is #1C1C1E nearBlack (stronger contrast, matches brand nearBlack token).
/// For dark mode on the home app bar use HuddlAppBarLogo instead.
class HuddlLockup extends StatelessWidget {
  /// Rendered height in logical pixels. Width is derived from aspect ratio.
  final double height;

  const HuddlLockup({super.key, this.height = 44});

  @override
  Widget build(BuildContext context) {
    // viewBox is 559×150 — width = height * (559/150)
    final double w = height * (559 / 150);
    return SvgPicture.asset(
      'assets/icons/huddl_lockup.svg',
      width: w,
      height: height,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => SizedBox(width: w, height: height),
    );
  }
}

/// Backwards-compatible alias — delegates to HuddlLockup.
/// Kept so existing call sites (login_screen, etc.) need no change.
class HuddlWordmarkLogo extends StatelessWidget {
  final double height;
  const HuddlWordmarkLogo({super.key, this.height = 44});

  @override
  Widget build(BuildContext context) => HuddlLockup(height: height);
}

/// Compact adaptive PNG logo for home screen app bar only.
/// Uses logo_huddl.png (light) / logo_huddl_dark.png (dark).
/// PNG variants are used here because they're pre-optimised for small sizes
/// and the dark variant has white text — not achievable with the locked SVG.
class HuddlAppBarLogo extends StatelessWidget {
  final double height;
  const HuddlAppBarLogo({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      isDark
          ? 'assets/images/logo_huddl_dark.png'
          : 'assets/images/logo_huddl.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => HuddlLockup(height: height),
    );
  }
}
