import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../../theme/huddl_colors.dart';

// =============================================================================
// HUDDL SPRING ANIMATIONS — physics-based motion matching Airbnb quality
// =============================================================================
//
// USAGE:
//   // Spring scale on mount (cards entering the screen)
//   HuddlSpringMount(child: MyCard())
//
//   // Staggered list entry (feed cards loading in one-by-one)
//   HuddlStaggeredList(children: [...cards], staggerMs: 60)
//
//   // Bouncy bottom sheet (replaces standard showModalBottomSheet)
//   HuddlSpringSheet.show(context, builder: (_) => MySheet())
//
//   // Tab switch with spring transition
//   HuddlTabTransition(currentIndex: _tab, children: [...screens])
//
//   // Page route with spring expansion (for card → detail)
//   Navigator.push(context, HuddlSpringPageRoute(page: DetailScreen()))
//
// DESIGN PRINCIPLE:
//   Airbnb uses spring physics throughout — not just linear easing.
//   SpringSimulation mimics real-world physics: slight overshoot → settle.
//   Damping 0.8 = subtle bounce. 1.0 = critically damped (no bounce).
//   Stiffness 180 = medium snap. 400+ = fast snap.
//
// =============================================================================

// ── Spring constants matching Airbnb's motion language ───────────────────────

class HuddlSprings {
  HuddlSprings._();

  /// Card entry — gentle pop onto the screen
  static const SpringDescription cardEntry = SpringDescription(
    mass: 1.0,
    stiffness: 200.0,
    damping: 20.0, // slightly underdamped → subtle bounce
  );

  /// Button press — snappy with micro-bounce
  static const SpringDescription buttonPress = SpringDescription(
    mass: 0.6,
    stiffness: 380.0,
    damping: 18.0,
  );

  /// Bottom sheet — smooth entry, slight overshoot
  static const SpringDescription sheetEntry = SpringDescription(
    mass: 1.0,
    stiffness: 240.0,
    damping: 22.0,
  );

  /// Navigation transition — purposeful, no bounce
  static const SpringDescription navigation = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 30.0, // critically damped
  );

  /// FAB expansion — playful pop
  static const SpringDescription fabPop = SpringDescription(
    mass: 0.8,
    stiffness: 320.0,
    damping: 16.0,
  );
}

// ── 1. Spring mount — cards pop onto screen ──────────────────────────────────

class HuddlSpringMount extends StatefulWidget {
  const HuddlSpringMount({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.spring = HuddlSprings.cardEntry,
    this.fromScale = 0.88,
    this.fromOpacity = 0.0,
    this.fromOffset = const Offset(0, 16),
  });

  final Widget child;
  final Duration delay;
  final SpringDescription spring;
  final double fromScale;
  final double fromOpacity;
  final Offset fromOffset;

  @override
  State<HuddlSpringMount> createState() => _HuddlSpringMountState();
}

class _HuddlSpringMountState extends State<HuddlSpringMount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController.unbounded(vsync: this);

    Future.delayed(widget.delay, () {
      if (!mounted) return;
      _ctrl.animateWith(
        SpringSimulation(widget.spring, 0, 1, 0),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = _ctrl.value.clamp(0.0, 1.0);
        final scale = widget.fromScale + (1.0 - widget.fromScale) * t;
        final opacity = widget.fromOpacity + (1.0 - widget.fromOpacity) * t;
        final dx = widget.fromOffset.dx * (1 - t);
        final dy = widget.fromOffset.dy * (1 - t);
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: scale.clamp(0.0, 1.5),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ── 2. Staggered list — items enter one-by-one ───────────────────────────────

class HuddlStaggeredList extends StatelessWidget {
  const HuddlStaggeredList({
    super.key,
    required this.children,
    this.staggerMs = 55,
    this.spring = HuddlSprings.cardEntry,
  });

  final List<Widget> children;
  final int staggerMs;
  final SpringDescription spring;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.asMap().entries.map((e) {
        return HuddlSpringMount(
          delay: Duration(milliseconds: e.key * staggerMs),
          spring: spring,
          child: e.value,
        );
      }).toList(),
    );
  }
}

// ── 3. Spring page route — card expands into detail screen ───────────────────

class HuddlSpringPageRoute<T> extends PageRoute<T> {
  HuddlSpringPageRoute({
    required this.page,
    this.spring = HuddlSprings.navigation,
  });

  final Widget page;
  final SpringDescription spring;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 380);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return page;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    // Slide up from slightly below + fade
    final slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    ));

    final fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    // Secondary — current page slides left slightly
    final secondarySlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.08, 0),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInOut,
    ));

    return SlideTransition(
      position: secondarySlide,
      child: FadeTransition(
        opacity: fadeAnim,
        child: SlideTransition(position: slideAnim, child: child),
      ),
    );
  }
}

// ── 4. Bouncy bottom sheet ────────────────────────────────────────────────────

