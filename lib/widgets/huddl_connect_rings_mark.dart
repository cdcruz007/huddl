import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

// =============================================================================
// HUDDL CONNECT RINGS MARK
// =============================================================================
//
// Two interlinked rings — the huddl Connect identity mark.
// Asset: assets/huddl_connect_rings.json
//   • 24×24 canvas, 60fps, 61 frames (~1.017s)
//   • ring_deep    (stroke #F2743A): slides in x=6→0, t=0→41;  opacity t=0→22
//   • ring_primary (stroke #FF965C): slides in x=6→0, t=8→49;  opacity t=8→30
//   • Stagger is baked into the Lottie — no external transform needed.
//
// Usage
// ─────
//   // Section header (Connect screen): full colour, size 20
//   HuddlConnectRingsMark(size: 20)
//
//   // Bottom-nav icon (Option B override in _NavItemState):
//   HuddlConnectRingsMark(size: 22, isActive: _isActive)
//
// Animation behaviour
// ───────────────────
//   • Plays once on first build (respects MediaQuery.disableAnimations).
//   • Call [replay] to re-run — invoked by the nav-bar didUpdateWidget and by
//     the section-header initState (via addPostFrameCallback).
//   • Holds at final frame after completion. Never loops.
//
// Colour modes
// ────────────
//   • isActive = true  → no colour filter; brand colours show as designed.
//   • isActive = false → ColorFilter.mode(textHint, srcIn) tints to grey.
// =============================================================================

class HuddlConnectRingsMark extends StatefulWidget {
  final double size;
  final bool isActive;

  const HuddlConnectRingsMark({
    super.key,
    this.size = 24,
    this.isActive = true,
  });

  @override
  State<HuddlConnectRingsMark> createState() =>
      HuddlConnectRingsMarkState();
}

class HuddlConnectRingsMarkState extends State<HuddlConnectRingsMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // The inactive grey tint — matches nav-bar sibling treatment
  static const Color _inactiveColor = Color(0xFF949494); // HuddlColors.textHint

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
    // First play fires once onLoaded has set _ctrl.duration
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Play the animation once from frame 0.
  /// Call this when the Connect tab becomes active.
  void replay() {
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reducedMotion) {
      if (_ctrl.duration != null) _ctrl.value = 1.0;
      return;
    }
    if (!_ctrl.isAnimating) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    Widget lottie = Lottie.asset(
      'assets/huddl_connect_rings.json',
      controller: _ctrl,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      onLoaded: (comp) {
        if (!mounted) return;
        _ctrl.duration = comp.duration;
        if (reducedMotion) {
          _ctrl.value = 1.0;
        } else {
          _ctrl.forward(from: 0);
        }
      },
    );

    // Inactive: tint to textHint grey (mirrors how Icon siblings look unselected)
    if (!widget.isActive) {
      lottie = ColorFiltered(
        colorFilter: ColorFilter.mode(_inactiveColor, BlendMode.srcIn),
        child: lottie,
      );
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: lottie,
    );
  }
}
