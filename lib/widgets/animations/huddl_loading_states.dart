import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

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
    final subColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;

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

            // Message with animated dots
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  height: 1.4,
                ),
                children: [
                  TextSpan(text: widget.message),
                  TextSpan(
                    text: '.' * _dotCount,
                    style: GoogleFonts.poppins(
                      color: HuddlColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            if (widget.submessage != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.submessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: subColor,
                ),
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
    final c2 = Paint()..color = HuddlColors.teal.withValues(alpha: 0.85);
    final c3 = Paint()..color = HuddlColors.accentAmber.withValues(alpha: 0.85);

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
      ..color = HuddlColors.teal.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 28, cy), width: 20, height: 30),
      -0.8, 1.6, false, wavePaint,
    );
    wavePaint.color = HuddlColors.teal.withValues(alpha: 0.4);
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
    _drawStar(canvas, Offset(cx - 40, cy - 30), 14, HuddlColors.accentAmber);
    _drawStar(canvas, Offset(cx + 42, cy - 24), 10, HuddlColors.teal);
    _drawStar(canvas, Offset(cx - 30, cy + 38), 8, HuddlColors.primary.withValues(alpha: 0.6));
    _drawStar(canvas, Offset(cx + 36, cy + 32), 12, HuddlColors.accentAmber.withValues(alpha: 0.7));
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
