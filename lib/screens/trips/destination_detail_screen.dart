import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';
import 'packing_list_screen.dart';
import 'parents_abroad_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DESTINATION DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class DestinationDetailScreen extends StatefulWidget {
  final TravelDestination destination;
  const DestinationDetailScreen({super.key, required this.destination});

  @override
  State<DestinationDetailScreen> createState() => _DestinationDetailScreenState();
}

class _DestinationDetailScreenState extends State<DestinationDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TravelService _travelService = TravelService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  TravelDestination get dest => widget.destination;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      body: CustomScrollView(
        slivers: [
          // ── Hero Header ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: HuddlColors.white,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: HuddlColors.white.withValues(alpha: 0.9),
                child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: HuddlColors.textDark), onPressed: () => Navigator.pop(context)),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: dest.imageUrl, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: HuddlColors.peachLight),
                    errorWidget: (_, __, ___) => Container(
                      decoration: const BoxDecoration(gradient: HuddlColors.splashGradient),
                      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.flight_takeoff, color: HuddlColors.primary, size: 48),
                        const SizedBox(height: 8),
                        Text(dest.name, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                      ])),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16, left: 20, right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dest.name, style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: HuddlColors.white)),
                        Text('${dest.country} · ${dest.region}', style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.white.withValues(alpha: 0.9))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Stats row ────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildStatsRow()),

          // ── Action buttons ───────────────────────────────────────
          SliverToBoxAdapter(child: _buildActionButtons()),

          // ── Tabs ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                labelColor: HuddlColors.primary,
                unselectedLabelColor: HuddlColors.textHint,
                labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
                indicatorColor: HuddlColors.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Reviews'),
                  Tab(text: 'Itinerary'),
                  Tab(text: 'Safety'),
                ],
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 500,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildReviewsTab(),
                  _buildItineraryTab(),
                  _buildSafetyTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats row ───────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          _buildStatChip(Icons.star, '${dest.rating}', HuddlColors.accentAmber),
          const SizedBox(width: 10),
          _buildStatChip(Icons.people, '${dest.huddlParentsVisited} families', HuddlColors.teal),
          const SizedBox(width: 10),
          _buildStatChip(Icons.thumb_up, '${dest.recommendPercent}% rec', HuddlColors.successGreen),
          const SizedBox(width: 10),
          _buildStatChip(Icons.flight, dest.flightTime, HuddlColors.blue),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  // ── Action buttons ──────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(Icons.luggage, 'Pack My Bag', HuddlColors.primary, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PackingListScreen(destination: dest)));
            }),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildActionButton(Icons.groups, 'Parents Abroad', HuddlColors.teal, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ParentsAbroadScreen(destination: dest)));
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  // ── Overview tab ────────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dest.description, style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textSecondary, height: 1.5)),
          const SizedBox(height: 20),
          _buildInfoCard('Best months', dest.bestMonths, Icons.calendar_today),
          _buildInfoCard('Average temperature', dest.avgTemp, Icons.thermostat),
          _buildInfoCard('Flight time from UK', dest.flightTime, Icons.flight),
          _buildInfoCard('Visa required', dest.visaRequired ? 'Yes' : 'No (UK passport)', Icons.article),
          const SizedBox(height: 20),
          Text('Best for ages', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: dest.bestForAges.map((age) => Chip(
            label: Text(age, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
            backgroundColor: HuddlColors.primary.withValues(alpha: 0.1),
            side: BorderSide.none,
          )).toList()),
          const SizedBox(height: 20),
          Text('Highlights', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 8),
          ...dest.highlights.map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: HuddlColors.primary, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text(h, style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark)),
            ]),
          )),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: HuddlColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
            Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
          ])),
        ],
      ),
    );
  }

  // ── Reviews tab ─────────────────────────────────────────────────────────

  Widget _buildReviewsTab() {
    final reviews = _travelService.getReviewsFor(dest.id);
    if (reviews.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.rate_review, size: 48, color: HuddlColors.textHint.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('No reviews yet', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500, color: HuddlColors.textHint)),
          const SizedBox(height: 4),
          Text('Be the first to review this destination!', style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textHint)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: reviews.length,
      itemBuilder: (ctx, i) => _buildReviewItem(reviews[i]),
    );
  }

  Widget _buildReviewItem(ParentReview review) {
    final color = Color(int.parse(review.avatarColor.replaceFirst('#', '0xFF')));
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.2),
                child: Text(review.parentName[0], style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: color))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(review.parentName, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                Text('Travelled with ${review.childAgesAtVisit} · ${review.visitDate}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
              ])),
              Row(children: List.generate(5, (i) => Icon(Icons.star, size: 14, color: i < review.rating.round() ? HuddlColors.accentAmber : HuddlColors.gray300))),
            ],
          ),
          const SizedBox(height: 12),
          Text(review.title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 6),
          Text(review.review, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary, height: 1.5)),
          if (review.topTips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: HuddlColors.peachVeryLight, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Top tips', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
                const SizedBox(height: 4),
                ...review.topTips.map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('  ', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.primary)),
                    Expanded(child: Text(tip, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textDark))),
                  ]),
                )),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: review.wouldRecommend ? HuddlColors.teal.withValues(alpha: 0.1) : HuddlColors.errorLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(review.wouldRecommend ? Icons.thumb_up : Icons.thumb_down, size: 12, color: review.wouldRecommend ? HuddlColors.teal : HuddlColors.error),
                const SizedBox(width: 4),
                Text(review.wouldRecommend ? 'Recommends' : 'Doesn\'t recommend', style: GoogleFonts.poppins(fontSize: 11, color: review.wouldRecommend ? HuddlColors.teal : HuddlColors.error)),
              ]),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Reply to ${review.parentName} — coming in the next update!',
                      style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.white)),
                  backgroundColor: HuddlColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                ));
              },
              child: Text('Reply', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Itinerary tab ───────────────────────────────────────────────────────

  Widget _buildItineraryTab() {
    final itinerary = _travelService.generateItinerary(dest.id, 5);
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: itinerary.length,
      itemBuilder: (ctx, i) {
        final day = itinerary[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(gradient: HuddlColors.primaryGradient, borderRadius: BorderRadius.circular(12)),
              child: Text('Day ${day.dayNumber}: ${day.title}', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.white)),
            ),
            const SizedBox(height: 8),
            ...day.activities.map((act) => Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(act.time, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: act.isNapTime ? HuddlColors.blue : HuddlColors.primary)),
                  ),
                  SizedBox(width: 2, height: 40, child: ColoredBox(color: HuddlColors.divider)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: act.isNapTime ? HuddlColors.blueBackground : HuddlColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          if (act.isNapTime) Icon(Icons.bedtime, size: 14, color: HuddlColors.blue),
                          if (act.isNapTime) const SizedBox(width: 4),
                          Expanded(child: Text(act.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark))),
                        ]),
                        const SizedBox(height: 2),
                        Text(act.description, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary, height: 1.4)),
                        if (act.ageNote != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(act.ageNote!, style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.primary, fontStyle: FontStyle.italic)),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  // ── Safety tab ──────────────────────────────────────────────────────────

  Widget _buildSafetyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Safety status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dest.safetyAlerts.isEmpty ? HuddlColors.successBg : HuddlColors.warningBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  dest.safetyAlerts.isEmpty ? Icons.check_circle : Icons.warning,
                  color: dest.safetyAlerts.isEmpty ? HuddlColors.teal : HuddlColors.warning,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(dest.safetyAlerts.isEmpty ? 'No active alerts' : '${dest.safetyAlerts.length} active alert(s)',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  Text(dest.safetyAlerts.isEmpty ? 'This destination is currently safe for family travel' : 'Check alerts below',
                      style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                ])),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // General travel safety tips
          Text('Family travel safety checklist', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 12),
          _buildSafetyItem(Icons.medical_services, 'Health', 'EHIC/GHIC card covers emergency care in EU. Travel insurance recommended for under-5s.'),
          _buildSafetyItem(Icons.vaccines, 'Vaccinations', 'No special vaccinations required for ${dest.country}. Keep routine vaccinations up to date.'),
          _buildSafetyItem(Icons.local_hospital, 'Nearest hospital', 'Research nearest hospital to your accommodation before you travel.'),
          _buildSafetyItem(Icons.water, 'Water safety', dest.tags.contains('beach') ? 'Beach destination — check lifeguard coverage and rip current warnings daily.' : 'Tap water is safe to drink in ${dest.country}.'),
          _buildSafetyItem(Icons.wb_sunny, 'Sun protection', 'UV index can reach 8-10. Reapply SPF50+ every 2 hours. Avoid midday sun (12-3pm) with babies.'),
          _buildSafetyItem(Icons.restaurant, 'Food safety', 'Most restaurants in ${dest.country} are baby-friendly. Always ask about allergens.'),
          const SizedBox(height: 20),
          // Community safety tips
          Text('Tips from huddl parents', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: HuddlColors.peachVeryLight, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('"Always take a photo of your hotel room number and address in the local language. Saved us when our toddler had a fever and we needed to tell the taxi driver where to go."',
                  style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark, fontStyle: FontStyle.italic, height: 1.5)),
              const SizedBox(height: 8),
              Text('— Emma, Cambridge (visited ${dest.name})', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: HuddlColors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text(description, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary, height: 1.4)),
          ])),
        ],
      ),
    );
  }
}
