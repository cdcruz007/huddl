import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/discover_ai_service.dart';

// =============================================================================
// DISCOVER AI ASSISTANT BOTTOM SHEET
//
// Progressive-disclosure AI assistant for the Discover Tab.
// Entry point: subtle sparkle icon that morphs into a floating bottom sheet.
// Features:
//   - Voice commands for multi-step group tasks (find, filter, join, create)
//   - Predictive search suggestions with pre-filling
//   - Quick actions (AI-generated contextual shortcuts)
//   - Feedback loop (thumbs up/down on suggestions)
//   - AI transparency badge & explanation
// =============================================================================

/// Show the Discover AI assistant bottom sheet.
Future<DiscoverAiResult?> showDiscoverAiSheet(
  BuildContext context, {
  List<DiscoverQuickAction> quickActions = const [],
  List<DiscoverSearchSuggestion> suggestions = const [],
  String contextExplanation = '',
}) {
  return showModalBottomSheet<DiscoverAiResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _DiscoverAiSheet(
      quickActions: quickActions,
      suggestions: suggestions,
      contextExplanation: contextExplanation,
    ),
  );
}

/// Result from the Discover AI assistant interaction.
class DiscoverAiResult {
  final String action; // 'search', 'filter', 'join', 'create', 'sort', 'quick_action'
  final String? query;
  final Map<String, dynamic> data;

  const DiscoverAiResult({
    required this.action,
    this.query,
    this.data = const {},
  });
}

class _DiscoverAiSheet extends StatefulWidget {
  final List<DiscoverQuickAction> quickActions;
  final List<DiscoverSearchSuggestion> suggestions;
  final String contextExplanation;

  const _DiscoverAiSheet({
    required this.quickActions,
    required this.suggestions,
    required this.contextExplanation,
  });

  @override
  State<_DiscoverAiSheet> createState() => _DiscoverAiSheetState();
}

class _DiscoverAiSheetState extends State<_DiscoverAiSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _isListening = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleListening() {
    HapticFeedback.lightImpact();
    setState(() {
      _isListening = !_isListening;
      if (_isListening) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });

    if (_isListening) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isListening) {
          setState(() {
            _isListening = false;
            _inputController.text = 'Find mums groups near me';
            _pulseController.stop();
            _pulseController.reset();
          });
        }
      });
    }
  }

  void _submitQuery(String text) {
    if (text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final aiService = DiscoverAiService();
    final intent = aiService.parseVoiceCommand(text.trim());

    Navigator.pop(
      context,
      DiscoverAiResult(
        action: intent.action,
        query: intent.target ?? text.trim(),
        data: intent.params,
      ),
    );
  }

  IconData _quickActionIcon(String iconName) {
    switch (iconName) {
      case 'trending_up':
        return Icons.trending_up;
      case 'add_circle':
        return Icons.add_circle_outline;
      case 'explore':
        return Icons.explore;
      case 'auto_awesome':
        return Icons.auto_awesome;
      default:
        return Icons.flash_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──────────────────────────────
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // ── Header ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // AI icon with gradient
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: HuddlColors.aiGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover Assistant',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        Text(
                          'Find groups, filter, or just ask',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // AI transparency badge
                  Semantics(
                    label: 'AI-powered assistant',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: HuddlColors.nearBlack.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified,
                              size: 12, color: HuddlColors.nearBlack),
                          const SizedBox(width: 3),
                          Text(
                            'Smart',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.nearBlack,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Input bar with voice ─────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: context.hc.inputBg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isListening
                        ? HuddlColors.nearBlack.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: context.hc.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: _isListening
                              ? 'Listening...'
                              : 'Try "find sleep groups" or "popular"...',
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 14,
                            color: _isListening
                                ? HuddlColors.nearBlack
                                : HuddlColors.textHint,
                            fontStyle: _isListening
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onSubmitted: _submitQuery,
                      ),
                    ),
                    // Voice button
                    Semantics(
                      label: _isListening
                          ? 'Stop listening'
                          : 'Start voice command',
                      button: true,
                      child: GestureDetector(
                        onTap: _toggleListening,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = _isListening
                                ? 1.0 + _pulseController.value * 0.15
                                : 1.0;
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _isListening
                                      ? HuddlColors.nearBlack
                                      : HuddlColors.background,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _isListening ? Icons.mic : Icons.mic_none,
                                  size: 18,
                                  color: _isListening
                                      ? Colors.white
                                      : HuddlColors.textDark,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Submit button
                    Semantics(
                      label: 'Submit query',
                      button: true,
                      child: GestureDetector(
                        onTap: () => _submitQuery(_inputController.text),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_upward,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Quick actions ────────────────────────────
            if (widget.quickActions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Suggested actions',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textTertiary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.auto_awesome,
                        size: 12, color: context.hc.textTertiary),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: widget.quickActions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final action = widget.quickActions[i];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(
                          context,
                          DiscoverAiResult(
                            action: 'quick_action',
                            query: action.id,
                            data: action.data,
                          ),
                        );
                      },
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.hc.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.hc.divider),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_quickActionIcon(action.iconName),
                                size: 18, color: HuddlColors.textDark),
                            const Spacer(),
                            Text(
                              action.label,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.hc.textPrimary,
                              ),
                            ),
                            Text(
                              action.description,
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                color: context.hc.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Search suggestions ───────────────────────
            if (widget.suggestions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Try asking for',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textTertiary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              ...widget.suggestions.take(4).map((s) => InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(
                        context,
                        DiscoverAiResult(
                          action: 'search',
                          query: s.query,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          Text(s.icon,
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.query,
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: context.hc.textPrimary,
                                  ),
                                ),
                                Text(
                                  s.reason,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: context.hc.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 12, color: context.hc.textTertiary),
                        ],
                      ),
                    ),
                  )),
            ],

            // ── Context explanation (AI transparency) ────
            if (widget.contextExplanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Semantics(
                  label: 'AI explanation: ${widget.contextExplanation}',
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: HuddlColors.nearBlack),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.contextExplanation,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.nearBlack,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            // ── Feedback hint ────────────────────────────
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.thumbs_up_down,
                        size: 14, color: HuddlColors.nearBlack),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap \u{1F44D} or \u{1F44E} on group cards to help us show you better matches.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.nearBlack,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }
}
