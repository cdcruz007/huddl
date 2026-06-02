// =============================================================================
// HuddlCategoryIcon — Branded category chip widget
//
// Renders a top-level app category using one of the 6 bespoke SVG glyphs
// inside a consistent rounded-square chip with brand-colour background tint.
//
// USAGE
//   HuddlCategoryIcon(category: 'Marketplace')
//   HuddlCategoryIcon(category: 'Groups', size: 48)
//   HuddlCategoryIcon.fromCategory(HuddlCategory.events)
//
// RULES
//   • Only for the 6 core app sections — NOT for ItemCategory sub-categories.
//   • SVG colour is driven by colorFilter so currentColor = brand colour.
//   • Background = brand colour at 14% opacity.
//   • Dark-mode: background uses a slightly higher opacity tint.
//   • Unknown category string → neutral fallback; layout never breaks.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/huddl_colors.dart';
import '../theme/huddl_icons.dart';

// ── Canonical category enum ────────────────────────────────────────────────
enum HuddlCategory {
  marketplace,
  groups,
  meetups,
  events,
  services,
  community,
}

extension HuddlCategoryExt on HuddlCategory {
  /// Canonical display label — matches the strings used in the smart-feed nudges.
  String get label {
    switch (this) {
      case HuddlCategory.marketplace:
        return 'Marketplace';
      case HuddlCategory.groups:
        return 'Groups';
      case HuddlCategory.meetups:
        return 'Meetups';
      case HuddlCategory.events:
        return 'Events';
      case HuddlCategory.services:
        return 'Services';
      case HuddlCategory.community:
        return 'Community';
    }
  }

  /// Bespoke SVG asset path.
  String get svgAsset {
    switch (this) {
      case HuddlCategory.marketplace:
        return 'assets/icons/category/cat_marketplace.svg';
      case HuddlCategory.groups:
        return 'assets/icons/category/cat_groups.svg';
      case HuddlCategory.meetups:
        return 'assets/icons/category/cat_meetups.svg';
      case HuddlCategory.events:
        return 'assets/icons/category/cat_events.svg';
      case HuddlCategory.services:
        return 'assets/icons/category/cat_services.svg';
      case HuddlCategory.community:
        return 'assets/icons/category/cat_community.svg';
    }
  }

  /// Brand colour for both the glyph tint and the chip background tint.
  Color get brandColor {
    switch (this) {
      case HuddlCategory.marketplace:
        return HuddlColors.primary;      // #FF965C — brand orange
      case HuddlCategory.groups:
        return HuddlColors.infoBlue;     // #347FEF — info blue
      case HuddlCategory.meetups:
        return HuddlColors.brandTeal;    // #199A85 — teal
      case HuddlCategory.events:
        return HuddlColors.infoBlue;     // #347FEF — calendar context
      case HuddlCategory.services:
        return HuddlColors.brandTeal;    // #199A85 — teal
      case HuddlCategory.community:
        return HuddlColors.primaryLight; // #FFAD7F — warm orange
    }
  }
}

