import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../services/tutorial_service.dart';
import '../../constants/app_text_styles.dart';

/// Lightweight, translucent tutorial overlay that walks the user through each
/// tab while keeping the actual screen fully visible underneath.
///
/// Design principles:
///   - Ultra-light scrim so the real screen content shows through
///   - Compact frosted-glass card near the bottom nav
///   - Pulsing highlight ring around the active nav tab
///   - Each step switches to the real tab so users see live content
///   - Swipe left/right to navigate steps
class TutorialOverlay extends StatefulWidget {
  final void Function(int tabIndex) onTabSwitch;
  final VoidCallback? onComplete;

  const TutorialOverlay({
    super.key,
    required this.onTabSwitch,
    this.onComplete,
  });

  /// Convenience launcher -- pushes the overlay as a transparent route.
  static Future<void> show(
    BuildContext context, {
    required void Function(int tabIndex) onTabSwitch,
    VoidCallback? onComplete,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, __, ___) => TutorialOverlay(
          onTabSwitch: onTabSwitch,
          onComplete: onComplete,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with TickerProviderStateMixin {
  int _current = 0;

  late final AnimationController _cardAnim;
  late final AnimationController _pulseAnim;
  late Animation<double> _cardFade;
  late Animation<Offset> _cardSlide;

  List<TutorialStep> get _steps => TutorialService.steps;
  TutorialStep get _step => _steps[_current];

  // Nav tab layout: 6 evenly-spaced items inside the pill bar
  // Each item centre is at (index + 0.5) / 6 of the bar width
  static const int _tabCount = 6;

  @override
  void initState() {
    super.initState();

    _cardAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _cardFade = CurvedAnimation(parent: _cardAnim, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardAnim, curve: Curves.easeOutCubic));

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _cardAnim.forward();
    // Defer the first tab-switch until after the overlay's first build.
    // Calling onTabSwitch() directly in initState() triggers setState() on
    // MainShell while the TutorialOverlay widget is being inflated, causing
    // "setState() called during build" crash (main_shell.dart:77).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTabSwitch(_step.tabIndex);
    });
  }

  @override
  void dispose() {
    _cardAnim.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  Future<void> _goTo(int index) async {
    await _cardAnim.reverse();
    setState(() => _current = index);
    widget.onTabSwitch(_steps[index].tabIndex);
    _cardAnim.forward();
  }

  Future<void> _next() async {
    if (_current < _steps.length - 1) {
      await _goTo(_current + 1);
    } else {
      await _finish();
    }
  }

  Future<void> _prev() async {
    if (_current > 0) await _goTo(_current - 1);
  }

  Future<void> _finish() async {
    await TutorialService().markCompleted();
    widget.onComplete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    await TutorialService().markCompleted();
    widget.onComplete?.call();
    if (mounted) Navigator.of(context).pop();
  }

  IconData _iconForName(String name) {
    switch (name) {
      case 'home':
        return Icons.home;
      case 'people':
        return Icons.people;
      case 'groups':
        return Icons.groups;
      case 'storefront':
        return Icons.storefront;
      case 'person':
        return Icons.person;
      default:
        return Icons.info;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Bottom nav pill sits at: padding 16 from sides, 12 from bottom, height 70
    // The safe-area bottom padding is handled by the nav bar itself
    final navBarBottom = mq.padding.bottom + 12;
    const navBarHeight = 70.0;
    const navBarHPad = 16.0;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        // Swipe left/right to navigate
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -200) {
            _next();
          } else if (details.primaryVelocity! > 200) {
            _prev();
          }
        },
        child: Stack(
          children: [
            // ── Ultra-light scrim -- screen shows through ─────────
            Positioned.fill(
              child: GestureDetector(
                onTap: () {}, // absorb taps
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ),

            // ── Pulsing highlight ring around active nav tab ──────
            _buildNavHighlight(
              navBarBottom: navBarBottom,
              navBarHeight: navBarHeight,
              navBarHPad: navBarHPad,
              screenWidth: mq.size.width,
            ),

            // ── Skip button (top-right) ──────────────────────────
            Positioned(
              top: mq.padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: _skip,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        'Skip',
                        style: HuddlText.body(color: Colors.white.withValues(alpha: 0.95))),
                    ),
                  ),
                ),
              ),
            ),

            // ── Compact frosted card above bottom nav ─────────────
            Positioned(
              left: 16,
              right: 16,
              bottom: navBarBottom + navBarHeight + 14,
              child: FadeTransition(
                opacity: _cardFade,
                child: SlideTransition(
                  position: _cardSlide,
                  child: _buildCompactCard(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pulsing glow ring positioned over the active bottom nav tab.
  Widget _buildNavHighlight({
    required double navBarBottom,
    required double navBarHeight,
    required double navBarHPad,
    required double screenWidth,
  }) {
    final tabIndex = _step.tabIndex;
    final barWidth = screenWidth - (navBarHPad * 2);
    final tabWidth = barWidth / _tabCount;
    final centreX = navBarHPad + (tabIndex * tabWidth) + (tabWidth / 2);

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) {
        final t = _pulseAnim.value; // 0 -> 1 -> 0
        final scale = 1.0 + (t * 0.15);
        final alpha = 0.35 + (t * 0.25);

        return Positioned(
          left: centreX - 28 * scale,
          bottom: navBarBottom + (navBarHeight / 2) - 28 * scale,
          child: IgnorePointer(
            child: Container(
              width: 56 * scale,
              height: 56 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: HuddlColors.primary.withValues(alpha: alpha),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: HuddlColors.primary.withValues(alpha: alpha * 0.5),
                    blurRadius: 16 + (t * 8),
                    spreadRadius: 2 + (t * 4),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Compact, frosted-glass card with icon, headline, short text, and nav.
  Widget _buildCompactCard() {
    final isLast = _current == _steps.length - 1;
    final isFirst = _current == 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top row: icon + headline + step counter ──────
              Row(
                children: [
                  // Icon badge
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _iconForName(_step.iconName),
                      color: HuddlColors.textDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title + headline
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _step.title,
                          style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textDark),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _step.headline,
                          style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  // Step counter
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HuddlColors.gray100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_current + 1}/${_steps.length}',
                      style: HuddlText.caption(weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Body text (short) ───────────────────────────
              Text(
                _step.body,
                style: HuddlText.caption(color: HuddlColors.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 12),

              // ── Progress dots + navigation ──────────────────
              Row(
                children: [
                  // Progress dots
                  Expanded(
                    child: Row(
                      children: List.generate(
                        _steps.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 4),
                          width: i == _current ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _current
                                ? HuddlColors.primary
                                : HuddlColors.gray300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Back button
                  if (!isFirst) ...[
                    GestureDetector(
                      onTap: _prev,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: HuddlColors.gray100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 14,
                          color: HuddlColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Next / Done button
                  GestureDetector(
                    onTap: _next,
                    child: Container(
                      height: 36,
                      padding:
                          EdgeInsets.symmetric(horizontal: isLast ? 20 : 16),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color:
                                HuddlColors.primary.withValues(alpha: 0.20),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLast ? 'Get started' : 'Next',
                            style: HuddlText.body(weight: FontWeight.w600),
                          ),
                          if (!isLast) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_ios,
                                size: 12, color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
