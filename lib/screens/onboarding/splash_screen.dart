import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/biometric_auth_service.dart';

// =============================================================================
// HUDDL SPLASH SCREEN — full-bleed primary orange, real SVG logomark
//
// Background: HuddlColors.primary (#FF965C) — full screen, no blobs.
// Logo: huddl_logomark.svg via SvgPicture.asset with white colorFilter.
// Wordmark: huddl_logo_full.svg — white colorFilter makes all fills white.
// Animation: scale 0.82→1.0 + fade 650ms easeOutCubic. Wordmark at 35%.
// Tagline at 65%. Exit 250ms fade. Status bar: white icons on orange.
// =============================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _logoCtrl;
  late final Animation<double>   _logoFade;
  late final Animation<double>   _logoScale;
  late final Animation<double>   _wordmarkFade;
  late final Animation<double>   _taglineFade;
  late final AnimationController _exitCtrl;
  late final Animation<double>   _exitFade;

  @override
  void initState() {
    super.initState();

    // White status bar icons — we are on a solid orange background
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness:     Brightness.dark,
    ));

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _logoFade  = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

    // Wordmark fades in starting at 35% through the logo animation
    _wordmarkFade = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    // Tagline fades in starting at 65%
    _taglineFade = CurvedAnimation(
      parent: _logoCtrl,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );

    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));

    _logoCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 700), _navigateNext);
    });
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;

    // Resolve destination before fading so the exit feels intentional.
    // Explicit logout flag takes priority over cached Firebase token.
    String destination = '/onboarding';
    try {
      final auth = FirebaseAuthService();
      final explicitlyLoggedOut =
          await FirebaseAuthService.hasExplicitlyLoggedOut;
      if (!mounted) return;

      if (explicitlyLoggedOut) {
        destination = '/login';
      } else if (auth.isSignedIn) {
        final biometric = BiometricAuthService();
        final biometricEnabled = await biometric.isEnabled;
        destination = biometricEnabled ? '/biometric_lock' : '/home';
      } else {
        destination = '/onboarding';
      }
    } catch (_) {
      destination = '/onboarding';
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
    // Full-bleed orange — the brand's strongest colour at full saturation.
    // This is the Airbnb/Spotify principle: one background colour, maximum
    // contrast, logo stands alone. No blobs, no gradients, no cream.
    const bg = HuddlColors.primary;

    return Scaffold(
      backgroundColor: bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_logoCtrl, _exitCtrl]),
        builder: (_, __) => Opacity(
          opacity: _exitFade.value,
          child: SizedBox.expand(
            child: ColoredBox(
              color: bg,
              child: Stack(
                alignment: Alignment.center,
                children: [

                  // ── Centred logo group ────────────────────────────────
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        // H mark SVG — white via colorFilter
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: SvgPicture.asset(
                              'assets/icons/huddl_logomark.svg',
                              width: 96,
                              // preserve 107:150 viewBox ratio
                              height: 96 * (150 / 107),
                              colorFilter: const ColorFilter.mode(
                                Colors.white,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        // Full wordmark SVG — white via colorFilter.
                        // BlendMode.srcIn makes ALL fills white:
                        // the orange H mark paths AND the grey "huddl" text
                        // paths both become white — correct on orange bg.
                        FadeTransition(
                          opacity: _wordmarkFade,
                          child: SvgPicture.asset(
                            'assets/icons/huddl_logo_full.svg',
                            height: 38,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                            placeholderBuilder: (_) => Text(
                              'huddl',
                              style: GoogleFonts.poppins(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Tagline — bottom anchored ─────────────────────────
                  Positioned(
                    bottom: 56,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _taglineFade,
                      child: Text(
                        'The mum and dad next door',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.72),
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
        ),
      ),
    );
  }
}
