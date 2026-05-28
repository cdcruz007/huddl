import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';

// =============================================================================
// HUDDL LOADING STATES — Airbnb-inspired illustrated loading screens
// =============================================================================
//
// AIRBNB PATTERN (from screenshots):
//   • White screen, centered 3D illustration, short copy beneath
//   • "We're getting your reservation ready" — animated dot dot dot
//   • "Reviewing payment details" — payment terminal illustration
//   No spinners. No progress bars. Just an illustration + animated copy.
//
// HUDDL EQUIVALENTS:
//   HuddlLoadingScreen.findingParents()    → finding nearby parents
//   HuddlLoadingScreen.joiningGroup()      → joining a group
//   HuddlLoadingScreen.postingNow()        → posting to noticeboard
//   HuddlLoadingScreen.matchmaking()       → AI matchmaker running
//   HuddlLoadingScreen.checkingPayment()   → subscription checkout
//
//   HuddlSkeletonFeed()                    → shimmer feed loading state
//   HuddlSkeletonCard()                    → single card skeleton
//   HuddlSkeletonProfile()                 → profile screen skeleton
//
// =============================================================================

// ── Illustrated loading screen ────────────────────────────────────────────────

class HuddlLoadingScreen extends StatefulWidget {
  const HuddlLoadingScreen._({
    required this.illustration,
    required this.message,
    this.submessage,
  });

  factory HuddlLoadingScreen.findingParents() => const HuddlLoadingScreen._(
        illustration: _HuddlLoadingIllustration.parents,
        message: 'Finding parents near you',
      );

  factory HuddlLoadingScreen.joiningGroup() => const HuddlLoadingScreen._(
        illustration: _HuddlLoadingIllustration.community,
        message: 'Joining your community',
      );

  factory HuddlLoadingScreen.postingNow() => const HuddlLoadingScreen._(
        illustration: _HuddlLoadingIllustration.megaphone,
        message: 'Sharing with your neighbours',
      );

  factory HuddlLoadingScreen.matchmaking() => const HuddlLoadingScreen._(
        illustration: _HuddlLoadingIllustration.sparkle,
        message: 'Finding your perfect match',
        submessage: 'AI is working its magic',
      );

  factory HuddlLoadingScreen.checkingPayment() => const HuddlLoadingScreen._(
        illustration: _HuddlLoadingIllustration.payment,
        message: 'Confirming your subscription',
        submessage: 'This only takes a moment',
      );

  factory HuddlLoadingScreen.reservationReady() => const HuddlLoadingScreen._(
        illustration: _HuddlLoadingIllustration.payment,
        message: 'Getting your listing ready',
        submessage: 'This only takes a moment',
      );

  // ignore: library_private_types_in_public_api
  final _HuddlLoadingIllustration illustration;
  final String message;
  final String? submessage;

  @override
  State<HuddlLoadingScreen> createState() => _HuddlLoadingScreenState();
}

enum _HuddlLoadingIllustration {
  parents, community, megaphone, sparkle, payment
}

