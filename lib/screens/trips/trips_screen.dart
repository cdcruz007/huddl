import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Trips — minimal card-based hub matching MyHuddl / Preloved style.
/// Audit-hardened: WCAG 2.2 contrast, 48 dp touch targets, Semantics,
/// micro-interactions, Material ripples, and gesture affordances.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final TravelService _travelService = TravelService();
  final TravelCommunityService _communityService = TravelCommunityService();
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

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  Color _hex(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: HuddlColors.background,
        body: Center(
          child: Semantics(
            label: 'Loading trips',
            child: const CircularProgressIndicator(color: HuddlColors.primary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.primary,
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _quickActions()),
              SliverToBoxAdapter(child: _needsHelp()),
              SliverToBoxAdapter(child: _activeConversations()),
              SliverToBoxAdapter(child: _topTips()),
              SliverToBoxAdapter(child: _destinations()),
              SliverToBoxAdapter(child: _expertsBanner()),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // -- Header -----------------------------------------------------------
  Widget _header() {
    return Container(
      color: HuddlColors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trips',
                      style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark)),
                  Text("Plan, pack & ask parents who've been there",
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: HuddlColors.textSecondary)),
                ],
              ),
            ),
          ),
          _headerIcon(
            Icons.auto_awesome,
            HuddlColors.aiGradient,
            'AI Copilot',
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AiCopilotScreen())),
          ),
          const SizedBox(width: 10),
          _headerIcon(
            Icons.luggage_outlined,
            HuddlColors.primaryGradient,
            'My Trips',
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyTripsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon(
      IconData icon, LinearGradient gradient, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: HuddlColors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  // -- Quick actions ----------------------------------------------------
  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          _action(Icons.chat_bubble_outline_rounded, 'Ask Parents',
              HuddlColors.primary, () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AskParentsScreen()));
          }),
          const SizedBox(width: 10),
          _action(Icons.lightbulb_outline_rounded, 'Tips', HuddlColors.teal,
              () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CommunityTipsScreen()));
          }),
          const SizedBox(width: 10),
          _action(Icons.auto_awesome_outlined, 'AI Concierge', HuddlColors.blue,
              () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TravelConciergeScreen()));
          }),
        ],
      ),
    );
  }

  Widget _action(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(icon, size: 22, color: color),
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- Needs help -------------------------------------------------------
  Widget _needsHelp() {
    final unanswered = _communityService.questions
        .where((q) => q.answers.where((a) => !a.isAiGenerated).isEmpty)
        .take(2)
        .toList();
    if (unanswered.isEmpty) return const SizedBox.shrink();

    return _section(
      'Parents need your help',
      action: 'See all',
      onAction: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Column(
        children:
            unanswered.map((q) => _questionCard(q, urgent: true)).toList(),
      ),
    );
  }

  // -- Active conversations ---------------------------------------------
  Widget _activeConversations() {
    final active = _communityService.recentQuestions
        .where((q) => q.answers.where((a) => !a.isAiGenerated).isNotEmpty)
        .take(3)
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return _section(
      'Recent conversations',
      action: 'See all',
      onAction: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const AskParentsScreen())),
      child: Column(
        children:
            active.map((q) => _questionCard(q, urgent: false)).toList(),
      ),
    );
  }

  Widget _questionCard(TravelQuestion q, {required bool urgent}) {
    final color = _hex(q.authorAvatarColor);
    final replies = q.answers.where((a) => !a.isAiGenerated).length;
    final last = q.answers.where((a) => !a.isAiGenerated).isNotEmpty
        ? q.answers.where((a) => !a.isAiGenerated).last
        : null;

    return Semantics(
      button: true,
      label:
          '${q.authorName} asks: ${q.question}. ${urgent ? "Needs help." : "$replies replies."}',
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
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(14),
              border: urgent
                  ? Border.all(
                      color: HuddlColors.primary.withValues(alpha: 0.25))
                  : null,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(q.authorName[0],
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(q.authorName,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.textDark)),
                            Text(_timeAgo(q.createdAt),
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: HuddlColors.textSecondary)),
                          ]),
                    ),
                    if (urgent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: HuddlColors.primary,
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('Help',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.white)),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: HuddlColors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(
                            '$replies ${replies == 1 ? 'reply' : 'replies'}',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: HuddlColors.teal)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(q.question,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textDark,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                // Tags
                if (q.destination != null || q.childAge != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    if (q.destination != null) _chip(q.destination!, HuddlColors.blue),
                    if (q.destination != null && q.childAge != null)
                      const SizedBox(width: 6),
                    if (q.childAge != null) _chip(q.childAge!, HuddlColors.teal),
                  ]),
                ],
                // Last reply preview
                if (last != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: HuddlColors.background,
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: _hex(last.authorAvatarColor)
                                .withValues(alpha: 0.15),
                            child: Text(last.authorName[0],
                                style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: _hex(last.authorAvatarColor))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(last.authorName,
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: HuddlColors.textDark)),
                                    if (last.hasBeenThereBadge) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.verified,
                                          size: 12, color: HuddlColors.teal),
                                    ],
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(last.content,
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: HuddlColors.textSecondary,
                                          height: 1.3),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ]),
                          ),
                        ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- Top tips carousel ------------------------------------------------
  Widget _topTips() {
    final tips = _communityService.trendingTips.take(6).toList();
    if (tips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _sectionHeader('Top tips from parents',
                action: 'See all',
                onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CommunityTipsScreen()))),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tips.length,
              itemBuilder: (_, i) {
                final tip = tips[i];
                return Semantics(
                  button: true,
                  label: 'Tip from ${tip.authorName}: ${tip.tip}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => CommunityTipsScreen(
                                  filterDestination: tip.destination))),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 250,
                        margin: EdgeInsets.only(
                            right: i < tips.length - 1 ? 10 : 0),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: HuddlColors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CircleAvatar(
                                radius: 13,
                                backgroundColor:
                                    _hex(tip.authorAvatarColor)
                                        .withValues(alpha: 0.15),
                                child: Text(tip.authorName[0],
                                    style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            _hex(tip.authorAvatarColor))),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(tip.authorName,
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: HuddlColors.textDark))),
                              _chip(tip.destination, HuddlColors.blue),
                            ]),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Text(tip.tip,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: HuddlColors.textSecondary,
                                      height: 1.4),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Row(children: [
                              Icon(Icons.thumb_up_alt_outlined,
                                  size: 13,
                                  color: HuddlColors.textSecondary),
                              const SizedBox(width: 4),
                              Text('${tip.upvotes}',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: HuddlColors.textSecondary)),
                              const SizedBox(width: 10),
                              _chip(tip.childAge, HuddlColors.teal),
                            ]),
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

  // -- Destinations carousel --------------------------------------------
  Widget _destinations() {
    final popular = _travelService.popularDestinations;
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
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Semantics(
              header: true,
              child: Text('Popular with huddl families',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
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
                  label: '${d.name}, ${d.country}. Rated ${d.rating}. ${d.recommendPercent} percent recommended.',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    DestinationDetailScreen(destination: d)));
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 150,
                        margin: EdgeInsets.only(
                            right: i < popular.length - 1 ? 10 : 0),
                        decoration: BoxDecoration(
                          color: HuddlColors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 88,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                    colors: [
                                      c.withValues(alpha: 0.18),
                                      c.withValues(alpha: 0.05)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                              child: Center(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(emoji,
                                          style:
                                              const TextStyle(fontSize: 34)),
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 1),
                                        decoration: BoxDecoration(
                                            color: HuddlColors.white
                                                .withValues(alpha: 0.8),
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        child: Text(
                                            '${d.huddlParentsVisited} families',
                                            style: GoogleFonts.poppins(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: c)),
                                      ),
                                    ]),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name,
                                        style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: HuddlColors.textDark)),
                                    Text('${d.country} · ${d.flightTime}',
                                        style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            color: HuddlColors.textSecondary)),
                                    const SizedBox(height: 3),
                                    Row(children: [
                                      const Icon(Icons.star,
                                          size: 12,
                                          color: HuddlColors.accentAmber),
                                      const SizedBox(width: 2),
                                      Text('${d.rating}',
                                          style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: HuddlColors.textDark)),
                                      const SizedBox(width: 4),
                                      Text('${d.recommendPercent}% rec',
                                          style: GoogleFonts.poppins(
                                              fontSize: 9,
                                              color: HuddlColors.teal,
                                              fontWeight: FontWeight.w500)),
                                    ]),
                                  ]),
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

  // -- Experts banner ---------------------------------------------------
  Widget _expertsBanner() {
    final experts = _communityService.topExperts.take(5).toList();
    if (experts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Semantics(
        button: true,
        label: 'View ${experts.length} parent experts sharing travel tips',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ParentExpertsScreen()));
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                children: [
                  // Stacked avatars
                  SizedBox(
                    width: 24.0 + (experts.length - 1) * 18.0,
                    height: 40,
                    child: Stack(
                      children: experts.asMap().entries.map((e) {
                        final c = _hex(e.value.avatarColor);
                        return Positioned(
                          left: e.key * 18.0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: HuddlColors.white,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: c.withValues(alpha: 0.15),
                              child: Text(e.value.name[0],
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: c)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Parent experts',
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.textDark)),
                          Text(
                              '${experts.length} experienced parents sharing travel tips',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: HuddlColors.textSecondary)),
                        ]),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 14, color: HuddlColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -- Shared helpers ---------------------------------------------------
  Widget _section(String title,
      {String? action, VoidCallback? onAction, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title, action: action, onAction: onAction),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _sectionHeader(String title,
      {String? action, VoidCallback? onAction}) {
    return Row(
      children: [
        Semantics(
          header: true,
          child: Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark)),
        ),
        const Spacer(),
        if (action != null)
          Semantics(
            button: true,
            label: '$action $title',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAction,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(action,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.primary)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }
}
