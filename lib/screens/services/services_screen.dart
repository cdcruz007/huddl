import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/local_services_service.dart';
import '../../services/ai_directory_service.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_empty_state.dart';

// =============================================================================
// SERVICES SCREEN — HUDDL TRUSTED LOCAL DIRECTORY
//
// Single unified screen (no sub-tabs).
//   • AnimatedCrossFade filter pill ↔ inline search
//   • "Suggested for you" / "Search results" section label
//   • Card: same _GroupMessageRow shell (horizontal tile with rounded avatar)
//   • AI badge  — shown when listingSource is 'places_api' / 'ai_discovered*'
//   • Parent badge — shown when listingSource is 'parent_added'
//   • + FAB (bottom-right) → opens Add / AI bottom sheet
// =============================================================================

// ── Category hero images — stable Unsplash CDN URLs (full-width hero covers) ─
const Map<ServiceCategory, String> _kCategoryImages = {
  ServiceCategory.childcare:
      'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?w=800&h=400&fit=crop',
  ServiceCategory.babysitting:
      'https://images.unsplash.com/photo-1566004100631-35d015d6a491?w=800&h=400&fit=crop',
  ServiceCategory.cleaning:
      'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=800&h=400&fit=crop',
  ServiceCategory.healthWellness:
      'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=800&h=400&fit=crop',
  ServiceCategory.education:
      'https://images.unsplash.com/photo-1503676260728-1c00da094a0b?w=800&h=400&fit=crop',
  ServiceCategory.fitness:
      'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&h=400&fit=crop',
  ServiceCategory.firstAid:
      'https://images.unsplash.com/photo-1516549655169-df83a0774514?w=800&h=400&fit=crop',
  ServiceCategory.doula:
      'https://images.unsplash.com/photo-1555252333-9f8e92e65df9?w=800&h=400&fit=crop',
  ServiceCategory.homeServices:
      'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800&h=400&fit=crop',
  ServiceCategory.photography:
      'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&h=400&fit=crop',
  ServiceCategory.food:
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&h=400&fit=crop',
  ServiceCategory.other:
      'https://images.unsplash.com/photo-1497366216548-37526070297c?w=800&h=400&fit=crop',
};

// ── Avatar photo pool (same pool as Events / Groups tabs) ──────────────────────
const List<String> _kAvatarPool = [
  'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=100&h=100&fit=crop&crop=face',
];

// ─── Source badge helpers ─────────────────────────────────────────────────────

bool _isParentSource(String source) => source == 'parent_added';

// Badge colour token — teal, same as 'Free' badge in Events
const Color _kBadgeParent = HuddlColors.teal;

// ─── Main screen ─────────────────────────────────────────────────────────────

class ServicesScreen extends StatefulWidget {
  final ValueNotifier<bool> searchTrigger;
  const ServicesScreen({super.key, required this.searchTrigger});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _service = LocalServicesService();