class _HuddlLoadingScreenState extends State<HuddlLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();

    // Animated dots — cycles 1, 2, 3
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
    _dotCtrl.addListener(() {
      final newDots = (_dotCtrl.value * 3).floor() + 1;
      if (newDots != _dotCount && mounted) {
        setState(() => _dotCount = newDots);
      }
    });

    // Gentle float for the illustration
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? HuddlColors.darkBackground : HuddlColors.white;
    final textColor = isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark;

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Floating illustration
            AnimatedBuilder(
              animation: _floatAnim,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, _floatAnim.value),
                child: child,
              ),
              child: SizedBox(
                width: 160,
                height: 160,
                child: _buildIllustration(widget.illustration, isDark),
              ),
            ),

            const SizedBox(height: 40),

            // Airbnb-style 3-dot bounce loader
            const SizedBox(height: 8),
            HuddlThreeDotsLoader(color: textColor),
            const SizedBox(height: 32),

            // Message — clean, no trailing dots (Airbnb shows dots separately above text)
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: HuddlText.display(color: textColor),
            ),

            if (widget.submessage != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.submessage!,
                textAlign: TextAlign.center,
                style: HuddlText.body(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(_HuddlLoadingIllustration type, bool isDark) {
    // Each illustration is a custom painted scene
    switch (type) {
      case _HuddlLoadingIllustration.parents:
        return CustomPaint(painter: _ParentsPainter(isDark: isDark));
      case _HuddlLoadingIllustration.community:
        return CustomPaint(painter: _CommunityPainter(isDark: isDark));
      case _HuddlLoadingIllustration.megaphone:
        return CustomPaint(painter: _MegaphonePainter(isDark: isDark));
      case _HuddlLoadingIllustration.sparkle:
        return CustomPaint(painter: _SparklePainter(isDark: isDark));
      case _HuddlLoadingIllustration.payment:
        return CustomPaint(painter: _PaymentPainter(isDark: isDark));
    }
  }
}

// ── Custom painters for each loading state ────────────────────────────────────

class _ParentsPainter extends CustomPainter {
  const _ParentsPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Location pin background
    final bgPaint = Paint()
      ..color = HuddlColors.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 70, bgPaint);

    // Location pin body
    final pinPaint = Paint()
      ..color = HuddlColors.primary
      ..style = PaintingStyle.fill;
    final pinPath = Path()
      ..addOval(Rect.fromCenter(center: Offset(cx, cy - 14), width: 48, height: 48))
      ..moveTo(cx - 10, cy + 6)
      ..lineTo(cx, cy + 28)
      ..lineTo(cx + 10, cy + 6);
    canvas.drawPath(pinPath, pinPaint);

    // Parent icon inside pin
    final iconPaint = Paint()
      ..color = HuddlColors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy - 18), 10, iconPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 4), width: 22, height: 10),
        const Radius.circular(5),
      ),
      iconPaint,
    );

    // Ripple rings
    final ripplePaint = Paint()
      ..color = HuddlColors.primary.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy - 14), 32, ripplePaint);
    ripplePaint.color = HuddlColors.primary.withValues(alpha: 0.12);
    canvas.drawCircle(Offset(cx, cy - 14), 44, ripplePaint);
  }

  @override
  bool shouldRepaint(_ParentsPainter old) => false;
}

class _CommunityPainter extends CustomPainter {
  const _CommunityPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 3 overlapping circles representing community
    final c1 = Paint()..color = HuddlColors.primary.withValues(alpha: 0.85);
    final c2 = Paint()..color = HuddlColors.nearBlack.withValues(alpha: 0.85);
    final c3 = Paint()..color = HuddlColors.primary.withValues(alpha: 0.85);

    canvas.drawCircle(Offset(cx - 24, cy - 8), 34, c1);
    canvas.drawCircle(Offset(cx + 24, cy - 8), 34, c2);
    canvas.drawCircle(Offset(cx, cy + 20), 34, c3);

    // White people icons in each circle
    final wp = Paint()..color = Colors.white;
    for (final pos in [
      Offset(cx - 24, cy - 14),
      Offset(cx + 24, cy - 14),
      Offset(cx, cy + 14),
    ]) {
      canvas.drawCircle(pos - const Offset(0, 8), 7, wp);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos + const Offset(0, 4), width: 16, height: 8),
          const Radius.circular(4),
        ),
        wp,
      );
    }
  }

  @override
  bool shouldRepaint(_CommunityPainter old) => false;
}

class _MegaphonePainter extends CustomPainter {
  const _MegaphonePainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background circle
    canvas.drawCircle(
      Offset(cx, cy),
      70,
      Paint()..color = HuddlColors.primary.withValues(alpha: 0.10),
    );

    // Megaphone body
    final bodyPaint = Paint()..color = HuddlColors.primary;
    final bodyPath = Path()
      ..moveTo(cx - 8, cy - 12)
      ..lineTo(cx - 8, cy + 12)
      ..lineTo(cx + 28, cy + 22)
      ..lineTo(cx + 28, cy - 22)
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    // Horn
    final hornPaint = Paint()..color = HuddlColors.primaryLight;
    final hornPath = Path()
      ..moveTo(cx - 8, cy - 12)
      ..lineTo(cx - 28, cy - 18)
      ..lineTo(cx - 28, cy + 18)
      ..lineTo(cx - 8, cy + 12)
      ..close();
    canvas.drawPath(hornPath, hornPaint);

    // Handle
    final handlePath = Path()
      ..moveTo(cx + 14, cy + 10)
      ..lineTo(cx + 14, cy + 30)
      ..lineTo(cx + 26, cy + 30)
      ..lineTo(cx + 26, cy + 10);
    canvas.drawPath(
      handlePath,
      Paint()..color = HuddlColors.primaryDark..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round,
    );

