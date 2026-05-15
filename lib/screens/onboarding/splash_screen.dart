import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../../theme/huddl_colors.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/onboarding_data_service.dart';

/// ── Huddl Splash Screen ────────────────────────────────────────────────────
/// Design:
///   • White background with soft brand-coloured decorative circles/blobs
///   • Blobs animate slowly bouncing toward the centre logo (ease-in-out loop)
///   • The full Huddl logo (H icon + "huddl" wordmark) centred on screen
///   • Twitter-style animation: logo scales 72 % → 100 % + fade-in
///   • Auto-advances to /onboarding after ≈ 2 s
/// ──────────────────────────────────────────────────────────────────────────

// ── Brand palette (mapped to HuddlColors) ──
const _kPrimaryLighter = HuddlColors.primaryLight;  // soft blush — mapped to token
const _kPrimaryLight = HuddlColors.primaryLight;
const _kPrimary = HuddlColors.primary;
const _kPrimaryPale = HuddlColors.primaryLight;
const _kYellow = HuddlColors.yellow;
const _kBlueLight = HuddlColors.lightBlue;

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
           radiusFrac: 0.24, color: HuddlColors.lightBlue,           opacity: 0.55, phaseOffset: 0.15),
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
           radiusFrac: 0.07, color: HuddlColors.lightBlue,           opacity: 0.40, phaseOffset: 0.35),
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

    // Start logo animation after short delay, then check auth & navigate.
    // Also set an absolute safety timeout so the splash never hangs.
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _logoCtrl.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          _navigateBasedOnAuth();
        });
      });
    });

    // Absolute safety net: if nothing has navigated within 8 seconds, force
    // navigation so the user never sees a stuck splash.
    Future.delayed(const Duration(seconds: 8), () async {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        // Respect the logout flag even in the safety timeout
        final loggedOut = await FirebaseAuthService.hasExplicitlyLoggedOut;
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          loggedOut ? '/login' : '/onboarding',
        );
      }
    });
  }

  /// Check Firebase Auth state and navigate to the right screen.
  /// If the user is signed in AND has biometric login enabled, show
  /// the biometric prompt before entering the app.
  Future<void> _navigateBasedOnAuth() async {
    try {
      final auth      = FirebaseAuthService();
      final biometric = BiometricAuthService();

      // ── Check if user explicitly logged out ────────────────────────────
      // On iOS the Firebase Auth Keychain token survives app reinstalls,
      // so isSignedIn can be true even after an explicit logout. We use a
      // SharedPreferences flag to distinguish "still actively logged in"
      // from "explicitly logged out — must re-authenticate".
      final explicitlyLoggedOut = await FirebaseAuthService.hasExplicitlyLoggedOut;
      if (!mounted) return;

      if (explicitlyLoggedOut) {
        // User deliberately logged out — require full login again
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      if (auth.isSignedIn) {
        // Check Firestore profile exists
        bool hasProfile = false;
        try {
          hasProfile = await auth.hasUserProfile()
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
        } catch (_) {
          hasProfile = false;
        }
        if (!mounted) return;

        if (hasProfile) {
          // ── Check if this user still needs to complete onboarding ───────
          // Accounts can exist in Firestore with isOnboarding:true when they
          // authenticated but never finished the registration flow (e.g. test
          // accounts that were reset). Route them through onboarding so they
          // can set their name, postcode, parent type, etc.
          bool needsOnboarding = false;
          try {
            final profileData = await auth.getUserProfile()
                .timeout(const Duration(seconds: 5));
            needsOnboarding = (profileData?['isOnboarding'] as bool?) ?? false;
          } catch (_) {
            needsOnboarding = false;
          }
          if (!mounted) return;

          if (needsOnboarding) {
            // Clear any stale local cache so onboarding starts clean
            await OnboardingDataService().clear();
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed('/onboarding');
            return;
          }

          // ── Restore profile from Firestore into local cache ─────────────
          // Critical on fresh installs / after BrowserStorage resets:
          // local SharedPreferences may be empty even though the user has a
          // valid Firestore profile. Restore before entering the app so
          // every screen sees the correct name, postcode, and profile data.
          Map<String, dynamic>? profileData;
          try {
            await auth.restoreProfileFromFirestore()
                .timeout(const Duration(seconds: 5));
            profileData = await auth.getUserProfile()
                .timeout(const Duration(seconds: 5));
          } catch (_) {
            // Non-fatal — app still loads; data will restore on next action
          }
          if (!mounted) return;

          // ── Email verification gate ──────────────────────────────────────
          // If the user has an email address on file but hasn't verified it
          // yet, route them to the pending-verification screen instead of home.
          // Users with no email stored are allowed through (they pre-date the
          // mandatory email requirement and should not be blocked).
          final hasEmail = (profileData?['email'] as String? ?? '').isNotEmpty;
          final emailVerified = (profileData?['emailVerified'] as bool?) ?? false;

          if (hasEmail && !emailVerified) {
            // Populate local cache with stored email so the pending screen
            // can display it masked.
            final storedEmail = (profileData?['email'] as String? ?? '').trim();
            if (storedEmail.isNotEmpty) {
              OnboardingDataService().setEmail(storedEmail);
            }
            if (!mounted) return;
            Navigator.of(context)
                .pushReplacementNamed('/email_pending_verification');
            return;
          }

          // Check if biometric login is enabled for this device
          final biometricEnabled = await biometric.isEnabled;
          final biometricAvailable = await biometric.isAvailable;

          if (biometricEnabled && biometricAvailable) {
            // Show biometric gate — user must authenticate before entering app
            if (!mounted) return;
            Navigator.of(context).pushReplacementNamed('/biometric_lock');
          } else {
            // Returning user, no biometric — go straight to home
            auth.updateLastActive();
            Navigator.of(context).pushReplacementNamed('/home');
          }
        } else {
          // Signed in but NO Firestore profile — stale auth session
          await auth.signOut();
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/login');
        }
      } else {
        // Not signed in at all → could be brand new user or someone who was
        // never registered. Show the onboarding carousel so they can sign up
        // or tap 'Already have an account' to get to login.
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } catch (e) {
      // Any unexpected error → go to onboarding so the app is always usable
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/onboarding');
    }
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
