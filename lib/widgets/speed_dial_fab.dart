import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';

// =============================================================================
// SPEED DIAL FAB  —  Progressive-disclosure floating action menu
// =============================================================================
// - 7 extended FABs (icon + label) stacked vertically above the primary button
// - Staggered slide+fade entrance animation (closest item animates first)
// - '+' morphs to 'x' with rotation animation
// - Full-screen scrim backdrop closes the menu on outside tap
// - 48dp minimum touch targets per Material / WCAG 2.2
// - Semantic labels on every item for screen readers
// - Haptic feedback on open / close / item tap
// =============================================================================

/// Data class for a single Speed Dial action.
class SpeedDialItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const SpeedDialItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// A Material 3 Speed Dial FAB designed to be placed as a direct child
/// inside a full-screen [Stack] in the shell widget.
///
/// The widget itself is an [IgnorePointer] when closed (only the FAB button
/// receives taps). When opened, the full-screen scrim and menu items become
/// interactive.
///
/// **Parent must be a full-screen Stack** — the scrim uses `Positioned.fill`.
///
/// [fabRight] and [fabBottom] control the position of the primary FAB button
/// within that parent Stack.
class SpeedDialFab extends StatefulWidget {
  final List<SpeedDialItem> items;
  final double fabRight;
  final double fabBottom;

  const SpeedDialFab({
    super.key,
    required this.items,
    this.fabRight = 20,
    this.fabBottom = 100,
  });

  @override
  State<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<SpeedDialFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _expandAnim;
  bool _isOpen = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Toggle ─────────────────────────────────────────────────────────────────

  void _toggle() {
    HapticFeedback.lightImpact();
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _close() {
    if (!_isOpen) return;
    HapticFeedback.lightImpact();
    setState(() => _isOpen = false);
    _controller.reverse();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // When closed, the Stack is transparent — taps pass through to whatever
    // is behind (the Scaffold / bottom nav). When open, the scrim absorbs
    // all taps. The Stack must fill its parent via Positioned.fill in the
    // parent widget.
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Full-screen scrim (only when open) ─────────────────────────────
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: FadeTransition(
                opacity: _expandAnim,
                child: Container(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.45),
                ),
              ),
            ),
          ),

        // ── Speed-dial items (anchored above the FAB) ──────────────────────
        if (_isOpen)
          Positioned(
            right: widget.fabRight,
            bottom: widget.fabBottom + 72, // FAB height (60) + gap (12)
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.items.length, (rawIndex) {
              // Items rendered top-to-bottom; animate bottom-up (closest first)
              final reverseIndex = widget.items.length - 1 - rawIndex;
              final item = widget.items[rawIndex];

              // Stagger: each item has its own interval
              final begin = (reverseIndex / widget.items.length) * 0.4;
              final end = begin + 0.6;
              final itemAnim = CurvedAnimation(
                parent: _expandAnim,
                curve: Interval(
                  begin.clamp(0.0, 1.0),
                  end.clamp(0.0, 1.0),
                  curve: Curves.easeOutCubic,
                ),
              );

              return FadeTransition(
                opacity: itemAnim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.4),
                    end: Offset.zero,
                  ).animate(itemAnim),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SpeedDialAction(
                      item: item,
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _close();
                        Future.delayed(
                          const Duration(milliseconds: 180),
                          item.onTap,
                        );
                      },
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // ── Primary FAB button (+ / x morph) ──────────────────────────────
        Positioned(
          right: widget.fabRight,
          bottom: widget.fabBottom,
          child: _PrimaryFab(
            animation: _expandAnim,
            isOpen: _isOpen,
            onTap: _toggle,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SPEED DIAL ACTION  —  individual extended FAB row  (icon + label)
// =============================================================================
class _SpeedDialAction extends StatelessWidget {
  final SpeedDialItem item;
  final bool isDark;
  final VoidCallback onTap;

  const _SpeedDialAction({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? HuddlColors.darkSurface : HuddlColors.white;
    final textColor =
        isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark;
    final shadow =
        isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.08);

    return Semantics(
      button: true,
      label: item.label,
      child: Material(
        color: surface,
        borderRadius: BorderRadius.circular(28),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          splashColor: item.color.withValues(alpha: 0.12),
          highlightColor: item.color.withValues(alpha: 0.06),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? HuddlColors.darkDivider : HuddlColors.gray200,
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(color: shadow, blurRadius: 12, offset: const Offset(0, 3)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.icon, size: 17, color: item.color),
                ),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PRIMARY FAB  —  the main '+' / 'x' button with rotation morph
// =============================================================================
class _PrimaryFab extends StatelessWidget {
  final Animation<double> animation;
  final bool isOpen;
  final VoidCallback onTap;

  const _PrimaryFab({
    required this.animation,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isOpen ? 'Close quick actions' : 'Open quick actions',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: HuddlColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: HuddlColors.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              return Transform.rotate(
                angle: animation.value * (math.pi / 4), // 0 -> 45 degrees
                child: Icon(
                  animation.value > 0.5 ? Icons.close : Icons.add,
                  color: HuddlColors.white,
                  size: 30,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
