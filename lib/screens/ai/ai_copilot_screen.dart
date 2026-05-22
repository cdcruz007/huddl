import 'dart:async';
import '../../services/browser_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../theme/huddl_colors.dart';
import '../../services/ai_copilot_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';


// =============================================================================
// §2B — Redesigned Huddl Co-pilot Screen
//
// Welcome state: personalised greeting, 3 dynamic contextual chips,
//   5 curated quick actions (unique to AI — no tab duplicates).
// Chat state: orange user bubbles, grey AI bubbles with sparkle avatar,
//   typing indicator, markdown rendering, keyboard-safe input bar.
// =============================================================================

class AiCopilotScreen extends StatefulWidget {
  final String? initialMessage;
  final bool autoSend;

  const AiCopilotScreen({
    super.key,
    this.initialMessage,
    this.autoSend = false,
  });

  @override
  State<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends State<AiCopilotScreen> {
  final AiCopilotService _copilot = AiCopilotService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  bool _isTyping = false;
  bool _isInitialized = false;

  // User context for personalised welcome state
  String _firstName = '';
  String _borough = '';
  List<String> _contextualChips = [];

  // §2C: Rate limiting — 20 messages/day (persisted daily via BrowserStorage)
  int _dailyMessageCount = 0;
  static const int _dailyLimit = 20;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _copilot.initialize();
    await _onboarding.initialize();

    if (!mounted) return;

    // Load user context for personalised welcome
    final name = _onboarding.name ?? '';
    _firstName = name.split(' ').first;
    final pc = _onboarding.postcode ?? '';
    _borough = _postcode.getBoroughFromPostcode(pc) ?? '';

    // §2D: Try Cloud Function first; fall back to local generation
    _contextualChips = await _fetchOrGenerateChips();

    _dailyMessageCount = await _loadDailyCount();
    if (mounted) setState(() => _isInitialized = true);

    // Pre-populate from home screen composer if provided
    final initial = widget.initialMessage?.trim() ?? '';
    if (initial.isNotEmpty) {
      if (widget.autoSend) {
        await _sendMessage(initial);
      } else {
        _inputController.text = initial;
        _inputController.selection =
            TextSelection.collapsed(offset: initial.length);
      }
    }
  }

