import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/huddl_colors.dart';

// =============================================================================
// HUDDL LOGO WIDGETS — single source of truth for all logo usage
//
// HuddlLogomark     → H mark only, SVG, tintable. Use on all onboarding
//                     data-entry screens, biometric lock, verification,
//                     login OTP, splash screen.
//
// HuddlWordmarkLogo → Full logo (H mark + "huddl" wordmark), PNG with
//                     dark-mode brightening. Use on login screen, About.
//
// HuddlAppBarLogo   → Compact adaptive full logo for home screen app bar.
//                     Switches between logo_huddl.png / logo_huddl_dark.png.
//
// RULE:
//   Onboarding data-entry  → HuddlLogomark(size: 40)
//   Splash screen          → HuddlLogomark(size: 110)
//   Login screen           → HuddlWordmarkLogo(height: 44)
//   Home app bar           → HuddlAppBarLogo()
//   About section          → HuddlWordmarkLogo(height: 56)
// =============================================================================

/// H mark only — SVG, tintable at runtime via [color].
/// Default colour: HuddlColors.primary orange.
/// Pass [color] to override (e.g. Colors.white for dark surfaces).
class HuddlLogomark extends StatelessWidget {
  final double size;
  final Color? color;

  const HuddlLogomark({
    super.key,
    this.size = 40,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? HuddlColors.primary;
    return SvgPicture.asset(
      'assets/icons/huddl_logomark.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      placeholderBuilder: (_) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
      ),
    );
  }
}

/// Full logo — H mark + "huddl" wordmark PNG with dark-mode brightening.
/// Use on login screen and About section (where brand reinforcement matters).
class HuddlWordmarkLogo extends StatelessWidget {
  final double height;

  const HuddlWordmarkLogo({super.key, this.height = 44});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Logo PNG is 593×208 px — preserve aspect ratio
    final double width = height * (593 / 208);
    final logo = Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: height,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => HuddlLogomark(size: height),
    );
    if (!isDark) return logo;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        2.0, 0, 0, 0, 60,
        0, 2.0, 0, 0, 60,
        0, 0, 2.0, 0, 60,
        0, 0, 0, 1.0, 0,
      ]),
      child: logo,
    );
  }
}

/// Compact adaptive logo for home screen app bar only.
/// Uses logo_huddl.png (light) / logo_huddl_dark.png (dark).
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
      errorBuilder: (_, __, ___) => HuddlLogomark(size: height),
    );
  }
}
