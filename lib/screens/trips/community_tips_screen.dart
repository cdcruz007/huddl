import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';

// =============================================================================
// COMMUNITY TIPS — Curated short-form tips from parents
// Max 3 sentences, tagged by destination + age, upvote-sorted
// =============================================================================

class CommunityTipsScreen extends StatefulWidget {
  final String? filterDestination;
  const CommunityTipsScreen({super.key, this.filterDestination});

  @override
  State<CommunityTipsScreen> createState() => _CommunityTipsScreenState();
}

class _CommunityTipsScreenState extends State<CommunityTipsScreen> {
  final TravelCommunityService _communityService = TravelCommunityService();
  bool _isLoading = true;
  String _selectedDestination = 'All';

  final List<String> _destinations = [
    'All', 'Tenerife', 'Mallorca', 'Costa del Sol', 'Algarve', 'Cornwall', 'Cotswolds', 'Lake Garda', 'Crete', 'General'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.filterDestination != null) {
      _selectedDestination = widget.filterDestination!;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    await _communityService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  List<CommunityTip> get _filteredTips {
    var tips = _communityService.trendingTips;
    if (_selectedDestination != 'All') {
      tips = tips.where((t) => t.destination.toLowerCase().contains(_selectedDestination.toLowerCase())).toList();
    }
    return tips;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text('Community Tips', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : Column(
              children: [
                // Filter row
                Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                  child: SizedBox(
                    height: 34,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _destinations.length,
                      itemBuilder: (ctx, i) {
                        final isSelected = _selectedDestination == _destinations[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedDestination = _destinations[i]),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? HuddlColors.primary : HuddlColors.background,
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: Text(_destinations[i], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: isSelected ? HuddlColors.white : HuddlColors.textSecondary)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Tips list
                Expanded(
                  child: _filteredTips.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.lightbulb_outline, size: 48, color: HuddlColors.textHint.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text('No tips yet for this destination', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: HuddlColors.textHint)),
                        ]))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: _filteredTips.length,
                          itemBuilder: (ctx, i) => _buildTipCard(_filteredTips[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildTipCard(CommunityTip tip) {
    final color = Color(int.parse(tip.authorAvatarColor.replaceFirst('#', '0xFF')));
    final hasBadge = tip.authorBadges.contains('expert') || tip.authorBadges.contains('trusted');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 16, backgroundColor: color.withValues(alpha: 0.15),
              child: Text(tip.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(tip.authorName, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                if (hasBadge) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.verified, size: 12, color: tip.authorBadges.contains('expert') ? HuddlColors.accentAmber : HuddlColors.blue),
                ],
              ]),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: HuddlColors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(tip.destination, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.blue)),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(tip.childAge, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                ),
              ]),
            ])),
            // Upvote count
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.thumb_up, size: 12, color: HuddlColors.primary),
                const SizedBox(width: 3),
                Text('${tip.upvotes}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Text(tip.tip, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark, height: 1.5)),
        ],
      ),
    );
  }
}