    // Sound waves
    final wavePaint = Paint()
      ..color = HuddlColors.nearBlack.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 28, cy), width: 20, height: 30),
      -0.8, 1.6, false, wavePaint,
    );
    wavePaint.color = HuddlColors.nearBlack.withValues(alpha: 0.4);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 28, cy), width: 36, height: 50),
      -0.8, 1.6, false, wavePaint,
    );
  }

  @override
  bool shouldRepaint(_MegaphonePainter old) => false;
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Central sparkle star
    _drawStar(canvas, Offset(cx, cy), 38, HuddlColors.primary);
    _drawStar(canvas, Offset(cx - 40, cy - 30), 14, HuddlColors.primary);
    _drawStar(canvas, Offset(cx + 42, cy - 24), 10, HuddlColors.nearBlack);
    _drawStar(canvas, Offset(cx - 30, cy + 38), 8, HuddlColors.primary.withValues(alpha: 0.6));
    _drawStar(canvas, Offset(cx + 36, cy + 32), 12, HuddlColors.primary.withValues(alpha: 0.7));
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color color) {
    final paint = Paint()..color = color;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (i * math.pi / 4);
      final radius = i % 2 == 0 ? r : r * 0.4;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklePainter old) => false;
}

class _PaymentPainter extends CustomPainter {
  const _PaymentPainter({required this.isDark});
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 8;

    // Terminal body
    final termPaint = Paint()..color = const Color(0xFF3A3A3A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 84, height: 62),
        const Radius.circular(8),
      ),
      termPaint,
    );

    // Screen
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 10), width: 60, height: 28),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF199A85), // brand teal
    );

    // Check on screen
    final checkPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final checkPath = Path()
      ..moveTo(cx - 10, cy - 10)
      ..lineTo(cx - 3, cy - 3)
      ..lineTo(cx + 12, cy - 18);
    canvas.drawPath(checkPath, checkPaint);

    // Keypad dots
    for (int row = 0; row < 2; row++) {
      for (int col = 0; col < 3; col++) {
        canvas.drawCircle(
          Offset(cx - 20 + col * 20.0, cy + 12 + row * 12.0),
          3,
          Paint()..color = Colors.white.withValues(alpha: 0.5),
        );
      }
    }

    // Receipt strip
    final receiptPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 18, cy + 30, 36, 22),
        const Radius.circular(2),
      ),
      receiptPaint,
    );
    // Receipt lines
    final linePaint = Paint()
      ..color = HuddlColors.gray300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(cx - 12, cy + 34 + i * 5.0),
        Offset(cx + (i == 2 ? 6 : 12), cy + 34 + i * 5.0),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PaymentPainter old) => false;
}

// ── Skeleton loading widgets ──────────────────────────────────────────────────

class HuddlSkeletonFeed extends StatelessWidget {
  const HuddlSkeletonFeed({super.key, this.cardCount = 3});
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        cardCount,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: HuddlSkeletonCard(),
        ),
      ),
    );
  }
}

/// Profile screen skeleton — avatar strip + 3 stat boxes + 2 section rows.
class HuddlSkeletonProfile extends StatefulWidget {
  const HuddlSkeletonProfile({super.key});

  @override
  State<HuddlSkeletonProfile> createState() => _HuddlSkeletonProfileState();
}

class _HuddlSkeletonProfileState extends State<HuddlSkeletonProfile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        final grad = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [const Color(0xFF2A2A2A), const Color(0xFF3E3E3E), const Color(0xFF2A2A2A)]
              : [const Color(0xFFEEEEEE), const Color(0xFFF8F8F8), const Color(0xFFEEEEEE)],
          stops: [
            (_shimmerCtrl.value - 1).clamp(0.0, 1.0),
            _shimmerCtrl.value.clamp(0.0, 1.0),
            (_shimmerCtrl.value + 1).clamp(0.0, 1.0),
          ],
        );

        Widget box(double w, double h, {double r = 10}) => Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(r),
              ),
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name strip
            Row(children: [
              box(72, 72, r: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  box(140, 16),
                  const SizedBox(height: 8),
                  box(100, 12),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            // Stat strip — 3 boxes
            Row(children: [
              Expanded(child: box(double.infinity, 56, r: 12)),
              const SizedBox(width: 10),
              Expanded(child: box(double.infinity, 56, r: 12)),
              const SizedBox(width: 10),
              Expanded(child: box(double.infinity, 56, r: 12)),
            ]),
            const SizedBox(height: 20),
            // Section header
            box(120, 14),
            const SizedBox(height: 12),
            // Row of small cards
            Row(children: [
              Expanded(child: box(double.infinity, 80, r: 12)),
              const SizedBox(width: 10),
              Expanded(child: box(double.infinity, 80, r: 12)),
            ]),
            const SizedBox(height: 20),
            // Another section header
            box(100, 14),
            const SizedBox(height: 12),
            box(double.infinity, 72, r: 12),
            const SizedBox(height: 10),
            box(double.infinity, 72, r: 12),
          ],
        );
      },
    );
  }
}

