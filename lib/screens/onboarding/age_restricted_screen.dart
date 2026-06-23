import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';

// =============================================================================
// AGE-1 — Age-restriction block screen
//
// Shown when the user enters a DOB that computes to < 18 years old.
// No back navigation — routes straight to /splash so there is no path to
// retry with a false DOB in the same session.
//
// Design mirrors not_available_screen.dart: white background, centred icon,
// concise copy, single CTA button back to /splash.
// =============================================================================

class AgeRestrictedScreen extends StatelessWidget {
  const AgeRestrictedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      // No WillPopScope needed — Navigator.pushNamedAndRemoveUntil in the CTA
      // clears the stack, and we disable the system back button via PopScope.
      body: PopScope(
        canPop: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.08),

                // ── Icon ────────────────────────────────────────────────────
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: HuddlColors.primary,
                  ),
                ),

                SizedBox(height: size.height * 0.05),

                // ── Heading ──────────────────────────────────────────────────
                Text(
                  'Huddl is for adults',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.25,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 16),

                // ── Body copy ────────────────────────────────────────────────
                Text(
                  'You must be 18 or older to use Huddl. '
                  'This app is a community space for parents and adults '
                  'in the Cambridge area.',
                  style: const TextStyle(
                    fontSize: 15,
                    color: HuddlColors.disabledText,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),

                const Spacer(),

                // ── CTA: back to splash — clears the entire nav stack ───────
                HuddlButton(
                  label: 'Back to start',
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
      ),
    );
  }
}
