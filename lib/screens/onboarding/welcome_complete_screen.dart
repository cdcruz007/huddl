import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/onboarding_progress_bar.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/backend_api_service.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/huddl_character.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/huddl_button.dart';

class WelcomeCompleteScreen extends StatefulWidget {
  const WelcomeCompleteScreen({super.key});

  @override
  State<WelcomeCompleteScreen> createState() => _WelcomeCompleteScreenState();
}

class _WelcomeCompleteScreenState extends State<WelcomeCompleteScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// Fire welcome email once — non-blocking, backend is idempotent (welcomeEmailSent guard).
  void _fireWelcomeEmail() {
    final onboarding = OnboardingDataService();
    final email = (onboarding.email ?? '').trim();
    if (email.isEmpty) return;
    BackendApiService()
        .sendWelcomeNotification(
          email: email,
          firstName: onboarding.name,
          borough: onboarding.postcode,
        )
        .catchError((Object e) {
      if (kDebugMode) debugPrint('[WelcomeComplete] welcome email error: $e');
      return null;
    });
  }

  void _navigateNext() {
    if (!mounted) return;
    Navigator.pushNamed(context, '/add_photo');
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _ctrl.forward();
    // Auto-navigate after 4 seconds if user hasn't tapped
    Future.delayed(const Duration(seconds: 4), _navigateNext);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleCtaTap() async {
    HuddlAnimations.heavyTap();
    _fireWelcomeEmail();
    // 🎉 Tutorial complete celebration overlay
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc =
            await FirebaseFirestore.instance.doc('users/$uid').get();
        final achievements =
            (doc.data()?['achievements'] as Map?) ?? {};
        if (achievements['tutorialComplete'] != true) {
          await FirebaseFirestore.instance.doc('users/$uid').set(
            {'achievements': {'tutorialComplete': true}},
            SetOptions(merge: true),
          );
          if (mounted) {
            await HuddlCelebrationOverlay.show(
              context,
              message: 'Welcome to Huddl! Your community awaits 🏡',
            );
          }
        }
      }
    } catch (_) {
      /* non-critical */
    }
    _navigateNext();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = OnboardingDataService();
    final name = onboarding.name ?? 'there';
    final borough = onboarding.borough ?? 'your area';
    final groupCount = onboarding.assignedGroupCount;
    final groupNames = onboarding.assignedGroupNames;

    // Celebration scale animation — clamp prevents easeOutBack overshoot crash
    final scaleAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
    );
    final headingFadeAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );
    final cardFadeAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Logo + progress bar ───────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: _HuddlLogo(),
            ),
            OnboardingProgressBar(step: OnboardingStep.welcomeComplete),
            const SizedBox(height: 32),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Celebration graphic — yellow circle with 🎉 ───────
                    AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => Transform.scale(
                        scale: scaleAnim.value
                            .clamp(0.0, 1.15), // guard overshoot
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(
                            color: HuddlColors.yellowSoft,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '🎉',
                              style: TextStyle(fontSize: 52),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Personalised heading ──────────────────────────────
                    FadeTransition(
                      opacity: headingFadeAnim,
                      child: Text(
                        'Welcome to $borough,\n$name! 👋',
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.nearBlack,
                          height: 1.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Group assignment — infoBluePale card ──────────────
                    if (groupCount > 0)
                      FadeTransition(
                        opacity: cardFadeAnim,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: HuddlColors.infoBluePale,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.people,
                                color: HuddlColors.infoBlue,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "You've been added to $groupCount local "
                                  "group${groupCount > 1 ? 's' : ''} "
                                  "in $borough. Say hello!",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: HuddlColors.infoBlue,
                                    fontWeight: FontWeight.w500,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Group name list (if available) ────────────────────
                    if (groupNames.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      FadeTransition(
                        opacity: cardFadeAnim,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: HuddlColors.divider,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your groups',
                                style:
                                    HuddlText.body(weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 10),
                              ...groupNames.map(
                                (gName) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: HuddlColors.infoBluePale,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.people_alt_rounded,
                                            size: 16,
                                            color: HuddlColors.infoBlue,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          gName,
                                          style: HuddlText.body(
                                            color: HuddlColors.nearBlack,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Subtext ───────────────────────────────────────────
                    Text(
                      'Your neighbours are waiting.',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: HuddlColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Celebrate CTA ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: HuddlButton(
                label: 'Explore $borough →',
                variant: HuddlButtonVariant.celebrate,
                fullWidth: true,
                onPressed: _handleCtaTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared Huddl logo ─────────────────────────────────────────────────────────
class _HuddlLogo extends StatelessWidget {
  const _HuddlLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/huddl_logomark.png',
      height: 40,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HuddlColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.people, color: Colors.white, size: 22),
      ),
    );
  }
}
