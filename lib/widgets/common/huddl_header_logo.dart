import 'package:flutter/material.dart';

/// Huddl header logo — shows the full logo PNG (H icon + "huddl" wordmark),
/// exactly matching the splash screen. Height is configurable; width scales
/// proportionally via BoxFit.contain.
class HuddlHeaderLogo extends StatelessWidget {
  final double height;

  const HuddlHeaderLogo({
    super.key,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}
