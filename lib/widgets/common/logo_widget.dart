import 'package:flutter/material.dart';

/// Displays the full Huddl logo (H icon + "huddl" wordmark) from the
/// official PNG asset. Width scales proportionally from the given height.
class LogoWidget extends StatelessWidget {
  final double height;

  const LogoWidget({
    super.key,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    // Logo PNG is 593×208 px — maintain aspect ratio
    final width = height * (593 / 208);
    return Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: height,
      width: width,
      fit: BoxFit.contain,
    );
  }
}
