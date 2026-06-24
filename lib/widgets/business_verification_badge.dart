import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import '../theme/huddl_icons.dart';
import '../constants/app_text_styles.dart';

// =============================================================================
// BUSINESS VERIFICATION BADGE  —  ANN-1 / sole-trader trust  (read-only)
//
// Renders one of three states:
//
//   businessVerified == true
//     → VERIFIED  — filled teal surface, sealCheck fill icon, "Verified"
//       Signals registry verification (Companies House / HMRC VAT).
//
//   businessVerified == false && businessSelfDeclared == true
//     → SELF-DECLARED  — outlined border only (no fill), muted grey,
//       info outline icon, "Self-declared"
//       Signals sole-trader declaration ONLY — NOT a trust signal.
//
//   both false
//     → SizedBox.shrink()  — render nothing, no layout space consumed.
//
// NON-NEGOTIABLE RULES (ANN-1):
//   • Self-declared MUST NOT use: filled background, success/teal colour,
//     sealCheck / shieldCheck icon, or the word "Verified".
//   • businessVerified is checked FIRST — mutual exclusivity enforced here.
//   • Widget is intentionally StatelessWidget — all state lives in caller.
//
// USAGE:
//   BusinessVerificationBadge(
//     businessVerified:     _businessVerified,
//     businessSelfDeclared: _businessSelfDeclared,
//     businessName:         _businessName,   // optional; unused in badge itself
//   )
// =============================================================================

class BusinessVerificationBadge extends StatelessWidget {
  final bool businessVerified;
  final bool businessSelfDeclared;

  /// Verified business name — accepted for API symmetry / future tooltip use.
  /// Not rendered in the badge text itself (caller owns name display).
  final String? businessName;

  const BusinessVerificationBadge({
    super.key,
    required this.businessVerified,
    required this.businessSelfDeclared,
    this.businessName,
  });

  @override
  Widget build(BuildContext context) {
    // ── State 1: registry-verified ─────────────────────────────────────────
    if (businessVerified) {
      return _VerifiedBadge();
    }

    // ── State 2: sole-trader self-declaration ──────────────────────────────
    if (businessSelfDeclared) {
      return _SelfDeclaredBadge();
    }

    // ── State 3: no badge ──────────────────────────────────────────────────
    return const SizedBox.shrink();
  }
}

// ─── Verified variant ─────────────────────────────────────────────────────────
// FILLED teal surface — maximum trust signal.
// Icon: PhosphorIconsFill.sealCheck  (HuddlIcons.verifiedFill)
// Label: "Verified"
// Colour: HuddlColors.brandTeal (= success = #199A85)

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: HuddlColors.tealBg,           // filled — teal surface
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: HuddlColors.brandTeal.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            HuddlIcons.verifiedFill,          // sealCheck fill — trust icon
            size: 13,
            color: HuddlColors.brandTeal,
          ),
          const SizedBox(width: 5),
          Text(
            'Verified',
            style: HuddlText.caption(
              weight: FontWeight.w700,
              color: HuddlColors.brandTeal,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Self-declared variant ────────────────────────────────────────────────────
// OUTLINED ONLY — no fill, no teal, no check/shield icon.
// Icon: PhosphorIconsRegular.info  (HuddlIcons.info)
// Label: "Self-declared"
// Colour: HuddlColors.textSecondary (muted grey #6C6C6C)
//
// INTENTIONALLY muted so it cannot be confused with the verified badge.

class _SelfDeclaredBadge extends StatelessWidget {
  const _SelfDeclaredBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.transparent,            // no fill — outline only
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: HuddlColors.neutral300,      // muted grey border
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            HuddlIcons.info,                  // info outline — NOT a check/shield
            size: 13,
            color: HuddlColors.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            'Self-declared',
            style: HuddlText.caption(
              weight: FontWeight.w500,         // lighter weight than verified
              color: HuddlColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
