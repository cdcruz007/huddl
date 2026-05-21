import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The emotional states of the Huddl character.
enum HuddlMood {
  neutral,      // General empty states
  celebrating,  // First join, first listing, tutorial complete
  curious,      // Co-pilot welcome, search empty state
  supportive,   // SEND section, broken streak, warmth moments
  waving,       // Onboarding welcome, tutorial start, co-pilot greeting
}

/// The Huddl character — a consistent illustrated figure used across
/// all empty states, onboarding screens, tutorial cards, and celebration moments.
///
/// Usage:
///   HuddlCharacter(mood: HuddlMood.waving, size: 160)
///   HuddlCharacter(mood: HuddlMood.celebrating, size: 120)
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
    }
  }
}

/// A full empty state screen using the Huddl character.
/// Use this across all empty states in the app for visual consistency.
///
/// Usage:
///   HuddlEmptyState(
///     mood: HuddlMood.neutral,
///     title: "Your crew is out there",
///     subtitle: "Parents near you are already chatting — jump in and say hi.",
///     ctaLabel: "Find my groups",
///     onCta: () => Navigator.pushNamed(context, '/discover/groups'),
///   )
class HuddlEmptyState extends StatelessWidget {
  const HuddlEmptyState({
    super.key,
    required this.mood,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.characterSize = 160,
  });

  final HuddlMood mood;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final double characterSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HuddlCharacter(mood: mood, size: characterSize),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF666666),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onCta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3580F0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(ctaLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Celebration overlay — full-screen Huddl celebrating moment.
/// Shows for 2.5 seconds then auto-dismisses.
///
/// Usage:
///   HuddlCelebrationOverlay.show(
///     context,
///     message: "Welcome to your first group! 🎉",
///   );
class HuddlCelebrationOverlay extends StatefulWidget {
  const HuddlCelebrationOverlay({super.key, required this.message});

  final String message;

  static Future<void> show(BuildContext context, {required String message}) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) =>
            HuddlCelebrationOverlay(message: message),
      ),
    );
  }

  @override
  State<HuddlCelebrationOverlay> createState() =>
      _HuddlCelebrationOverlayState();
}

class _HuddlCelebrationOverlayState extends State<HuddlCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();

    // Auto-dismiss after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HuddlCharacter(
                    mood: HuddlMood.celebrating,
                    size: 160,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.message,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
