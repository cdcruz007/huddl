// ============================================================================
// HUDDL -- PARTNER PROFILE SCREEN
// ============================================================================
//
// Dedicated public business profile page for Huddl Partner subscribers.
// Layout mirrors group_details_screen.dart:
//   — SliverAppBar with expandedHeight: 240, pinned: true
//   — Business name + tagline in collapsed bar
//   — Below: stat row, listings grid, recent endorsements list
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../services/local_services_service.dart';
import '../../services/subscription_service.dart';

class PartnerProfileScreen extends StatefulWidget {
  /// UID of the Partner whose profile to show.
  /// Defaults to the current user if null.
  final String? ownerUid;

  const PartnerProfileScreen({super.key, this.ownerUid});

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  final _svc = LocalServicesService();
  List<ServiceListing> _listings = [];
  bool _loading = true;

  String get _targetUid =>
      widget.ownerUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _isOwnProfile =>
      _targetUid == (FirebaseAuth.instance.currentUser?.uid ?? '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    
    final stream = _svc.myListingsStream();
    stream.first.then((listings) {
      if (mounted) {
        setState(() {
          _listings = listings
              .where((l) => l.ownerUid == _targetUid || l.isPartnerListing)
              .toList();
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sub = SubscriptionService().subscription;
    final displayName = sub.tierDisplayName;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Sliver header ───────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: HuddlColors.primary,
            leading: BackButton(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.only(left: 56, bottom: 14),
              title: Text(
                'Partner Profile',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          HuddlColors.primary,
                          HuddlColors.primary.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                  // Business name overlay
                  Positioned(
                    left: 20,
                    bottom: 60,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            displayName.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _listings.isNotEmpty
                              ? _listings.first.name
                              : 'Partner Business',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                        if (_listings.isNotEmpty)
                          Text(
                            _listings.first.tagline,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (_isOwnProfile)
                IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  tooltip: 'Add listing',
                  onPressed: () =>
                      Navigator.pushNamed(context, '/create_partner_listing'),
                ),
            ],
          ),

          // ── Stat row ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StatRow(listings: _listings),
          ),

          // ── Listings grid ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Services',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: HuddlColors.nearBlack,
                ),
              ),
            ),
          ),

          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_listings.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.storefront_outlined,
                        size: 48, color: HuddlColors.textHint),
                    const SizedBox(height: 12),
                    Text(
                      'No listings yet',
                      style: GoogleFonts.poppins(
                          fontSize: 15, color: HuddlColors.textTertiary),
                    ),
                    if (_isOwnProfile) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                            context, '/create_partner_listing'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HuddlColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: Text(
                          'Add first listing',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ListingTile(listing: _listings[i]),
                childCount: _listings.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final List<ServiceListing> listings;

  const _StatRow({required this.listings});

  @override
  Widget build(BuildContext context) {
    final totalViews =
        listings.fold<int>(0, (sum, l) => sum + l.viewCount);
    final totalEndorsements =
        listings.fold<int>(0, (sum, l) => sum + l.endorsementCount);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(vertical: 16),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _Stat(label: 'Listings', value: '${listings.length}'),
          _divider(),
          _Stat(label: 'Views', value: '$totalViews'),
          _divider(),
          _Stat(label: 'Endorsements', value: '$totalEndorsements'),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: HuddlColors.divider,
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 20,
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
    );
  }
}

class _ListingTile extends StatelessWidget {
  final ServiceListing listing;

  const _ListingTile({required this.listing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: HuddlColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.storefront_outlined,
                color: HuddlColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.nearBlack,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  listing.tagline,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${listing.viewCount}',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.nearBlack,
                ),
              ),
              Text(
                'views',
                style: GoogleFonts.poppins(
                  fontSize: 10,
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
