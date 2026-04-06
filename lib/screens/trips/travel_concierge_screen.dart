import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';
import '../../services/travel_community_service.dart';
import 'destination_detail_screen.dart';
import 'packing_list_screen.dart';


// ═══════════════════════════════════════════════════════════════════════════════
// AI TRAVEL CONCIERGE — Chat-based travel assistant
// ═══════════════════════════════════════════════════════════════════════════════

class TravelConciergeScreen extends StatefulWidget {
  const TravelConciergeScreen({super.key});

  @override
  State<TravelConciergeScreen> createState() => _TravelConciergeScreenState();
}

class _TravelConciergeScreenState extends State<TravelConciergeScreen> {
  final TravelService _travelService = TravelService();
  final TravelCommunityService _communityService = TravelCommunityService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  final bool _useCommunityAI = true; // Toggle between community-enhanced and basic AI

  final List<String> _quickActions = [
    'Best places for a toddler?',
    'Tell me about Tenerife',
    'What should I pack?',
    'Is Spain safe for babies?',
    'Indoor activities for rain?',
    'Malaga with kids?',
  ];

  @override
  void initState() {
    super.initState();
    _travelService.initialize();
    _communityService.initialize();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _messageController.clear();
    setState(() => _isTyping = true);

    if (_useCommunityAI) {
      // Use community-enhanced AI that draws from parent Q&A data
      try {
        final response = await _communityService.askCommunityAI(text.trim());
        // Add user message
        _travelService.addConversation(
          role: 'user',
          message: text.trim(),
        );
        // Add AI response with community context
        _travelService.addConversation(
          role: 'assistant',
          message: response,
          actionType: _detectActionType(text.trim()),
        );
      } catch (e) {
        // Fallback to basic concierge
        await _travelService.askConcierge(text.trim());
      }
    } else {
      await _travelService.askConcierge(text.trim());
    }

    setState(() => _isTyping = false);
    _scrollToBottom();
  }

