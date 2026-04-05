import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_colors.dart';
import '../../services/travel_service.dart';
import 'destination_detail_screen.dart';
import 'travel_concierge_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL TRIPS — Main Screen
// ═══════════════════════════════════════════════════════════════════════════════

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final TravelService _travelService = TravelService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  bool _isLoading = true;
  String _searchQuery = '';

  final List<String> _filters = ['All', 'Beach', 'Staycation', 'Culture', 'Budget', 'Short flight'];
  final Map<String, String> _filterKeys = {
    'All': '', 'Beach': 'beach', 'Staycation': 'staycation',
    'Culture': 'culture', 'Budget': 'budget-friendly', 'Short flight': 'short-flight',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _travelService.initialize();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TravelDestination> get _filteredDestinations {
    var dests = _searchQuery.isNotEmpty
        ? _travelService.search(_searchQuery)
        : _travelService.destinations;

    if (_selectedFilter != 'All') {
      final key = _filterKeys[_selectedFilter] ?? '';
      if (key.isNotEmpty) {
        dests = dests.where((d) => d.tags.contains(key)).toList();
      }
    }
    return dests;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
          : CustomScrollView(
              slivers: [
                // ── Header ────────────────────────────────────────────────
                SliverToBoxAdapter(child: _buildHeader()),
                // ── AI Concierge Card ─────────────────────────────────────
                SliverToBoxAdapter(child: _buildConciergeCard()),
                // ── Filter chips ──────────────────────────────────────────
                SliverToBoxAdapter(child: _buildFilterChips()),
                // ── Popular with huddl parents ────────────────────────────
                SliverToBoxAdapter(child: _buildSectionTitle('Popular with huddl parents', '${_travelService.popularDestinations.length} destinations')),
                SliverToBoxAdapter(child: _buildPopularCarousel()),
                // ── Community reviews highlight ───────────────────────────
                SliverToBoxAdapter(child: _buildSectionTitle('Latest parent reviews', '${_travelService.reviews.length} reviews')),
                SliverToBoxAdapter(child: _buildReviewsCarousel()),
                // ── All destinations ──────────────────────────────────────
                SliverToBoxAdapter(child: _buildSectionTitle('Explore destinations', '${_filteredDestinations.length} places')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildDestinationListTile(_filteredDestinations[i]),
                      childCount: _filteredDestinations.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: HuddlColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.flight_takeoff, color: HuddlColors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trips', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
                    Text('Travel smarter with parents who\'ve been there', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: HuddlColors.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search destinations, countries...',
                hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                prefixIcon: const Icon(Icons.search, color: HuddlColors.textHint, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                        child: const Icon(Icons.close, color: HuddlColors.textHint, size: 18),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── AI Concierge Card ──────────────────────────────────────────────────

  Widget _buildConciergeCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TravelConciergeScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF3ED), Color(0xFFFFF8F0), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: HuddlColors.aiGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Travel Concierge', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  const SizedBox(height: 4),
                  Text('Ask me anything about family travel — powered by real parent experiences',
                      style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: HuddlColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_ios, size: 14, color: HuddlColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter chips ───────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _filters.length,
          itemBuilder: (ctx, i) {
            final isSelected = _selectedFilter == _filters[i];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFilter = _filters[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isSelected ? HuddlColors.primaryGradient : null,
                    color: isSelected ? null : HuddlColors.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _filters[i],
                    style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: isSelected ? HuddlColors.white : HuddlColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Section title ──────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const Spacer(),
          Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
        ],
      ),
    );
  }

  // ── Popular carousel ───────────────────────────────────────────────────

  Widget _buildPopularCarousel() {
    final popular = _travelService.popularDestinations;
    return SizedBox(
      height: 230,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: popular.length,
        itemBuilder: (ctx, i) => _buildPopularCard(popular[i]),
      ),
    );
  }

  Widget _buildPopularCard(TravelDestination dest) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetailScreen(destination: dest))),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: HuddlColors.gray900.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: dest.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: HuddlColors.peachLight, child: const Center(child: Icon(Icons.flight, color: HuddlColors.primary))),
                  errorWidget: (_, __, ___) => Container(
                    color: HuddlColors.peachLight,
                    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.flight_takeoff, color: HuddlColors.primary, size: 32),
                      const SizedBox(height: 4),
                      Text(dest.name, style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.primary, fontWeight: FontWeight.w500)),
                    ])),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dest.name, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  const SizedBox(height: 2),
                  Text('${dest.country} · ${dest.flightTime}', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.star, size: 14, color: HuddlColors.accentAmber),
                      const SizedBox(width: 3),
                      Text('${dest.rating}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: HuddlColors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text('${dest.huddlParentsVisited} families', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w500, color: HuddlColors.teal)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reviews carousel ───────────────────────────────────────────────────

  Widget _buildReviewsCarousel() {
    final reviews = _travelService.reviews;
    return SizedBox(
      height: 160,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: reviews.length,
        itemBuilder: (ctx, i) => _buildReviewCard(reviews[i]),
      ),
    );
  }

  Widget _buildReviewCard(ParentReview review) {
    final dest = _travelService.destinations.firstWhere(
      (d) => d.id == review.destinationId,
      orElse: () => _travelService.destinations.first,
    );
    final color = Color(int.parse(review.avatarColor.replaceFirst('#', '0xFF')));

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 14),
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
              CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.2),
                child: Text(review.parentName[0], style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(review.parentName, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  Text('${dest.name} · ${review.visitDate}', style: GoogleFonts.poppins(fontSize: 10, color: HuddlColors.textHint)),
                ]),
              ),
              Row(children: List.generate(5, (i) => Icon(Icons.star, size: 12, color: i < review.rating.round() ? HuddlColors.accentAmber : HuddlColors.gray300))),
            ],
          ),
          const SizedBox(height: 10),
          Text(review.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
          const SizedBox(height: 4),
          Expanded(
            child: Text(review.review, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }

  // ── Destination list tile ──────────────────────────────────────────────

  Widget _buildDestinationListTile(TravelDestination dest) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DestinationDetailScreen(destination: dest))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HuddlColors.divider),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72, height: 72,
                child: CachedNetworkImage(
                  imageUrl: dest.imageUrl, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: HuddlColors.peachLight, child: const Icon(Icons.flight, color: HuddlColors.primary, size: 24)),
                  errorWidget: (_, __, ___) => Container(color: HuddlColors.peachLight, child: const Icon(Icons.flight_takeoff, color: HuddlColors.primary, size: 24)),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dest.name, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
                  Text('${dest.country} · ${dest.flightTime} from UK', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.star, size: 13, color: HuddlColors.accentAmber),
                      const SizedBox(width: 3),
                      Text('${dest.rating}', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 6),
                      Text('·', style: GoogleFonts.poppins(color: HuddlColors.textHint)),
                      const SizedBox(width: 6),
                      Icon(Icons.people, size: 13, color: HuddlColors.teal),
                      const SizedBox(width: 3),
                      Text('${dest.huddlParentsVisited} families', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.teal, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 6),
                      Text('·', style: GoogleFonts.poppins(color: HuddlColors.textHint)),
                      const SizedBox(width: 6),
                      Text('${dest.recommendPercent}% rec', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.successGreen, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: HuddlColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}
