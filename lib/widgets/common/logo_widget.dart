import 'package:flutter/material.dart';

/// Displays the full Huddl logo (H icon + "huddl" wordmark) from the
/// official PNG asset. Width scales proportionally from the given height.
///
/// In dark mode the logo is brightened so the grey wordmark meets WCAG AA
/// contrast against the dark surface.
class LogoWidget extends StatelessWidget {
  final double height;

  const LogoWidget({
    super.key,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Logo PNG is 593×208 px — maintain aspect ratio
    final width = height * (593 / 208);
    final logo = Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: height,
      width: width,
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
