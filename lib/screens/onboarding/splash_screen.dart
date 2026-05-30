import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../theme/huddl_colors.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/biometric_auth_service.dart';

// =============================================================================
// HUDDL SPLASH SCREEN v4 — dotLottie animated logo
//
// Background  : white
// Centre      : logo.lottie (182×49 viewport, 8.5s @ 60fps, 1 play-through)
//               Rendered at width 220px (height scales proportionally ~59px)
// Tagline     : "The mum and dad next door" — fades in at 60% of animation
// Exit        : navigates on animation complete (or 9s safety timeout)
// =============================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late final AnimationController _lottieCtrl;
  late final AnimationController _taglineCtrl;
  late final Animation<double> _taglineFade;
  late final AnimationController _exitCtrl;
  late final Animation<double> _exitFade;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── Lottie controller — driven by the animation duration ─────────
    // Duration is set in onLoaded callback once the composition is known.
    _lottieCtrl = AnimationController(vsync: this);

    // ── Tagline fade — 400ms ─────────────────────────────────────────
    _taglineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _taglineFade = CurvedAnimation(
      parent: _taglineCtrl,
      curve: Curves.easeOut,
    );

    // ── Exit fade — 300ms ────────────────────────────────────────────
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn),
    );

    // Safety timeout — navigate if Lottie fails to fire completion
    Future.delayed(const Duration(milliseconds: 9500), () {
      if (mounted && !_navigated) _navigateNext();
    });
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieCtrl.duration = composition.duration;
    _lottieCtrl.forward();

    // Fade tagline in at 60% through the animation
    final taglineDelay = composition.duration * 0.60;
    Future.delayed(taglineDelay, () {
      if (mounted) _taglineCtrl.forward();
    });

    // Navigate when animation completes
    _lottieCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && !_navigated) {
        _navigateNext();
      }
    });
  }

  Future<void> _navigateNext() async {
    if (_navigated || !mounted) return;
    _navigated = true;

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
    _lottieCtrl.dispose();
    _taglineCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: AnimatedBuilder(
        animation: _exitCtrl,
        builder: (_, child) => Opacity(
          opacity: _exitFade.value,
          child: child,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Lottie logo — centred ────────────────────────────────
            Center(
              child: Lottie.asset(
                'assets/icons/logo_animation.json',
                controller: _lottieCtrl,
                width: 220,
                // height derives from 182×49 aspect ratio → ~59px
                fit: BoxFit.contain,
                onLoaded: _onLottieLoaded,
                // Fallback while loading
                frameBuilder: (ctx, child, composition) {
                  if (composition == null) {
                    return const SizedBox(width: 220, height: 59);
                  }
                  return child;
                },
              ),
            ),

            // ── Tagline at bottom ────────────────────────────────────
            Positioned(
              bottom: 64,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _taglineFade,
                child: Text(
                  'The mum and dad next door',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: HuddlColors.textTertiary,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
