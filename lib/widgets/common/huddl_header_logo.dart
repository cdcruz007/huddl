import 'package:flutter/material.dart';

/// Huddl header logo — shows the full logo PNG (H icon + "huddl" wordmark),
/// exactly matching the splash screen. Height is configurable; width scales
/// proportionally via BoxFit.contain.
///
/// In dark mode the logo is brightened so the grey wordmark meets WCAG AA
/// contrast against the dark surface.
class HuddlHeaderLogo extends StatelessWidget {
  final double height;

  const HuddlHeaderLogo({
    super.key,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: height,
      fit: BoxFit.contain,
    );

    if (!isDark) return logo;

    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        2.0, 0, 0, 0, 60,
        0, 2.0, 0, 0, 60,
        0, 0, 2.0, 0, 60,
        0, 0, 0, 1.0, 0,
      ]),
      child: logo,
    );
  }
}
