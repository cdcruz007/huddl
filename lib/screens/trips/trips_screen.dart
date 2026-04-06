import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';
import '../../services/travel_community_service.dart';
import 'destination_detail_screen.dart';
import 'travel_concierge_screen.dart';
import 'ask_parents_screen.dart';
import 'parent_experts_screen.dart';
import 'community_tips_screen.dart';
import 'my_trips_screen.dart';
import '../ai/ai_copilot_screen.dart';

// =============================================================================
// HUDDL TRIPS — WhatsApp-style Live Community Feed
// "A parent just asked a question — jump in and help!"
// The Trips screen now feels like an active group chat, not a passive forum.
// =============================================================================

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> with TickerProviderStateMixin {
  final TravelService _travelService = TravelService();
  final TravelCommunityService _communityService = TravelCommunityService();
  bool _isLoading = true;

  // Live activity simulation
  Timer? _activityTimer;
  int _onlineParents = 0;
  String _typingParent = '';
  bool _showTypingIndicator = false;
  int _newActivityCount = 0;
  List<_LiveActivity> _liveActivities = [];
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _loadData();
  }

  Future<void> _loadData() async {
    await _travelService.initialize();
    await _communityService.initialize();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _onlineParents = 14 + DateTime.now().minute % 8;
      });
      _startLiveActivity();
    }
  }

  void _startLiveActivity() {
    // Simulate live activity like WhatsApp
    _liveActivities = [
      _LiveActivity(type: 'answer', parent: 'Sarah M.', text: 'just answered a question about Tenerife', time: DateTime.now().subtract(const Duration(minutes: 2)), color: '#FF975C'),
      _LiveActivity(type: 'question', parent: 'New mum', text: 'asked: "Flying with a 4-month-old — help!"', time: DateTime.now().subtract(const Duration(minutes: 5)), color: '#78B0FF', isUrgent: true),
      _LiveActivity(type: 'tip', parent: 'Tom & Emma', text: 'shared a tip about Mallorca', time: DateTime.now().subtract(const Duration(minutes: 8)), color: '#3580F0'),
    ];

    _activityTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (!mounted) return;
      final parents = ['Priya K.', 'Meg C.', 'Rachel W.', 'James', 'Laura S.'];
      final actions = ['is typing an answer...', 'is reading questions...', 'just joined Trips'];
      setState(() {
        _typingParent = parents[timer.tick % parents.length];
        _showTypingIndicator = timer.tick % 3 != 0;
        if (timer.tick % 4 == 0) _newActivityCount++;
      });
    });
  }

  @override
  void dispose() {
    _activityTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildLiveHeader()),
                SliverToBoxAdapter(child: _buildOnlineBar()),
                SliverToBoxAdapter(child: _buildUrgentHelpBanner()),
                SliverToBoxAdapter(child: _buildLiveActivityFeed()),
                SliverToBoxAdapter(child: _buildNeedsYourHelpSection()),
                SliverToBoxAdapter(child: _buildQuickActionBar()),
                SliverToBoxAdapter(child: _buildHotConversations()),
                SliverToBoxAdapter(child: _buildMyTripsCard()),
                SliverToBoxAdapter(child: _buildExpertsRow()),
                SliverToBoxAdapter(child: _buildPopularDestinations()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
    );
  }

  // ── Live Header with pulse ──────────────────────────────────────────────
  Widget _buildLiveHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 0),
      child: Row(
        children: [
          // Live pulse dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: HuddlColors.primary.withValues(alpha: _pulseAnimation.value * 0.3), blurRadius: 12, spreadRadius: 2)],
              ),
              child: const Icon(Icons.flight_takeoff, color: HuddlColors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Trips', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
                    const SizedBox(width: 8),
                    // Live indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: HuddlColors.successGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (_, __) => Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: HuddlColors.successGreen.withValues(alpha: _pulseAnimation.value),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('Live', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.successGreen)),
                      ]),
                    ),
                  ],
                ),
                Text('Parents helping parents, right now', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiCopilotScreen())),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  // ── Online parents bar (WhatsApp-style) ─────────────────────────────────
  Widget _buildOnlineBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HuddlColors.successGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.successGreen.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Stacked avatars
          SizedBox(
            width: 60, height: 28,
            child: Stack(
              children: List.generate(3, (i) => Positioned(
                left: i * 18.0,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: [HuddlColors.primary, HuddlColors.blue, HuddlColors.teal][i],
                    shape: BoxShape.circle,
                    border: Border.all(color: HuddlColors.white, width: 2),
                  ),
                  child: Center(child: Text(['S', 'T', 'P'][i], style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white))),
                ),
              )),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_onlineParents parents online now', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                if (_showTypingIndicator)
                  Row(
                    children: [
                      Text('$_typingParent is typing', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.successGreen, fontStyle: FontStyle.italic)),
                      const SizedBox(width: 4),
                      _TypingDots(),
                    ],
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: HuddlColors.successGreen, borderRadius: BorderRadius.circular(10)),
            child: Text('Join', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.white)),
          ),
        ],
      ),
    );
  }

  // ── Urgent Help Banner ──────────────────────────────────────────────────
  Widget _buildUrgentHelpBanner() {
    final unanswered = _communityService.questions.where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty).toList();
    if (unanswered.isEmpty) return const SizedBox.shrink();

    final urgent = unanswered.first;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF0E6), Color(0xFFFFE8D6)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            // Animated hand wave
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, __) => Transform.rotate(
                angle: _pulseAnimation.value * 0.2 - 0.1,
                child: Text('🙋', style: TextStyle(fontSize: 28 + _pulseAnimation.value * 4)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(6)),
                        child: Text('NEEDS YOUR HELP', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: HuddlColors.white, letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 6),
                      Text(_timeAgo(urgent.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(urgent.question, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('Be the first parent to help ${urgent.authorName}!', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.reply, color: HuddlColors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live Activity Feed (WhatsApp group vibes) ───────────────────────────
  Widget _buildLiveActivityFeed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: HuddlColors.successGreen, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Live Activity', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const Spacer(),
              if (_newActivityCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('+$_newActivityCount new', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ..._liveActivities.map((a) => _buildActivityItem(a)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(_LiveActivity activity) {
    final color = Color(int.parse(activity.color.replaceFirst('#', '0xFF')));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: activity.isUrgent ? HuddlColors.primary.withValues(alpha: 0.06) : HuddlColors.background,
            borderRadius: BorderRadius.circular(10),
            border: activity.isUrgent ? Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14, backgroundColor: color.withValues(alpha: 0.15),
                child: Text(activity.parent[0], style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark),
                    children: [
                      TextSpan(text: activity.parent, style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: ' ${activity.text}'),
                    ],
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(_timeAgo(activity.time), style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
              if (activity.isUrgent) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.reply, color: HuddlColors.white, size: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── "Needs Your Help" — Unanswered questions with urgency ───────────────
  Widget _buildNeedsYourHelpSection() {
    final unanswered = _communityService.questions
        .where((q) => q.answers.where((a) => !a.isAiGenerated).length < 2)
        .take(3)
        .toList();

    if (unanswered.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.front_hand, size: 18, color: HuddlColors.primary),
              const SizedBox(width: 6),
              Text('Parents need your help', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
                child: Text('See all', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Your experience could help these parents right now', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
          const SizedBox(height: 10),
          ...unanswered.map((q) => _buildHelpCard(q)),
        ],
      ),
    );
  }

  Widget _buildHelpCard(TravelQuestion question) {
    final color = Color(int.parse(question.authorAvatarColor.replaceFirst('#', '0xFF')));
    final parentAnswers = question.answers.where((a) => !a.isAiGenerated).length;
    final waitTime = DateTime.now().difference(question.createdAt);
    final isUrgent = waitTime.inHours < 2 && parentAnswers == 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isUrgent ? HuddlColors.primary.withValues(alpha: 0.3) : HuddlColors.divider),
          boxShadow: isUrgent ? [BoxShadow(color: HuddlColors.primary.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(question.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(question.authorName, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                    Text('Waiting ${_timeAgo(question.createdAt).replaceAll(' ago', '')}', style: GoogleFonts.poppins(fontSize: 10, color: isUrgent ? HuddlColors.primary : HuddlColors.textHint)),
                  ]),
                ),
                if (parentAnswers == 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.reply, size: 12, color: HuddlColors.white),
                      const SizedBox(width: 3),
                      Text('Help', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                    ]),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('$parentAnswers replied', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(question.question, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                if (question.destination != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: HuddlColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(question.destination!, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.blue)),
                  ),
                  const SizedBox(width: 6),
                ],
                if (question.childAge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(question.childAge!, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                  ),
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 12, color: HuddlColors.textHint),
                const SizedBox(width: 3),
                Text('${question.views}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick Action Bar ────────────────────────────────────────────────────
  Widget _buildQuickActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _buildQuickAction(Icons.edit, 'Ask a\nQuestion', HuddlColors.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen()))),
          const SizedBox(width: 10),
          _buildQuickAction(Icons.lightbulb, 'Share a\nTip', HuddlColors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityTipsScreen()))),
          const SizedBox(width: 10),
          _buildQuickAction(Icons.auto_awesome, 'AI Travel\nConcierge', HuddlColors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen()))),
          const SizedBox(width: 10),
          _buildQuickAction(Icons.emoji_events, 'Parent\nExperts', HuddlColors.accentAmber, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentExpertsScreen()))),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color, height: 1.2), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  // ── Hot Conversations (active threads) ──────────────────────────────────
  Widget _buildHotConversations() {
    final hot = _communityService.hotQuestions.where((q) => q.answers.isNotEmpty).take(3).toList();
    if (hot.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, size: 18, color: HuddlColors.error),
              const SizedBox(width: 6),
              Text('Hot Conversations', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
                child: Text('Join in', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...hot.map((q) => _buildHotConversationCard(q)),
        ],
      ),
    );
  }

  Widget _buildHotConversationCard(TravelQuestion question) {
    final parentAnswers = question.answers.where((a) => !a.isAiGenerated).toList();
    final lastAnswer = parentAnswers.isNotEmpty ? parentAnswers.last : null;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question preview
            Text(question.question, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            // Latest answer preview (chat-like)
            if (lastAnswer != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Color(int.parse(lastAnswer.authorAvatarColor.replaceFirst('#', '0xFF'))).withValues(alpha: 0.15),
                      child: Text(lastAnswer.authorName[0], style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w600, color: Color(int.parse(lastAnswer.authorAvatarColor.replaceFirst('#', '0xFF'))))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(lastAnswer.authorName, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                              if (lastAnswer.hasBeenThereBadge) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, size: 10, color: HuddlColors.teal),
                              ],
                            ],
                          ),
                          Text(lastAnswer.content, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.chat_bubble, size: 12, color: HuddlColors.primary),
                    const SizedBox(width: 4),
                    Text('${parentAnswers.length} replies', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                  ]),
                ),
                const SizedBox(width: 6),
                Icon(Icons.thumb_up, size: 12, color: HuddlColors.textHint),
                const SizedBox(width: 3),
                Text('${question.totalUpvotes}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text('Join conversation', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── My Trips Card ───────────────────────────────────────────────────────
  Widget _buildMyTripsCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTripsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFF3ED), Color(0xFFFFFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(gradient: HuddlColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.luggage, color: HuddlColors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Trips', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text('Checklists, packing lists & saved research', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
          ])),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_forward_ios, size: 12, color: HuddlColors.primary),
          ),
        ]),
      ),
    );
  }

  // ── Experts Row ─────────────────────────────────────────────────────────
  Widget _buildExpertsRow() {
    final experts = _communityService.topExperts.take(5).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('Parent Experts', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentExpertsScreen())),
                child: Text('View all', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: experts.length,
              itemBuilder: (ctx, i) {
                final expert = experts[i];
                final color = Color(int.parse(expert.avatarColor.replaceFirst('#', '0xFF')));
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentExpertsScreen())),
                  child: Container(
                    width: 80, margin: const EdgeInsets.only(right: 10),
                    child: Column(children: [
                      Stack(children: [
                        CircleAvatar(radius: 26, backgroundColor: color.withValues(alpha: 0.15),
                          child: Text(expert.name[0], style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: color))),
                        // Online indicator
                        Positioned(bottom: 0, right: 0, child: Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(color: HuddlColors.successGreen, shape: BoxShape.circle, border: Border.all(color: HuddlColors.white, width: 2)),
                        )),
                      ]),
                      const SizedBox(height: 4),
                      Text(expert.name.split(' ').first, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('${expert.totalUpvotes} upvotes', style: GoogleFonts.poppins(fontSize: 9, color: HuddlColors.textHint)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Popular Destinations ────────────────────────────────────────────────
  Widget _buildPopularDestinations() {
    final popular = _travelService.popularDestinations;
    final destEmojis = {'Tenerife': '🌴', 'Mallorca': '🏖️', 'Algarve': '🌊', 'Costa del Sol': '☀️', 'Lake Garda': '⛵', 'Cornwall': '🏄', 'Cotswolds': '🌿', 'Crete': '🏛️'};
    final destColors = {'Tenerife': const Color(0xFFFF975C), 'Mallorca': const Color(0xFF3580F0), 'Algarve': const Color(0xFF199A85), 'Costa del Sol': const Color(0xFFF3C54F), 'Lake Garda': const Color(0xFF5B9DFF), 'Cornwall': const Color(0xFF22C55E), 'Cotswolds': const Color(0xFF78B0FF), 'Crete': const Color(0xFFF69F72)};

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Popular with huddl families', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: popular.length,
              itemBuilder: (ctx, i) {
                final dest = popular[i];
                final emoji = destEmojis[dest.name] ?? '✈️';
                final color = destColors[dest.name] ?? HuddlColors.primary;
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetailScreen(destination: dest))),
                  child: Container(
                    width: 155, margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: HuddlColors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Destination image area with gradient + emoji
                        Container(
                          height: 95,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.05)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          ),
                          child: Center(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(emoji, style: const TextStyle(fontSize: 36)),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: HuddlColors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
                                child: Text('${dest.huddlParentsVisited} families', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
                              ),
                            ]),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(dest.name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                            Text('${dest.country} · ${dest.flightTime}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.star, size: 12, color: HuddlColors.accentAmber),
                              const SizedBox(width: 2),
                              Text('${dest.rating}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                              const SizedBox(width: 4),
                              Text('${dest.recommendPercent}% rec', style: GoogleFonts.poppins(fontSize: 9, color: HuddlColors.teal, fontWeight: FontWeight.w500)),
                            ]),
                          ]),
                        ),
                      ],
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

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── Live Activity data model ──────────────────────────────────────────────
class _LiveActivity {
  final String type;
  final String parent;
  final String text;
  final DateTime time;
  final String color;
  final bool isUrgent;

  _LiveActivity({
    required this.type, required this.parent, required this.text,
    required this.time, required this.color, this.isUrgent = false,
  });
}

// ── Typing indicator dots ─────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 500)));
    _animations = _controllers.map((c) => Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _animations[i],
        builder: (_, __) => Container(
          width: 4, height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: HuddlColors.successGreen.withValues(alpha: 0.3 + _animations[i].value * 0.7),
            shape: BoxShape.circle,
          ),
        ),
      )),
    );
  }
}
