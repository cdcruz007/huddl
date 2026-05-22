import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import 'package:flutter_svg/flutter_svg.dart';

// =============================================================================
// HUDDL CHARACTER — updated with locked + upgrade moods (Phase 2 audit)
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
  noticeboard,  // Noticeboard empty state — character holding megaphone
}

/// The Huddl character — a consistent illustrated figure used across
/// all empty states, onboarding screens, tutorial cards, and celebration moments.
///
/// Usage:
///   HuddlCharacter(mood: HuddlMood.waving, size: 160)
///   HuddlCharacter(mood: HuddlMood.locked, size: 120)
///   HuddlCharacter(mood: HuddlMood.upgrade, size: 160)
///   HuddlCharacter(mood: HuddlMood.noticeboard, size: 140)
class HuddlCharacter extends StatelessWidget {
  const HuddlCharacter({
    super.key,
    required this.mood,
    this.size = 140,
  });

  final HuddlMood mood;

  /// The rendered size (width = height * 0.833 to maintain 200:240 aspect ratio).
  final double size;

  String get _assetPath {
    switch (mood) {
      case HuddlMood.neutral:
        return 'assets/illustrations/huddl_neutral.svg';
      case HuddlMood.celebrating:
        return 'assets/illustrations/huddl_celebrating.svg';
      case HuddlMood.curious:
        return 'assets/illustrations/huddl_curious.svg';
      case HuddlMood.supportive:
        return 'assets/illustrations/huddl_supportive.svg';
      case HuddlMood.waving:
        return 'assets/illustrations/huddl_waving.svg';
      case HuddlMood.locked:
        return 'assets/illustrations/huddl_locked.svg';
      case HuddlMood.upgrade:
        return 'assets/illustrations/huddl_upgrade.svg';
      case HuddlMood.noticeboard:
        return 'assets/illustrations/huddl_noticeboard.svg';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Maintain 200:240 aspect ratio (width:height)
    final double width = size * (200 / 240);

    return SvgPicture.asset(
      _assetPath,
      width: width,
      height: size,
      semanticsLabel: _semanticsLabel,
    );
  }

  String get _semanticsLabel {
    switch (mood) {
      case HuddlMood.neutral:
        return 'Huddl character';
      case HuddlMood.celebrating:
        return 'Huddl character celebrating';
      case HuddlMood.curious:
        return 'Huddl character looking curious';
      case HuddlMood.supportive:
        return 'Huddl character offering support';
      case HuddlMood.waving:
        return 'Huddl character waving hello';
      case HuddlMood.locked:
        return 'Huddl character holding a lock';
      case HuddlMood.upgrade:
        return 'Huddl character celebrating an upgrade';
      case HuddlMood.noticeboard:
        return 'Huddl character with a megaphone';
    }
  }
}

// =============================================================================
// HUDDL EMPTY STATE — full empty state with character + copy + optional CTA
// =============================================================================

/// A full empty state screen using the Huddl character.
/// Use this across all empty states in the app for visual consistency.
///
/// Usage:
///   HuddlEmptyState(
///     mood: HuddlMood.waving,
///     title: 'No groups yet',
///     subtitle: 'Join a group to connect with parents near you',
///     ctaLabel: 'Find groups',
///     onCtaTap: () => _switchToTab(2),
///   )
class HuddlEmptyState extends StatelessWidget {
  const HuddlEmptyState({
    super.key,
    required this.mood,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
    this.characterSize = 120,
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

/// Displays a temporary full-screen celebration overlay with confetti and a
/// message. Automatically dismisses after 2.5 seconds.
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
