import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/borough_scope_guard.dart';

// =============================================================================
// BOROUGH UI HELPERS (Step 7)
//
// Centralised utility for cross-borough interaction blocking UI.
// Provides consistent user-facing feedback when a hyperlocal rule
// prevents an action: SnackBars, dialogs, and disabled-state checks.
// =============================================================================

class BoroughUiHelpers {
  BoroughUiHelpers._();

  /// The single guard instance.
  static final BoroughScopeGuard _guard = BoroughScopeGuard();

  // ── Quick checks for UI gating ───────────────────────────────────────

  /// Returns true if the user can interact with content from [targetBorough]
  /// for the given [feature]. If false, the UI should disable the action.
  static bool canAct({
    required HuddlFeature feature,
    String? targetBorough,
  }) {
    if (BoroughScopeGuard.isUkWide(feature)) return true;
    if (targetBorough == null || targetBorough.isEmpty) return true;
    return _guard.isSameBorough(targetBorough);
  }

  /// The user's resolved borough, or 'your borough' as fallback.
  static String get userBoroughLabel =>
      _guard.currentBorough ?? 'your borough';

  // ── SnackBar feedback ────────────────────────────────────────────────

  /// Shows a themed SnackBar explaining that the action is limited to
  /// the user's borough. Call this when a tap/action is blocked.
  static void showBlockedSnackBar(
    BuildContext context, {
    required String featureLabel,
    String? targetBorough,
  }) {
    HapticFeedback.heavyImpact();
    final borough = userBoroughLabel;
    final msg = targetBorough != null && targetBorough.isNotEmpty
        ? '$featureLabel is limited to $borough. '
            'You cannot interact with content from $targetBorough.'
        : '$featureLabel is limited to parents in $borough.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.location_off, color: HuddlColors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.white),
              ),
            ),
          ],
        ),
        backgroundColor: HuddlColors.accentAmber.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Confirmation dialog ──────────────────────────────────────────────

  /// Shows a modal dialog explaining the cross-borough restriction.
  /// Returns true if the user taps "OK" (acknowledges).
  static Future<bool> showBlockedDialog(
    BuildContext context, {
    required String featureLabel,
    String? targetBorough,
  }) async {
    final borough = userBoroughLabel;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.location_off,
                color: HuddlColors.accentAmber, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Borough Restriction',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          '$featureLabel is only available within $borough.\n\n'
          'Huddl Connect is a hyper-local community app. To keep '
          'interactions safe and relevant, most features are limited to '
          'parents in your borough.'
          '${targetBorough != null ? "\n\nYou tried to access content from $targetBorough." : ""}',
          style: GoogleFonts.poppins(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('OK, got it',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.primary,
                )),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Inline disabled overlay ──────────────────────────────────────────

  /// Wraps a [child] widget. If [blocked] is true, renders it greyed-out
  /// with an overlay tap that shows the blocked SnackBar.
  static Widget gatedWidget({
    required BuildContext context,
    required Widget child,
    required bool blocked,
    required String featureLabel,
    String? targetBorough,
  }) {
    if (!blocked) return child;

    return GestureDetector(
      onTap: () => showBlockedSnackBar(
        context,
        featureLabel: featureLabel,
        targetBorough: targetBorough,
      ),
      child: Opacity(
        opacity: 0.45,
        child: AbsorbPointer(
          child: child,
        ),
      ),
    );
  }
}