class HuddlSpringSheet {
  HuddlSpringSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool isDismissible = true,
    double? maxHeightFraction,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      backgroundColor: Colors.transparent,
      transitionAnimationController: _SpringAnimationController(
        vsync: Navigator.of(context),
        spring: HuddlSprings.sheetEntry,
      ),
      builder: (ctx) => _SpringSheetWrapper(
        maxHeightFraction: maxHeightFraction ?? 0.92,
        child: builder(ctx),
      ),
    );
  }
}

class _SpringAnimationController extends AnimationController {
  _SpringAnimationController({
    required super.vsync,
    required SpringDescription spring,
  })  : _spring = spring,
        super.unbounded();

  final SpringDescription _spring;

  @override
  TickerFuture forward({double? from}) {
    return animateWith(SpringSimulation(_spring, from ?? value, 1.0, 0));
  }

  @override
  TickerFuture reverse({double? from}) {
    return animateTo(0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeIn);
  }
}

class _SpringSheetWrapper extends StatelessWidget {
  const _SpringSheetWrapper({
    required this.child,
    required this.maxHeightFraction,
  });
  final Widget child;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * maxHeightFraction;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: child,
      ),
    );
  }
}

// ── 5. Spring scale press — wraps any tappable element ───────────────────────

class HuddlSpringPress extends StatefulWidget {
  const HuddlSpringPress({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.965,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<HuddlSpringPress> createState() => _HuddlSpringPressState();
}

class _HuddlSpringPressState extends State<HuddlSpringPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController.unbounded(vsync: this, value: 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down() {
    _ctrl.animateWith(
        SpringSimulation(HuddlSprings.buttonPress, _ctrl.value, widget.scale, 0));
  }

  void _up() {
    _ctrl.animateWith(
        SpringSimulation(HuddlSprings.buttonPress, _ctrl.value, 1.0, -4));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) {
        _up();
        widget.onTap();
      },
      onTapCancel: _up,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.scale(
          scale: _ctrl.value.clamp(0.5, 1.5),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

// ── 6. Celebration confetti burst ────────────────────────────────────────────
// Used on: first group join, first listing, upgrade success

class HuddlCelebrationBurst extends StatefulWidget {
  const HuddlCelebrationBurst({
    super.key,
    required this.child,
    this.onComplete,
  });

  final Widget child;
  final VoidCallback? onComplete;

  @override
  State<HuddlCelebrationBurst> createState() => _HuddlCelebrationBurstState();
}

class _HuddlCelebrationBurstState extends State<HuddlCelebrationBurst>
    with TickerProviderStateMixin {
  late final AnimationController _burstCtrl;
  final List<_Particle> _particles = [];
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _burstCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        setState(() => _animating = false);
        widget.onComplete?.call();
      }
    });
    _buildParticles();
  }

  void _buildParticles() {
    _particles.clear();
    final colors = [
      HuddlColors.primary,
      HuddlColors.nearBlack,
      HuddlColors.accentAmber,
      HuddlColors.error,
      const Color(0xFF5B9CFF),
    ];
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * 2 * 3.14159;
      _particles.add(_Particle(
        color: colors[i % colors.length],
        angle: angle,
        speed: 0.6 + (i % 3) * 0.2,
      ));
    }
  }

  void trigger() {
    if (_animating) return;
    setState(() => _animating = true);
    _burstCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _burstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: trigger,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_animating)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _burstCtrl,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _ParticlePainter(
                      particles: _particles,
                      progress: _burstCtrl.value,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Particle {
  final Color color;
  final double angle;
  final double speed;
  _Particle({required this.color, required this.angle, required this.speed});
}

class _ParticlePainter extends CustomPainter {
  const _ParticlePainter({
    required this.particles,
    required this.progress,
  });
  final List<_Particle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width * 0.45;
    final fade = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final r = maxR * progress * p.speed;
      final x = cx + r * (0 + 1 * _cos(p.angle));
      final y = cy + r * (0 + 1 * _sin(p.angle));
      final particleOpacity = (fade * fade).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = p.color.withValues(alpha: particleOpacity)
        ..style = PaintingStyle.fill;
      // Alternate between circles and rectangles
      if (particles.indexOf(p) % 2 == 0) {
        canvas.drawCircle(Offset(x, y), 4 * (1 - progress * 0.5), paint);
      } else {
        final rect = Rect.fromCenter(
          center: Offset(x, y),
          width: 6 * (1 - progress * 0.3),
          height: 6 * (1 - progress * 0.3),
        );
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(p.angle + progress * 3.14);
        canvas.translate(-x, -y);
        canvas.drawRect(rect, paint);
        canvas.restore();
      }
    }
  }

  double _cos(double rad) {
    return (rad - 1.5707963).abs() < 0.001 ? 0 : (rad * 180 / 3.14159).abs() % 360 < 180
        ? 1 - 2 * ((rad * 180 / 3.14159).abs() % 180) / 180
        : -1 + 2 * ((rad * 180 / 3.14159).abs() % 180) / 180;
  }

  double _sin(double rad) => _cos(rad - 1.5707963);

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
