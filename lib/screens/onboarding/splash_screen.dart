import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/onboarding_data_service.dart';

// =============================================================================
// HUDDL SPLASH SCREEN — v2
//
// Design: warm cream background (#FFF8F3), centred H mark logo, simple
// scale+fade entrance. Matches the photography-first, minimal app identity.
//
// Animation sequence:
//   0ms   → logo at scale 0.82, opacity 0.0
//   600ms → logo at scale 1.0,  opacity 1.0  (ease out cubic)
//   1400ms → hold (800ms after logo entrance completes)
//   exit  → screen fades out over 300ms before navigating
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
  late final AnimationController _exitCtrl;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Logo entrance — 600ms ease out ──────────────────────────────
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic),
    );

    // ── Exit fade — 300ms ease in ────────────────────────────────────
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn),
    );

    // ── Sequence: enter → hold 800ms → resolve destination → exit ───
    _logoCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 800), _navigateNext);
    });
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;

    // Resolve destination before fading so the fade-out feels intentional.
    // Mirrors the original navigation logic — explicit logout flag takes
    // priority, then biometric, then onboarding progress.
    String destination = '/onboarding_carousel';
    try {
      final auth = FirebaseAuthService();

      // Explicit logout flag prevents re-entry via cached Firebase token
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
    // Warm cream — exactly matches app scaffold warmCream so the transition
    // from splash to first onboarding screen is seamless with no colour flash.
    const bg = Color(0xFFFFF8F3);

    return Scaffold(
      backgroundColor: bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_logoCtrl, _exitCtrl]),
        builder: (context, _) {
          return Opacity(
            opacity: _exitFade.value,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Warm background ──────────────────────────────────
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
                          child: Image.asset(
                            'assets/images/huddl_logomark.png',
                            width: 120,
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: HuddlColors.primary,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: const Icon(
                                Icons.people,
                                color: Colors.white,
                                size: 56,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Wordmark — fades in at 40% through animation
                      // so the mark always leads the wordmark
                      FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _logoCtrl,
                          curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
                        ),
                        child: Text(
                          'huddl',
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: HuddlColors.nearBlack,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Tagline at bottom — fades in at 60% ──────────────
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _logoCtrl,
                      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
                    ),
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
          );
        },
      ),
    );
  }
}
