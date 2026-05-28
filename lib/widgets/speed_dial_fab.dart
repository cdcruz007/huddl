import 'package:flutter/material.dart';
import '../theme/huddl_colors.dart';
import '../theme/huddl_animations.dart';
import '../constants/app_text_styles.dart';

// =============================================================================
// SPEED DIAL FAB — Huddl floating action menu
//
// A single orange FAB that expands into a vertical speed-dial when tapped.
// Four quick-access actions:
//   • Local Services  — /services  (blue, storefront icon)
//   • SEND Navigator  — /send      (teal, accessibility icon)
//   • Huddl Wisdom    — tab 5      (amber, auto_awesome icon)
//   • AI Copilot      — /copilot   (indigo, smart_toy icon)
//
// Collapses automatically when the user taps any action or taps the backdrop.
// Uses AnimationController for smooth scale + fade entrance of each mini-FAB.
// =============================================================================

class SpeedDialFab extends StatefulWidget {
  final VoidCallback onServicesPressed;
  final VoidCallback onInsightsPressed;
  final VoidCallback onAiPressed;
  final VoidCallback onSendPressed;

  const SpeedDialFab({
    super.key,
    required this.onServicesPressed,
    required this.onInsightsPressed,
    required this.onAiPressed,
    required this.onSendPressed,
  });

  @override
  State<SpeedDialFab> createState() => _SpeedDialFabState();
}

class _SpeedDialFabState extends State<SpeedDialFab>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 220),
    );
    _fade   = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _rotate = Tween<double>(begin: 0.0, end: 0.125).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _close() {
    if (_open) _toggle();
  }

  void _onAction(VoidCallback action) {
    _close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Speed-dial items (shown when open) ────────────────────────────
        FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _DialItem(
                animation:  _fade,
                delay:      0.0,
                icon:       Icons.storefront_rounded,
                label:      'Local Services',
                color:      HuddlColors.primaryLight,  // soft warm orange
                onPressed:  () => _onAction(widget.onServicesPressed),
              ),
              const SizedBox(height: 10),
              _DialItem(
                animation:  _fade,
                delay:      0.05,
                icon:       Icons.accessibility_new_rounded,
                label:      'SEND Navigator',
                color:      HuddlColors.success,        // teal — accessibility
                onPressed:  () => _onAction(widget.onSendPressed),
              ),
              const SizedBox(height: 10),
              _DialItem(
                animation:  _fade,
                delay:      0.1,
                icon:       Icons.auto_awesome_rounded,
                label:      'Huddl Wisdom',
                color:      HuddlColors.primary,    // amber — wisdom
                onPressed:  () => _onAction(widget.onInsightsPressed),
              ),
              const SizedBox(height: 10),
              _DialItem(
                animation:  _fade,
                delay:      0.15,
                icon:       Icons.smart_toy_outlined,
                label:      'AI Copilot',
                color:      HuddlColors.primary,        // brand orange — AI
                onPressed:  () => _onAction(widget.onAiPressed),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
        // ── Main FAB ─────────────────────────────────────────────────────
        RotationTransition(
          turns: _rotate,
          child: FloatingActionButton(
            onPressed:       _toggle,
            backgroundColor: HuddlColors.primary,
            foregroundColor: Colors.white,
            elevation:       4,
            tooltip:         _open ? 'Close menu' : 'Quick actions',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _open ? Icons.close_rounded : Icons.add_rounded,
                key: ValueKey(_open),
                size: 26,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Individual dial item ─────────────────────────────────────────────────

class _DialItem extends StatelessWidget {
  final Animation<double> animation;
  final double delay;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _DialItem({
    required this.animation,
    required this.delay,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Label pill ──────────────────────────────────────────────────
        AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Opacity(
            opacity: animation.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset((1 - animation.value) * 20, 0),
              child: child,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? HuddlColors.darkSurface
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: HuddlText.body(weight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // ── Mini FAB ────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Transform.scale(
            scale: animation.value.clamp(0.0, 1.0),
            child: child,
          ),
          child: FabScaleOnPress(
            onTap: onPressed,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}
