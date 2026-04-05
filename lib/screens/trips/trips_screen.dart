import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
// HUDDL TRIPS — Restructured Main Screen
// "Ask Parents Who Know" — Community-powered personal travel assistant
// =============================================================================

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final TravelService _travelService = TravelService();
  final TravelCommunityService _communityService = TravelCommunityService();
  final TextEditingController _quickQuestionController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _travelService.initialize();
    await _communityService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _quickQuestionController.dispose();
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
                // ── Header ──────────────────────────────────────────
                SliverToBoxAdapter(child: _buildHeader()),
                // ── Quick Question Bar ──────────────────────────────
                SliverToBoxAdapter(child: _buildQuickQuestionBar()),
                // ── My Trips CTA ─────────────────────────────────────
                SliverToBoxAdapter(child: _buildMyTripsCard()),
                // ── Quick Stats ─────────────────────────────────────
                SliverToBoxAdapter(child: _buildQuickStats()),
                // ── Recent Questions ────────────────────────────────
                SliverToBoxAdapter(child: _buildSectionHeader('Latest from Parents', 'See all', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())))),
                SliverToBoxAdapter(child: _buildRecentQuestions()),
                // ── Community Experts ────────────────────────────────
                SliverToBoxAdapter(child: _buildSectionHeader('Parent Experts', 'View all', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentExpertsScreen())))),
                SliverToBoxAdapter(child: _buildExpertsRow()),
                // ── Trending Tips ───────────────────────────────────
                SliverToBoxAdapter(child: _buildSectionHeader('Top Community Tips', 'All tips', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityTipsScreen())))),
                SliverToBoxAdapter(child: _buildTrendingTips()),
                // ── AI Concierge Card ───────────────────────────────
                SliverToBoxAdapter(child: _buildConciergeCard()),
                // ── Popular Destinations ────────────────────────────
                SliverToBoxAdapter(child: _buildSectionHeader('Popular with huddl families', '${_travelService.popularDestinations.length} places', null)),
                SliverToBoxAdapter(child: _buildPopularCarousel()),
                // ── Saved Research ──────────────────────────────────
                if (_communityService.savedAnswers.isNotEmpty)
                  SliverToBoxAdapter(child: _buildSavedResearch()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(gradient: HuddlColors.primaryGradient, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.flight_takeoff, color: HuddlColors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Trips', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
                Text('Ask parents who\'ve been there', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
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

  // ── Quick Question Bar ─────────────────────────────────────────────────
  Widget _buildQuickQuestionBar() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: HuddlColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.forum, color: HuddlColors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ask a travel question...', style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint)),
                  Text('Parents who\'ve been there will answer', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textLight)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('Ask', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── My Trips Card ──────────────────────────────────────────────────────
  Widget _buildMyTripsCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTripsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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

  // ── Quick Stats ────────────────────────────────────────────────────────
  Widget _buildQuickStats() {
    final qCount = _communityService.questions.length;
    final expertCount = _communityService.experts.length;
    final tipCount = _communityService.tips.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _buildStatChip(Icons.forum, '$qCount Questions', HuddlColors.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen()))),
          const SizedBox(width: 8),
          _buildStatChip(Icons.verified, '$expertCount Experts', HuddlColors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentExpertsScreen()))),
          const SizedBox(width: 8),
          _buildStatChip(Icons.lightbulb, '$tipCount Tips', HuddlColors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityTipsScreen()))),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  // ── Section Header ─────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, String action, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        const Spacer(),
        if (onTap != null)
          GestureDetector(
            onTap: onTap,
            child: Text(action, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
          )
        else
          Text(action, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
      ]),
    );
  }

  // ── Recent Questions ───────────────────────────────────────────────────
  Widget _buildRecentQuestions() {
    final questions = _communityService.recentQuestions.take(3).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: questions.map((q) => _buildQuestionPreview(q)).toList(),
      ),
    );
  }

  Widget _buildQuestionPreview(TravelQuestion question) {
    final color = Color(int.parse(question.authorAvatarColor.replaceFirst('#', '0xFF')));
    final parentAnswers = question.answers.where((a) => !a.isAiGenerated).length;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: question.isSolved ? HuddlColors.successGreen.withValues(alpha: 0.2) : HuddlColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundColor: color.withValues(alpha: 0.15),
                child: Text(question.authorName[0], style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color))),
              const SizedBox(width: 8),
              Text(question.authorName, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(width: 6),
              Text(_timeAgo(question.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
              const Spacer(),
              if (question.isSolved)
                const Icon(Icons.check_circle, size: 14, color: HuddlColors.successGreen),
            ]),
            const SizedBox(height: 8),
            Text(question.question, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textDark, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(children: [
              if (question.destination != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: HuddlColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(question.destination!, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.blue)),
                ),
                const SizedBox(width: 6),
              ],
              Icon(Icons.people_outline, size: 13, color: HuddlColors.textHint),
              const SizedBox(width: 3),
              Text('$parentAnswers answers', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textSecondary)),
              const SizedBox(width: 8),
              Icon(Icons.thumb_up_outlined, size: 12, color: HuddlColors.textHint),
              const SizedBox(width: 3),
              Text('${question.totalUpvotes}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textSecondary)),
              const Spacer(),
              if (question.hasAiSynthesis)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 11, color: HuddlColors.aiBlue),
                  const SizedBox(width: 2),
                  Text('AI Summary', style: GoogleFonts.poppins(fontSize: 9, color: HuddlColors.aiBlue)),
                ]),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Experts Row ────────────────────────────────────────────────────────
  Widget _buildExpertsRow() {
    final experts = _communityService.topExperts.take(5).toList();
    return SizedBox(
      height: 115,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: experts.length,
        itemBuilder: (ctx, i) => _buildExpertChip(experts[i]),
      ),
    );
  }

  Widget _buildExpertChip(ParentExpertProfile expert) {
    final color = Color(int.parse(expert.avatarColor.replaceFirst('#', '0xFF')));

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ParentExpertsScreen())),
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 10),
        child: Column(children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 28, backgroundColor: color.withValues(alpha: 0.15),
                child: Text(expert.name[0], style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: color)),
              ),
              if (expert.rankLevel >= 2)
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: expert.rankLevel >= 3 ? HuddlColors.accentAmber : HuddlColors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: HuddlColors.white, width: 2),
                    ),
                    child: Icon(
                      expert.rankLevel >= 3 ? Icons.emoji_events : Icons.verified,
                      size: 10, color: HuddlColors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(expert.name.split(' ').first, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${expert.totalUpvotes} upvotes', style: GoogleFonts.poppins(fontSize: 9, color: HuddlColors.textHint)),
          // Top badge
          if (expert.badges.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
              child: Text(expert.badges.first.destinationName, style: GoogleFonts.poppins(fontSize: 8, color: HuddlColors.teal), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
    );
  }

  // ── Trending Tips ──────────────────────────────────────────────────────
  Widget _buildTrendingTips() {
    final tips = _communityService.trendingTips.take(3).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: tips.map((t) => _buildTipPreview(t)).toList(),
      ),
    );
  }

  Widget _buildTipPreview(CommunityTip tip) {
    final color = Color(int.parse(tip.authorAvatarColor.replaceFirst('#', '0xFF')));

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityTipsScreen(filterDestination: tip.destination))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14, backgroundColor: color.withValues(alpha: 0.15),
              child: Text(tip.authorName[0], style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(tip.authorName, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: HuddlColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(tip.destination, style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w500, color: HuddlColors.blue)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(tip.tip, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Column(children: [
              const Icon(Icons.thumb_up, size: 12, color: HuddlColors.primary),
              Text('${tip.upvotes}', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
            ]),
          ],
        ),
      ),
    );
  }

  // ── AI Concierge Card ──────────────────────────────────────────────────
  Widget _buildConciergeCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFEDF4FF), Color(0xFFF5F9FF), Color(0xFFFFFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(gradient: HuddlColors.aiGradient, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Travel Concierge', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text('Powered by community knowledge', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
          ])),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: HuddlColors.aiBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.arrow_forward_ios, size: 12, color: HuddlColors.aiBlue),
          ),
        ]),
      ),
    );
  }

  // ── Popular Destinations Carousel ──────────────────────────────────────
  Widget _buildPopularCarousel() {
    final popular = _travelService.popularDestinations;
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: popular.length,
        itemBuilder: (ctx, i) => _buildDestCard(popular[i]),
      ),
    );
  }

  Widget _buildDestCard(TravelDestination dest) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetailScreen(destination: dest))),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 100, width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: dest.imageUrl, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: HuddlColors.peachLight, child: const Center(child: Icon(Icons.flight, color: HuddlColors.primary))),
                  errorWidget: (_, __, ___) => Container(
                    color: HuddlColors.peachLight,
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.flight_takeoff, color: HuddlColors.primary, size: 28),
                      Text(dest.name, style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.primary)),
                    ])),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dest.name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                Text('${dest.country} · ${dest.flightTime}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.star, size: 12, color: HuddlColors.accentAmber),
                  const SizedBox(width: 2),
                  Text('${dest.rating}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('${dest.huddlParentsVisited} families', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                  ),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Saved Research ─────────────────────────────────────────────────────
  Widget _buildSavedResearch() {
    final saved = _communityService.savedAnswers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
          child: Row(children: [
            const Icon(Icons.bookmark, size: 18, color: HuddlColors.primary),
            const SizedBox(width: 6),
            Text('My Saved Research', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            const Spacer(),
            Text('${saved.length} items', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: saved.take(3).map((s) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.bookmark, size: 14, color: HuddlColors.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.questionText, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 4),
                Text('${s.authorName} · ${s.destination}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
              ]),
            )).toList(),
          ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
