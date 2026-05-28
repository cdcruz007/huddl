import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// HUDDL ANIMATIONS — single source of truth for all motion tokens
// =============================================================================
//
// Usage:
//   HuddlAnimations.slideRoute(MyScreen())          → slide-right page route
//   HuddlAnimations.lightTap()                      → light haptic
//   HuddlAnimations.mediumTap()                     → medium haptic
//   HuddlAnimations.heavyTap()                      → heavy haptic
//
//   ScaleOnPress(child: MyButton(...))               → 0.97 press scale
//   HuddlFadeIn(child: MyWidget())                  → fade-in on mount
//   ShimmerBox(width: 200, height: 20)              → skeleton shimmer
// =============================================================================

class HuddlAnimations {
  // ── Durations ──────────────────────────────────────────────────────────────
  static const Duration fast        = Duration(milliseconds: 100);
  static const Duration quick       = Duration(milliseconds: 150);
  static const Duration normal      = Duration(milliseconds: 250);
  static const Duration moderate    = Duration(milliseconds: 300);
  static const Duration slow        = Duration(milliseconds: 400);
  static const Duration verySlow    = Duration(milliseconds: 500);

  // ── Curves ─────────────────────────────────────────────────────────────────
  static const Curve defaultIn      = Curves.easeInOut;
  static const Curve sheetEntry     = Curves.easeOut;
  static const Curve sheetExit      = Curves.easeIn;
  static const Curve springBounce   = Curves.elasticOut;
  static const Curve snappy         = Curves.fastOutSlowIn;

  // ── Haptic feedback helpers ────────────────────────────────────────────────

  /// Light — chips, checkboxes, tabs, card taps, toast dismissal
  static void lightTap() => HapticFeedback.lightImpact();

  /// Medium — join group/meetup, save/unsave, endorse, send message, EHCP stage
  static void mediumTap() => HapticFeedback.mediumImpact();

  /// Heavy — submit listing, complete onboarding, confirm account deletion
  static void heavyTap() => HapticFeedback.heavyImpact();

  /// Selection click — OTP key presses, slider increments
  static void selectionClick() => HapticFeedback.selectionClick();

  /// Vibrate — foreground push notification, new DM while on Connect tab
  static void notify() => HapticFeedback.vibrate();

  // ── Page route builders ────────────────────────────────────────────────────

  /// Horizontal slide route (300ms, easeInOut) — replaces default push animation.
  static PageRouteBuilder<T> slideRoute<T>(
    Widget page, {
    bool replace = false,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: moderate,
      reverseTransitionDuration: normal,
      transitionsBuilder: (_, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: defaultIn));

        final secondarySlide = Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.3, 0.0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: defaultIn));

        return SlideTransition(
          position: secondarySlide,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }

  /// Fade route — used for tab switches and modal overlays.
  static PageRouteBuilder<T> fadeRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: quick,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  /// Reduce-motion safe slide route — uses fade when animations are disabled.
  static PageRouteBuilder<T> safeSlideRoute<T>(
    Widget page,
    BuildContext context,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return reduceMotion ? fadeRoute<T>(page) : slideRoute<T>(page);
  }
}

// =============================================================================
// SCALE ON PRESS — wraps any widget with a 0.97 press scale
// =============================================================================
class ScaleOnPress extends StatefulWidget {
  const ScaleOnPress({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.duration = HuddlAnimations.fast,
    this.onTap,
    this.haptic = true,
  });

  final Widget child;
  final double scale;
  final Duration duration;
  final VoidCallback? onTap;
  final bool haptic;

  @override
  State<ScaleOnPress> createState() => _ScaleOnPressState();
}

class _ScaleOnPressState extends State<ScaleOnPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnim = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!MediaQuery.of(context).disableAnimations) _ctrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _ctrl.reverse();
    if (widget.haptic) HuddlAnimations.lightTap();
    widget.onTap?.call();
  }

  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(scale: _scaleAnim, child: widget.child),
    );
  }
}