// ── Category string → enum resolver ─────────────────────────────────────────
HuddlCategory? huddlCategoryFromString(String raw) {
  switch (raw.toLowerCase().trim()) {
    case 'marketplace':
    case 'market':
    case 'rehome':
    case 'buy':
    case 'sell':
      return HuddlCategory.marketplace;
    case 'groups':
    case 'group':
      return HuddlCategory.groups;
    case 'meetups':
    case 'meetup':
      return HuddlCategory.meetups;
    case 'events':
    case 'event':
      return HuddlCategory.events;
    case 'services':
    case 'local services':
    case 'service':
    case 'local service':
      return HuddlCategory.services;
    case 'community':
    case 'noticeboard':
    case 'board':
      return HuddlCategory.community;
    default:
      return null;
  }
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// Branded category chip that renders one of the 6 bespoke SVG glyphs.
///
/// Accepts a [category] string (matched case-insensitively).
/// For type-safe construction use the [HuddlCategoryIcon.fromCategory] factory.
class HuddlCategoryIcon extends StatelessWidget {
  const HuddlCategoryIcon({
    super.key,
    required this.category,
    this.resolvedCategory,
    this.size = 40.0,
    this.chipRadius = 12.0,
    this.iconPadding = 8.0,
    this.showBackground = true,
    this.backgroundOpacity = 0.14,
  });

  /// Convenience factory — type-safe enum path.
  factory HuddlCategoryIcon.fromCategory(
    HuddlCategory cat, {
    Key? key,
    double size = 40.0,
    double chipRadius = 12.0,
    double iconPadding = 8.0,
    bool showBackground = true,
    double backgroundOpacity = 0.14,
  }) {
    return HuddlCategoryIcon(
      key: key,
      category: cat.label,
      resolvedCategory: cat,
      size: size,
      chipRadius: chipRadius,
      iconPadding: iconPadding,
      showBackground: showBackground,
      backgroundOpacity: backgroundOpacity,
    );
  }

  /// Category label string — matched case-insensitively.
  /// E.g. 'Marketplace', 'groups', 'Local services'.
  final String category;

  /// Pre-resolved enum — set by [fromCategory] to skip string matching.
  final HuddlCategory? resolvedCategory;

  /// Overall chip size (width = height = [size]).
  final double size;

  /// Corner radius of the chip background container.
  final double chipRadius;

  /// Padding between chip edge and SVG glyph.
  final double iconPadding;

  /// Whether to draw the tinted rounded-square background.
  final bool showBackground;

  /// Opacity of the background tint (default 0.14 = 14%).
  final double backgroundOpacity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final HuddlCategory? cat = resolvedCategory ?? huddlCategoryFromString(category);

    if (cat == null) {
      // Unknown category — render a neutral fallback pill so layout never breaks.
      return _buildChip(
        isDark: isDark,
        brandColor: HuddlColors.neutral300,
        child: Icon(
          HuddlIcons.label,
          size: size - iconPadding * 2,
          color: HuddlColors.neutral300,
        ),
      );
    }

    final color = cat.brandColor;
    final glyphSize = size - iconPadding * 2;

    return _buildChip(
      isDark: isDark,
      brandColor: color,
      child: SvgPicture.asset(
        cat.svgAsset,
        width: glyphSize,
        height: glyphSize,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }

  Widget _buildChip({
    required bool isDark,
    required Color brandColor,
    required Widget child,
  }) {
    if (!showBackground) {
      return SizedBox(width: size, height: size, child: Center(child: child));
    }

    // Dark mode: slightly higher opacity so chip reads on dark surfaces.
    final bgOpacity = isDark
        ? (backgroundOpacity + 0.06).clamp(0.0, 1.0)
        : backgroundOpacity;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brandColor.withValues(alpha: bgOpacity),
        borderRadius: BorderRadius.circular(chipRadius),
      ),
      child: Center(child: child),
    );
  }
}

// ── Label + chip combo (convenience) ────────────────────────────────────────

/// Horizontal chip: [HuddlCategoryIcon] + category text label side-by-side.
///
/// Use wherever you need a labelled category pill, e.g. feed cards or nudges.
class HuddlCategoryChip extends StatelessWidget {
  const HuddlCategoryChip({
    super.key,
    required this.category,
    this.iconSize = 32.0,
    this.gap = 6.0,
    this.textStyle,
    this.showBackground = true,
  });

  final String category;
  final double iconSize;
  final double gap;
  final TextStyle? textStyle;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final cat = huddlCategoryFromString(category);
    final color = cat?.brandColor ?? HuddlColors.neutral300;
    final label = cat?.label ?? category;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HuddlCategoryIcon(
          category: category,
          size: iconSize,
          chipRadius: iconSize * 0.3,
          iconPadding: iconSize * 0.2,
          showBackground: showBackground,
        ),
        SizedBox(width: gap),
        Text(
          label,
          style: textStyle ??
              TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.2,
              ),
        ),
      ],
    );
  }
}
