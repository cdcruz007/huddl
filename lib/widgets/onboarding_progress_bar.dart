import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// ONBOARDING PROGRESS BAR
//
// Displays a slim animated progress bar at the bottom of every onboarding
// screen so users can see exactly how far through the sign-up flow they are.
//
// Usage — add to the *bottom* of any onboarding Scaffold body:
//
//   Scaffold(
//     body: SafeArea(
//       child: Column(
//         children: [
//           ...
//           const OnboardingProgressBar(step: OnboardingStep.name),
//         ],
//       ),
//     ),
//   )
//
// The SafeArea wrapping the Column means the bar sits just above the system
// navigation strip.  It is intentionally placed inside SafeArea so that it
// is always visible (not hidden behind gesture bars).
// =============================================================================

// ── Step definitions ──────────────────────────────────────────────────────────
//
// The flow has two branching sub-paths (due_date / child_info) that both
// converge at postcode, so we normalise them to the same step index.
//
// Total visible steps: 11 (excluding the carousel / splash)
//
// 1  name_input
// 2  parent_type
// 3  stage_of_life
// 4  due_date  |  child_info   (same position in the bar — branch A or B)
// 5  postcode
// 6  phone_number
// 7  password
// 8  verification
// 9  welcome_complete
// 10 add_photo
// 11 about_you

enum OnboardingStep {
  name,          // step  1 / 11
  parentType,    // step  2 / 11
  stageOfLife,   // step  3 / 11
  dueDate,       // step  4 / 11
  childInfo,     // step  4 / 11  (same visual position as dueDate)
  postcode,      // step  5 / 11
  phoneNumber,   // step  6 / 11
  password,      // step  7 / 11
  verification,  // step  8 / 11
  welcomeComplete, // step 9 / 11
  addPhoto,      // step 10 / 11
  aboutYou,      // step 11 / 11
}

extension OnboardingStepInfo on OnboardingStep {
  static const int _totalSteps = 11;

  /// 1-based step number used for progress calculation.
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

  /// Progress fraction in [0.0, 1.0].
  double get progress => stepNumber / _totalSteps;

  /// Human-readable label shown below the bar (e.g. "Step 3 of 11").
  String get label => 'Step $stepNumber of $_totalSteps';
}

// ── Widget ────────────────────────────────────────────────────────────────────

class OnboardingProgressBar extends StatelessWidget {
  final OnboardingStep step;

  /// If false, the step counter text is hidden (bar only).
  final bool showLabel;

  const OnboardingProgressBar({
    super.key,
    required this.step,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final progress = step.progress;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : HuddlColors.onboardingOrange.withValues(alpha: 0.15);
    final fillColor = HuddlColors.onboardingOrange;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : HuddlColors.textSecondary;

    return Padding(
      // Horizontal breathing room; 4 px bottom gap so the bar isn't flush
      // against the system navigation bar.
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Segmented dot row ────────────────────────────────────────
          _SegmentedBar(
            progress: progress,
            totalSteps: OnboardingStepInfo._totalSteps,
            completedSteps: step.stepNumber,
            trackColor: trackColor,
            fillColor: fillColor,
          ),
          if (showLabel) ...[
            const SizedBox(height: 6),
            Text(
              step.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: labelColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Segmented bar ─────────────────────────────────────────────────────────────
// Renders one pill per step. Completed steps fill with brand orange;
// the current step is partially filled; future steps are the ghost track.

class _SegmentedBar extends StatelessWidget {
  final double progress;
  final int totalSteps;
  final int completedSteps; // 1-based current step
  final Color trackColor;
  final Color fillColor;

  const _SegmentedBar({
    required this.progress,
    required this.totalSteps,
    required this.completedSteps,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 4.0;
      final segW = (constraints.maxWidth - gap * (totalSteps - 1)) / totalSteps;

      return Row(
        children: List.generate(totalSteps, (i) {
          final stepIndex = i + 1; // 1-based
          final isCompleted = stepIndex < completedSteps;
          final isCurrent   = stepIndex == completedSteps;

          return Padding(
            padding: EdgeInsets.only(right: i < totalSteps - 1 ? gap : 0),
            child: _Segment(
              width: segW,
              isCompleted: isCompleted,
              isCurrent: isCurrent,
              trackColor: trackColor,
              fillColor: fillColor,
            ),
          );
        }),
      );
    });
  }
}

class _Segment extends StatelessWidget {
  final double width;
  final bool isCompleted;
  final bool isCurrent;
  final Color trackColor;
  final Color fillColor;

  const _Segment({
    required this.width,
    required this.isCompleted,
    required this.isCurrent,
    required this.trackColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0,
        end: isCompleted ? 1.0 : (isCurrent ? 0.55 : 0.0),
      ),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) {
        return SizedBox(
          width: width,
          height: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                // Track
                Container(color: trackColor),
                // Fill
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(3),
                      // Subtle glow on current segment
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: fillColor.withValues(alpha: 0.45),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              )
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
