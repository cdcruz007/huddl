import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import '../services/messages_ai_service.dart';

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
                  child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Huddl',
                        style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      Text(
                        'Ask me anything or try a voice command',
                        style: GoogleFonts.poppins(
                          fontSize: 11, color: context.hc.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // AI transparency badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: HuddlColors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified, size: 12, color: HuddlColors.teal),
                      const SizedBox(width: 3),
                      Text('AI', style: GoogleFonts.poppins(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: HuddlColors.teal,
                      )),
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
                      ? HuddlColors.blue.withValues(alpha: 0.4)
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
                      style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: _isListening ? 'Listening...' : 'Type a command or question...',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 14,
                          color: _isListening ? HuddlColors.blue : context.hc.textTertiary,
                          fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
                        ),
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
                                  ? HuddlColors.blue
                                  : HuddlColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              size: 18,
                              color: _isListening ? Colors.white : HuddlColors.primary,
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
                        gradient: HuddlColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
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
                  Text('Suggested actions', style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: context.hc.textTertiary, letterSpacing: 0.3,
                  )),
                  const SizedBox(width: 6),
                  Icon(Icons.auto_awesome, size: 12, color: context.hc.textTertiary),
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
                  Text('Try searching for', style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: context.hc.textTertiary, letterSpacing: 0.3,
                  )),
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
                          Text(s.query, style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w500,
                            color: context.hc.textPrimary,
                          )),
                          Text(s.reason, style: GoogleFonts.poppins(
                            fontSize: 11, color: context.hc.textTertiary,
                          )),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 12, color: context.hc.textTertiary),
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
                color: HuddlColors.blueBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: HuddlColors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI suggestions improve as you use them. Tap \u{1F44D} or \u{1F44E} on any suggestion to help me learn.',
                      style: GoogleFonts.poppins(
                        fontSize: 11, color: HuddlColors.blue, height: 1.3,
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
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final AiQuickAction action;
  final VoidCallback onTap;

  const _QuickActionChip({required this.action, required this.onTap});

  IconData get _icon {
    switch (action.iconName) {
      case 'auto_awesome': return Icons.auto_awesome;
      case 'mail': return Icons.mail_outline;
      case 'chat': return Icons.chat_bubble_outline;
      default: return Icons.flash_on;
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
            Icon(_icon, size: 18, color: HuddlColors.primary),
            const Spacer(),
            Text(action.label, style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            )),
            Text(action.description, style: GoogleFonts.poppins(
              fontSize: 9, color: context.hc.textTertiary,
            ), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
