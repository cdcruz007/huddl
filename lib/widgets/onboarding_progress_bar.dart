import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// ONBOARDING PROGRESS BAR
//
// Rendered inline — placed in the Column right below the app bar.
// Uses a peach-tinted background so it is always visible against
// the white scaffold background.
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
  String get label    => 'Step $stepNumber of $_totalSteps';
}

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingProgressBar extends StatelessWidget {
  final OnboardingStep step;
  final bool showLabel;

  const OnboardingProgressBar({
    super.key,
    required this.step,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Colours ───────────────────────────────────────────────────────
    // Light mode: peach background so the bar stands out against the
    // white scaffold; dark mode: dark card surface.
    final bg         = isDark ? HuddlColors.darkSurfaceVariant : HuddlColors.primary.withValues(alpha: 0.08);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : HuddlColors.onboardingOrange.withValues(alpha: 0.18);
    const fillColor  = HuddlColors.onboardingOrange;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : HuddlColors.onboardingOrange.withValues(alpha: 0.7);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : HuddlColors.onboardingOrange.withValues(alpha: 0.15);

    return Container(
      width: double.infinity,
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // top border line
          Container(height: 1, color: borderColor),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── label row ─────────────────────────────────────────
                if (showLabel) ...[
                  Row(
                    children: [
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: fillColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(step.progress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                ],

                // ── pill segments ──────────────────────────────────────
                _SegmentedBar(
                  totalSteps:     OnboardingStepInfo._totalSteps,
                  completedSteps: step.stepNumber,
                  trackColor:     trackColor,
                  fillColor:      fillColor,
                ),
              ],
            ),
          ),

          // bottom border line
          Container(height: 1, color: borderColor),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SegmentedBar extends StatelessWidget {
  final int   totalSteps;
  final int   completedSteps;
  final Color trackColor;
  final Color fillColor;

  const _SegmentedBar({
    required this.totalSteps,
    required this.completedSteps,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      const gap = 4.0;
      final segW = (constraints.maxWidth - gap * (totalSteps - 1)) / totalSteps;

      return Row(
        children: List.generate(totalSteps, (i) {
          final idx         = i + 1;
          final isCompleted = idx < completedSteps;
          final isCurrent   = idx == completedSteps;

          return Padding(
            padding: EdgeInsets.only(right: i < totalSteps - 1 ? gap : 0),
            child: _Segment(
              width:       segW,
              isCompleted: isCompleted,
              isCurrent:   isCurrent,
              trackColor:  trackColor,
              fillColor:   fillColor,
            ),
          );
        }),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Segment extends StatelessWidget {
  final double width;
  final bool   isCompleted;
  final bool   isCurrent;
  final Color  trackColor;
  final Color  fillColor;

  const _Segment({
    required this.width,
    required this.isCompleted,
    required this.isCurrent,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final filled = isCompleted || isCurrent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width:  width,
      height: 9,
      decoration: BoxDecoration(
        color: filled
            ? (isCurrent ? fillColor : fillColor.withValues(alpha: 0.75))
            : trackColor,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
