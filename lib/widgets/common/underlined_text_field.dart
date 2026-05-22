import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../constants/app_text_styles.dart';

class UnderlinedTextField extends StatelessWidget {
  final String? label;
  final String? hintText;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final int maxLines;

  const UnderlinedTextField({
    super.key,
    this.label,
    this.hintText,
    this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTextStyles.inputLabel.copyWith(
              color: HuddlColors.textDark,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          onChanged: onChanged,
          maxLines: maxLines,
          style: AppTextStyles.body1.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppTextStyles.inputHint,
            suffixIcon: suffixIcon,
            errorText: errorText,
            filled: true,
            fillColor: context.hc.inputBg, // Light gray background
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.divider, width: 2),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.primary, width: 2),
            ),
            errorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.error, width: 1),
            ),
            focusedErrorBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.error, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
          ),
        ),
      ],
    );
  }
}
