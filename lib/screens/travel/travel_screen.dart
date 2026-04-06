import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';
import '../../services/travel_community_service.dart';
import 'destination_detail_screen.dart';
import 'ask_parents_screen.dart';
import 'community_tips_screen.dart';
import 'my_travel_screen.dart';

/// Travel — "Invisible AI" redesign.
///
/// Design principles:
///  1. Less is more — one scannable feed, no button overload
///  2. Invisible AI — content is ranked/personalised behind the scenes
///  3. Progressive disclosure — sparkle icon reveals AI concierge bottom sheet
///  4. Predictive search — natural-language bar replaces browsing menus
///  5. Contextual intelligence — shows what matters NOW (upcoming trip / trending Q)
class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key});

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  final TravelService _travelService = TravelService();
  final TravelCommunityService _communityService = TravelCommunityService();
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // AI feedback state (thumbs up/down)
  final Set<String> _likedItems = {};
  final Set<String> _dislikedItems = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await _travelService.initialize();
    await _communityService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Color _hex(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));

  // ── AI concierge bottom sheet ────────────────────────────────────────
  void _openConcierge({String? prefill}) {
    HapticFeedback.lightImpact();
    final msgCtrl = TextEditingController(text: prefill);
    final conversations = <_ConciergeMsg>[];
    bool isTyping = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Handle + header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: HuddlColors.gray300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              gradient: HuddlColors.aiGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AI Travel Concierge',
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.onSurface)),
                                Text('Powered by ${_communityService.experts.length} parent experts',
                                    style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.teal)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 20,
                                color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),

                // Chat area
                Expanded(
                  child: conversations.isEmpty
                      ? _conciergeWelcome(ctx, (q) {
                          ss(() {
                            msgCtrl.text = q;
                          });
                          _sendConciergeMsg(q, conversations, ss, () => ss(() => isTyping = true), () => ss(() => isTyping = false));
                        })
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: conversations.length + (isTyping ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == conversations.length && isTyping) {
                              return _typingIndicator();
                            }
                            return _chatBubble(conversations[i]);
                          },
                        ),
                ),

                // Input
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: msgCtrl,
                              style: GoogleFonts.poppins(fontSize: 14),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (t) {
                                _sendConciergeMsg(t, conversations, ss,
                                    () => ss(() => isTyping = true),
                                    () => ss(() => isTyping = false));
                                msgCtrl.clear();
                              },
                              decoration: InputDecoration(
                                hintText: 'Ask about family travel...',
                                hintStyle: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            _sendConciergeMsg(msgCtrl.text, conversations, ss,
                                () => ss(() => isTyping = true),
                                () => ss(() => isTyping = false));
                            msgCtrl.clear();
                          },
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              gradient: HuddlColors.aiGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send, color: HuddlColors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendConciergeMsg(
      String text,
      List<_ConciergeMsg> conversations,
      StateSetter ss,
      VoidCallback onTypingStart,
      VoidCallback onTypingEnd) async {
    if (text.trim().isEmpty) return;
    ss(() => conversations.add(_ConciergeMsg(role: 'user', message: text.trim())));
    onTypingStart();

    try {
      final response = await _communityService.askCommunityAI(text.trim());
      ss(() => conversations.add(_ConciergeMsg(role: 'assistant', message: response)));
    } catch (e) {
      ss(() => conversations.add(_ConciergeMsg(
          role: 'assistant',
          message: "I'm having trouble connecting right now. Try asking the community directly!")));
    }
    onTypingEnd();
  }

  Widget _conciergeWelcome(BuildContext ctx, ValueChanged<String> onQuickTap) {
    final suggestions = [
      'Best family beach for a toddler?',
      'What should I pack for Tenerife?',
      'Is Mallorca safe with a baby?',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              gradient: HuddlColors.aiGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Ask me anything',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface)),
          const SizedBox(height: 6),
          Text('I draw from ${_communityService.questions.length} real parent conversations',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12,
                  color: Theme.of(ctx).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary)),
          const SizedBox(height: 24),
          ...suggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onQuickTap(s),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 16, color: HuddlColors.aiBlue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s,
                                style: GoogleFonts.poppins(fontSize: 13,
                                    fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _chatBubble(_ConciergeMsg msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? HuddlColors.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: isUser
              ? null
              : [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Text(
          msg.message,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: isUser ? HuddlColors.white : Theme.of(context).colorScheme.onSurface,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _typingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24, height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (i) => Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: HuddlColors.aiBlue.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                )),
              ),
            ),
            const SizedBox(width: 8),
            Text('Thinking...',
                style: GoogleFonts.poppins(fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.primary,
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _searchBar()),
              SliverToBoxAdapter(child: _contextCard()),
              SliverToBoxAdapter(child: _destinations()),
              SliverToBoxAdapter(child: _communityFeed()),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header — clean, minimal ─────────────────────────────────────────
  Widget _header() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('Travel',
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
            ),
          ),
          // Single subtle entry: AI sparkle
          Semantics(
            button: true,
            label: 'AI Travel Concierge',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openConcierge,
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: HuddlColors.aiGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'My Travel',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const MyTravelScreen()));
                },
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: HuddlColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.luggage_outlined, color: HuddlColors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Predictive search bar ───────────────────────────────────────────
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.transparent
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          style: GoogleFonts.poppins(fontSize: 14),
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              _openConcierge(prefill: v.trim());
              _searchCtrl.clear();
              setState(() => _searchQuery = '');
            }
          },
          decoration: InputDecoration(
            hintText: 'Ask anything — "Is Crete good for toddlers?"',
            hintStyle: GoogleFonts.poppins(fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
            prefixIcon: Icon(Icons.search, size: 20,
                color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Context card — AI-detected, shows what matters NOW ──────────────
  Widget _contextCard() {
    // Simulated contextual intelligence:
    // In production, AI would rank what to show based on user behavior,
    // upcoming trips, time of year, etc.
    final unanswered = _communityService.questions
        .where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty)
        .toList();

    if (unanswered.isEmpty) return const SizedBox.shrink();

    final q = unanswered.first;
    final color = _hex(q.authorAvatarColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Semantics(
        button: true,
        label: '${q.authorName} needs help: ${q.question}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AskParentsScreen())),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.transparent
                        : Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8, offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI label
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: HuddlColors.primary),
                      const SizedBox(width: 6),
                      Text('A parent needs your help',
                          style: GoogleFonts.poppins(fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary)),
                      const Spacer(),
                      Text(_timeAgo(q.createdAt),
                          style: GoogleFonts.poppins(fontSize: 10,
                              color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Text(q.authorName[0],
                            style: GoogleFonts.poppins(fontSize: 13,
                                fontWeight: FontWeight.w600, color: color)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(q.authorName,
                                style: GoogleFonts.poppins(fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onSurface)),
                            const SizedBox(height: 2),
                            Text(q.question,
                                style: GoogleFonts.poppins(fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    height: 1.4),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (q.destination != null || q.childAge != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      if (q.destination != null) _chip(q.destination!, HuddlColors.blue),
                      if (q.destination != null && q.childAge != null) const SizedBox(width: 6),
                      if (q.childAge != null) _chip(q.childAge!, HuddlColors.teal),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Destinations — compact, AI-ranked ───────────────────────────────
  Widget _destinations() {
    var popular = _travelService.popularDestinations;
    // Filter by search
    if (_searchQuery.isNotEmpty) {
      popular = popular
          .where((d) =>
              d.name.toLowerCase().contains(_searchQuery) ||
              d.country.toLowerCase().contains(_searchQuery))
          .toList();
    }
    if (popular.isEmpty) return const SizedBox.shrink();

    final emojis = {
      'Tenerife': '🌴', 'Mallorca': '🏖️', 'Algarve': '🌊',
      'Costa del Sol': '☀️', 'Lake Garda': '⛵', 'Cornwall': '🏄',
      'Cotswolds': '🌿', 'Crete': '🏛️',
    };
    final colors = {
      'Tenerife': const Color(0xFFFF975C), 'Mallorca': const Color(0xFF3580F0),
      'Algarve': const Color(0xFF199A85), 'Costa del Sol': const Color(0xFFF3C54F),
      'Lake Garda': const Color(0xFF5B9DFF), 'Cornwall': const Color(0xFF22C55E),
      'Cotswolds': const Color(0xFF78B0FF), 'Crete': const Color(0xFFF69F72),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Semantics(
                  header: true,
                  child: Text('Popular with families',
                      style: GoogleFonts.poppins(fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
                const Spacer(),
                _aiLabel('Personalised'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: popular.length,
              itemBuilder: (_, i) {
                final d = popular[i];
                final emoji = emojis[d.name] ?? '✈️';
                final c = colors[d.name] ?? HuddlColors.primary;
                return Semantics(
                  button: true,
                  label: '${d.name}, ${d.country}. ${d.rating} stars.',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(context, MaterialPageRoute(
                            builder: (_) => DestinationDetailScreen(destination: d)));
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 120,
                        margin: EdgeInsets.only(right: i < popular.length - 1 ? 10 : 0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.transparent
                                  : Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8, offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Emoji header
                            Container(
                              height: 60,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [c.withValues(alpha: 0.18), c.withValues(alpha: 0.05)],
                                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                                ),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                              ),
                              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.name,
                                      style: GoogleFonts.poppins(fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.onSurface)),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, size: 11, color: HuddlColors.accentAmber),
                                      const SizedBox(width: 2),
                                      Text('${d.rating}',
                                          style: GoogleFonts.poppins(fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.onSurface)),
                                      const SizedBox(width: 4),
                                      Text('${d.huddlParentsVisited} families',
                                          style: GoogleFonts.poppins(fontSize: 9,
                                              color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Unified community feed — AI-ranked blend of Q&A + tips ─────────
  Widget _communityFeed() {
    // Blend recent Q&A and tips into a single ranked feed
    final questions = _communityService.recentQuestions.take(3).toList();
    final tips = _communityService.trendingTips.take(2).toList();

    if (questions.isEmpty && tips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                header: true,
                child: Text('From the community',
                    style: GoogleFonts.poppins(fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface)),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: 'See all community conversations',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AskParentsScreen())),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text('See all',
                          style: GoogleFonts.poppins(fontSize: 13,
                              fontWeight: FontWeight.w500, color: HuddlColors.primary)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Questions
          ...questions.map((q) => _feedQuestionCard(q)),

          // Tips (interleaved)
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 4),
            _feedTipsRow(tips),
          ],
        ],
      ),
    );
  }

  Widget _feedQuestionCard(TravelQuestion q) {
    final color = _hex(q.authorAvatarColor);
    final replies = q.answers.where((a) => !a.isAiGenerated).length;
    final id = 'q_${q.question.hashCode}';

    return Semantics(
      button: true,
      label: '${q.authorName}: ${q.question}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AskParentsScreen())),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6, offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(q.authorName[0],
                          style: GoogleFonts.poppins(fontSize: 10,
                              fontWeight: FontWeight.w600, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(q.authorName,
                          style: GoogleFonts.poppins(fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface)),
                    ),
                    if (replies > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: HuddlColors.teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$replies ${replies == 1 ? 'reply' : 'replies'}',
                            style: GoogleFonts.poppins(fontSize: 10,
                                fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                      ),
                    Text('  ${_timeAgo(q.createdAt)}',
                        style: GoogleFonts.poppins(fontSize: 10,
                            color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(q.question,
                    style: GoogleFonts.poppins(fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                // Tags + AI feedback
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (q.destination != null) _chip(q.destination!, HuddlColors.blue),
                    if (q.destination != null && q.childAge != null) const SizedBox(width: 6),
                    if (q.childAge != null) _chip(q.childAge!, HuddlColors.teal),
                    const Spacer(),
                    // AI feedback loop — thumbs up/down
                    _feedbackButtons(id),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedTipsRow(List<CommunityTip> tips) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 16, color: HuddlColors.teal),
            const SizedBox(width: 6),
            Text('Top tips',
                style: GoogleFonts.poppins(fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface)),
            const Spacer(),
            Semantics(
              button: true,
              label: 'See all tips',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const CommunityTipsScreen())),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('More',
                        style: GoogleFonts.poppins(fontSize: 12,
                            fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...tips.map((CommunityTip tip) {
          final id = 'tip_${tip.tip.hashCode}';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6, offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _hex(tip.authorAvatarColor).withValues(alpha: 0.15),
                  child: Text(tip.authorName[0],
                      style: GoogleFonts.poppins(fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _hex(tip.authorAvatarColor))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tip.tip,
                          style: GoogleFonts.poppins(fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface,
                              height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _chip(tip.destination, HuddlColors.blue),
                          const SizedBox(width: 6),
                          _chip(tip.childAge, HuddlColors.teal),
                          const Spacer(),
                          _feedbackButtons(id),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── AI feedback buttons (thumbs up/down) ────────────────────────────
  Widget _feedbackButtons(String id) {
    final liked = _likedItems.contains(id);
    final disliked = _dislikedItems.contains(id);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              if (liked) {
                _likedItems.remove(id);
              } else {
                _likedItems.add(id);
                _dislikedItems.remove(id);
              }
            });
          },
          child: Icon(
            liked ? Icons.thumb_up : Icons.thumb_up_outlined,
            size: 15,
            color: liked ? HuddlColors.primary : (Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              if (disliked) {
                _dislikedItems.remove(id);
              } else {
                _dislikedItems.add(id);
                _likedItems.remove(id);
              }
            });
          },
          child: Icon(
            disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
            size: 15,
            color: disliked ? HuddlColors.error : (Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint),
          ),
        ),
      ],
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────────
  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }

  Widget _aiLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: HuddlColors.aiBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 10, color: HuddlColors.aiBlue),
          const SizedBox(width: 3),
          Text(text,
              style: GoogleFonts.poppins(fontSize: 9,
                  fontWeight: FontWeight.w500, color: HuddlColors.aiBlue)),
        ],
      ),
    );
  }
}

/// Simple message model for the bottom-sheet concierge
class _ConciergeMsg {
  final String role;
  final String message;
  _ConciergeMsg({required this.role, required this.message});
}
