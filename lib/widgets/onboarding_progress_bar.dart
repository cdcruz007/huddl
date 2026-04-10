import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// ONBOARDING PROGRESS BAR
//
// Placed in Scaffold.bottomNavigationBar on every onboarding screen so it is
// always visible — keyboard-open or not.  Screens must also set:
//
//   resizeToAvoidBottomInset: false
//
// so the keyboard cannot compress the Scaffold body and hide the bar.
// =============================================================================

// ── Step definitions ──────────────────────────────────────────────────────────
//
// Total visible steps: 11
// 1  name_input
// 2  parent_type
// 3  stage_of_life
// 4  due_date | child_info  (same visual slot — branch A or B)
// 5  postcode
// 6  phone_number
// 7  password
// 8  verification
// 9  welcome_complete
// 10 add_photo
// 11 about_you

enum OnboardingStep {
  name,            // step  1 / 11
  parentType,      // step  2 / 11
  stageOfLife,     // step  3 / 11
  dueDate,         // step  4 / 11
  childInfo,       // step  4 / 11  (same visual position as dueDate)
  postcode,        // step  5 / 11
  phoneNumber,     // step  6 / 11
  password,        // step  7 / 11
  verification,    // step  8 / 11
  welcomeComplete, // step  9 / 11
  addPhoto,        // step 10 / 11
  aboutYou,        // step 11 / 11
}

extension OnboardingStepInfo on OnboardingStep {
  static const int _totalSteps = 11;

  /// 1-based step number.
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

  /// Label shown beside the bar.
  String get label => 'Step $stepNumber of $_totalSteps';
}

// ── Widget ────────────────────────────────────────────────────────────────────

class OnboardingProgressBar extends StatelessWidget {
  final OnboardingStep step;

  /// When false the "Step X of Y" text is hidden.
  final bool showLabel;

  const OnboardingProgressBar({
    super.key,
    required this.step,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Colours — deliberately high-contrast so the bar is impossible to miss
    final bg         = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFE8E8E8); // solid light grey — clearly visible
    const fillColor  = HuddlColors.onboardingOrange;
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF8E8E93);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEEEEEE);

    return Material(
      color: bg,
      elevation: 0,
      child: SafeArea(
        top: false, // only apply bottom safe-area inset
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top divider ──────────────────────────────────────────
            Container(height: 1, color: dividerColor),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Step label row ───────────────────────────────────
                  if (showLabel)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Text(
                            step.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: fillColor,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const Spacer(),
                          // Percentage text
                          Text(
                            '${(step.progress * 100).round()}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: labelColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── Segmented pill bar ───────────────────────────────
                  _SegmentedBar(
                    totalSteps: OnboardingStepInfo._totalSteps,
                    completedSteps: step.stepNumber,
                    trackColor: trackColor,
                    fillColor: fillColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Segmented bar ─────────────────────────────────────────────────────────────

class _SegmentedBar extends StatelessWidget {
  final int totalSteps;
  final int completedSteps; // 1-based current step
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
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 5.0;
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

// ── Single segment ────────────────────────────────────────────────────────────

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
        end: isCompleted ? 1.0 : (isCurrent ? 1.0 : 0.0),
      ),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) {
        return SizedBox(
          width: width,
          height: 8, // taller — clearly visible
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // Track (empty segment)
                Container(color: trackColor),
                // Fill (completed / current)
                if (value > 0)
                  FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? fillColor
                            : fillColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
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
