import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// ONBOARDING PROGRESS BAR
//
// Rendered inline — placed directly in the Column, right below the app bar.
// No Material/SafeArea wrappers so it always renders at its natural height.
//
// Steps:
//  1  name_input
//  2  parent_type
//  3  stage_of_life
//  4  due_date | child_info  (same visual slot)
//  5  postcode
//  6  phone_number
//  7  password
//  8  verification
//  9  welcome_complete
// 10  add_photo
// 11  about_you
// =============================================================================

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

// ── Widget ────────────────────────────────────────────────────────────────────

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
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bg          = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final trackColor  = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : const Color(0xFFE0E0E0);
    const fillColor   = HuddlColors.onboardingOrange;
    final labelColor  = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF8E8E93);
    final divider     = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEEEEEE);

    return Container(
      width: double.infinity,
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── thin top divider ──────────────────────────────────────────
          Container(height: 1, color: divider),

          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── label row ────────────────────────────────────────────
                if (showLabel) ...[
                  Row(
                    children: [
                      Text(
                        step.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fillColor,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const Spacer(),
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
                  const SizedBox(height: 8),
                ],

                // ── segmented pill bar ────────────────────────────────────
                _SegmentedBar(
                  totalSteps:     OnboardingStepInfo._totalSteps,
                  completedSteps: step.stepNumber,
                  trackColor:     trackColor,
                  fillColor:      fillColor,
                ),
              ],
            ),
          ),

          // ── thin bottom divider ───────────────────────────────────────
          Container(height: 1, color: divider),
        ],
      ),
    );
  }
}

// ── Segmented bar ─────────────────────────────────────────────────────────────

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

// ── Single segment ────────────────────────────────────────────────────────────

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

    return SizedBox(
      width:  width,
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            // ── empty track ──────────────────────────────────────────────
            Container(color: trackColor),
            // ── filled portion ───────────────────────────────────────────
            if (filled)
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                color: isCompleted
                    ? fillColor.withValues(alpha: 0.8)
                    : fillColor,
              ),
          ],
        ),
      ),
    );
  }
}
