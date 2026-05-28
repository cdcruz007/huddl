import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/onboarding_progress_bar.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/backend_api_service.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../widgets/huddl_character.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../constants/app_text_styles.dart';

class WelcomeCompleteScreen extends StatelessWidget {
  const WelcomeCompleteScreen({super.key});

  /// Fire welcome email once — non-blocking, backend is idempotent (welcomeEmailSent guard).
  void _fireWelcomeEmail() {
    final onboarding = OnboardingDataService();
    final email = (onboarding.email ?? '').trim();
    if (email.isEmpty) return;
    BackendApiService().sendWelcomeNotification(
      email: email,
      firstName: onboarding.name,
      borough: onboarding.postcode,
    ).catchError((Object e) {
      if (kDebugMode) debugPrint('[WelcomeComplete] welcome email error: $e');
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = OnboardingDataService();
    final groupCount = onboarding.assignedGroupCount;
    final groupNames = onboarding.assignedGroupNames;

    return Scaffold(
      backgroundColor: HuddlColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // -- Huddl logo centered at top --
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: _HuddlLogo(),
            ),

            OnboardingProgressBar(step: OnboardingStep.welcomeComplete),
            const SizedBox(height: 24),

            // -- Title --
            Text(
              'Welcome to Huddl!',
              style: HuddlText.display(color: HuddlColors.nearBlack),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 20),

            // -- SUCCESS banner (green) --
            if (groupCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(
                    color: HuddlColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: HuddlColors.success.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: HuddlColors.success, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: HuddlText.body(color: HuddlColors.success),
                            children: [
                              const TextSpan(text: 'You\'ve been added to '),
                              TextSpan(
                                text: '$groupCount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              TextSpan(
                                text: groupCount == 1
                                    ? ' community group!'
                                    : ' community groups!',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (groupCount > 0) const SizedBox(height: 16),

            // -- Group list (replaces old black box) --
            if (groupNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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
                        style: HuddlText.body(weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      ...groupNames.map(
                        (name) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F7F7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(Icons.people_alt_rounded,
                                      size: 16, color: HuddlColors.textDark),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  style: HuddlText.body(color: HuddlColors.nearBlack),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (groupCount > 0)
              // Fallback: show count if names aren't available yet
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: HuddlColors.divider,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '$groupCount',
                            style: HuddlText.heading(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          groupCount == 1
                              ? 'community group ready for you'
                              : 'community groups ready for you',
                          style: HuddlText.body(color: HuddlColors.nearBlack),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (groupCount > 0) const SizedBox(height: 16),

            // -- Subtitle --
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Before we start, let your neighbours know you!',
                style: HuddlText.body(color: HuddlColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            // -- Let's go! button --
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () async {
                    HuddlAnimations.heavyTap();
                    _fireWelcomeEmail();
                    // 🎉 Tutorial complete celebration overlay
                    try {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid != null) {
                        final doc = await FirebaseFirestore.instance.doc('users/$uid').get();
                        final achievements = (doc.data()?['achievements'] as Map?) ?? {};
                        if (achievements['tutorialComplete'] != true) {
                          await FirebaseFirestore.instance.doc('users/$uid')
                              .set({'achievements': {'tutorialComplete': true}}, SetOptions(merge: true));
                          if (context.mounted) {
                            await HuddlCelebrationOverlay.show(context,
                                message: 'Welcome to Huddl! Your community awaits 🏡');
                          }
                        }
                      }
                    } catch (_) { /* non-critical */ }
                    if (context.mounted) Navigator.pushNamed(context, '/add_photo');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Let\'s go!',
                    style: HuddlText.heading(),
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

// -- Shared Huddl logo --
class _HuddlLogo extends StatelessWidget {
  const _HuddlLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo_huddl_splash.png',
      height: 34,
      fit: BoxFit.contain,
    );
  }
}
