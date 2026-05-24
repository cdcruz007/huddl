// ============================================================================
// HUDDL -- PARTNER ANALYTICS SCREEN
// ============================================================================
//
// Shows reach metrics for a Partner's service listings:
//   — 2×2 metric grid: Total Views, Total Clicks, Endorsements, Avg Rating
//   — CustomPaint 7-day bar chart for daily views (no external chart library)
//   — Loads per-listing view data from partner_analytics/{listingId}/views/
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../services/local_services_service.dart';

class PartnerAnalyticsScreen extends StatefulWidget {
  const PartnerAnalyticsScreen({super.key});

  @override
  State<PartnerAnalyticsScreen> createState() => _PartnerAnalyticsScreenState();
}

class _PartnerAnalyticsScreenState extends State<PartnerAnalyticsScreen> {
  final _svc = LocalServicesService();
  List<ServiceListing> _listings = [];
  List<double> _dailyViews = List.filled(7, 0);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final stream = _svc.myListingsStream();
      final listings = await stream.first;
      final myListings = listings
          .where((l) => l.isPartnerListing && l.ownerUid == uid)
          .toList();

      // Fetch 7-day view data from partner_analytics
      final today = DateTime.now();
      final views = List<double>.filled(7, 0);
      for (final listing in myListings) {
        for (int i = 0; i < 7; i++) {
          final day = today.subtract(Duration(days: 6 - i));
          final dateKey =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          try {
            final doc = await FirebaseFirestore.instance
                .collection('partner_analytics')
                .doc(listing.id)
                .collection('views')
                .doc(dateKey)
                .get();
            if (doc.exists) {
              views[i] += (doc.data()?['count'] as num?)?.toDouble() ?? 0;
            }
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _listings = myListings;
          _dailyViews = views;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalViews =>
      _listings.fold(0, (sum, l) => sum + l.viewCount);
  int get _totalEndorsements =>
      _listings.fold(0, (sum, l) => sum + l.endorsementCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.background,
        elevation: 0,
        leading: BackButton(color: HuddlColors.nearBlack),
        title: Text(
          'Analytics',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.nearBlack,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 2×2 metric grid ──────────────────────────────
                  _MetricGrid(
                    totalViews: _totalViews,
                    totalEndorsements: _totalEndorsements,
                    listingCount: _listings.length,
                  ),
                  const SizedBox(height: 24),

                  // ── 7-day bar chart ───────────────────────────────
                  Text(
                    '7-Day Views',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _DailyBarChart(views: _dailyViews),
                  ),
                  const SizedBox(height: 24),

                  // ── Per-listing breakdown ─────────────────────────
                  Text(
                    'Listing Breakdown',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.nearBlack,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_listings.isEmpty)
                    Center(
                      child: Text(
                        'No Partner listings yet',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textTertiary,
                        ),
                      ),
                    )
                  else
                    ..._listings.map((l) => _ListingRow(listing: l)),
                ],
              ),
            ),
    );
  }
}

// ── Metric grid ───────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final int totalViews;
  final int totalEndorsements;
  final int listingCount;

  const _MetricGrid({
    required this.totalViews,
    required this.totalEndorsements,
    required this.listingCount,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _MetricCard(
          icon: Icons.visibility_outlined,
          label: 'Total Views',
          value: '$totalViews',
          color: HuddlColors.primary,
        ),
        _MetricCard(
          icon: Icons.thumb_up_alt_outlined,
          label: 'Endorsements',
          value: '$totalEndorsements',
          color: HuddlColors.success,
        ),
        _MetricCard(
          icon: Icons.storefront_outlined,
          label: 'Listings',
          value: '$listingCount',
          color: HuddlColors.accentAmber,
        ),
        _MetricCard(
          icon: Icons.trending_up_outlined,
          label: 'This Week',
          value: '—',
          color: HuddlColors.textTertiary,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: HuddlColors.nearBlack,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: HuddlColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bar chart ─────────────────────────────────────────────────────────────────

class _DailyBarChart extends StatelessWidget {
  final List<double> views; // 7 values, oldest first

  const _DailyBarChart({required this.views});

  @override
  Widget build(BuildContext context) {
    final maxVal = views.reduce((a, b) => a > b ? a : b);
    final labels = _dayLabels();

    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (i) {
          final frac =
              maxVal > 0 ? (views[i] / maxVal).clamp(0.0, 1.0) : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (views[i] > 0)
                    Text(
                      '${views[i].toInt()}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    height: (90 * frac).clamp(4.0, 90.0),
                    decoration: BoxDecoration(
                      color: i == 6
                          ? HuddlColors.primary
                          : HuddlColors.primary.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: HuddlColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  static List<String> _dayLabels() {
    const abbr = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    final today = DateTime.now();
    return List.generate(
        7, (i) => abbr[(today.subtract(Duration(days: 6 - i)).weekday % 7)]);
  }
}

// ── Listing row ───────────────────────────────────────────────────────────────

class _ListingRow extends StatelessWidget {
  final ServiceListing listing;

  const _ListingRow({required this.listing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.name,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.nearBlack,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  listing.category.displayName,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: HuddlColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          _Pill(label: '${listing.viewCount}', icon: Icons.visibility_outlined),
          const SizedBox(width: 8),
          _Pill(
              label: '${listing.endorsementCount}',
              icon: Icons.thumb_up_alt_outlined),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Pill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: HuddlColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: HuddlColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: HuddlColors.nearBlack,
            ),
          ),
        ],
      ),
    );
  }
}
