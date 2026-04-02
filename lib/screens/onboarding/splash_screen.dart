import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

/// ── Huddl Splash Screen ────────────────────────────────────────────────────
/// Design:
///   • White background with soft brand-coloured decorative circles/blobs
///   • Blobs animate slowly bouncing toward the centre logo (ease-in-out loop)
///   • The full Huddl logo (H icon + "huddl" wordmark) centred on screen
///   • Twitter-style animation: logo scales 72 % → 100 % + fade-in
///   • Auto-advances to /onboarding after ≈ 2 s
/// ──────────────────────────────────────────────────────────────────────────

// ── Brand palette (sampled directly from style guide illustration assets) ──
const _kPrimary        = Color(0xFFFCA878); // warm peach – main brand orange
const _kPrimaryLight   = Color(0xFFFFBFA3); // lighter peach
const _kPrimaryLighter = Color(0xFFFFD9C2); // soft blush
const _kPrimaryPale    = Color(0xFFFFECDF); // barely-there blush
const _kBlue           = Color(0xFF2878F0); // style-guide blue
const _kBlueLight      = Color(0xFF508CF0); // lighter style-guide blue
const _kYellow         = Color(0xFFF3C54F); // style-guide yellow (#F3C54F)

// ── Blob definitions ─────────────────────────────────────────────────────
// Each blob has a start position (edge) and an end position (closer to centre).
// The animation oscillates between start and end with a bouncy curve.
class _BlobDef {
  final double startX;  // fraction of screen width  (start = edge position)
  final double startY;  // fraction of screen height
  final double endX;    // fraction (end = nudged toward centre)
  final double endY;
  final double radiusFrac;
  final Color color;
  final double opacity;
  final double phaseOffset; // 0.0–1.0, staggers each blob's bounce cycle

  const _BlobDef({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.radiusFrac,
    required this.color,
    required this.opacity,
    this.phaseOffset = 0.0,
  });
}

const _kBlobs = [
  // Top-left: large blush — bounces toward upper-centre
  _BlobDef(startX: -0.15, startY: -0.10, endX: 0.00, endY: 0.05,
           radiusFrac: 0.32, color: _kPrimaryLighter, opacity: 0.90, phaseOffset: 0.00),
  // Top-right: medium blue — bounces toward upper-centre
  _BlobDef(startX: 1.10,  startY: 0.03,  endX: 0.85, endY: 0.12,
           radiusFrac: 0.24, color: _kBlue,           opacity: 0.55, phaseOffset: 0.15),
  // Top-center-right: small yellow — dips down toward centre
  _BlobDef(startX: 0.82,  startY: -0.07, endX: 0.75, endY: 0.08,
           radiusFrac: 0.13, color: _kYellow,         opacity: 0.75, phaseOffset: 0.30),
  // Top-center-left: tiny pale blush — dips down
  _BlobDef(startX: 0.18,  startY: -0.04, endX: 0.22, endY: 0.07,
           radiusFrac: 0.08, color: _kPrimaryPale,    opacity: 0.85, phaseOffset: 0.45),
  // Bottom-left: medium orange — bounces toward lower-centre
  _BlobDef(startX: -0.12, startY: 0.90,  endX: 0.03, endY: 0.80,
           radiusFrac: 0.26, color: _kPrimary,        opacity: 0.45, phaseOffset: 0.10),
  // Bottom-right: large light blue — bounces toward lower-centre
  _BlobDef(startX: 1.08,  startY: 0.92,  endX: 0.88, endY: 0.82,
           radiusFrac: 0.30, color: _kBlueLight,      opacity: 0.45, phaseOffset: 0.25),
  // Bottom-center: yellow dot — rises toward centre
  _BlobDef(startX: 0.38,  startY: 1.06,  endX: 0.40, endY: 0.90,
           radiusFrac: 0.14, color: _kYellow,         opacity: 0.65, phaseOffset: 0.40),
  // Bottom-center-right: peach dot — rises toward centre
  _BlobDef(startX: 0.72,  startY: 1.04,  endX: 0.68, endY: 0.88,
           radiusFrac: 0.10, color: _kPrimaryLight,   opacity: 0.60, phaseOffset: 0.55),
  // Mid-left: tiny blush — moves right toward centre
  _BlobDef(startX: -0.05, startY: 0.50,  endX: 0.06, endY: 0.50,
           radiusFrac: 0.09, color: _kPrimaryLighter, opacity: 0.65, phaseOffset: 0.20),
  // Mid-right: tiny blue — moves left toward centre
  _BlobDef(startX: 1.03,  startY: 0.58,  endX: 0.92, endY: 0.56,
           radiusFrac: 0.07, color: _kBlue,           opacity: 0.40, phaseOffset: 0.35),
];

// ── Main screen ──────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Logo animation
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;

  // Blob bounce animation — repeating loop
  late final AnimationController _blobCtrl;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Logo controller (one-shot, 900 ms) ───────────────────────────
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);

    _logoScale = Tween<double>(begin: 0.72, end: 1.00).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeInOut),
    );

    // ── Blob controller — slow repeating bounce (2.4 s per cycle) ────
    _blobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true); // bounces back and forth continuously

    // Start logo animation after short delay, then navigate
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _logoCtrl.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/onboarding');
        });
      });
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _blobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Animated blobs ────────────────────────────────────────────
          AnimatedBuilder(
            animation: _blobCtrl,
            builder: (_, __) {
              return CustomPaint(
                painter: _BlobPainter(progress: _blobCtrl.value),
                child: const SizedBox.expand(),
              );
            },
          ),

          // ── Centred animated logo ─────────────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: _logoCtrl,
              builder: (_, child) => FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(scale: _logoScale, child: child),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.10),
                child: Image.asset(
                  'assets/images/logo_huddl_splash.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Blob painter ──────────────────────────────────────────────────────────────
/// Receives the current [progress] (0.0 → 1.0, reversing) from the animation
/// controller and interpolates each blob between its start (edge) and end
/// (toward centre) positions using a bouncy ease-in-out curve.
class _BlobPainter extends CustomPainter {
  final double progress;

  const _BlobPainter({required this.progress});

  // Smooth bounce curve — easeInOut applied to the raw linear progress
  static double _ease(double t) {
    // Cubic ease-in-out: smooth deceleration at both ends
    return t < 0.5
        ? 4 * t * t * t
        : 1 - math.pow(-2 * t + 2, 3) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final blob in _kBlobs) {
      // Apply per-blob phase offset so they don't all move in perfect sync
      final phasedT = _ease(((progress + blob.phaseOffset) % 1.0));

      final x = blob.startX + (blob.endX - blob.startX) * phasedT;
      final y = blob.startY + (blob.endY - blob.startY) * phasedT;

      final paint = Paint()
        ..color = blob.color.withValues(alpha: blob.opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        math.min(size.width, size.height) * blob.radiusFrac,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.progress != progress;
}
