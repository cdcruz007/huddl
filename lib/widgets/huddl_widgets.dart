import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/member_photo_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SIMPLE TIME PICKER — scroll-wheel bottom sheet replacing complex clock dial
// ═══════════════════════════════════════════════════════════════════════════════

/// Shows a simple scroll-wheel time picker bottom sheet.
/// Returns the selected [TimeOfDay] or null if cancelled.
Future<TimeOfDay?> showSimpleTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (ctx) => _SimpleTimePickerSheet(initialTime: initialTime),
  );
}

class _SimpleTimePickerSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  const _SimpleTimePickerSheet({required this.initialTime});

  @override
  State<_SimpleTimePickerSheet> createState() => _SimpleTimePickerSheetState();
}

class _SimpleTimePickerSheetState extends State<_SimpleTimePickerSheet> {
  late int _selectedHour;
  late int _selectedMinute;
  late bool _isAM;

  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final h24 = widget.initialTime.hour;
    _isAM = h24 < 12;
    _selectedHour = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    _selectedMinute = widget.initialTime.minute;
    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  TimeOfDay get _resultTime {
    int h24 = _selectedHour;
    if (_isAM) {
      if (h24 == 12) h24 = 0;
    } else {
      if (h24 != 12) h24 += 12;
    }
    return TimeOfDay(hour: h24, minute: _selectedMinute);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header with Cancel / Done
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      alignment: Alignment.centerLeft,
                      child: Text('Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: context.hc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  Text('Select time',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, _resultTime),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      alignment: Alignment.centerRight,
                      child: Text('Done',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Scroll wheels
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // Hour wheel
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _hourController,
                      itemExtent: 44,
                      perspective: 0.003,
                      diameterRatio: 1.5,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (i) =>
                          setState(() => _selectedHour = i + 1),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 12,
                        builder: (ctx, i) {
                          final h = i + 1;
                          final selected = h == _selectedHour;
                          return Center(
                            child: Text(
                              h.toString(),
                              style: GoogleFonts.poppins(
                                fontSize: selected ? 22 : 16,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? HuddlColors.primary
                                    : HuddlColors.textHint,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Colon separator
                  Text(':',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                  ),
                  // Minute wheel
                  Expanded(
                    child: ListWheelScrollView.useDelegate(
                      controller: _minuteController,
                      itemExtent: 44,
                      perspective: 0.003,
                      diameterRatio: 1.5,
                      physics: const FixedExtentScrollPhysics(),
                      onSelectedItemChanged: (i) =>
                          setState(() => _selectedMinute = i),
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 60,
                        builder: (ctx, i) {
                          final selected = i == _selectedMinute;
                          return Center(
                            child: Text(
                              i.toString().padLeft(2, '0'),
                              style: GoogleFonts.poppins(
                                fontSize: selected ? 22 : 16,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? HuddlColors.primary
                                    : HuddlColors.textHint,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // AM / PM toggle
                  SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _isAM = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isAM
                                  ? HuddlColors.primary
                                  : context.hc.scaffold,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('AM',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isAM
                                    ? Colors.white
                                    : HuddlColors.textHint,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => setState(() => _isAM = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: !_isAM
                                  ? HuddlColors.primary
                                  : context.hc.scaffold,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('PM',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: !_isAM
                                    ? Colors.white
                                    : HuddlColors.textHint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Primary gradient button matching Figma design
class HuddlPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;

  const HuddlPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: onPressed != null ? HuddlColors.primary : HuddlColors.gray300,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(24),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.hc.surface,
                    ),
                  )
                : Text(
                    text,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.hc.surface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Secondary outlined button
class HuddlSecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color borderColor;

  const HuddlSecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.borderColor = HuddlColors.divider,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: borderColor, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: borderColor,
          ),
        ),
      ),
    );
  }
}

/// Huddl text input field matching Figma
class HuddlTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final TextInputType? keyboardType;
  final int maxLines;

  const HuddlTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType,
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
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: context.hc.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            prefixIcon: prefixIcon,
          ),
        ),
      ],
    );
  }
}

/// Avatar with orange border
class HuddlAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final bool hasBorder;
  /// Used to select John.png (dad) or Emma.png (mum/other) when no photo.
  final String? parentType;

  const HuddlAvatar({
    super.key,
    this.imageUrl,
    this.size = 48,
    this.hasBorder = false,
    this.parentType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: hasBorder
            ? Border.all(color: HuddlColors.primary, width: 2)
            : null,
        color: HuddlColors.primary.withValues(alpha: 0.08),
      ),
      child: ClipOval(
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _defaultAvatar(),
              )
            : _defaultAvatar(),
      ),
    );
  }

  Widget _defaultAvatar() {
    final asset = MemberPhotoService.getDefaultAvatar(parentType: parentType);
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Center(
        child: Icon(Icons.person, size: size * 0.5, color: HuddlColors.primary),
      ),
    );
  }
}

