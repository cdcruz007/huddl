import 'package:flutter/material.dart';
import '../theme/huddl_icons.dart';
import 'package:flutter/services.dart';
import '../theme/huddl_colors.dart';
import '../services/messages_ai_service.dart';
import '../constants/app_text_styles.dart';

// =============================================================================
// AI ASSISTANT BOTTOM SHEET
//
// Progressive-disclosure AI assistant revealed via a subtle sparkle icon.
// Provides: voice commands, smart suggestions, quick actions, and feedback.
// =============================================================================

/// Show the AI assistant bottom sheet.
Future<AiAssistantResult?> showAiAssistantSheet(
  BuildContext context, {
  List<AiQuickAction> quickActions = const [],
  List<AiSearchSuggestion> suggestions = const [],
  int totalUnread = 0,
}) {
  return showModalBottomSheet<AiAssistantResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AiAssistantSheet(
      quickActions: quickActions,
      suggestions: suggestions,
      totalUnread: totalUnread,
    ),
  );
}

/// Result from AI assistant interaction.
class AiAssistantResult {
  final String action; // 'search', 'navigate', 'catch_up', 'voice_command'
  final String? query;
  final Map<String, dynamic> data;

  const AiAssistantResult({
    required this.action,
    this.query,
    this.data = const {},
  });
}

class _AiAssistantSheet extends StatefulWidget {
  final List<AiQuickAction> quickActions;
  final List<AiSearchSuggestion> suggestions;
  final int totalUnread;

  const _AiAssistantSheet({
    required this.quickActions,
    required this.suggestions,
    required this.totalUnread,
  });

  @override
  State<_AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<_AiAssistantSheet>
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

    // Simulate voice recognition after 2 seconds
    if (_isListening) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _isListening) {
          setState(() {
            _isListening = false;
            _inputController.text = 'Show unread messages';
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
    final aiService = MessagesAiService();
    final intent = aiService.parseVoiceCommand(text.trim());

    Navigator.pop(context, AiAssistantResult(
      action: intent.action,
      query: intent.target ?? text.trim(),
      data: {
        'confidence': intent.confidence,
        'message': intent.message,
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: context.hc.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: HuddlColors.aiGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(HuddlIcons.ai, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Huddl',
                        style: HuddlText.body(weight: FontWeight.w700),
                      ),
                      Text(
                        'Ask me anything or try a voice command',
                        style: HuddlText.caption(),
                      ),
                    ],
                  ),
                ),
                // AI transparency badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: HuddlColors.nearBlack.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(HuddlIcons.verifiedFill, size: 12, color: HuddlColors.success),
                      const SizedBox(width: 3),
                      Text('Smart', style: HuddlText.label()),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Input bar with voice button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: context.hc.scaffold,
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
                      style: HuddlText.body(color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening...' : 'Type a command or question...',
                        hintStyle: HuddlText.body(color: _isListening ? HuddlColors.nearBlack : context.hc.textTertiary),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onSubmitted: _submitQuery,
                    ),
                  ),
                  // Voice button
                  GestureDetector(
                    onTap: _toggleListening,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale = _isListening ? 1.0 + _pulseController.value * 0.15 : 1.0;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _isListening
                                  ? HuddlColors.nearBlack
                                  : HuddlColors.neutral50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isListening ? HuddlIcons.mic : HuddlIcons.mic,
                              size: 18,
                              color: _isListening ? Colors.white : HuddlColors.textDark,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Submit button
                  GestureDetector(
                    onTap: () => _submitQuery(_inputController.text),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(HuddlIcons.arrowUp, size: 18, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick actions
          if (widget.quickActions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('Suggested actions', style: HuddlText.caption(weight: FontWeight.w600, color: context.hc.textTertiary)),
                  const SizedBox(width: 6),
                  Icon(HuddlIcons.ai, size: 12, color: context.hc.textTertiary),
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
                  return _QuickActionChip(
                    action: action,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, AiAssistantResult(
                        action: action.id,
                        data: action.routeArgs,
                      ));
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Search suggestions
          if (widget.suggestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('Try searching for', style: HuddlText.caption(weight: FontWeight.w600, color: context.hc.textTertiary)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...widget.suggestions.take(4).map((s) => InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context, AiAssistantResult(
                  action: 'search',
                  query: s.query,
                ));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(s.icon, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.query, style: HuddlText.body()),
                          Text(s.reason, style: HuddlText.caption()),
                        ],
                      ),
                    ),
                    Icon(HuddlIcons.arrowForward, size: 12, color: context.hc.textTertiary),
                  ],
                ),
              ),
            )),
          ],

          const SizedBox(height: 16),

          // Feedback hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HuddlColors.peachSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(HuddlIcons.info, size: 14, color: HuddlColors.nearBlack),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Suggestions improve as you use them. Tap \u{1F44D} or \u{1F44E} on any suggestion.',
                      style: HuddlText.caption(color: HuddlColors.nearBlack),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final AiQuickAction action;
  final VoidCallback onTap;

  const _QuickActionChip({required this.action, required this.onTap});

  IconData get _icon {
    switch (action.iconName) {
      case 'auto_awesome': return HuddlIcons.ai;
      case 'mail': return HuddlIcons.email;
      case 'chat': return HuddlIcons.chat;
      default: return HuddlIcons.flash;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            Icon(_icon, size: 18, color: HuddlColors.textDark),
            const Spacer(),
            Text(action.label, style: HuddlText.caption(weight: FontWeight.w600)),
            Text(action.description, style: HuddlText.label(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
