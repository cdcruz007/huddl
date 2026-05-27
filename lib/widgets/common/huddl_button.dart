import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

/// Huddl Design Language System — canonical button component.
///
/// Variants:
///   primary     — orange fill, white text. Main CTA.
///   secondary   — white fill, nearBlack 1.5px border. Optional action.
///   confirmed   — nearBlack fill, white text. Done / completion state.
///   destructive — text-only, error red. Destructive actions.
///   ghost       — text-only, orange text. Inline links, "See all", etc.
///
/// Spec: 52px height, 14px radius, 16px/w600 Poppins, 0 elevation.
enum HuddlButtonVariant { primary, secondary, confirmed, destructive, ghost }

class HuddlButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final HuddlButtonVariant variant;
  final bool isLoading;
  final bool fullWidth;
  final IconData? leadingIcon;

  const HuddlButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = HuddlButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = true,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 52,
      child: _buildButton(context),
    );
  }

  Widget _buildButton(BuildContext context) {
    switch (variant) {
      case HuddlButtonVariant.primary:
        return ElevatedButton(
          onPressed: onPressed == null ? null : _handleTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: HuddlColors.primary,
            disabledBackgroundColor: const Color(0xFFEEEEEE),
            foregroundColor: Colors.white,
            disabledForegroundColor: const Color(0xFF9E9E9E),
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          child: _child(Colors.white, const Color(0xFF9E9E9E)),
        );

      case HuddlButtonVariant.secondary:
        return OutlinedButton(
          onPressed: onPressed == null ? null : _handleTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1C1C1E),
            side: const BorderSide(color: Color(0xFF1C1C1E), width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          child: _child(const Color(0xFF1C1C1E), const Color(0xFF9E9E9E)),
        );

      case HuddlButtonVariant.confirmed:
        return ElevatedButton(
          onPressed: onPressed == null ? null : _handleTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1C1C1E),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          child: _child(Colors.white, Colors.white),
        );

      case HuddlButtonVariant.destructive:
        return TextButton(
          onPressed: onPressed == null ? null : _handleTap,
          style: TextButton.styleFrom(
            foregroundColor: HuddlColors.error,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          child: _child(HuddlColors.error, HuddlColors.error),
        );

      case HuddlButtonVariant.ghost:
        return TextButton(
          onPressed: onPressed == null ? null : _handleTap,
          style: TextButton.styleFrom(
            foregroundColor: HuddlColors.primary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
          child: _child(HuddlColors.primary, HuddlColors.primary),
        );
    }
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    onPressed?.call();
  }

  Widget _child(Color textColor, Color disabledColor) {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(textColor),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