  String? _detectActionType(String query) {
    final q = query.toLowerCase();
    if (q.contains('pack') || q.contains('bring') || q.contains('luggage')) return 'packing';
    if (q.contains('safe') || q.contains('health') || q.contains('vaccine') || q.contains('medicine')) return 'safety';
    if (q.contains('about') || q.contains('tell me') || q.contains('info')) return 'destination';
    return null;
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
    final conversations = _travelService.conversations;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Travel Concierge', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                Text('Powered by ${_communityService.experts.length} parent experts', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.teal)),
              ],
            ),
          ],
        ),
        actions: [
          if (conversations.isNotEmpty)
            IconButton(
              icon: Icon(Icons.refresh, size: 20, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
              onPressed: () {
                _travelService.clearConversations();
                setState(() {});
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Chat messages ──────────────────────────────────────
          Expanded(
            child: conversations.isEmpty
                ? _buildWelcomeView()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: conversations.length + (_isTyping ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == conversations.length && _isTyping) {
                        return _buildTypingIndicator();
                      }
                      return _buildMessageBubble(conversations[i]);
                    },
                  ),
          ),
          // ── Quick actions (only if empty) ──────────────────────
          if (conversations.isEmpty) _buildQuickActions(),
          // ── Input bar ──────────────────────────────────────────
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── Welcome view ────────────────────────────────────────────────────────

  Widget _buildWelcomeView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 30),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: HuddlColors.aiGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: HuddlColors.aiBlue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 40),
          ),
          const SizedBox(height: 24),
          Text('Your AI Travel Concierge', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text(
            'I know what huddl parents say about every destination.\nAsk me anything about family travel!',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 32),
          // Community stats
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HuddlColors.teal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('${_communityService.questions.length}', 'Questions'),
                Container(width: 1, height: 30, color: Theme.of(context).dividerColor),
                _buildStatItem('${_communityService.experts.length}', 'Experts'),
                Container(width: 1, height: 30, color: Theme.of(context).dividerColor),
                _buildStatItem('${_communityService.tips.length}', 'Tips'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Feature highlights
          _buildFeatureRow(Icons.people, 'Community intelligence', 'Drawing from ${_communityService.questions.length} real parent Q&As'),
          _buildFeatureRow(Icons.child_care, 'Age-aware advice', 'Personalised to your children\'s ages'),
          _buildFeatureRow(Icons.luggage, 'Smart packing lists', 'Generated for your family & destination'),
          _buildFeatureRow(Icons.forum, 'Ask Parents', 'Can\'t find what you need? Ask the community'),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(children: [
      Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: HuddlColors.teal)),
      Text(label, style: GoogleFonts.poppins(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
    ]);
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: HuddlColors.aiBlue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
              Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary)),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Chat bubble ─────────────────────────────────────────────────────────

  Widget _buildMessageBubble(TravelConversation msg) {
    final isUser = msg.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? HuddlColors.primary : HuddlColors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: isUser ? null : [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: HuddlColors.aiBlue),
                    const SizedBox(width: 4),
                    Text('AI Concierge', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.aiBlue)),
                  ],
                ),
              ),
            Text(
              msg.message,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: isUser ? HuddlColors.white : HuddlColors.textDark,
                height: 1.5,
              ),
            ),
            if (msg.actionType != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildActionButton(msg.actionType!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String type) {
    IconData icon;
    String label;
    switch (type) {
      case 'destination':
        icon = Icons.place;
        label = 'View destination';
        break;
      case 'packing':
        icon = Icons.luggage;
        label = 'Generate packing list';
        break;
      case 'safety':
        icon = Icons.health_and_safety;
        label = 'View safety details';
        break;
      default:
        icon = Icons.arrow_forward;
        label = 'Learn more';
    }

    return GestureDetector(
      onTap: () => _handleActionTap(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: HuddlColors.aiBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: HuddlColors.aiBlue),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
          ],
        ),
      ),
    );
  }

  void _handleActionTap(String type) {
    // Try to find a matching destination from the conversation context
    TravelDestination? dest;
    final dests = _travelService.destinations;

    // Check conversations for destination mentions
    for (final conv in _travelService.conversations.reversed) {
      final msg = conv.message.toLowerCase();
      for (final d in dests) {
        if (msg.contains(d.name.toLowerCase())) {
          dest = d;
          break;
        }
      }
      if (dest != null) break;
    }

    dest ??= dests.isNotEmpty ? dests.first : null;
    if (dest == null) return;

    switch (type) {
      case 'destination':
        Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetailScreen(destination: dest!)));
        break;
      case 'packing':
        Navigator.push(context, MaterialPageRoute(builder: (_) => PackingListScreen(destination: dest!)));
        break;
      case 'safety':
        Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetailScreen(destination: dest!)));
        // On arrival, the Safety tab (index 3) could be pre-selected
        break;
    }
  }

  // ── Typing indicator ────────────────────────────────────────────────────

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(0), const SizedBox(width: 4), _buildDot(1), const SizedBox(width: 4), _buildDot(2),
            const SizedBox(width: 8),
            Text('Searching community reviews...', style: GoogleFonts.poppins(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return _AnimatedDot(delay: index * 200);
  }

  // ── Quick actions ───────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _quickActions.map((action) => GestureDetector(
          onTap: () => _sendMessage(action),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.3)),
            ),
            child: Text(action, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.aiBlue, fontWeight: FontWeight.w500)),
          ),
        )).toList(),
      ),
    );
  }

  // ── Input bar ───────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(24)),
                child: TextField(
                  controller: _messageController,
                  style: GoogleFonts.poppins(fontSize: 14),
                  textInputAction: TextInputAction.send,
                  onSubmitted: _sendMessage,
                  decoration: InputDecoration(
                    hintText: 'Ask about family travel...',
                    hintStyle: GoogleFonts.poppins(fontSize: 14, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _sendMessage(_messageController.text),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(gradient: HuddlColors.aiGradient, shape: BoxShape.circle),
                child: const Icon(Icons.send, color: HuddlColors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated pulsing dot for typing indicator
class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween(begin: 0.3, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
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
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(
          color: HuddlColors.aiBlue,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
