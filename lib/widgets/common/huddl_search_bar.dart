import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';

// =============================================================================
// HUDDL SEARCH BAR — Airbnb-inspired animated pill that expands on tap
// =============================================================================
//
// USAGE — Collapsed (home screen):
//   HuddlSearchPill(
//     borough: 'Cambridge',
//     onTap: () => _openSearch(),
//   )
//
// USAGE — Expanded (full search screen):
//   HuddlSearchExpanded(
//     initialQuery: '',
//     onSubmit: (q) => _runSearch(q),
//     onClose: () => Navigator.pop(context),
//   )
//
// ANIMATION PRINCIPLE:
//   The pill morphs into a full-screen search using a Hero widget +
//   spring-physics AnimationController. Matches Airbnb's search expansion
//   pattern but adapted for huddl's community discovery context.
//
// Cross-platform: iOS + Android + Web.
// =============================================================================

// ── Collapsed pill ────────────────────────────────────────────────────────────

class HuddlSearchPill extends StatefulWidget {
  const HuddlSearchPill({
    super.key,
    required this.borough,
    required this.onTap,
    this.hint = 'Search in',
  });

  final String borough;
  final VoidCallback onTap;
  final String hint;

  @override
  State<HuddlSearchPill> createState() => _HuddlSearchPillState();
}

class _HuddlSearchPillState extends State<HuddlSearchPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? HuddlColors.darkSurface : HuddlColors.white;
    final textColor = isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark;
    final hintColor = isDark ? HuddlColors.darkTextSecondary : HuddlColors.textSecondary;

    return Hero(
      tag: 'huddl_search_pill',
      flightShuttleBuilder: (_, anim, __, ___, ____) {
        return AnimatedBuilder(
          animation: anim,
          builder: (_, __) => _buildPillShape(surface, textColor, hintColor, isDark),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => _pressCtrl.forward(),
        onTapUp: (_) {
          _pressCtrl.reverse();
          HuddlAnimations.lightTap();
          widget.onTap();
        },
        onTapCancel: () => _pressCtrl.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: _buildPillShape(surface, textColor, hintColor, isDark),
        ),
      ),
    );
  }

  Widget _buildPillShape(
    Color surface, Color textColor, Color hintColor, bool isDark) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: isDark
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20, offset: const Offset(0, 4))]
            : [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4, offset: const Offset(0, 1)),
              ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Icon(Icons.search, size: 20, color: textColor),
          const SizedBox(width: 12),
          // Vertical divider
          Container(width: 1, height: 22,
              color: (isDark ? HuddlColors.darkDivider : HuddlColors.divider)),
          const SizedBox(width: 12),
          // Location pin
          Icon(Icons.location_on_outlined, size: 15,
              color: HuddlColors.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${widget.hint} ${widget.borough}',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: hintColor,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Filter button — dark pill
          Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            decoration: BoxDecoration(
              color: textColor,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.tune, size: 16,
                color: isDark ? HuddlColors.darkBackground : HuddlColors.white),
          ),
        ],
      ),
    );
  }
}

// ── Expanded search sheet ─────────────────────────────────────────────────────

class HuddlSearchExpanded extends StatefulWidget {
  const HuddlSearchExpanded({
    super.key,
    this.initialQuery = '',
    required this.onSubmit,
    required this.onClose,
    this.suggestions = const [],
  });

  final String initialQuery;
  final void Function(String query) onSubmit;
  final VoidCallback onClose;
  final List<HuddlSearchSuggestion> suggestions;

  @override
  State<HuddlSearchExpanded> createState() => _HuddlSearchExpandedState();
}

class _HuddlSearchExpandedState extends State<HuddlSearchExpanded>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  late final Animation<double> _suggestionsAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    _focus = FocusNode();

    _expandCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    // Spring-like curve for the expansion
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: Curves.easeOutCubic,
    );
    _suggestionsAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _expandCtrl.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _expandCtrl.dispose();
    super.dispose();
  }

  void _close() {
    HuddlAnimations.lightTap();
    _expandCtrl.reverse().then((_) => widget.onClose());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? HuddlColors.darkSurface : HuddlColors.white;
    final textColor = isDark ? HuddlColors.darkTextPrimary : HuddlColors.textDark;
    final bg = isDark ? HuddlColors.darkBackground : HuddlColors.background;

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (_, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _expandAnim.value * 4,
            sigmaY: _expandAnim.value * 4,
          ),
          child: child,
        );
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Search input row ───────────────────────────────────────────
              Hero(
                tag: 'huddl_search_pill',
                child: AnimatedBuilder(
                  animation: _expandAnim,
                  builder: (_, __) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: HuddlColors.primary.withValues(alpha: 0.35 * _expandAnim.value),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Back arrow
                            GestureDetector(
                              onTap: _close,
                              child: SizedBox(
                                width: 52,
                                child: Icon(Icons.arrow_back,
                                    size: 20, color: textColor),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _focus,
                                onSubmitted: (q) {
                                  HuddlAnimations.mediumTap();
                                  widget.onSubmit(q);
                                },
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  color: textColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search parents, groups, meetups…',
                                  hintStyle: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: isDark
                                        ? HuddlColors.darkTextTertiary
                                        : HuddlColors.textHint,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                textInputAction: TextInputAction.search,
                              ),
                            ),
                            if (_ctrl.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _ctrl.clear();
                                  setState(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? HuddlColors.darkSurfaceVariant
                                          : HuddlColors.gray300,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.close, size: 13,
                                        color: textColor),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // ── Suggestions list ───────────────────────────────────────────
              FadeTransition(
                opacity: _suggestionsAnim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.1),
                    end: Offset.zero,
                  ).animate(_suggestionsAnim),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.suggestions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1,
                            color: isDark
                                ? HuddlColors.darkDivider
                                : HuddlColors.divider),
                    itemBuilder: (_, i) {
                      final s = widget.suggestions[i];
                      return _SuggestionTile(
                        suggestion: s,
                        isDark: isDark,
                        onTap: () {
                          HuddlAnimations.selectionClick();
                          _ctrl.text = s.label;
                          widget.onSubmit(s.label);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.isDark,
    required this.onTap,
  });
  final HuddlSearchSuggestion suggestion;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? HuddlColors.darkSurfaceVariant
                    : HuddlColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(suggestion.icon, size: 20,
                  color: isDark
                      ? HuddlColors.darkTextSecondary
                      : HuddlColors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.label,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? HuddlColors.darkTextPrimary
                          : HuddlColors.textDark,
                    ),
                  ),
                  if (suggestion.sublabel != null)
                    Text(
                      suggestion.sublabel!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: isDark
                            ? HuddlColors.darkTextTertiary
                            : HuddlColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.north_west, size: 16,
                color: isDark
                    ? HuddlColors.darkTextTertiary
                    : HuddlColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class HuddlSearchSuggestion {
  final String label;
  final String? sublabel;
  final IconData icon;

  const HuddlSearchSuggestion({
    required this.label,
    this.sublabel,
    this.icon = Icons.search,
  });
}
