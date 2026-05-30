import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// ONBOARDING PROGRESS BAR — minimal
//
// A single thin animated line at the top of each onboarding screen.
// No labels. No percentage. No background band. No border lines.
// 3px height. Orange fill on light track. Animates smoothly between steps.
//
// Reference: Spotify (progress dots), Airbnb (thin line, no label).
// Rule: the progress indicator should be noticed subconsciously,
//       not consciously. It should not compete with the screen content.
//
// Steps:
//  1  name_input        6  phone_number
//  2  parent_type       7  password
//  3  stage_of_life     8  verification
//  4  due_date |        9  welcome_complete
//     child_info       10  add_photo
//  5  postcode         11  about_you
// =============================================================================

enum OnboardingStep {
  name,
  parentType,
  stageOfLife,
  dueDate,
  childInfo,
  postcode,
  phoneNumber,
  password,
  verification,
  welcomeComplete,
  addPhoto,
  aboutYou,
}

extension OnboardingStepInfo on OnboardingStep {
  static const int _totalSteps = 11;

  int get stepNumber {
    switch (this) {
      case OnboardingStep.name:             return 1;
      case OnboardingStep.parentType:       return 2;
      case OnboardingStep.stageOfLife:      return 3;
      case OnboardingStep.dueDate:          return 4;
      case OnboardingStep.childInfo:        return 4;
      case OnboardingStep.postcode:         return 5;
      case OnboardingStep.phoneNumber:      return 6;
      case OnboardingStep.password:         return 7;
      case OnboardingStep.verification:     return 8;
      case OnboardingStep.welcomeComplete:  return 9;
      case OnboardingStep.addPhoto:         return 10;
      case OnboardingStep.aboutYou:         return 11;
    }
  }

  double get progress => stepNumber / _totalSteps;
}

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingProgressBar extends StatelessWidget {
  final OnboardingStep step;
  // showLabel kept for API compatibility — ignored, label is never shown
  final bool showLabel;

  const OnboardingProgressBar({
    super.key,
    required this.step,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : HuddlColors.primary.withValues(alpha: 0.12);

    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (_, constraints) {
          return Stack(
            children: [
              // Track — full width
              Container(
                width: constraints.maxWidth,
                height: 3,
                color: trackColor,
              ),
              // Fill — animated width
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                width: constraints.maxWidth * step.progress,
                height: 3,
                color: HuddlColors.primary,
              ),
            ],
          );
        },
      ),
    );
  }
}
