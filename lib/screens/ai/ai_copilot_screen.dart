import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/ai_copilot_service.dart';
import '../main_shell.dart';
import 'package:url_launcher/url_launcher.dart';

// =============================================================================
// AI PARENTING COPILOT -- Full-screen chat interface
// Real conversational AI powered by Gemini
// =============================================================================

class AiCopilotScreen extends StatefulWidget {
  const AiCopilotScreen({super.key});

  @override
  State<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends State<AiCopilotScreen> {
  final AiCopilotService _copilot = AiCopilotService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _copilot.initialize();
    if (mounted) setState(() => _isInitialized = true);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isTyping) return;
    final query = text.trim();
    _inputController.clear();

    // Show the user message immediately
    setState(() => _isTyping = true);

    // Add user message to the service and get AI response
    try {
      await _copilot.sendMessage(query);
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTyping = false);
      }
    }

    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
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
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios,
              color: context.hc.textPrimary, size: 20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: HuddlColors.aiGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome,
                  color: context.hc.surface, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'huddl AI',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _copilot.isOnline
                            ? HuddlColors.successGreen
                            : HuddlColors.textHint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _copilot.isOnline ? 'Online' : 'Offline mode',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: _copilot.isOnline
                            ? HuddlColors.textSecondary
                            : HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_copilot.messages.isNotEmpty)
            IconButton(
              onPressed: () {
                _copilot.clearConversation();
                setState(() {});
              },
              icon: Icon(Icons.refresh,
                  color: context.hc.textTertiary, size: 22),
              tooltip: 'New conversation',
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _copilot.messages.isEmpty
                ? _buildWelcomeView()
                : _buildChatView(),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildWelcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: HuddlColors.aiGradient,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome,
                color: context.hc.surface, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Hi! I\'m your huddl AI copilot',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask me anything about parenting, local services,\nor huddl features. I\'m here to help!',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: context.hc.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // Feature cards
          _buildFeatureCard(
              Icons.health_and_safety,
              'Health & Development',
              'Milestones, sleep, feeding advice',
              HuddlColors.success,
              query: 'What milestones should my baby be hitting?'),
          _buildFeatureCard(
              Icons.location_on,
              'Local Services',
              'Nurseries, GPs, classes near you',
              HuddlColors.teal,
              query: 'Find nurseries near me'),
          _buildFeatureCard(
              Icons.storefront,
              'Market AI',
              'Sell items instantly with AI',
              HuddlColors.aiBlue,
              query: 'Help me sell an item on Market'),
          _buildFeatureCard(
              Icons.groups,
              'Meetups & Social',
              'Find compatible parents nearby',
              HuddlColors.teal,
              query: 'Help me plan a meetup with local parents'),
          const SizedBox(height: 24),
          // Quick actions
          Text(
            'Quick actions',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: (_isInitialized
                    ? _copilot.contextualQuickActions
                    : <CopilotQuickAction>[])
                .map((action) {
              return GestureDetector(
                onTap: () => _sendMessage(action.query),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.hc.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.hc.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(action.emoji,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        action.label,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.hc.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
      IconData icon, String title, String subtitle, Color color,
      {String? query}) {
    return GestureDetector(
      onTap: query != null ? () => _sendMessage(query) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.hc.divider),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textPrimary,
                      )),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: context.hc.textSecondary,
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: context.hc.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChatView() {
    final displayMessages = _copilot.messages;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: displayMessages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isTyping && index == displayMessages.length) {
          return _buildTypingIndicator();
        }
        final msg = displayMessages[index];
        return msg.isUser ? _buildUserBubble(msg) : _buildAiBubble(msg);
      },
    );
  }

  Widget _buildUserBubble(CopilotMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 60),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: HuddlColors.aiGradient,
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
            color: context.hc.surface,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildAiBubble(CopilotMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, right: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI label
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: HuddlColors.aiGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 12, color: HuddlColors.white),
                ),
                const SizedBox(width: 6),
                Text(
                  'huddl AI',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.aiBlue,
                  ),
                ),
              ],
            ),
          ),
          // Message bubble
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: msg.isError
                  ? HuddlColors.errorLight
                  : HuddlColors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(
                  color: msg.isError
                      ? HuddlColors.error.withValues(alpha: 0.3)
                      : HuddlColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRichText(msg.text),
                if (msg.actions != null && msg.actions!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: msg.actions!.map((action) {
                      return GestureDetector(
                        onTap: () => _handleActionTap(action),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: HuddlColors.blueBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getActionIcon(action.icon),
                                  size: 14, color: HuddlColors.aiBlue),
                              const SizedBox(width: 6),
                              Text(
                                action.label,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.aiBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (msg.sourceNote != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    msg.sourceNote!,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: context.hc.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Parse basic markdown bold (**text**) and bullet points
  Widget _buildRichText(String text) {
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        spans.add(const TextSpan(text: '\n'));
      }
      final line = lines[i];
      // Parse bold markers
      final boldRegex = RegExp(r'\*\*(.+?)\*\*');
      int lastEnd = 0;
      for (final match in boldRegex.allMatches(line)) {
        if (match.start > lastEnd) {
          spans.add(TextSpan(text: line.substring(lastEnd, match.start)));
        }
        spans.add(TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
        lastEnd = match.end;
      }
      if (lastEnd < line.length) {
        spans.add(TextSpan(text: line.substring(lastEnd)));
      }
    }

    return RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: context.hc.textPrimary,
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, right: 100),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: HuddlColors.aiGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome,
                size: 12, color: HuddlColors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.hc.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Thinking',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: context.hc.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 8),
                _TypingDot(delay: 0),
                const SizedBox(width: 4),
                _TypingDot(delay: 200),
                const SizedBox(width: 4),
                _TypingDot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: context.hc.surface,
        boxShadow: [
          BoxShadow(
            color: HuddlColors.gray900.withValues(alpha: 0.06),
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
              onSubmitted: _sendMessage,
              enabled: !_isTyping,
              textAlignVertical: TextAlignVertical.center,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: _isTyping
                    ? 'Waiting for response...'
                    : 'Ask me anything...',
                hintStyle: GoogleFonts.poppins(
                    fontSize: 14, color: context.hc.textTertiary),
                filled: true,
                fillColor: context.hc.scaffold,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isTyping
                ? null
                : () => _sendMessage(_inputController.text),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isTyping ? HuddlColors.gray300 : HuddlColors.primary,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.send, color: context.hc.surface, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  void _handleActionTap(CopilotAction action) {
    // External URLs
    if (action.route == 'url') {
      final url = action.params['url'] as String?;
      if (url != null) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      return;
    }

    // Tab-based navigation via MainShell
    final tabRoutes = {
      '/groups': 1,
      '/meetups': 2,
      '/marketplace': 3,
      '/profile': 4,
    };

    if (tabRoutes.containsKey(action.route)) {
      Navigator.pop(context);
      final shellState = MainShell.shellKey.currentState;
      if (shellState != null) {
        shellState.switchTab(tabRoutes[action.route]!);
      }
      return;
    }

    // Named route navigation
    if (action.route.startsWith('/')) {
      Navigator.pop(context);
      Navigator.pushNamed(context, action.route,
          arguments: action.params.isNotEmpty ? action.params : null);
      return;
    }
  }

  IconData _getActionIcon(String iconName) {
    const iconMap = {
      'health_and_safety': Icons.health_and_safety,
      'forum': Icons.forum,
      'groups': Icons.groups,
      'add': Icons.add,
      'storefront': Icons.storefront,
      'flight': Icons.flight,
      'search': Icons.search,
      'add_a_photo': Icons.add_a_photo,
      'auto_awesome': Icons.auto_awesome,
      'bedtime': Icons.bedtime,
      'group_add': Icons.group_add,
      'restaurant': Icons.restaurant,
      'timeline': Icons.timeline,
      'luggage': Icons.luggage,
    };
    return iconMap[iconName] ?? Icons.arrow_forward;
  }
}

class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: HuddlColors.aiBlue
              .withValues(alpha: 0.3 + _controller.value * 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
