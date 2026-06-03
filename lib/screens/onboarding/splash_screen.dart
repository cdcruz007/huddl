import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/biometric_auth_service.dart';

// =============================================================================
// HUDDL SPLASH SCREEN — white background, natural brand colours
//
// Background: Colors.white — clean canvas for two-tone lockup.
// Logo: Row of huddl_logomark.svg (orange H mark, #FF975C/#FFA878) +
//   huddl_wordmark.svg (letters only, #1C1C1E nearBlack). No colorFilter —
//   each SVG renders its own native fills.
//   - Logomark: height 48 (107×150 ratio → width ~34px)
//   - Wordmark: viewBox "162 42 397 106" (tightly cropped to letter bbox),
//     height 34 → renders ~127px wide.
// crossAxisAlignment.end bottom-aligns H mark leg bottoms with letter baselines.
// Animation: settle — entire Row starts 15° tilted + scale 0.72, rotates
//   level and springs to 1.0 via 1.06 overshoot. Total splash: 1,100ms.
//   600ms settle + 300ms hold + 200ms exit fade — Airbnb-tier timing.
// Tagline at 78% (468ms).
// Status bar: dark icons on white.
// =============================================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Single controller drives the entire entrance sequence
  late final AnimationController _settleCtrl;

  // H mark rotation: starts +15° clockwise, settles to 0°
  // Using turns (1 turn = 360°): 15° = 15/360 = 0.04167 turns
  late final Animation<double> _rotation;

  // H mark scale: spring overshoot 0.72 → 1.06 → 1.0
  late final Animation<double> _markScale;

  // H mark opacity: 0 → 1 in first 43% of animation (258ms)
  late final Animation<double> _markOpacity;

  // Tagline opacity: fades in from 78% of animation (468ms)
  late final Animation<double> _taglineOpacity;

  late final AnimationController _exitCtrl;
  late final Animation<double>   _exitFade;

  @override
  void initState() {
    super.initState();

    // ── Settle controller — 600ms total entrance ──────────────────────────
    _settleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // ── Rotation: 15° → 0° with easeOutCubic ─────────────────────────────
    // Decelerates smoothly so logo clicks precisely into level position.
    _rotation = Tween<double>(
      begin: 15 / 360,  // 15° expressed as turns
      end:   0.0,
    ).animate(CurvedAnimation(
      parent: _settleCtrl,
      curve: Curves.easeOutCubic,
    ));

    // ── Scale: spring overshoot — 0.72 → 1.06 → 1.0 ─────────────────────
    // First 75% of animation: accelerates past target (small → slightly large)
    // Final 25%: settles back to exact target size
    _markScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.72, end: 1.06)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 75,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_settleCtrl);

    // ── Mark opacity: 0 → 1 in the first 43% of animation (258ms) ────────
    // Fully visible well before rotation completes — no ghost effect
    _markOpacity = CurvedAnimation(
      parent: _settleCtrl,
      curve: const Interval(0.0, 0.43, curve: Curves.easeOut),
    );

    // ── Tagline: fades in from 78% through the settle (468ms) ────────────
    _taglineOpacity = CurvedAnimation(
      parent: _settleCtrl,
      curve: const Interval(0.78, 1.0, curve: Curves.easeOut),
    );

    // ── Start sequence then hold 300ms before navigating ─────────────────
    // 300ms hold = Twitter/X standard — fast and confident, not sluggish
    _settleCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), _navigateNext);
    });

    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),  // was 250
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn));
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
    _settleCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Light mode: white canvas, nearBlack wordmark — original brand treatment.
    // Dark mode: dark background, white wordmark — avoids blinding flash.
    final Color bg = isDark ? HuddlColors.darkBackground : Colors.white;
    final Color wordmarkColor = isDark ? Colors.white : HuddlColors.nearBlack;
    final Color taglineColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : HuddlColors.nearBlack.withValues(alpha: 0.45);

    // Status bar icons: dark on white, light on dark background
    SystemChrome.setSystemUIOverlayStyle(isDark
        ? const SystemUiOverlayStyle(
            statusBarColor:          Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness:     Brightness.dark,
          )
        : const SystemUiOverlayStyle(
            statusBarColor:          Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness:     Brightness.light,
          ));

    return Scaffold(
      backgroundColor: bg,
      body: AnimatedBuilder(
        animation: Listenable.merge([_settleCtrl, _exitCtrl]),
        builder: (_, __) => Opacity(
          opacity: _exitFade.value,
          child: SizedBox.expand(
            child: ColoredBox(
              color: bg,
              child: Stack(
                alignment: Alignment.center,
                children: [

                  // ── Centred lockup — settle animation applied to whole unit ──
                  Center(
                    child: FadeTransition(
                      opacity: _markOpacity,
                      child: RotationTransition(
                        turns: _rotation,
                        child: ScaleTransition(
                          scale: _markScale,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // H mark logomark — renders native orange fills
                              SvgPicture.asset(
                                'assets/icons/huddl_logomark.svg',
                                height: 48,
                                placeholderBuilder: (_) =>
                                    const SizedBox(width: 34, height: 48),
                              ),
                              const SizedBox(width: 12),
                              // "huddl" wordmark — colour-filtered for dark mode
                              SvgPicture.asset(
                                'assets/icons/huddl_wordmark.svg',
                                height: 34,
                                colorFilter: ColorFilter.mode(
                                    wordmarkColor, BlendMode.srcIn),
                                placeholderBuilder: (_) =>
                                    const SizedBox(width: 149, height: 34),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Tagline — bottom anchored ─────────────────────────
                  Positioned(
                    bottom: 56,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: _taglineOpacity,
                      child: Text(
                        'The mum and dad next door',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: taglineColor,
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
