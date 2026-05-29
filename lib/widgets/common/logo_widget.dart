import 'package:flutter/material.dart';
import 'huddl_logo.dart';

/// Displays the full Huddl logo (H mark + "huddl" wordmark).
/// Delegates to [HuddlWordmarkLogo] — single source of truth for logo rendering.
/// Use on login screen and About section only.
class LogoWidget extends StatelessWidget {
  final double height;

  const LogoWidget({
    super.key,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return HuddlWordmarkLogo(height: height);
  }
}