/// Section header with optional action
class HuddlSectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  const HuddlSectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
        if (actionText != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionText!,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: HuddlColors.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

/// Chip / Tag widget
class HuddlChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? textColor;

  const HuddlChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (backgroundColor ?? HuddlColors.primary)
              : context.hc.scaffold,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: isSelected
                ? (textColor ?? HuddlColors.white)
                : HuddlColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Search bar widget
class HuddlSearchBar extends StatelessWidget {
  final String hint;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  const HuddlSearchBar({
    super.key,
    this.hint = 'Search',
    this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.hc.scaffold,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search, size: 20, color: context.hc.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: context.hc.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                hintStyle: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textTertiary,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            trailing!,
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet handle
class HuddlBottomSheetHandle extends StatelessWidget {
  const HuddlBottomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 8, bottom: 16),
        decoration: BoxDecoration(
          color: HuddlColors.gray300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Card with image at top
class HuddlImageCard extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double imageHeight;

  const HuddlImageCard({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.imageHeight = 120,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF7F7F7),
                  child: const Center(
                    child: Icon(Icons.image, color: HuddlColors.textDark, size: 32),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: context.hc.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Universal member avatar that resolves profile photos from:
/// 1. Explicit imageUrl (data-URI, http, blob, asset)
/// 2. Member name lookup via MemberPhotoService
/// 3. Falls back to coloured circle with initial letter
class MemberAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl; // explicit override
  final double size;
  final Color? accentColor;
  final bool showOnlineDot;
  final bool isOnline;
  /// Used to select John.png (dad) or Emma.png (mum/other) when no photo.
  final String? parentType;

  const MemberAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.accentColor,
    this.showOnlineDot = false,
    this.isOnline = false,
    this.parentType,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve photo: explicit url > name lookup
    final resolvedUrl = imageUrl ?? MemberPhotoService.getPhotoByName(name);
    final color = accentColor ?? HuddlColors.primary;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    Widget avatar;

    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      if (resolvedUrl.startsWith('data:')) {
        // Base64 data-URI (user-uploaded photos)
        try {
          final parts = resolvedUrl.split(',');
          if (parts.length > 1) {
            final bytes = base64Decode(parts[1]);
            avatar = ClipOval(
              child: Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(color, initial),
              ),
            );
          } else {
            avatar = _fallback(color, initial);
          }
        } catch (_) {
          avatar = _fallback(color, initial);
        }
      } else if (resolvedUrl.startsWith('http') ||
          resolvedUrl.startsWith('blob:')) {
        // Network or blob URL
        avatar = ClipOval(
          child: Image.network(
            resolvedUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(color, initial),
          ),
        );
      } else if (resolvedUrl.startsWith('assets/')) {
        avatar = ClipOval(
          child: Image.asset(
            resolvedUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(color, initial),
          ),
        );
      } else {
        avatar = _fallback(color, initial);
      }
    } else {
      avatar = _fallback(color, initial);
    }

    if (!showOnlineDot) return avatar;

    return Stack(
      children: [
        avatar,
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: HuddlColors.actionGreen,
                shape: BoxShape.circle,
                border: Border.all(color: context.hc.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fallback(Color color, String initial) {
    // If parentType is known, show the gender-appropriate illustrated avatar.
    if (parentType != null) {
      final asset = MemberPhotoService.getDefaultAvatar(parentType: parentType);
      return ClipOval(
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsCircle(color, initial),
        ),
      );
    }
    return _initialsCircle(color, initial);
  }

  Widget _initialsCircle(Color color, String initial) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
      ),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.poppins(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Notification badge
class HuddlBadge extends StatelessWidget {
  final int count;
  final Widget child;

  const HuddlBadge({
    super.key,
    required this.count,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: HuddlColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: context.hc.surface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
