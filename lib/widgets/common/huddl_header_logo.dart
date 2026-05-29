import 'package:flutter/material.dart';
import 'huddl_logo.dart';

/// Huddl header logo — H mark only, SVG, at configurable height.
/// Delegates to [HuddlLogomark] — single source of truth for the H mark.
/// Use where a compact brand mark is needed in screen headers.
class HuddlHeaderLogo extends StatelessWidget {
  final double height;

  const HuddlHeaderLogo({
    super.key,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    return HuddlLogomark(size: height);
  }
}