  /// §2D: Call `generateCopilotSuggestions` Cloud Function.
  /// Falls back to local chip generation if the function is unavailable.
  Future<List<String>> _fetchOrGenerateChips() async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateCopilotSuggestions',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call();
      final raw = (result.data as Map<dynamic, dynamic>?)?['suggestions'];
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => e.toString()).take(3).toList();
      }
    } catch (_) {
      // Non-fatal — fall through to local generation
    }
    return _generateContextualChips();
  }

  /// §2D: Generate 3 contextual chips from user profile.
  List<String> _generateContextualChips() {
    final chips = <String>[];
    // stagesOfLife is the correct getter — e.g. ['expecting', 'newborn']
    final stages = _onboarding.stagesOfLife;
    final stage = stages.isNotEmpty ? stages.first : '';
    final borough = _borough.isNotEmpty ? _borough : 'your area';

    // Age-based chip — derived from childBirthday (stored as 'YYYY-MM-DD' string)
    final childBirthdayStr = _onboarding.childBirthday;
    if (childBirthdayStr != null && childBirthdayStr.isNotEmpty) {
      try {
        final childDob = DateTime.parse(childBirthdayStr);
        final ageMonths = DateTime.now().difference(childDob).inDays ~/ 30;
        if (ageMonths <= 3) {
          chips.add('Sleep tips for a $ageMonths-month-old');
        } else if (ageMonths <= 12) {
          chips.add('Milestones for a $ageMonths-month-old');
        } else if (ageMonths <= 36) {
          final years = ageMonths ~/ 12;
          chips.add('Activities for a $years-year-old');
        } else {
          chips.add('What should my child be doing this week?');
        }
      } catch (_) {
        chips.add('What should my child be doing this week?');
      }
    } else {
      chips.add('What should my child be doing this week?');
    }

    // Stage-based chip
    if (stage.toLowerCase().contains('expect')) {
      chips.add('What to expect this week of pregnancy');
    } else if (stage.toLowerCase().contains('new')) {
      chips.add('Newborn feeding and sleep schedules');
    } else {
      chips.add('Help me find parenting groups nearby');
    }

    // Location-based chip
    chips.add('Best parent groups in $borough');

    return chips.take(3).toList();
  }

  Future<int> _loadDailyCount() async {
    try {
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final raw = await BrowserStorage.getString('copilot_daily_$dateStr');
      return int.tryParse(raw ?? '') ?? 0;
    } catch (_) { return 0; }
  }

  Future<void> _saveDailyCount(int count) async {
    try {
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      await BrowserStorage.setString('copilot_daily_$dateStr', count.toString());
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isTyping) return;

    // §2C: Client-side daily rate limit guard (server also enforces)
    _dailyMessageCount = await _loadDailyCount();
    if (_dailyMessageCount >= _dailyLimit) {
      _showRateLimitMessage();
      return;
    }

    _inputController.clear();
    await _saveDailyCount(_dailyMessageCount + 1);
    _dailyMessageCount++;
    setState(() => _isTyping = true);

    try {
      await _copilot.sendMessage(query);
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _isTyping = false);
        // Handle server-side rate limit (resource-exhausted code)
        if (e.code == 'resource-exhausted') {
          _showRateLimitMessage();
        }
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _isTyping = false);
    }

    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _showRateLimitMessage() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome,
                  size: 40, color: HuddlColors.primary),
              const SizedBox(height: 16),
              Text(
                "You've reached today's chat limit.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Come back tomorrow — I\'ll be here!',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: context.hc.textSecondary),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('OK',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Scaffold(
      backgroundColor: hc.scaffold,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(hc),
      body: Column(
        children: [
          Expanded(
            child: _copilot.messages.isEmpty && !_isTyping
                ? _buildWelcomeView(hc)
                : _buildChatView(hc),
          ),
          _buildInputBar(hc),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  AppBar _buildAppBar(dynamic hc) {
    return AppBar(
      backgroundColor: hc.surface,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: hc.textPrimary, size: 20),
      ),
      title: Column(
        children: [
          Text(
            'huddl Assistant',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: hc.textPrimary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _copilot.isOnline
                      ? HuddlColors.teal
                      : HuddlColors.textHint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _copilot.isOnline ? 'Online' : 'Offline mode',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: _copilot.isOnline
                      ? HuddlColors.teal
                      : HuddlColors.textHint,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_copilot.messages.isNotEmpty)
          IconButton(
            onPressed: () async {
              _copilot.clearConversation();
              _dailyMessageCount = 0;
              await _saveDailyCount(0);
              setState(() {});
            },
            icon:
                Icon(Icons.refresh, color: hc.textTertiary, size: 22),
            tooltip: 'New conversation',
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── §2B Welcome state ─────────────────────────────────────────────────────
  Widget _buildWelcomeView(dynamic hc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          // Large orange sparkle icon — warm, not enterprise
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                size: 36, color: HuddlColors.primary),
          ),
          const SizedBox(height: 16),

          // Personalised greeting
          Text(
            _isInitialized && _firstName.isNotEmpty
                ? 'Hi $_firstName! 👋 What\'s on your mind?'
                : 'Hi there! 👋 What\'s on your mind?',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'I know your family, your area, and what\'s on locally. Ask me anything.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: hc.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // §2B: 3 dynamic contextual chips
          if (_isInitialized && _contextualChips.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _contextualChips
                  .map((chip) => _buildContextChip(chip, hc))
                  .toList(),
            ),
            const SizedBox(height: 28),
          ],

          // §2B: Quick actions — curated, AI-unique only
          Text(
            'Quick actions',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: hc.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _quickActions
                .map((action) => _buildQuickActionChip(action, hc))
                .toList(),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // §2B: 5 curated quick actions — unique to AI, no tab duplicates
  static const List<_QuickAction> _quickActions = [
    _QuickAction(
      emoji: '📋',
      label: 'What should I be doing this week?',
      query: 'What should I be doing with my child this week?',
    ),
    _QuickAction(
      emoji: '💬',
      label: 'Help me write a group message',
      query: 'Help me write a warm message to introduce myself to my parent group.',
    ),
    _QuickAction(
      emoji: '🤔',
      label: 'Is this meetup right for us?',
      query: 'Help me decide if a meetup is right for my family.',
    ),
    _QuickAction(
      emoji: '🗒️',
      label: 'Explain my child\'s EHCP rights',
      query: 'Can you explain my child\'s EHCP rights and what support we\'re entitled to?',
    ),
    _QuickAction(
      emoji: '🌟',
      label: 'Surprise me',
      query: 'What\'s the most relevant thing for my family today?',
    ),
  ];

  Widget _buildContextChip(String label, dynamic hc) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _sendMessage(label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: HuddlColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome,
                size: 13, color: HuddlColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: HuddlColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip(_QuickAction action, dynamic hc) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _sendMessage(action.query);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hc.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(action.emoji,
                style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              action.label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: hc.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat view ─────────────────────────────────────────────────────────────
  Widget _buildChatView(dynamic hc) {
    final displayMessages = _copilot.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: displayMessages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isTyping && index == displayMessages.length) {
          return _buildTypingIndicator(hc);
        }
        final msg = displayMessages[index];
        return msg.isUser
            ? _buildUserBubble(msg, hc)
            : _buildAiBubble(msg, hc);
      },
    );
  }

  // Orange bubble — right-aligned
  Widget _buildUserBubble(CopilotMessage msg, dynamic hc) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 60),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: HuddlColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          msg.text,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.white,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // Light grey bubble with sparkle avatar — left-aligned
  Widget _buildAiBubble(CopilotMessage msg, dynamic hc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Sparkle avatar
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                size: 14, color: HuddlColors.primary),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: hc.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                    border: Border.all(
                        color: hc.divider.withValues(alpha: 0.8)),
                  ),
                  child: _buildRichText(msg.text, hc),
                ),
                // Error retry
                if (msg.isError)
                  GestureDetector(
                    onTap: () => _sendMessage(
                        _copilot.messages
                            .lastWhere((m) => m.isUser)
                            .text),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Tap to retry',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // §2B: Markdown rendering — bold, bullets, line breaks
  Widget _buildRichText(String text, dynamic hc) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.startsWith('• ') || line.startsWith('- ')) {
          final content = line.substring(2);
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: hc.textSecondary)),
                Expanded(
                    child: _buildBoldText(content, hc, 14)),
              ],
            ),
          );
        }
        if (line.startsWith('**') && line.endsWith('**')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              line.replaceAll('**', ''),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: hc.textPrimary,
                height: 1.4,
              ),
            ),
          );
        }
        if (line.trim().isEmpty) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _buildBoldText(line, hc, 14),
        );
      }).toList(),
    );
  }

  Widget _buildBoldText(String text, dynamic hc, double fontSize) {
    final spans = <TextSpan>[];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: GoogleFonts.poppins(
          fontSize: fontSize,
          fontWeight: i.isOdd ? FontWeight.w700 : FontWeight.w400,
          color: hc.textPrimary,
          height: 1.4,
        ),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }

  // §2B: 3 animated dots typing indicator
  Widget _buildTypingIndicator(dynamic hc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, right: 24),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                size: 14, color: HuddlColors.primary),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border:
                  Border.all(color: hc.divider.withValues(alpha: 0.8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                _TypingDot(delay: 0),
                SizedBox(width: 4),
                _TypingDot(delay: 200),
                SizedBox(width: 4),
                _TypingDot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────
  Widget _buildInputBar(dynamic hc) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: hc.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              onSubmitted: _sendMessage,
              enabled: !_isTyping,
              textAlignVertical: TextAlignVertical.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: hc.textPrimary),
              decoration: InputDecoration(
                hintText: _isTyping
                    ? 'huddl is thinking...'
                    : 'Ask me anything...',
                hintStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: hc.textTertiary,
                    fontStyle: FontStyle.italic),
                filled: true,
                fillColor: hc.scaffold,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button — orange circle with arrow
          GestureDetector(
            onTap: _isTyping
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    _sendMessage(_inputController.text);
                  },
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _isTyping
                    ? HuddlColors.primary.withValues(alpha: 0.3)
                    : HuddlColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick action data class ───────────────────────────────────────────────
class _QuickAction {
  final String emoji;
  final String label;
  final String query;

  const _QuickAction({
    required this.emoji,
    required this.label,
    required this.query,
  });
}

// ── Animated typing dot ───────────────────────────────────────────────────
class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Color.lerp(
            HuddlColors.textHint,
            HuddlColors.primary,
            _anim.value,
          ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
