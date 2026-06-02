import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/huddl_character.dart';


/// Shown when a user enters a postcode outside the Cambridge launch area.
/// Follows the same visual language as all onboarding screens:
/// white background, illustration centred, concise warm copy, single CTA.
class NotAvailableScreen extends StatelessWidget {
  const NotAvailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              // ── Top spacer ────────────────────────────────────────────
              SizedBox(height: size.height * 0.06),

              // ── Illustration ───────────────────────────────────────────
              const Expanded(
                child: Center(
                  child: WarmCircleIllustration(
                    assetPath: 'assets/illustrations/location_community.webp',
                    size: 160,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Heading ────────────────────────────────────────────────
              Text(
                'Coming soon to your area!',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // ── Body copy ──────────────────────────────────────────────
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 15,
                    color: HuddlColors.disabledText,
                    height: 1.6,
                  ),
                  children: [
                    TextSpan(
                      text:
                          'Hi, we are excited you want to be part of the community! '
                          'We have not launched in your borough yet, so please go to '
                          'our website and join our waiting list:',
                    ),
                    TextSpan(
                      text: 'www.huddlparents.com',
                      style: TextStyle(
                        color: HuddlColors.onboardingOrange,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: HuddlColors.onboardingOrange,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' We are working hard to get to your area and will '
                          'reach out to let you know when we have. Stay tuned!',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── OK button → back to splash ─────────────────────────────
              HuddlButton(
                label: 'OK',
                variant: HuddlButtonVariant.primary,
                fullWidth: true,
                onPressed: () {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/splash',
                    (route) => false,
                  );
                },
              ),

              SizedBox(height: size.height * 0.05),
            ],
          ),
        ),
      ),
    );
  }
}