  ServiceCategory? _selectedCategory;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // searchTrigger from the top AppBar magnifier now focuses the inline bar
    widget.searchTrigger.addListener(_onSearchTrigger);
    _triggerAiRefreshIfDue();
  }

  // AppBar magnifier tap focuses the always-visible search bar directly
  void _onSearchTrigger() {
    if (widget.searchTrigger.value) {
      widget.searchTrigger.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocus.requestFocus();
      });
    }
  }

  Future<void> _triggerAiRefreshIfDue() async {
    try {
      await AiDirectoryService().runIfDue();
    } catch (_) {
      // Silent
    }
  }

  @override
  void dispose() {
    widget.searchTrigger.removeListener(_onSearchTrigger);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Keywords that signal an entry is an event/activity, not a service provider.
  static const _kEventKeywords = [
    'parkrun', 'park run', 'fun run', 'race', '5k', '10k', 'marathon',
    'community event', 'open day', 'open house', 'festival', 'fair',
    'boot camp event', 'boot camp run',
  ];

  bool _isEventLike(ServiceListing l) {
    final haystack =
        '${l.name} ${l.tagline} ${l.description} ${l.tags.join(' ')}'
            .toLowerCase();
    return _kEventKeywords.any((kw) => haystack.contains(kw));
  }

  List<ServiceListing> _filter(List<ServiceListing> all) {
    var result = all.where((l) => !_isEventLike(l)).toList();
    if (_selectedCategory != null) {
      result = result.where((l) => l.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((l) {
        return l.name.toLowerCase().contains(q) ||
            l.tagline.toLowerCase().contains(q) ||
            l.description.toLowerCase().contains(q) ||
            l.tags.any((t) => t.toLowerCase().contains(q));
      }).toList();
    }
    return result;
  }

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddServiceSheet(service: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hc = context.hc;
    const Color filterText = Color(0xFF42464C);
    final bool hasActiveFilter = _selectedCategory != null;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: Column(
        children: [
          // ══ TOP HEADER — always-visible search + filter pill ══════════════
          // Matches Groups and Meetups exactly:
          //   Row 1: persistent pill search bar (height 40, inputBg, orange icon)
          //   Row 2: filter pill + optional Clear link
          //   Row 3: section label ("Suggested for you" / "Search results")
          Container(
            color: hc.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: Search bar — always visible (Groups/Meetups style) ─
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: hc.inputBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(left: 12, right: 6),
                        child: Icon(Icons.search, size: 18,
                            color: HuddlColors.primary),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          textAlignVertical: TextAlignVertical.center,
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.trim()),
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: filterText),
                          decoration: InputDecoration(
                            hintText: 'Search services…',
                            hintStyle: GoogleFonts.poppins(
                              fontSize: 14,
                              color: HuddlColors.textTertiary,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.only(bottom: 2),
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _searchQuery = '');
                            _searchCtrl.clear();
                            _searchFocus.unfocus();
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.close,
                                size: 16,
                                color: HuddlColors.textTertiary),
                          ),
                        )
                      else
                        const SizedBox(width: 10),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── Row 2: Filter pill + Clear ────────────────────────────────
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showCategorySheet(context),
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: hasActiveFilter
                              ? HuddlColors.primary.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasActiveFilter
                                ? HuddlColors.primary.withValues(alpha: 0.3)
                                : hc.divider,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: hasActiveFilter
                                  ? HuddlColors.primary
                                  : filterText,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasActiveFilter
                                  ? _selectedCategory!.displayName
                                  : 'Filter by category',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: hasActiveFilter
                                    ? HuddlColors.primary
                                    : filterText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (hasActiveFilter) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _selectedCategory = null);
                        },
                        child: Text(
                          'Clear',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // ── Row 3: Section label ──────────────────────────────────────
                Text(
                  _searchQuery.isEmpty ? 'Suggested for you' : 'Search results',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: filterText,
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),

          // ── Listing stream ────────────────────────────────────────────────
          Expanded(
            child: ColoredBox(
              color: HuddlColors.background,
              child: StreamBuilder<List<ServiceListing>>(
                stream: _service.listingsStream(category: _selectedCategory),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: HuddlColors.primary));
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Could not load listings.\nCheck your connection.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: context.hc.textSecondary),
                        ),
                      ),
                    );
                  }
                  final all = snap.data ?? [];
                  final filtered = _filter(all);

                  if (filtered.isEmpty) {
                    return _EmptyDirectory(
                      hasFilter: _selectedCategory != null ||
                          _searchQuery.isNotEmpty,
                      onClear: () {
                        setState(() {
                          _selectedCategory = null;
                          _searchCtrl.clear();
                          _searchQuery = '';
                        });
                      },
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _ListingCard(
                      listing: filtered[i],
                      service: _service,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      // ── + FAB (matches Groups tab) ────────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _openAddSheet(context);
        },
        backgroundColor: HuddlColors.primary,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }

  // Category filter bottom sheet
  void _showCategorySheet(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Filter by category',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.hc.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _CategorySheetTile(
              label: 'All categories',
              emoji: '🏠',
              selected: _selectedCategory == null,
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(ctx);
              },
            ),
            ...ServiceCategory.values.map((cat) => _CategorySheetTile(
                  label: cat.displayName,
                  emoji: cat.emoji,
                  selected: _selectedCategory == cat,
                  onTap: () {
                    setState(() => _selectedCategory =
                        _selectedCategory == cat ? null : cat);
                    Navigator.pop(ctx);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Category sheet tile ──────────────────────────────────────────────────────

class _CategorySheetTile extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  const _CategorySheetTile({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? HuddlColors.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? HuddlColors.primary : hc.divider,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? HuddlColors.primary : hc.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded,
                  size: 18, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }
}

// ─── Service category initial avatar (replaces emoji in compact list thumbnail) ─
// Shows the first 1-2 letters of the listing name on a soft-coloured background,
// matching the existing initials-avatar pattern used across the Huddl app.

class _ServiceCategoryInitial extends StatelessWidget {
  final String name;
  final Color color;

  const _ServiceCategoryInitial({required this.name, required this.color});

  String get _initial {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _initial,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }
}

// ─── Overlaid badge pill (Events-style: solid colour, white text) ────────────

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;

  const _BadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ─── Listing card — Events-style (full-width hero + overlaid badges + body + avatar row) ─

class _ListingCard extends StatefulWidget {
  final ServiceListing listing;
  final LocalServicesService service;

  const _ListingCard({required this.listing, required this.service});

  @override
  State<_ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<_ListingCard> {
  bool _hasEndorsed = false;
  bool _endorsing   = false;
  late int _count;

  @override
  void initState() {
    super.initState();
    _hasEndorsed = widget.listing.hasEndorsed;
    _count       = widget.listing.endorsementCount;
    _checkEndorsed();
  }

  Future<void> _checkEndorsed() async {
    final result = await widget.service.hasEndorsed(widget.listing.id);
    if (mounted) setState(() => _hasEndorsed = result);
  }

  Future<void> _toggleEndorse() async {
    if (_endorsing) return;
    setState(() => _endorsing = true);
    HapticFeedback.mediumImpact();
    if (_hasEndorsed) {
      await widget.service.removeEndorsement(widget.listing.id);
      if (mounted) setState(() { _hasEndorsed = false; _count = (_count - 1).clamp(0, 9999); });
    } else {
      final quote = await _showEndorseDialog();
      if (quote == null) { if (mounted) setState(() => _endorsing = false); return; }
      await widget.service.endorseListing(widget.listing.id, quote: quote.isEmpty ? null : quote);
      if (mounted) setState(() { _hasEndorsed = true; _count = _count + 1; });
    }
    if (mounted) setState(() => _endorsing = false);
  }

  Future<String?> _showEndorseDialog() => showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            backgroundColor: context.hc.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Endorse \${widget.listing.name}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add a personal note (optional)',
                    style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 120,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '"Reliable, insured, brilliant with our kids"',
                    hintStyle: GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary),
                    filled: true,
                    fillColor: context.hc.inputBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('Cancel',
                      style: GoogleFonts.poppins(color: context.hc.textSecondary))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text('Endorse',
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final catColor = _categoryColor(listing.category);

    // Hero image: Google Places photo first, then Unsplash category fallback
    final imageUrl = (listing.imageUrl?.isNotEmpty == true)
        ? listing.imageUrl!
        : (_kCategoryImages[listing.category] ?? _kCategoryImages[ServiceCategory.other]!);

    final isParent = _isParentSource(listing.listingSource);
    final isVerified = listing.isVerified ||
        listing.verificationTier == VerificationTier.verified;
    final isCommunityPick = listing.verificationTier == VerificationTier.community ||
        listing.endorsementCount >= 3;

    // ── Events-style card shell ───────────────────────────────────────────
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.service.recordView(listing.id);
        _showListingDetail(context, listing, widget.service);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero image with overlaid badge pills ────────────────────
            Stack(
              children: [
                SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 190,
                    errorBuilder: (_, __, ___) => Container(
                      height: 190,
                      color: catColor.withValues(alpha: 0.14),
                      child: Center(
                        child: Icon(Icons.store_mall_directory_outlined,
                            size: 48, color: catColor.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
                // Subtle bottom gradient (mirrors Events card)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.22),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top-left: Parent badge — only shown for parent-added listings
                if (isParent)
                  Positioned(
                    top: 12, left: 12,
                    child: _BadgePill(label: 'Parent Added', color: _kBadgeParent),
                  ),
                // Top-right: Verified / Community Pick
                if (isVerified || isCommunityPick)
                  Positioned(
                    top: 12, right: 12,
                    child: _BadgePill(
                      label: isVerified ? 'Verified' : 'Community Pick',
                      color: HuddlColors.teal,
                    ),
                  ),
              ],
            ),

            // ── Card body (category meta + bold name + tagline/address) ───────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category row — small uppercase label (no emoji — Huddl design standard)
                  Text(
                    listing.category.displayName.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: HuddlColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Bold listing name — 2-line max (mirrors Event title style)
                  Text(
                    listing.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.hc.textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Tagline / borough (mirrors Event location row)
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 14, color: context.hc.textTertiary),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          listing.tagline.isNotEmpty
                              ? listing.tagline
                              : listing.borough,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: context.hc.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Bottom row: avatar stack + endorsement count + Enquire pill ──
            // Mirrors exactly the Events card bottom row (avatars + count + Join pill)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  // Overlapping avatar circles — deterministic from listing id
                  SizedBox(
                    width: 62,
                    height: 24,
                    child: Stack(
                      children: [
                        for (int i = 0; i < 3; i++)
                          Positioned(
                            left: i * 18.0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: ClipOval(
                                child: Image.network(
                                  _kAvatarPool[
                                      (listing.id.hashCode + i).abs() % _kAvatarPool.length],
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: catColor.withValues(alpha: 0.25),
                                    child: Icon(Icons.person, size: 12, color: catColor),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _count > 0 ? '\$_count endorsed' : '0 endorsements',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: context.hc.textTertiary,
                      ),
                    ),
                  ),
                  // Endorse pill — grey resting, primary fill when endorsed
                  // Same visual spec as grey 'Join' pill in Events tab
                  GestureDetector(
                    onTap: _endorsing ? null : _toggleEndorse,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: _hasEndorsed
                            ? HuddlColors.primary
                            : const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _endorsing
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _hasEndorsed ? Colors.white : HuddlColors.primary,
                              ),
                            )
                          : Text(
                              _hasEndorsed ? 'Endorsed ✓' : 'Endorse',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _hasEndorsed
                                    ? Colors.white
                                    : const Color(0xFF42464C),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ─── Inline tag chip ─────────────────────────────────────────────────────────

class _InlineTagChip extends StatelessWidget {
  final String tag;
  const _InlineTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hc.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.divider),
      ),
      child: Text(
        tag,
        style: GoogleFonts.poppins(
            fontSize: 10,
            color: hc.textSecondary,
            fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─── Verified badge (used in detail sheet) ────────────────────────────────────

class _VerifiedBadge extends StatelessWidget {
  final VerificationTier tier;
  const _VerifiedBadge({required this.tier});

  @override
  Widget build(BuildContext context) {
    final isVerified = tier == VerificationTier.verified;
    const color = HuddlColors.teal;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVerified ? Icons.verified_rounded : Icons.people_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            tier.badgeLabel,
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Listing detail bottom sheet ─────────────────────────────────────────────

void _showListingDetail(BuildContext context, ServiceListing listing,
    LocalServicesService service) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) =>
        _ListingDetailSheet(listing: listing, service: service),
  );
}

class _ListingDetailSheet extends StatefulWidget {
  final ServiceListing listing;
  final LocalServicesService service;
  const _ListingDetailSheet(
      {required this.listing, required this.service});

  @override
  State<_ListingDetailSheet> createState() => _ListingDetailSheetState();
}

class _ListingDetailSheetState extends State<_ListingDetailSheet> {
  List<ServiceEndorsement> _endorsements = [];
  bool _loadingEndorsements = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final endorsements =
        await widget.service.getEndorsements(widget.listing.id);
    if (mounted) {
      setState(() {
        _endorsements = endorsements;
        _loadingEndorsements = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final listing = widget.listing;
    final catColor = _categoryColor(listing.category);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Hero + name ──────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: _ServiceCategoryInitial(
                        name: listing.name,
                        color: catColor,
                      ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.name,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: hc.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            listing.category.displayName,
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: hc.textSecondary),
                          ),
                          const SizedBox(width: 6),
                          if (_isParentSource(listing.listingSource))
                            _BadgePill(label: 'Parent Added', color: _kBadgeParent),
                        ],
                      ),
                    ],
                  ),
                ),
                if (listing.isVerified ||
                    listing.verificationTier == VerificationTier.community)
                  _VerifiedBadge(tier: listing.verificationTier),
              ],
            ),
            const SizedBox(height: 14),
            // ── "Added by parent" row — only on parent_added listings ────
            if (_isParentSource(listing.listingSource) &&
                listing.parentName != null &&
                listing.parentName!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: HuddlColors.teal.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: HuddlColors.teal.withValues(alpha: 0.22)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: HuddlColors.teal.withValues(alpha: 0.15),
                      child: Text(
                        listing.parentName![0].toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended by',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.teal.withValues(alpha: 0.8),
                            ),
                          ),
                          Text(
                            listing.parentName!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Message this parent if they are a Huddl member
                    if (listing.createdByUid.isNotEmpty &&
                        listing.createdByUid !=
                            FirebaseAuth.instance.currentUser?.uid)
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.of(context).pushNamed(
                            '/dm_chat',
                            arguments: {
                              'recipientId':   listing.createdByUid,
                              'recipientName': listing.parentName,
                              'recipientAvatarColor': '#3580F0',
                              'conversationId': '',
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: HuddlColors.teal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline_rounded,
                                  size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Text(
                                'Message',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            // ── Tagline ──────────────────────────────────────────────────
            if (listing.tagline.isNotEmpty) ...[
              Text(
                listing.tagline,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hc.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            // ── Description ──────────────────────────────────────────────
            if (listing.description.isNotEmpty) ...[
              Text(
                listing.description,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: hc.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            // ── Tags ────────────────────────────────────────────────────
            if (listing.tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    listing.tags.map((t) => _InlineTagChip(tag: t)).toList(),
              ),
              const SizedBox(height: 16),
            ],
            // ── Stats row ────────────────────────────────────────────────
            Row(
              children: [
                _StatPill(
                  icon: Icons.thumb_up_rounded,
                  label: '${listing.endorsementCount} endorsements',
                  color: HuddlColors.teal,
                ),
                const SizedBox(width: 8),
                _StatPill(
                  icon: Icons.visibility_outlined,
                  label: '${listing.viewCount} views',
                  color: HuddlColors.teal,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Contact CTAs ─────────────────────────────────────────────
            if (listing.phone != null) ...[
              _ContactRow(
                icon: Icons.phone_outlined,
                label: listing.phone!,
                color: HuddlColors.teal,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Call ${listing.phone}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            if (listing.website != null) ...[
              _ContactRow(
                icon: Icons.language_outlined,
                label: listing.website!,
                color: HuddlColors.teal,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Opening ${listing.website}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            // ── Enquire via Huddl DM ────────────────────────────────────
            if (listing.ownerUid != null &&
                listing.ownerUid !=
                    FirebaseAuth.instance.currentUser?.uid) ...[
              const SizedBox(height: 4),
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
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 18),
                  label: Text(
                    'Enquire via Huddl',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).pushNamed(
                      '/dm_chat',
                      arguments: {
                        'recipientId': listing.ownerUid,
                        'recipientName': listing.name,
                        'recipientAvatarColor': '#3580F0',
                        'conversationId': '',
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            // ── Endorsements section ─────────────────────────────────────
            Row(
              children: [
                Text(
                  'Parent Endorsements',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: hc.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: HuddlColors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${listing.endorsementCount}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.teal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingEndorsements)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child:
                        CircularProgressIndicator(color: HuddlColors.teal)),
              )
            else if (_endorsements.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No endorsements yet — be the first local parent to vouch!',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: hc.textSecondary),
                ),
              )
            else
              ...(_endorsements.map((e) => _EndorsementTile(endorsement: e))),
          ],
        ),
      ),
    );
  }
}

// ─── Endorsement tile ────────────────────────────────────────────────────────

class _EndorsementTile extends StatelessWidget {
  final ServiceEndorsement endorsement;
  const _EndorsementTile({required this.endorsement});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? HuddlColors.darkSurfaceVariant
            : HuddlColors.blueBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: HuddlColors.teal.withValues(alpha: 0.15),
                child: Text(
                  endorsement.firstName.isNotEmpty
                      ? endorsement.firstName[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.teal,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                endorsement.credit,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hc.textPrimary,
                ),
              ),
            ],
          ),
          if (endorsement.quote != null && endorsement.quote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${endorsement.quote}"',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: hc.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Stat pill ───────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatPill(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Contact row ─────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: hc.inputBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hc.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style:
                    GoogleFonts.poppins(fontSize: 13, color: hc.textPrimary),
              ),
            ),
            Icon(Icons.open_in_new, size: 14, color: hc.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyDirectory extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onClear;
  const _EmptyDirectory({required this.hasFilter, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return HuddlEmptyState(
      illustration: HuddlIllustration.community,
      title: hasFilter
          ? 'No listings match your filter'
          : 'No listings in your area yet',
      subtitle: hasFilter
          ? 'Try a different category or search term'
          : 'Be the first to add a trusted local pro.\nPaste a WhatsApp recommendation or add manually.',
      actionLabel: hasFilter ? 'Clear filters' : null,
      onAction: hasFilter ? onClear : null,
    );
  }
}

// ─── Add / AI bottom sheet (triggered by FAB) ────────────────────────────────

class _AddServiceSheet extends StatefulWidget {
  final LocalServicesService service;
  const _AddServiceSheet({required this.service});

  @override
  State<_AddServiceSheet> createState() => _AddServiceSheetState();
}

class _AddServiceSheetState extends State<_AddServiceSheet> {
  final TextEditingController _chatPasteCtrl = TextEditingController();
  final TextEditingController _parentNameCtrl = TextEditingController();
  bool _extracting = false;
  List<ExtractedServiceRecommendation> _extracted = [];
  String? _extractError;
  bool _showManual = false;

  @override
  void dispose() {
    _chatPasteCtrl.dispose();
    _parentNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _runExtraction() async {
    final text = _chatPasteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _extracting = true;
      _extracted = [];
      _extractError = null;
    });
    try {
      final results = await widget.service.extractFromChatText(text);
      if (mounted) {
        setState(() {
          _extracted = results;
          _extracting = false;
          _extractError = results.isEmpty
              ? 'No service recommendations found in that text. Try pasting a message like "Has anyone tried Sandra at Clean2Perfection?"'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractError = 'AI extraction failed. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return DraggableScrollableSheet(
      initialChildSize: 0.70,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
          children: [
            // Handle + title
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: hc.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: HuddlColors.aiGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_business_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a Service',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: hc.textPrimary,
                          ),
                        ),
                        Text(
                          'Paste a WhatsApp message or add manually',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: hc.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── AI extraction card ────────────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: HuddlColors.aiGradient,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.auto_awesome,
                            color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI Extraction',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: hc.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _chatPasteCtrl,
                    maxLines: 4,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: hc.textPrimary),
                    decoration: InputDecoration(
                      hintText:
                          '"Has anyone used Sandra at Clean2Perfection? She\'s insured, reliable — 07700 900123"',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 12,
                          color: hc.textTertiary,
                          fontStyle: FontStyle.italic),
                      filled: true,
                      fillColor: hc.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ─ Parent name for attribution ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: HuddlColors.teal.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: HuddlColors.teal.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline_rounded,
                                size: 14, color: HuddlColors.teal),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Your name in the borough (optional)',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: HuddlColors.teal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'So other parents can message you about this recommendation.',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.teal.withValues(alpha: 0.85),
                              height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _parentNameCtrl,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: hc.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'e.g. Sarah from Chesterton',
                            hintStyle: GoogleFonts.poppins(
                                fontSize: 12, color: hc.textTertiary),
                            filled: true,
                            fillColor: hc.inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
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
                      icon: _extracting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search, size: 18),
                      label: Text(
                        _extracting
                            ? 'Analysing\u2026'
                            : 'Extract recommendations',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      onPressed: _extracting ? null : _runExtraction,
                    ),
                  ),
                  if (_extractError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: HuddlColors.warningBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _extractError!,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: HuddlColors.warningDark),
                      ),
                    ),
                  ],
                  if (_extracted.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${_extracted.length} recommendation${_extracted.length > 1 ? 's' : ''} found',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: hc.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._extracted.map((r) => _ExtractedRecommendationCard(
                          rec: r,
                          service: widget.service,
                          parentName: _parentNameCtrl.text.trim().isEmpty
                              ? null
                              : _parentNameCtrl.text.trim(),
                          onSubmit: (listingId) {
                            if (listingId != null) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${r.name} added to the directory!'),
                                  backgroundColor: HuddlColors.success,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        )),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Manual add toggle ─────────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showManual = !_showManual),
              child: Row(
                children: [
                  Icon(
                    _showManual
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: hc.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showManual ? 'Hide manual form' : 'Or add manually',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hc.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (_showManual) ...[
              const SizedBox(height: 12),
              _ManualAddForm(
                service: widget.service,
                onSubmit: (listingId) {
                  if (listingId != null) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Listing added to the directory!'),
                        backgroundColor: HuddlColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Extracted recommendation card ───────────────────────────────────────────

class _ExtractedRecommendationCard extends StatefulWidget {
  final ExtractedServiceRecommendation rec;
  final LocalServicesService service;
  final void Function(String? listingId) onSubmit;
  final String? parentName;

  const _ExtractedRecommendationCard({
    required this.rec,
    required this.service,
    required this.onSubmit,
    this.parentName,
  });

  @override
  State<_ExtractedRecommendationCard> createState() =>
      _ExtractedRecommendationCardState();
}

class _ExtractedRecommendationCardState
    extends State<_ExtractedRecommendationCard> {
  bool _submitting = false;
  bool _submitted = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final id = await widget.service.createListing(
      name: widget.rec.name,
      tagline: widget.rec.quote ?? widget.rec.category.displayName,
      description: widget.rec.quote ?? '',
      category: widget.rec.category,
      tags: widget.rec.tags,
      phone: widget.rec.phone,
      website: widget.rec.website,
      parentName: widget.parentName,
    );
    if (mounted) {
      setState(() {
        _submitting = false;
        _submitted = id != null;
      });
      widget.onSubmit(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final rec = widget.rec;

    if (_submitted) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.successBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: HuddlColors.success, size: 20),
            const SizedBox(width: 8),
            Text('${rec.name} added!',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.success)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hc.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rec.name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: hc.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      _confidenceColor(rec.confidence).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rec.confidence,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _confidenceColor(rec.confidence),
                  ),
                ),
              ),
            ],
          ),
          if (rec.quote != null && rec.quote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '"${rec.quote}"',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: hc.textSecondary,
              ),
            ),
          ],
          if (rec.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: rec.tags.map((t) => _InlineTagChip(tag: t)).toList(),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      'Add to directory',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _confidenceColor(String confidence) => switch (confidence) {
      'high' => HuddlColors.success,
      'medium' => HuddlColors.warning,
      _ => HuddlColors.textTertiary,
    };

// ─── Manual add form ──────────────────────────────────────────────────────────

class _ManualAddForm extends StatefulWidget {
  final LocalServicesService service;
  final void Function(String? listingId) onSubmit;
  const _ManualAddForm({required this.service, required this.onSubmit});

  @override
  State<_ManualAddForm> createState() => _ManualAddFormState();
}

class _ManualAddFormState extends State<_ManualAddForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _parentNameCtrl = TextEditingController();
  ServiceCategory _category = ServiceCategory.other;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    _descriptionCtrl.dispose();
    _phoneCtrl.dispose();
    _websiteCtrl.dispose();
    _tagsCtrl.dispose();
    _parentNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final tags = _tagsCtrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final id = await widget.service.createListing(
      name: _nameCtrl.text.trim(),
      tagline: _taglineCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      category: _category,
      tags: tags,
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      website: _websiteCtrl.text.trim().isEmpty ? null : _websiteCtrl.text.trim(),
      parentName: _parentNameCtrl.text.trim().isEmpty ? null : _parentNameCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _submitting = false);
      widget.onSubmit(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return _SectionCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add manually',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: hc.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            _FormField(
              controller: _nameCtrl,
              label: 'Name *',
              hint: 'e.g. Sandra at Clean2Perfection',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ServiceCategory>(
              initialValue: _category,
              items: ServiceCategory.values
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Text(cat.emoji,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(cat.displayName,
                                style: GoogleFonts.poppins(fontSize: 13)),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (cat) =>
                  setState(() => _category = cat ?? ServiceCategory.other),
              decoration: InputDecoration(
                labelText: 'Category',
                labelStyle: GoogleFonts.poppins(
                    fontSize: 13, color: hc.textSecondary),
                filled: true,
                fillColor: hc.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _taglineCtrl,
              label: 'Tagline',
              hint: 'e.g. Insured, reliable, DBS checked',
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _descriptionCtrl,
              label: 'Endorsement / description',
              hint: 'What would you tell a friend about them?',
              maxLines: 3,
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _tagsCtrl,
              label: 'Tags (comma-separated)',
              hint: 'insured, DBS checked, flexible hours',
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _phoneCtrl,
              label: 'Phone (optional)',
              hint: '07700 900123',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: _websiteCtrl,
              label: 'Website / Instagram (optional)',
              hint: 'instagram.com/sandracleans',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            // ── Who's recommending this? ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HuddlColors.teal.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: HuddlColors.teal.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 15, color: HuddlColors.teal),
                      const SizedBox(width: 6),
                      Text(
                        'Your recommendation (optional)',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add your name so other parents can message you about your experience with this provider.',
                    style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: HuddlColors.teal.withValues(alpha: 0.85),
                        height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  _FormField(
                    controller: _parentNameCtrl,
                    label: 'Your name in the borough',
                    hint: 'e.g. Sarah from Chesterton',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        'Add to directory',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.validator,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.poppins(fontSize: 13, color: hc.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle:
            GoogleFonts.poppins(fontSize: 13, color: hc.textSecondary),
        hintStyle:
            GoogleFonts.poppins(fontSize: 12, color: hc.textTertiary),
        filled: true,
        fillColor: hc.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorStyle:
            GoogleFonts.poppins(fontSize: 11, color: HuddlColors.error),
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: hc.cardBorder,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }
}

// ─── Category colour helper ───────────────────────────────────────────────────

Color _categoryColor(ServiceCategory cat) => switch (cat) {
      ServiceCategory.childcare => HuddlColors.categoryBaby,
      ServiceCategory.babysitting => HuddlColors.accentCoral,
      ServiceCategory.cleaning => HuddlColors.teal,
      ServiceCategory.healthWellness => HuddlColors.success,
      ServiceCategory.education => HuddlColors.teal,
      ServiceCategory.fitness => HuddlColors.categorySport,
      ServiceCategory.firstAid => HuddlColors.error,
      ServiceCategory.doula => HuddlColors.pinkSoft,
      ServiceCategory.homeServices => HuddlColors.accentAmber,
      ServiceCategory.photography => HuddlColors.purpleAccent,
      ServiceCategory.food => HuddlColors.primary,
      ServiceCategory.other => HuddlColors.gray400,
    };
