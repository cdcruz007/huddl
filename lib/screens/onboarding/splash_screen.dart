import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../widgets/common/huddl_logo.dart';

// =============================================================================
// HUDDL SPLASH SCREEN v2 — minimal, photography-aligned
//
// Background: warm cream #FFF8F3 — identical to app scaffold warmCream.
// Logo: HuddlLogomark SVG at 110px (H mark only, no wordmark clutter).
// Wordmark: "huddl" Poppins text — fades in at 40% through animation.
// Tagline: fades in at 65% — "The mum and dad next door".
// Animation: scale 0.82→1.0 + fade over 700ms, easeOutCubic.
// Exit: 300ms fade before navigation.
//
// No blobs. No bouncing circles. The logo stands alone.
// =============================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _logoCtrl;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _taglineFade;
  late final AnimationController _exitCtrl;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Logo entrance — 700ms ────────────────────────────────────────
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic),
    );
    _wordmarkFade = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
    _taglineFade = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );

    // ── Exit fade — 300ms ease in ────────────────────────────────────
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn),
    );

    // ── Sequence: enter → hold 700ms → resolve destination → exit ───
    _logoCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 700), _navigateNext);
    });
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;

    // Resolve destination before fading so the exit feels intentional.
    // Explicit logout flag takes priority over cached Firebase token.
    String destination = '/onboarding_carousel';
    try {
      final auth = FirebaseAuthService();
      final explicitlyLoggedOut = await FirebaseAuthService.hasExplicitlyLoggedOut;
      if (!mounted) return;

      if (explicitlyLoggedOut) {
        destination = '/login';
      } else if (auth.isSignedIn) {
        final biometric = BiometricAuthService();
        final biometricEnabled = await biometric.isEnabled;
        destination = biometricEnabled ? '/biometric_lock' : '/home';
      } else {
        final onboarding = OnboardingDataService();
        final hasStarted = onboarding.name != null || onboarding.postcode != null;
        destination = hasStarted ? '/onboarding' : '/onboarding_carousel';
      }
    } catch (_) {
      destination = '/onboarding_carousel';
    }

    if (!mounted) return;
    await _exitCtrl.forward();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, destination);
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Warm cream — matches app scaffold warmCream exactly.
    // Seamless visual transition from splash to first onboarding screen.
    const bg = Color(0xFFFFF8F3);

    return Scaffold(
      backgroundColor: bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_logoCtrl, _exitCtrl]),
        builder: (_, __) => Opacity(
          opacity: _exitFade.value,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: bg),

              // ── Centred logo mark + wordmark ─────────────────────
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // H mark — scale + fade entrance
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const HuddlLogomark(size: 110),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Wordmark — fades in at 40% so mark always leads
                    FadeTransition(
                      opacity: _wordmarkFade,
                      child: Text(
                        'huddl',
                        style: GoogleFonts.poppins(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.nearBlack,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tagline at bottom ─────────────────────────────────
              Positioned(
                bottom: 64,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'The mum and dad next door',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: HuddlColors.textTertiary,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
