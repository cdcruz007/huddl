import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// HUDDL CHARACTER — PNG illustration + icon fallback
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
      return 'assets/illustrations/search_found.png';
    case HuddlMood.celebrating:
      return 'assets/illustrations/celebrating.png';
    case HuddlMood.curious:
      return 'assets/illustrations/questions.png';
    case HuddlMood.supportive:
      return 'assets/illustrations/community_wave.png';
    case HuddlMood.waving:
      return 'assets/illustrations/waving_phone.png';
    case HuddlMood.locked:
      return 'assets/illustrations/security.png';
    case HuddlMood.upgrade:
      return 'assets/illustrations/growth.png';
    case HuddlMood.noticeboard:
      return 'assets/illustrations/announcement.png';
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
        return Icons.people_outline_rounded;
      case HuddlMood.celebrating:
        return Icons.celebration_outlined;
      case HuddlMood.curious:
        return Icons.search_rounded;
      case HuddlMood.supportive:
        return Icons.favorite_border_rounded;
      case HuddlMood.waving:
        return Icons.waving_hand_outlined;
      case HuddlMood.locked:
        return Icons.lock_outline_rounded;
      case HuddlMood.upgrade:
        return Icons.star_border_rounded;
      case HuddlMood.noticeboard:
        return Icons.campaign_outlined;
    }
  }

  Color get _iconColor {
    switch (mood) {
      case HuddlMood.locked:
        return HuddlColors.textTertiary;
      case HuddlMood.upgrade:
        return HuddlColors.primary;
      case HuddlMood.celebrating:
        return HuddlColors.primary;
      default:
        return HuddlColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final illustrationPath = _illustrationForMood(mood);

    if (illustrationPath != null) {
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
// =============================================================================

class HuddlEmptyState extends StatelessWidget {
  const HuddlEmptyState({
    super.key,
    required this.mood,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
    this.characterSize = 160,
  });

  final HuddlMood mood;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;
  final double characterSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HuddlCharacter(mood: mood, size: characterSize),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: HuddlColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (ctaLabel != null && onCtaTap != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onCtaTap,
                style: FilledButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  foregroundColor: HuddlColors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  ctaLabel!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
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
                    color: Color(0xFF1A1A1A),
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
