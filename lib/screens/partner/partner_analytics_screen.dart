import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/huddl_character.dart';
import '../../constants/app_text_styles.dart';

// =============================================================================
// PARTNER ANALYTICS SCREEN
//
// Shows reach analytics for the current Partner subscriber.
// Data source: partner_analytics/{currentUid} — flat Firestore doc.
// Fields: totalProfileViews, totalListingViews, totalBookingClicks,
//         totalEndorsements, lastUpdated
// =============================================================================

class PartnerAnalyticsScreen extends StatefulWidget {
  const PartnerAnalyticsScreen({super.key});

  @override
  State<PartnerAnalyticsScreen> createState() =>
      _PartnerAnalyticsScreenState();
}

class _PartnerAnalyticsScreenState extends State<PartnerAnalyticsScreen> {
  bool _loading = true;
  String? _error;

  int _totalProfileViews  = 0;
  int _totalListingViews  = 0;
  int _totalBookingClicks = 0;
  int _totalEndorsements  = 0;
  bool _hasAnyData        = false;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _error = 'Please sign in to view analytics.';
          _loading = false;
        });
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('partner_analytics')
          .doc(uid)
          .get();

      if (!mounted) return;

      final data = doc.data() ?? {};
      final profileViews  = (data['totalProfileViews']  as num?)?.toInt() ?? 0;
      final listingViews  = (data['totalListingViews']  as num?)?.toInt() ?? 0;
      final bookingClicks = (data['totalBookingClicks'] as num?)?.toInt() ?? 0;
      final endorsements  = (data['totalEndorsements']  as num?)?.toInt() ?? 0;

      setState(() {
        _totalProfileViews  = profileViews;
        _totalListingViews  = listingViews;
        _totalBookingClicks = bookingClicks;
        _totalEndorsements  = endorsements;
        _hasAnyData =
            profileViews + listingViews + bookingClicks + endorsements > 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load analytics. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Scaffold(
      backgroundColor: hc.scaffold,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: hc.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reach analytics',
          style: HuddlText.heading(),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: HuddlColors.primary,
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(color: HuddlColors.primary))
          : _error != null
              ? _buildError()
              : _buildContent(context),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: HuddlColors.error),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: HuddlText.body(color: context.hc.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          HuddlButton(
            label: 'Retry',
            onPressed: _loadAnalytics,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final hc = context.hc;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subtitle
          Text(
            'How parents are finding and engaging with your business',
            style: HuddlText.body(color: hc.textSecondary),
          ),
          const SizedBox(height: 20),

          // 2×2 metric grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _MetricCard(
                  label: 'Profile views', value: _totalProfileViews),
              _MetricCard(
                  label: 'Listing views', value: _totalListingViews),
              _MetricCard(
                  label: 'Booking clicks', value: _totalBookingClicks),
              _MetricCard(
                  label: 'Endorsements', value: _totalEndorsements),
            ],
          ),

          const SizedBox(height: 28),

          // Chart or empty state
          if (!_hasAnyData)
            _buildEmptyState(context)
          else
            _buildChartSection(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const HuddlEmptyState(
      mood: HuddlMood.curious,
      illustrationAsset: 'assets/illustrations/growth_yellow.webp',
      title: 'No analytics yet',
      subtitle: 'Analytics will appear here once your listing starts getting views and engagement.',
    );
  }

  Widget _buildChartSection(BuildContext context) {
    final hc = context.hc;
    final bars = [
      _BarData('Profile', _totalProfileViews),
      _BarData('Listings', _totalListingViews),
      _BarData('Bookings', _totalBookingClicks),
      _BarData('Endorsed', _totalEndorsements),
    ];
    final maxValue =
        bars.map((b) => b.value).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: HuddlText.body(weight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HuddlColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: bars.map((bar) {
              final fraction =
                  maxValue > 0 ? bar.value / maxValue : 0.0;
              const maxBarHeight = 100.0;
              return _BarItem(
                label: bar.label,
                value: bar.value,
                fraction: fraction,
                maxHeight: maxBarHeight,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'All-time totals',
          style: HuddlText.caption(color: hc.textTertiary),
        ),
      ],
    );
  }
}

// =============================================================================
// _MetricCard
// White surface, 12px radius, orange accent top border
// Label: 12px textHint, Value: 28px bold primary
// =============================================================================

class _MetricCard extends StatelessWidget {
  final String label;
  final int value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: Column(
        children: [
          // Orange accent top border
          Container(
            height: 3,
            decoration: const BoxDecoration(
              color: HuddlColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: HuddlText.caption(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$value',
                    style: HuddlText.display(color: HuddlColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simple bar chart helpers ──────────────────────────────────────────────────

class _BarData {
  final String label;
  final int value;
  const _BarData(this.label, this.value);
}

class _BarItem extends StatelessWidget {
  final String label;
  final int value;
  final double fraction;
  final double maxHeight;

  const _BarItem({
    required this.label,
    required this.value,
    required this.fraction,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final barH = (maxHeight * fraction).clamp(4.0, maxHeight);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: HuddlText.caption(weight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          width: 36,
          height: barH,
          decoration: BoxDecoration(
            color: HuddlColors.primary.withValues(alpha: 0.75),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: HuddlText.label(),
        ),
      ],
    );
  }
}
