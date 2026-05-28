import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';

// =============================================================================
// HUDDL CARD — Design-system surface container
// =============================================================================
//
// Variants:
//   standard  — white/darkSurface, subtle shadow, 1px divider border in dark.
//              Default for most content cards.
//   elevated  — same background, stronger shadow. For modals / hero cards.
//   selected  — primary-tinted border (2px HuddlColors.primary). Active state.
//   flat      — no shadow, no border. For list rows inside already-elevated
//              parents (e.g. bottom sheets, detail screens).
//
// Usage:
//   HuddlCard(child: ...)
//   HuddlCard(variant: HuddlCardVariant.selected, child: ...)
//   HuddlCard(variant: HuddlCardVariant.flat, padding: EdgeInsets.zero, child: ...)
//
// Spec:
//   - Corner radius: 16px (overridable via borderRadius param)
//   - Standard padding: 16px all sides (overridable)
//   - Standard shadow: 0 3px 8px black 6% opacity
//   - Elevated shadow: 0 6px 20px black 10% opacity
//   - Dark mode: no shadow, uses cardBorder from HuddlContextColors
// =============================================================================

enum HuddlCardVariant { standard, elevated, selected, flat }

class HuddlCard extends StatelessWidget {
  const HuddlCard({
    super.key,
    required this.child,
    this.variant = HuddlCardVariant.standard,
    this.padding,
    this.borderRadius,
    this.color,
    this.margin,
    this.clipBehavior = Clip.antiAlias,
    this.onTap,
  });

  final Widget child;
  final HuddlCardVariant variant;
  final EdgeInsetsGeometry? padding;
  final BorderRadiusGeometry? borderRadius;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(16);
    final bg = color ??
        (isDark ? HuddlColors.darkSurface : Colors.white);

    BoxDecoration decoration;
    switch (variant) {
      case HuddlCardVariant.standard:
        decoration = BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: isDark
              ? Border.all(color: HuddlColors.darkDivider, width: 1)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        );
      case HuddlCardVariant.elevated:
        decoration = BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: isDark
              ? Border.all(color: HuddlColors.darkDivider, width: 1)
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        );
      case HuddlCardVariant.selected:
        decoration = BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: HuddlColors.primary, width: 2),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: HuddlColors.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        );
      case HuddlCardVariant.flat:
        decoration = BoxDecoration(
          color: bg,
          borderRadius: radius,
        );
    }

    Widget card = Container(
      margin: margin,
      decoration: decoration,
      clipBehavior: clipBehavior,
      child: padding != null
          ? Padding(padding: padding!, child: child)
          : child,
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: radius is BorderRadius ? radius : BorderRadius.circular(16),
        child: card,
      );
    }

    return card;
  }
}