// =============================================================================
// FAB SCALE — 0.94 scale for floating action buttons
// =============================================================================
class FabScaleOnPress extends StatefulWidget {
  const FabScaleOnPress({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<FabScaleOnPress> createState() => _FabScaleOnPressState();
}

class _FabScaleOnPressState extends State<FabScaleOnPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (!MediaQuery.of(context).disableAnimations) _ctrl.forward();
      },
      onTapUp: (_) {
        _ctrl.reverse();
        HuddlAnimations.mediumTap();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// =============================================================================
// HEART POP ANIMATION — tap triggers 1.0 → 1.3 → 1.0 with elasticOut
// =============================================================================
class HeartPopButton extends StatefulWidget {
  const HeartPopButton({
    super.key,
    required this.isLiked,
    required this.onToggle,
    this.size = 24,
  });

  final bool isLiked;
  final VoidCallback onToggle;
  final double size;

  @override
  State<HeartPopButton> createState() => _HeartPopButtonState();
}

class _HeartPopButtonState extends State<HeartPopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!MediaQuery.of(context).disableAnimations) {
      _ctrl.forward(from: 0);
    }
    HuddlAnimations.mediumTap();
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Icon(
          widget.isLiked ? Icons.favorite : Icons.favorite_border,
          color: widget.isLiked ? const Color(0xFFE53935) : const Color(0xFF999999),
          size: widget.size,
        ),
      ),
    );
  }
}

// =============================================================================
// FADE IN — fades a widget in on mount
// =============================================================================
class HuddlFadeIn extends StatefulWidget {
  const HuddlFadeIn({
    super.key,
    required this.child,
    this.duration = HuddlAnimations.normal,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;

  @override
  State<HuddlFadeIn> createState() => _HuddlFadeInState();
}

class _HuddlFadeInState extends State<HuddlFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

// =============================================================================
// SHIMMER BOX — skeleton loading placeholder
// =============================================================================
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (MediaQuery.of(context).disableAnimations) {
      // Static placeholder when reduce motion is on
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: isDark
                  ? const [
                      Color(0xFF2A2A2A),
                      Color(0xFF3A3A3A),
                      Color(0xFF2A2A2A),
                    ]
                  : const [
                      Color(0xFFE0E0E0),
                      Color(0xFFF5F5F5),
                      Color(0xFFE0E0E0),
                    ],
              stops: [
                (_shimmer.value - 1).clamp(0.0, 1.0),
                _shimmer.value.clamp(0.0, 1.0),
                (_shimmer.value + 1).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// CARD SKELETON — full card skeleton for list loading states
// =============================================================================
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({super.key, this.imageHeight = 160});
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1A1A)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(
            width: double.infinity,
            height: imageHeight,
            borderRadius: 12,
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 120, height: 14, borderRadius: 4),
                const SizedBox(height: 8),
                ShimmerBox(width: double.infinity, height: 12, borderRadius: 4),
                const SizedBox(height: 4),
                ShimmerBox(width: 160, height: 12, borderRadius: 4),
                const SizedBox(height: 12),
                ShimmerBox(width: 80, height: 20, borderRadius: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// JOIN BUTTON — animated Join → Joined state transition
// Parameterised colours so the same widget serves groups (orange confirmed),
// services/events (nearBlack confirmed), and any future variant.
// =============================================================================
class JoinButton extends StatefulWidget {
  const JoinButton({
    super.key,
    required this.isJoined,
    required this.onTap,
    this.label = 'Join',
    this.joinedLabel = 'Joined',
    this.joinedColor = const Color(0xFF1C1C1E),     // nearBlack — confirmed state
    this.unJoinedColor = const Color(0xFFF7F7F7),   // light grey — available state
    this.unJoinedTextColor = const Color(0xFF1C1C1E),
  });

  final bool isJoined;
  final VoidCallback onTap;
  final String label;
  final String joinedLabel;
  final Color joinedColor;
  final Color unJoinedColor;
  final Color unJoinedTextColor;

  @override
  State<JoinButton> createState() => _JoinButtonState();
}

class _JoinButtonState extends State<JoinButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.isJoined ? 1.0 : 0.0,
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(JoinButton old) {
    super.didUpdateWidget(old);
    if (widget.isJoined != old.isJoined) {
      if (widget.isJoined) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (_, __) {
        final t = _progress.value;
        // Lerp between caller-supplied colours
        final bg = Color.lerp(widget.unJoinedColor, widget.joinedColor, t)!;
        final fg = Color.lerp(widget.unJoinedTextColor, Colors.white, t)!;

        return GestureDetector(
          onTap: () {
            HuddlAnimations.mediumTap();
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: HuddlAnimations.normal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              // Pill shape — join pills are always pill-shaped
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: t > 0.5
                    ? widget.joinedColor.withValues(alpha: 0.3)
                    : const Color(0xFFE8E8E8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t > 0.5) ...[
                  Icon(Icons.check, size: 14, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  t > 0.5 ? widget.joinedLabel : widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
