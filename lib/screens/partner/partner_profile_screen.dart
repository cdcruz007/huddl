import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/local_services_service.dart';
import '../../theme/huddl_colors.dart';

// =============================================================================
// PARTNER BUSINESS PROFILE SCREEN
//
// Dedicated public-facing business page for Partner subscribers.
// Accessible to all users (read-only for non-owners).
// Layout: CustomScrollView with SliverAppBar(expandedHeight: 240, pinned: true)
// =============================================================================

class PartnerProfileScreen extends StatefulWidget {
  final String partnerUid;
  const PartnerProfileScreen({super.key, required this.partnerUid});

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  // Data state
  bool _loading = true;
  String? _error;

  // User doc fields
  String _businessName = '';
  bool _businessVerified = false;

  // Listings + endorsements
  List<ServiceListing> _listings = [];
  List<ServiceEndorsement> _recentEndorsements = [];

  final _service = LocalServicesService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      // 1. User doc
      final userDocFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.partnerUid)
          .get();

      // 2. Listings for this partner
      final listingsFuture = FirebaseFirestore.instance
          .collection('local_services')
          .where('ownerUid', isEqualTo: widget.partnerUid)
          .get();

      // 3. Run in parallel
      final results = await Future.wait([userDocFuture, listingsFuture]);

      final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final listingsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;

      if (!mounted) return;

      final userData = userSnap.data() ?? {};
      final listings = listingsSnap.docs
          .map((d) => ServiceListing.fromFirestore(d))
          .toList();

      // Sort: Partner listings first, then by endorsement count
      listings.sort((a, b) {
        if (a.isPartnerListing && !b.isPartnerListing) return -1;
        if (!a.isPartnerListing && b.isPartnerListing) return 1;
        return b.endorsementCount.compareTo(a.endorsementCount);
      });

      // Collect recent endorsements across all listings (top 5)
      final List<ServiceEndorsement> allEndorsements = [];
      for (final listing in listings.take(3)) {
        try {
          final endorsements = await _service.getEndorsements(listing.id);
          allEndorsements.addAll(endorsements);
        } catch (_) {}
      }
      allEndorsements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final recent = allEndorsements.take(5).toList();

      if (!mounted) return;

      setState(() {
        _businessName = (userData['verifiedBusinessName'] as String?) ??
            (userData['displayName'] as String?) ?? '';
        _businessVerified = (userData['businessVerified'] as bool?) ?? false;
        _listings = listings;
        _recentEndorsements = recent;
        _loading = false;
      });

      // Track profile view (fire-and-forget, not for own profile)
      if (FirebaseAuth.instance.currentUser?.uid != widget.partnerUid) {
        FirebaseFirestore.instance
            .collection('partner_analytics')
            .doc(widget.partnerUid)
            .set({
          'totalProfileViews': FieldValue.increment(1),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load business profile.';
        _loading = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _initial =>
      _businessName.isNotEmpty ? _businessName[0].toUpperCase() : '?';

  String get _boroughLabel {
    if (_listings.isEmpty) return '';
    return _listings.first.borough;
  }

  String get _aboutText {
    for (final l in _listings) {
      if (l.description.isNotEmpty) return l.description;
    }
    return 'Trusted local business on Huddl.';
  }

  ServiceListing? get _primaryListing =>
      _listings.isNotEmpty ? _listings.first : null;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    if (_loading) {
      return Scaffold(
        backgroundColor: hc.scaffold,
        body: const Center(
            child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: hc.scaffold,
        appBar: AppBar(backgroundColor: hc.surface, elevation: 0),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 48, color: HuddlColors.error),
              const SizedBox(height: 16),
              Text(_error!,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: hc.textSecondary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadData,
                style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary),
                child: Text('Retry',
                    style:
                        GoogleFonts.poppins(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: hc.scaffold,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar ─────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: hc.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: HuddlColors.nearBlack,
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (FirebaseAuth.instance.currentUser?.uid == widget.partnerUid)
                IconButton(
                  icon: const Icon(Icons.bar_chart_rounded),
                  color: HuddlColors.primary,
                  onPressed: () =>
                      Navigator.pushNamed(context, '/partner_analytics'),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: HuddlColors.primary.withValues(alpha: 0.08),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      // Business initial avatar — 80px orange circle
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: HuddlColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: HuddlColors.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _initial,
                            style: GoogleFonts.poppins(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Business name
                      if (_businessName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _businessName,
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.nearBlack,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 8),
                      // HMRC-verified badge + borough
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_businessVerified) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: HuddlColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_rounded,
                                      size: 12, color: HuddlColors.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'HMRC Verified',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (_boroughLabel.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on_outlined,
                                    size: 13,
                                    color: HuddlColors.nearBlack
                                        .withValues(alpha: 0.6)),
                                const SizedBox(width: 3),
                                Text(
                                  _boroughLabel,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: HuddlColors.nearBlack
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1 — About
                  _SectionHeader(title: 'About'),
                  const SizedBox(height: 8),
                  Text(
                    _aboutText,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: context.hc.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Section 2 — Services
                  if (_listings.isNotEmpty) ...[
                    _SectionHeader(title: 'Services'),
                    const SizedBox(height: 12),
                    if (_listings.length <= 2)
                      Column(
                        children: _listings
                            .map((l) => _ListingMiniCard(
                                  listing: l,
                                  onTap: () => _showListingDetail(context, l),
                                ))
                            .toList(),
                      )
                    else
                      SizedBox(
                        height: 130,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _listings.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (ctx, i) => _ListingMiniCard(
                            listing: _listings[i],
                            onTap: () => _showListingDetail(ctx, _listings[i]),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],

                  // Section 3 — Parent endorsements
                  if (_recentEndorsements.isNotEmpty) ...[
                    _SectionHeader(title: 'Parent endorsements'),
                    const SizedBox(height: 12),
                    ..._recentEndorsements.map((e) => _EndorsementRow(e: e)),
                    const SizedBox(height: 24),
                  ],

                  // Section 4 — Contact / booking CTA
                  if (_primaryListing?.externalBookingUrl?.isNotEmpty == true)
                    _buildBookingCta(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCta(BuildContext context) {
    final url = _primaryListing!.externalBookingUrl!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Get in touch'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(
              'Book / Enquire',
              style:
                  GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            onPressed: () async {
              final hasScheme =
                  url.startsWith('http://') || url.startsWith('https://');
              final uri = Uri.parse(hasScheme ? url : 'https://$url');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      ],
    );
  }

  void _showListingDetail(BuildContext context, ServiceListing listing) {
    // Navigate to services screen with listing opened — or push named route
    // For now show a simple bottom sheet summary
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(listing.name,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary)),
            const SizedBox(height: 4),
            Text(listing.category.displayName,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: context.hc.textSecondary)),
            if (listing.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(listing.description,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: context.hc.textSecondary, height: 1.5)),
            ],
            const SizedBox(height: 16),
            if (listing.externalBookingUrl?.isNotEmpty == true)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('Book / Enquire',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  onPressed: () async {
                    final url = listing.externalBookingUrl!;
                    final hasScheme = url.startsWith('http://') ||
                        url.startsWith('https://');
                    final uri = Uri.parse(hasScheme ? url : 'https://$url');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: context.hc.textPrimary,
      ),
    );
  }
}

class _ListingMiniCard extends StatelessWidget {
  final ServiceListing listing;
  final VoidCallback onTap;
  const _ListingMiniCard({required this.listing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.work_outline_rounded,
                    size: 16, color: HuddlColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    listing.category.displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.primary,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              listing.name,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hc.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (listing.tagline.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                listing.tagline,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: hc.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.thumb_up_rounded, size: 11, color: HuddlColors.primary),
                const SizedBox(width: 4),
                Text(
                  '${listing.endorsementCount}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: HuddlColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EndorsementRow extends StatelessWidget {
  final ServiceEndorsement e;
  const _EndorsementRow({required this.e});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: HuddlColors.primary.withValues(alpha: 0.15),
                child: Text(
                  e.firstName.isNotEmpty ? e.firstName[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                e.credit,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hc.textPrimary,
                ),
              ),
            ],
          ),
          if (e.quote != null && e.quote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${e.quote}"',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: hc.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          // Owner reply
          if (e.ownerReply != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.hc.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 14, color: HuddlColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.ownerReply!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
