import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/ai_copilot_service.dart';
import '../main_shell.dart';
import 'package:url_launcher/url_launcher.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AI PARENTING COPILOT — Full-screen chat interface
// Cross-feature assistant accessible from any screen
// ═══════════════════════════════════════════════════════════════════════════════

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

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    setState(() => _isTyping = true);

    // Simulate typing delay
    Future.delayed(const Duration(milliseconds: 800), () {
      _copilot.sendMessage(text.trim());
      if (mounted) {
        setState(() => _isTyping = false);
        _scrollToBottom();
      }
    });

    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: HuddlColors.textDark, size: 20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'huddl AI',
                  style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
                Text(
                  'Your parenting copilot',
                  style: GoogleFonts.poppins(
                    fontSize: 11, color: HuddlColors.textSecondary,
                  ),
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
              icon: const Icon(Icons.refresh, color: HuddlColors.textHint, size: 22),
              tooltip: 'Clear conversation',
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
              gradient: HuddlColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Hi! I\'m your huddl AI copilot',
            style: GoogleFonts.poppins(
              fontSize: 20, fontWeight: FontWeight.w700,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'I know your community inside out.\nAsk me anything about parenting, local services, or huddl features!',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13, color: HuddlColors.textSecondary, height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // Feature cards
          _buildFeatureCard(Icons.health_and_safety, 'Health & Development',
              'Milestones, sleep, feeding advice', HuddlColors.success,
              query: 'What milestones should my baby be hitting?'),
          _buildFeatureCard(Icons.location_on, 'Local Services',
              'Nurseries, GPs, classes near you', HuddlColors.blue,
              query: 'Find nurseries near me'),
          _buildFeatureCard(Icons.storefront, 'Preloved AI',
              'Sell items instantly with AI', HuddlColors.primary,
              query: 'Help me sell an item on Preloved'),
          _buildFeatureCard(Icons.groups, 'Meetups & Social',
              'Find compatible parents nearby', HuddlColors.teal,
              query: 'Help me plan a meetup with local parents'),
          _buildFeatureCard(Icons.flight, 'Family Travel',
              'Destinations & packing lists', HuddlColors.accentAmber,
              query: 'Best family-friendly holiday destinations'),
          const SizedBox(height: 24),
          // Quick actions
          Text(
            'Quick actions',
            style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: (_isInitialized ? _copilot.contextualQuickActions : []).map((action) {
              return GestureDetector(
                onTap: () => _sendMessage(action.query),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: HuddlColors.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(action.emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        action.label,
                        style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: HuddlColors.textDark,
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

  Widget _buildFeatureCard(IconData icon, String title, String subtitle, Color color, {String? query}) {
    return GestureDetector(
      onTap: query != null ? () => _sendMessage(query) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.divider),
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
                  Text(title, style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark,
                  )),
                  Text(subtitle, style: GoogleFonts.poppins(
                    fontSize: 11, color: HuddlColors.textSecondary,
                  )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: HuddlColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChatView() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _copilot.messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isTyping && index == _copilot.messages.length) {
          return _buildTypingIndicator();
        }
        final msg = _copilot.messages[index];
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
          gradient: HuddlColors.primaryGradient,
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
            fontSize: 14, color: HuddlColors.white, height: 1.4,
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
                    gradient: HuddlColors.primaryGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 12, color: HuddlColors.white),
                ),
                const SizedBox(width: 6),
                Text(
                  'huddl AI',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: HuddlColors.primary,
                  ),
                ),
              ],
            ),
          ),
          // Message bubble
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HuddlColors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: HuddlColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.text,
                  style: GoogleFonts.poppins(
                    fontSize: 13, color: HuddlColors.textDark, height: 1.5,
                  ),
                ),
                if (msg.actions != null && msg.actions!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: msg.actions!.map((action) {
                      return GestureDetector(
                        onTap: () => _handleActionTap(action),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: HuddlColors.peachLight,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getActionIcon(action.icon), size: 14, color: HuddlColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                action.label,
                                style: GoogleFonts.poppins(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: HuddlColors.primary,
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
                      fontSize: 10, color: HuddlColors.textHint,
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

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, right: 100),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: HuddlColors.primaryGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome, size: 12, color: HuddlColors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: HuddlColors.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
      padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        boxShadow: [
          BoxShadow(
            color: HuddlColors.gray900.withValues(alpha: 0.06),
            blurRadius: 10, offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              onSubmitted: _sendMessage,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ask me anything...',
                hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                filled: true,
                fillColor: HuddlColors.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(_inputController.text),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: HuddlColors.white, size: 20),
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
      '/trips': 4,
      '/profile': 5,
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
      Navigator.pushNamed(context, action.route, arguments: action.params.isNotEmpty ? action.params : null);
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

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
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
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.3 + _controller.value * 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
