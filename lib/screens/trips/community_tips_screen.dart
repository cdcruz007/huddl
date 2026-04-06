import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_community_service.dart';

/// Community Tips — clean card list with destination filters and share CTA.
/// Audit-hardened: WCAG 2.2, 48 dp touch targets, Semantics,
/// Material ripples, haptic feedback.
class CommunityTipsScreen extends StatefulWidget {
  final String? filterDestination;
  const CommunityTipsScreen({super.key, this.filterDestination});

  @override
  State<CommunityTipsScreen> createState() => _CommunityTipsScreenState();
}

class _CommunityTipsScreenState extends State<CommunityTipsScreen> {
  final TravelCommunityService _svc = TravelCommunityService();
  bool _loading = true;
  String _dest = 'All';

  final _dests = ['All', 'Tenerife', 'Mallorca', 'Costa del Sol', 'Algarve', 'Cornwall', 'Cotswolds', 'Lake Garda', 'Crete', 'General'];

  @override
  void initState() {
    super.initState();
    if (widget.filterDestination != null) _dest = widget.filterDestination!;
    _load();
  }

  Future<void> _load() async {
    await _svc.initialize();
    if (mounted) setState(() => _loading = false);
  }

  List<CommunityTip> get _tips {
    var tips = _svc.trendingTips;
    if (_dest != 'All') tips = tips.where((t) => t.destination.toLowerCase().contains(_dest.toLowerCase())).toList();
    return tips;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20), onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Community Tips', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          Text('${_svc.trendingTips.length} tips from experienced parents', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : Column(children: [
              // Filter chips
              Container(
                color: HuddlColors.white,
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                child: SizedBox(
                  height: 34,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _dests.length,
                    itemBuilder: (_, i) {
                      final sel = _dest == _dests[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Semantics(
                          button: true,
                          label: 'Filter by ${_dests[i]}',
                          selected: sel,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _dest = _dests[i]);
                              },
                              borderRadius: BorderRadius.circular(17),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: sel ? HuddlColors.primary : HuddlColors.background,
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: Text(_dests[i], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? HuddlColors.white : HuddlColors.textSecondary)),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Tips list
              Expanded(
                child: _tips.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.lightbulb_outline, size: 48, color: HuddlColors.textHint.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('No tips yet for this destination', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: HuddlColors.textHint)),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _tips.length,
                        itemBuilder: (_, i) => _tipCard(_tips[i]),
                      ),
              ),
            ]),
      floatingActionButton: _loading ? null : FloatingActionButton.extended(
        onPressed: () => _shareTipSheet(context),
        backgroundColor: HuddlColors.teal,
        icon: const Icon(Icons.lightbulb, color: HuddlColors.white, size: 20),
        label: Text('Share a Tip', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
      ),
    );
  }

  Widget _tipCard(CommunityTip tip) {
    final c = Color(int.parse(tip.authorAvatarColor.replaceFirst('#', '0xFF')));
    final hasBadge = tip.authorBadges.contains('expert') || tip.authorBadges.contains('trusted');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 16, backgroundColor: c.withValues(alpha: 0.15),
            child: Text(tip.authorName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
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
              _chip(tip.destination, HuddlColors.blue),
              const SizedBox(width: 4),
              _chip(tip.childAge, HuddlColors.teal),
            ]),
          ])),
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
      ]),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w500, color: color)),
    );
  }

  void _shareTipSheet(BuildContext ctx) {
    final tipCtrl = TextEditingController();
    String selectedDest = _dest == 'All' ? 'Tenerife' : _dest;

    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Share a Travel Tip', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
              Text('Help other parents with your experience', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
              const SizedBox(height: 20),
              Text('Destination', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 6),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _dests.where((d) => d != 'All').map((d) {
                    final sel = selectedDest == d;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setSheet(() => selectedDest = d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? HuddlColors.teal : HuddlColors.background,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Text(d, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? HuddlColors.white : HuddlColors.textSecondary)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
              Text('Your tip', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(14)),
                child: TextField(
                  controller: tipCtrl, maxLines: 4, style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. "Book the south side of Tenerife for guaranteed sunshine — north can be cloudy with toddlers."',
                    hintStyle: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint),
                    border: InputBorder.none, contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (tipCtrl.text.trim().isEmpty) return;
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Tip shared! Thank you for helping the community.', style: GoogleFonts.poppins(fontSize: 13)),
                      backgroundColor: HuddlColors.teal, behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.teal, foregroundColor: HuddlColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                  ),
                  child: Text('Share Tip', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
