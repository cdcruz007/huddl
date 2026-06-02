import 'package:flutter/material.dart';
import '../theme/huddl_icons.dart';
import '../theme/huddl_colors.dart';
import '../services/borough_scope_guard.dart';
import '../constants/app_text_styles.dart';

// =============================================================================
// BOROUGH BADGE & HEADER WIDGETS (Step 6)
//
// Reusable UI components that communicate borough-scoping to the user.
//
// BoroughBadge        - Small pill badge: "Cambridge" or "UK-wide"
// BoroughScopeChip    - Chip with icon: lock for borough-only, globe for UK-wide
// BoroughHeader       - Full-width header bar: "Showing results in Cambridge"
// BoroughGateMessage  - Inline message when cross-borough action is blocked
// =============================================================================

/// Compact pill badge showing the borough name or "UK-wide".
///
/// Use on cards, list tiles, and headers to indicate geographic scope.
/// - Borough-only features: shows the borough name with a location pin
/// - UK-wide features (Events): shows "UK-wide" with a globe icon
class BoroughBadge extends StatelessWidget {
  /// If provided, displays this borough name.
  /// If null, resolves from BoroughScopeGuard.
  final String? borough;

  /// The feature this badge represents. Determines styling:
  /// - boroughOnly  -> teal badge with pin icon
  /// - ukWide       -> blue badge with globe icon
  /// - boroughAware -> subtle grey badge
  final HuddlFeature? feature;

  /// If true, always shows "UK-wide" regardless of borough.
  final bool forceUkWide;

  /// Size variant.
  final BoroughBadgeSize size;

  const BoroughBadge({
    super.key,
    this.borough,
    this.feature,
    this.forceUkWide = false,
    this.size = BoroughBadgeSize.small,
  });

  @override
  Widget build(BuildContext context) {
    final guard = BoroughScopeGuard();
    final isUkWide = forceUkWide ||
        (feature != null && BoroughScopeGuard.isUkWide(feature!));
    final boroughName = borough ?? guard.currentBorough ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isUkWide && boroughName.isEmpty) return const SizedBox.shrink();

    final double fontSize = size == BoroughBadgeSize.small ? 10.0 : 12.0;
    final double iconSize = size == BoroughBadgeSize.small ? 10.0 : 14.0;
    final EdgeInsets padding = size == BoroughBadgeSize.small
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

    if (isUkWide) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: isDark
              ? HuddlColors.nearBlack.withValues(alpha: 0.35)
              : HuddlColors.nearBlack.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: HuddlColors.nearBlack.withValues(alpha: isDark ? 0.25 : 0.12),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HuddlIcons.language, size: iconSize, color: HuddlColors.textTertiary),
            const SizedBox(width: 3),
            Text(
              'UK-wide',
              style: HuddlText.caption(color: HuddlColors.textTertiary).copyWith(fontSize: fontSize),
            ),
          ],
        ),
      );
    }

    // Borough-only badge
    final Color badgeColor = isDark
        ? HuddlColors.nearBlack.withValues(alpha: 0.35)
        : HuddlColors.nearBlack.withValues(alpha: 0.06);
    final Color textColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textTertiary;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: HuddlColors.nearBlack.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(HuddlIcons.locationPin, size: iconSize, color: textColor),
          const SizedBox(width: 3),
          Text(
            boroughName,
            style: HuddlText.caption(color: textColor).copyWith(fontSize: fontSize),
          ),
        ],
      ),
    );
  }
}

/// Size variants for BoroughBadge.
enum BoroughBadgeSize { small, medium }

/// Scope-indicating chip with icon for feature headers.
///
/// Shows a lock icon for borough-only features and a globe for UK-wide.
class BoroughScopeChip extends StatelessWidget {
  final HuddlFeature feature;
  final String? borough;

  const BoroughScopeChip({
    super.key,
    required this.feature,
    this.borough,
  });

  @override
  Widget build(BuildContext context) {
    final guard = BoroughScopeGuard();
    final scope = BoroughScopeGuard.scopeOf(feature);
    final boroughName = borough ?? guard.currentBorough ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (scope) {
      case FeatureScope.ukWide:
        return _buildChip(
          context: context,
          icon: HuddlIcons.language,
          label: 'UK-wide',
          color: HuddlColors.textTertiary,
          isDark: isDark,
        );
      case FeatureScope.boroughOnly:
        return _buildChip(
          context: context,
          icon: HuddlIcons.locationPin,
          label: boroughName.isNotEmpty ? boroughName : 'Your borough',
          color: HuddlColors.textTertiary,
          isDark: isDark,
        );
      case FeatureScope.boroughAware:
        return _buildChip(
          context: context,
          icon: HuddlIcons.nearMe,
          label: boroughName.isNotEmpty ? 'Near $boroughName' : 'Nearby',
          color: isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary,
          isDark: isDark,
        );
    }
  }

  Widget _buildChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: HuddlText.caption(),
          ),
        ],
      ),
    );
  }
}

/// Full-width header bar showing borough scope context.
///
/// Use at the top of list screens (Groups, Marketplace, Meetups) to remind
/// users that content is scoped to their borough.
class BoroughHeader extends StatelessWidget {
  final HuddlFeature feature;
  final String? borough;
  final String? customLabel;

  const BoroughHeader({
    super.key,
    required this.feature,
    this.borough,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    final guard = BoroughScopeGuard();
    final scope = BoroughScopeGuard.scopeOf(feature);
    final boroughName = borough ?? guard.currentBorough ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String label;
    IconData icon;
    Color color;

    switch (scope) {
      case FeatureScope.ukWide:
        label = customLabel ?? 'Showing events across the UK';
        icon = HuddlIcons.language;
        color = HuddlColors.textTertiary;
        break;
      case FeatureScope.boroughOnly:
        label = customLabel ??
            (boroughName.isNotEmpty
                ? 'Showing results in $boroughName'
                : 'Showing results in your borough');
        icon = HuddlIcons.locationPin;
        color = HuddlColors.textTertiary;
        break;
      case FeatureScope.boroughAware:
        label = customLabel ??
            (boroughName.isNotEmpty
                ? 'Prioritising results near $boroughName'
                : 'Showing nearby results');
        icon = HuddlIcons.nearMe;
        color = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;
        break;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: HuddlText.caption(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline message shown when a cross-borough action is blocked.
///
/// Use in bottom sheets, dialogs, or inline when the user tries to
/// interact with content outside their borough.
class BoroughGateMessage extends StatelessWidget {
  final String? userBorough;
  final String? targetBorough;
  final String featureLabel;

  const BoroughGateMessage({
    super.key,
    this.userBorough,
    this.targetBorough,
    required this.featureLabel,
  });

  @override
  Widget build(BuildContext context) {
    final guard = BoroughScopeGuard();
    final myBorough = userBorough ?? guard.currentBorough ?? 'your borough';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? HuddlColors.nearBlack.withValues(alpha: 0.18)
            : HuddlColors.nearBlack.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: HuddlColors.nearBlack.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            HuddlIcons.info,
            size: 20,
            color: HuddlColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$featureLabel is limited to $myBorough. '
              'Only parents in your borough can see and interact with this content.',
              style: HuddlText.caption(color: HuddlColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
