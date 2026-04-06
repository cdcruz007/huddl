import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';

/// Parent Experts — clean leaderboard with profiles and badges.
/// Audit-hardened: WCAG 2.2, 48 dp touch targets, Semantics,
/// Material ripples, haptic feedback.
class ParentExpertsScreen extends StatefulWidget {
  const ParentExpertsScreen({super.key});

  @override
  State<ParentExpertsScreen> createState() => _ParentExpertsScreenState();
}

class _ParentExpertsScreenState extends State<ParentExpertsScreen> {
  final TravelCommunityService _svc = TravelCommunityService();
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    await _svc.initialize();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text('Parent Experts', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFF3ED), Color(0xFFFFFFFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(gradient: HuddlColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.emoji_events, color: HuddlColors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Community Experts', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                      Text('Parents who share travel knowledge earn badges', style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary, height: 1.3)),
                    ])),
                  ]),
                ),

                // Badges
                const SizedBox(height: 20),
                Text('How badges work', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 10),
                Row(children: [
                  _badgeLegend('Been There', '3+ answers', HuddlColors.teal, Icons.place),
                  const SizedBox(width: 8),
                  _badgeLegend('Trusted', '10+ upvotes', HuddlColors.blue, Icons.verified),
                  const SizedBox(width: 8),
                  _badgeLegend('Expert', '25+ upvotes', HuddlColors.accentAmber, Icons.emoji_events),
                ]),

                // Leaderboard
                const SizedBox(height: 24),
                Text('Top Contributors', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text('Parents who help the community the most', style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary)),
                const SizedBox(height: 12),
                ..._svc.topExperts.asMap().entries.map((e) => _expertCard(e.value, e.key + 1)),

                // CTA
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    const Icon(Icons.volunteer_activism, size: 32, color: HuddlColors.primary),
                    const SizedBox(height: 10),
                    Text('Share your travel knowledge!', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 4),
                    Text('Answer questions to earn your first badge.', textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary, foregroundColor: HuddlColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                        ),
                        child: Text('Answer Questions', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 80),
              ]),
            ),
    );
  }

  Widget _badgeLegend(String title, String req, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 6),
          Text(title, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface), textAlign: TextAlign.center),
          Text(req, style: GoogleFonts.poppins(fontSize: 9, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _expertCard(ParentExpertProfile expert, int rank) {
    final c = Color(int.parse(expert.avatarColor.replaceFirst('#', '0xFF')));
    final rankColors = [HuddlColors.accentAmber, HuddlColors.gray400, const Color(0xFFCD7F32)];
    final rc = rank <= rankColors.length ? rankColors[rank - 1] : HuddlColors.textHint;

    return Semantics(
      button: true,
      label: 'Rank $rank: ${expert.name}, ${expert.totalUpvotes} upvotes, ${expert.totalAnswers} answers',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showProfile(expert);
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14),
              border: rank <= 3 ? Border.all(color: rc.withValues(alpha: 0.25)) : null,
            ),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: rank <= 3 ? rc.withValues(alpha: 0.15) : HuddlColors.background, shape: BoxShape.circle),
            child: Center(child: Text('$rank', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: rank <= 3 ? rc : HuddlColors.textHint))),
          ),
          const SizedBox(width: 12),
          CircleAvatar(radius: 22, backgroundColor: c.withValues(alpha: 0.15),
            child: Text(expert.name[0], style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: c))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(expert.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              _rankBadge(expert),
            ]),
            Text('${expert.location} · ${expert.childAges.join(", ")}', style: GoogleFonts.poppins(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, children: expert.badges.take(3).map((b) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.place, size: 10, color: HuddlColors.teal),
                const SizedBox(width: 2),
                Text(b.destinationName, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
              ]),
            )).toList()),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.thumb_up, size: 12, color: HuddlColors.primary),
              const SizedBox(width: 3),
              Text('${expert.totalUpvotes}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
            ]),
            const SizedBox(height: 2),
            Text('${expert.totalAnswers} answers', style: GoogleFonts.poppins(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
          ]),
        ]),
      ),
    ),
    ),
    );
  }

  Widget _rankBadge(ParentExpertProfile expert) {
    Color bc;
    String label;
    IconData icon;
    switch (expert.rankLevel) {
      case 4: bc = HuddlColors.accentAmber; label = 'Legend'; icon = Icons.star; break;
      case 3: bc = HuddlColors.accentAmber; label = 'Expert'; icon = Icons.emoji_events; break;
      case 2: bc = HuddlColors.blue; label = 'Trusted'; icon = Icons.verified; break;
      default: bc = HuddlColors.teal; label = 'Active'; icon = Icons.person;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: bc),
        const SizedBox(width: 2),
        Text(label, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: bc)),
      ]),
    );
  }

  void _showProfile(ParentExpertProfile expert) {
    final c = Color(int.parse(expert.avatarColor.replaceFirst('#', '0xFF')));
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            CircleAvatar(radius: 36, backgroundColor: c.withValues(alpha: 0.15),
              child: Text(expert.name[0], style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w600, color: c))),
            const SizedBox(height: 12),
            Text(expert.name, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
            Text('${expert.location} · ${expert.rank}', style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary)),
            const SizedBox(height: 8),
            Text(expert.bio, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).colorScheme.onSurface, height: 1.4)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _stat('${expert.totalAnswers}', 'Answers'),
              Container(width: 1, height: 30, color: Theme.of(context).dividerColor, margin: const EdgeInsets.symmetric(horizontal: 20)),
              _stat('${expert.totalUpvotes}', 'Upvotes'),
              Container(width: 1, height: 30, color: Theme.of(context).dividerColor, margin: const EdgeInsets.symmetric(horizontal: 20)),
              _stat('${expert.badges.length}', 'Badges'),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              const Icon(Icons.child_care, size: 16, color: HuddlColors.teal),
              const SizedBox(width: 6),
              Text('Children: ${expert.childAges.join(", ")}', style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary)),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.star_outline, size: 16, color: HuddlColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text('Specialities: ${expert.specialities.join(", ")}', style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color ?? HuddlColors.textSecondary))),
            ]),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerLeft, child: Text('Destination Badges', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))),
            const SizedBox(height: 8),
            ...expert.badges.map((b) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: b.level == 'expert' ? HuddlColors.accentAmber.withValues(alpha: 0.15) : b.level == 'trusted' ? HuddlColors.blue.withValues(alpha: 0.15) : HuddlColors.teal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    b.level == 'expert' ? Icons.emoji_events : b.level == 'trusted' ? Icons.verified : Icons.place,
                    size: 18,
                    color: b.level == 'expert' ? HuddlColors.accentAmber : b.level == 'trusted' ? HuddlColors.blue : HuddlColors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.destinationName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                  Text('${b.levelLabel} · ${b.answersGiven} answers · ${b.upvotesReceived} upvotes', style: GoogleFonts.poppins(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
                ])),
              ]),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String val, String label) {
    return Column(children: [
      Text(val, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.primary)),
      Text(label, style: GoogleFonts.poppins(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color ?? HuddlColors.textHint)),
    ]);
  }
}
