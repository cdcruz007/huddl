import 'package:flutter/material.dart';
import '../theme/huddl_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/huddl_colors.dart';
import '../constants/app_text_styles.dart';
import 'common/huddl_button.dart';

// =============================================================================
// HUDDL CHARACTER — SVG/PNG illustration + icon fallback
// =============================================================================

/// The emotional states of the Huddl character.
enum HuddlMood {
  neutral,      // General empty states
  celebrating,  // First join, first listing, tutorial complete
  curious,      // Co-pilot welcome, search empty state
  supportive,   // SEND section, broken streak, warmth moments
  waving,       // Onboarding welcome, tutorial start, co-pilot greeting
  locked,       // Subscription gate — feature not available on current plan
  upgrade,      // Post-upgrade celebration moment
  noticeboard,  // Noticeboard empty state
}

/// Maps each mood to the matching PNG illustration asset path.
String? _illustrationForMood(HuddlMood mood) {
  switch (mood) {
    case HuddlMood.neutral:
      return 'assets/icons/illustrations/community_wave.svg';
    case HuddlMood.celebrating:
      return 'assets/icons/illustrations/celebrating.svg';
    case HuddlMood.curious:
      return 'assets/icons/illustrations/questions.svg';
    case HuddlMood.supportive:
      return 'assets/icons/illustrations/waving_thumbs.svg';
    case HuddlMood.waving:
      return 'assets/icons/illustrations/waving_orange.svg';
    case HuddlMood.locked:
      return 'assets/icons/illustrations/security.svg';
    case HuddlMood.upgrade:
      return 'assets/icons/illustrations/growth.svg';
    case HuddlMood.noticeboard:
      return 'assets/icons/illustrations/announcement.svg';
  }
}

/// The Huddl character — renders a PNG illustration if available,
/// falling back to a Material icon inside a circular container.
class HuddlCharacter extends StatelessWidget {
  const HuddlCharacter({
    super.key,
    required this.mood,
    this.size = 140,
  });

  final HuddlMood mood;
  final double size;

  IconData get _icon {
    switch (mood) {
      case HuddlMood.neutral:
        return HuddlIcons.usersThree;
      case HuddlMood.celebrating:
        return HuddlIcons.celebration;
      case HuddlMood.curious:
        return HuddlIcons.search;
      case HuddlMood.supportive:
        return HuddlIcons.heart;
      case HuddlMood.waving:
        return HuddlIcons.waving;
      case HuddlMood.locked:
        return HuddlIcons.lock;
      case HuddlMood.upgrade:
        return HuddlIcons.star;
      case HuddlMood.noticeboard:
        return HuddlIcons.campaign;
    }
  }

  Color get _iconColor {
    switch (mood) {
      case HuddlMood.locked:
        return HuddlColors.textTertiary;
      case HuddlMood.upgrade:
        // Star icon for upgrade moment \u2014 yellow = celebration, not a CTA.
        return HuddlColors.yellow;
      case HuddlMood.celebrating:
        // First-join, milestone celebration \u2014 yellow = joy/achievement.
        return HuddlColors.yellow;
      default:
        return HuddlColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final illustrationPath = _illustrationForMood(mood);

    if (illustrationPath != null) {
      final isSvg = illustrationPath.endsWith('.svg');
      if (isSvg) {
        return SvgPicture.asset(
          illustrationPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => SizedBox(width: size, height: size),
        );
      }
      // PNG fallback — used during migration for any unconverted assets
      return Image.asset(
        illustrationPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    // Fallback: icon in circular container
    final double iconSize = size * 0.6;
    final double containerSize = size * 0.85;
    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        color: HuddlColors.inputBg,
        shape: BoxShape.circle,
      ),
      child: Icon(
        _icon,
        size: iconSize,
        color: _iconColor,
      ),
    );
  }
}

// =============================================================================
// HUDDL EMPTY STATE — full empty state with illustration + copy + optional CTA
// Animated entrance: 450ms fade + 6% upward slide with 80ms delay
// =============================================================================

class HuddlEmptyState extends StatefulWidget {
  const HuddlEmptyState({
    super.key,
    required this.mood,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
    this.characterSize = 160,
    this.illustrationAsset,
  });

  final HuddlMood mood;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;
  final double characterSize;
  /// Optional path to a WebP illustration in assets/illustrations/.
  /// When provided, replaces the HuddlCharacter icon with the illustration
  /// rendered inside a warm soft-orange circle (the huddl warm-circle treatment).
  final String? illustrationAsset;

  @override
  State<HuddlEmptyState> createState() => _HuddlEmptyStateState();
}

class _HuddlEmptyStateState extends State<HuddlEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    // Small delay prevents flash on fast loads
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.illustrationAsset != null
                    ? WarmCircleIllustration(
                        assetPath: widget.illustrationAsset!,
                        size: widget.characterSize,
                      )
                    : HuddlCharacter(
                        mood: widget.mood,
                        size: widget.characterSize,
                      ),
                const SizedBox(height: 20),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: HuddlText.heading(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? HuddlColors.darkTextPrimary
                        : HuddlColors.nearBlack,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  textAlign: TextAlign.center,
                  style: HuddlText.body(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? HuddlColors.darkTextSecondary
                        : HuddlColors.textSecondary,
                  ),
                ),
                if (widget.ctaLabel != null && widget.onCtaTap != null) ...[
                  const SizedBox(height: 28),
                  HuddlButton(
                    label: widget.ctaLabel!,
                    onPressed: widget.onCtaTap,
                    variant: HuddlButtonVariant.primary,
                    fullWidth: false,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// WarmCircleIllustration — WebP illustration with warm-circle treatment
//
// Rendering treatment matches the huddl brand:
//   • Soft orange-tinted circle background (#FFF5F0) — huddl's palest warm tint
//   • Illustration at 80% opacity inside the circle
//   • Circle diameter = size, illustration fills 80% of circle
// =============================================================================
class WarmCircleIllustration extends StatelessWidget {
  const WarmCircleIllustration({
    super.key,
    required this.assetPath,
    required this.size,
  });

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final double circleSize = size;
    final double imageSize = size * 0.80;

    return Container(
      width: circleSize,
      height: circleSize,
      decoration: const BoxDecoration(
        color: HuddlColors.peachWarm, // huddl warm pale-orange tint
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Opacity(
          opacity: 0.82,
          child: Image.asset(
            assetPath,
            width: imageSize,
            height: imageSize,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              HuddlIcons.imageNotSupported,
              size: imageSize * 0.5,
              color: HuddlColors.textHint,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// HuddlCelebrationOverlay — full-screen confetti celebration
// =============================================================================

class HuddlCelebrationOverlay {
  static Future<void> show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(milliseconds: 2500),
  }) async {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CelebrationOverlayWidget(
        message: message,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    await Future.delayed(duration);
    if (entry.mounted) entry.remove();
  }
}

class _CelebrationOverlayWidget extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _CelebrationOverlayWidget({required this.message, required this.onDone});

  @override
  State<_CelebrationOverlayWidget> createState() => _CelebrationOverlayWidgetState();
}

class _CelebrationOverlayWidgetState extends State<_CelebrationOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _ctrl.reverse().then((_) => widget.onDone());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.neutral900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