class HuddlSkeletonCard extends StatefulWidget {
  const HuddlSkeletonCard({super.key, this.imageHeight = 220});
  final double imageHeight;

  @override
  State<HuddlSkeletonCard> createState() => _HuddlSkeletonCardState();
}

class _HuddlSkeletonCardState extends State<HuddlSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) {
        final grad = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isDark
              ? [
                  const Color(0xFF2A2A2A),
                  const Color(0xFF3E3E3E),
                  const Color(0xFF2A2A2A),
                ]
              : [
                  const Color(0xFFEEEEEE),
                  const Color(0xFFF8F8F8),
                  const Color(0xFFEEEEEE),
                ],
          stops: [
            (_shimmerCtrl.value - 1).clamp(0.0, 1.0),
            _shimmerCtrl.value.clamp(0.0, 1.0),
            (_shimmerCtrl.value + 1).clamp(0.0, 1.0),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo skeleton
            Container(
              height: widget.imageHeight,
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 10),
            // Title line
            Container(
              height: 14,
              width: 180,
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            const SizedBox(height: 6),
            // Subtitle
            Container(
              height: 12,
              width: 240,
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 12,
              width: 140,
              decoration: BoxDecoration(
                gradient: grad,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// HUDDL THREE DOTS LOADER — Airbnb "•••" bounce animation
// =============================================================================
//
// Exact match to Airbnb's loading screen pattern:
//   • 3 circular dots in a horizontal row
//   • Sequential bounce animation: dot 1 → dot 2 → dot 3 → repeat
//   • 360ms per cycle, 120ms stagger between dots
//   • Scale: 1.0 → 1.5 → 1.0 per dot (spring-like feel)
//   • Dots are nearBlack (matches Airbnb's dark dot color)
//
// Usage:
//   HuddlThreeDotsLoader()                         // default nearBlack
//   HuddlThreeDotsLoader(color: Colors.white)       // white on dark bg
//   HuddlThreeDotsLoader(dotSize: 10)               // custom size
// =============================================================================

class HuddlThreeDotsLoader extends StatefulWidget {
  final Color? color;
  final double dotSize;
  final double spacing;

  const HuddlThreeDotsLoader({
    super.key,
    this.color,
    this.dotSize = 8.0,
    this.spacing = 6.0,
  });

  @override
  State<HuddlThreeDotsLoader> createState() => _HuddlThreeDotsLoaderState();
}

class _HuddlThreeDotsLoaderState extends State<HuddlThreeDotsLoader>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _scaleAnims;

  static const int _dotCount = 3;
  static const int _durationMs = 360;
  static const int _staggerMs = 120;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(_dotCount, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: _durationMs),
      );
    });

    _scaleAnims = _controllers.map((ctrl) {
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.55)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.55, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 60,
        ),
      ]).animate(ctrl);
    }).toList();

    // Stagger-start each dot
    for (int i = 0; i < _dotCount; i++) {
      Future.delayed(Duration(milliseconds: i * _staggerMs), () {
        if (mounted) {
          _controllers[i].repeat(
            period: Duration(milliseconds: _durationMs + (_dotCount - 1) * _staggerMs),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.color ?? HuddlColors.nearBlack;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_dotCount, (i) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
          child: AnimatedBuilder(
            animation: _scaleAnims[i],
            builder: (_, __) => Transform.scale(
              scale: _scaleAnims[i].value,
              child: Container(
                width: widget.dotSize,
                height: widget.dotSize,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// =============================================================================
// HUDDL PROCESS LOADING SCREEN — Airbnb "Reviewing payment" style
// =============================================================================
//
// Full-screen white overlay with:
//   • Centered HuddlThreeDotsLoader (••• bounce)
//   • Short message below (e.g. "We're getting your listing ready")
//   • Optional submessage in grey
//
// Usage:
//   showDialog(
//     context: context,
//     barrierDismissible: false,
//     builder: (_) => HuddlProcessLoadingOverlay(
//       message: "We're getting your listing ready",
//     ),
//   );
// =============================================================================

class HuddlProcessLoadingOverlay extends StatelessWidget {
  final String message;
  final String? submessage;

  const HuddlProcessLoadingOverlay({
    super.key,
    required this.message,
    this.submessage,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Airbnb 3-dot bounce
              const HuddlThreeDotsLoader(
                dotSize: 10,
                spacing: 8,
              ),
              const SizedBox(height: 32),
              // Main message
              Text(
                message,
                textAlign: TextAlign.center,
                style: HuddlText.heading(color: HuddlColors.nearBlack),
              ),
              if (submessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  submessage!,
                  textAlign: TextAlign.center,
                  style: HuddlText.body(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
