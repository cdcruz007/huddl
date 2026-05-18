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
// Three tabs:
//   1. Directory   — Borough-scoped listing list. Category chips. Search.
//                    Each card matches Groups/Meetups/Events card pattern:
//                    hero gradient block + badges, name/tagline body,
//                    endorser avatar stack + count + grey "Enquire" pill.
//   2. Add / AI    — Two paths: AI extraction + manual form.
//   3. My Listings — Listings the current user has added.
//
// Design language: matches Groups / Meetups / Events tabs exactly.
//   • AnimatedCrossFade filter pill ↔ inline search
//   • "Suggested for you" / "Search results" section label
//   • Card: gradient hero block, overlapping badge pills, bottom avatar row
//   • Grey "Enquire" pill — same spec as grey "Join" pill in other tabs
// =============================================================================

// ── Endorser avatar URLs (mirrors _kMemberAvatars / _kAttendeeAvatars) ───────
const List<String> _kEndorserAvatars = [
  'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1502767089025-6572583495b9?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1519345182560-3f2917c472ef?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1521119989659-a83eee488004?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop&crop=face',
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=100&h=100&fit=crop&crop=face',
];

// ─────────────────────────────────────────────────────────────────────────────

class ServicesScreen extends StatefulWidget {
  final ValueNotifier<bool> searchTrigger;
  const ServicesScreen({super.key, required this.searchTrigger});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _service = LocalServicesService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sub-tab bar (Directory / Add·AI / My Listings) ─────────────────
        Container(
          color: hc.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: HuddlColors.primary,
            unselectedLabelColor: hc.textTertiary,
            indicatorColor: HuddlColors.primary,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: hc.divider,
            labelStyle: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w400),
            tabs: const [
              Tab(text: 'Directory'),
              Tab(text: 'Add / AI'),
              Tab(text: 'My Listings'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DirectoryTab(
                service: _service,
                searchTrigger: widget.searchTrigger,
              ),
              _AddServiceTab(
                service: _service,
                onListingAdded: () => _tabController.animateTo(0),
              ),
              _MyListingsTab(service: _service),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── TAB 1: Directory ─────────────────────────────────────────────────────────

class _DirectoryTab extends StatefulWidget {
  final LocalServicesService service;
  final ValueNotifier<bool> searchTrigger;
  const _DirectoryTab({required this.service, required this.searchTrigger});

  @override
  State<_DirectoryTab> createState() => _DirectoryTabState();
}

class _DirectoryTabState extends State<_DirectoryTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  ServiceCategory? _selectedCategory;
  bool _isSearchActive = false;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searchTrigger.addListener(_onSearchTrigger);
    _triggerAiRefreshIfDue();
  }

  void _onSearchTrigger() {
    if (widget.searchTrigger.value) {
      widget.searchTrigger.value = false;
      setState(() => _isSearchActive = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocus.requestFocus();
      });
    }
  }

  void _clearSearch() {
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
      _searchCtrl.clear();
    });
    _searchFocus.unfocus();
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

  List<ServiceListing> _filter(List<ServiceListing> all) {
    var result = all;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hc = context.hc;
    const Color filterText = Color(0xFF42464C);
    final bool hasActiveFilter = _selectedCategory != null;

    return Column(
      children: [
        // ══ TOP HEADER — filter pill ↔ inline search (Events/Meetups pattern) ══
        Container(
          color: hc.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AnimatedCrossFade: filter pill ↔ inline search bar
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _isSearchActive
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showCategorySheet(context),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: hasActiveFilter
                                  ? HuddlColors.primary
                                  : filterText,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasActiveFilter
                                  ? '${_selectedCategory!.emoji} ${_selectedCategory!.displayName} •'
                                  : 'Filter by category',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
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
                    const Spacer(),
                    if (hasActiveFilter)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _selectedCategory = null);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          child: Text(
                            'Clear',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // ── Inline search bar ───────────────────────────────────────
                secondChild: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: HuddlColors.background,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: HuddlColors.primary.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            const Icon(Icons.search,
                                size: 18, color: HuddlColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                focusNode: _searchFocus,
                                onChanged: (v) =>
                                    setState(() => _searchQuery = v.trim()),
                                style: GoogleFonts.poppins(
                                    fontSize: 14, color: filterText),
                                decoration: InputDecoration(
                                  hintText: 'Search cleaners, tutors…',
                                  hintStyle: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: HuddlColors.textTertiary,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () => setState(() {
                                  _searchQuery = '';
                                  _searchCtrl.clear();
                                }),
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 10),
                                  child: Icon(Icons.close,
                                      size: 16,
                                      color: HuddlColors.textTertiary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _clearSearch,
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              // Section label — mirrors Events/Meetups pattern
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

        // ── Listing stream ──────────────────────────────────────────────────
        Expanded(
          child: ColoredBox(
            color: HuddlColors.background,
            child: StreamBuilder<List<ServiceListing>>(
              stream: widget.service.listingsStream(category: _selectedCategory),
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

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, i) => _ListingCard(
                    listing: filtered[i],
                    service: widget.service,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // Category filter bottom sheet — replaces the horizontal chip row
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
            // "All" option
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

// ─── Category sheet tile ────────────────────────────────────────────────────

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
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
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

// ─── Listing card — matches Groups/Meetups/Events card pattern ───────────────

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
      if (quote == null) {
        if (mounted) setState(() => _endorsing = false);
        return;
      }
      await widget.service.endorseListing(
          widget.listing.id, quote: quote.isEmpty ? null : quote);
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Endorse ${widget.listing.name}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add a personal note (optional)',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: context.hc.textSecondary),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  maxLength: 120,
                  style: GoogleFonts.poppins(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '"Reliable, insured, brilliant with our kids"',
                    hintStyle: GoogleFonts.poppins(
                        fontSize: 12, color: context.hc.textTertiary),
                    filled: true,
                    fillColor: context.hc.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(
                        color: context.hc.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text('Endorse',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final listing = widget.listing;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catColor = _categoryColor(listing.category);

    return GestureDetector(
      onTap: () {
        widget.service.recordView(listing.id);
        _showListingDetail(context, listing, widget.service);
      },
      child: Container(
        decoration: BoxDecoration(
          color: hc.surface,
          borderRadius: BorderRadius.circular(16),
          border: hc.cardBorder,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero block with gradient + badges ─────────────────────────
            Stack(
              children: [
                // Gradient hero (same height as Events card)
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        catColor.withValues(alpha: 0.85),
                        catColor.withValues(alpha: 0.55),
                        catColor.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      listing.category.emoji,
                      style: const TextStyle(fontSize: 52),
                    ),
                  ),
                ),
                // Gradient scrim at bottom (for badge readability)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.25),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top-left badges: category type + "New" if few endorsements
                Positioned(
                  top: 10,
                  left: 10,
                  child: Row(
                    children: [
                      // Category type pill (blueDark)
                      _HeroBadge(
                        label: listing.category.displayName,
                        color: HuddlColors.blueDark,
                      ),
                      if (_count < 3) ...[
                        const SizedBox(width: 6),
                        _HeroBadge(
                          label: 'New',
                          color: HuddlColors.accentAmber,
                        ),
                      ],
                    ],
                  ),
                ),
                // Top-right: verified / community pick badge
                Positioned(
                  top: 10,
                  right: 10,
                  child: _HeroVerifiedBadge(listing: listing),
                ),
              ],
            ),

            // ── Card body ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    listing.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: hc.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Tagline
                  Text(
                    listing.tagline,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: hc.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // ── Bottom row: avatar stack + count (left) | Endorse pill (right) ──
                  Row(
                    children: [
                      // Overlapping endorser avatar stack — driven by live _count
                      if (_count > 0)
                        SizedBox(
                          width: _count >= 3
                              ? 24.0 + 18.0 + 18.0
                              : _count == 2
                                  ? 24.0 + 18.0
                                  : 24.0,
                          height: 24,
                          child: Stack(
                            children: List.generate(
                              _count.clamp(0, 3),
                              (i) {
                                final seed = listing.id.hashCode + i;
                                final url = _kEndorserAvatars[
                                    seed.abs() % _kEndorserAvatars.length];
                                return Positioned(
                                  left: i * 18.0,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 1.5),
                                    ),
                                    child: ClipOval(
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            CircleAvatar(
                                          backgroundColor: catColor
                                              .withValues(alpha: 0.25),
                                          radius: 12,
                                          child: Text(
                                            listing.name.isNotEmpty
                                                ? listing.name[0]
                                                : '?',
                                            style: const TextStyle(
                                                fontSize: 10),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      if (_count > 0) const SizedBox(width: 8),
                      // Parent endorsement count — the trust signal
                      Text(
                        _count > 0
                            ? '$_count parent${_count == 1 ? '' : 's'} endorsed'
                            : 'Be the first to endorse',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: _count > 0
                              ? hc.textSecondary
                              : hc.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      // Endorse pill — orange + filled when endorsed, grey when not
                      GestureDetector(
                        onTap: _endorsing ? null : _toggleEndorse,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
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
                                    color: _hasEndorsed
                                        ? Colors.white
                                        : HuddlColors.primary,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _hasEndorsed
                                          ? Icons.thumb_up_rounded
                                          : Icons.thumb_up_outlined,
                                      size: 14,
                                      color: _hasEndorsed
                                          ? Colors.white
                                          : hc.textSecondary,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _hasEndorsed ? 'Endorsed' : 'Endorse',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _hasEndorsed
                                            ? Colors.white
                                            : hc.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
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
}

// ─── Hero badge (top-left overlay pill) ───────────────────────────────────────

class _HeroBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _HeroBadge({required this.label, required this.color});

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

// ─── Hero verified badge (top-right overlay) ──────────────────────────────────

class _HeroVerifiedBadge extends StatelessWidget {
  final ServiceListing listing;
  const _HeroVerifiedBadge({required this.listing});

  @override
  Widget build(BuildContext context) {
    if (listing.isVerified ||
        listing.verificationTier == VerificationTier.verified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: HuddlColors.teal,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded,
                size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'Verified',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    if (listing.verificationTier == VerificationTier.community ||
        listing.endorsementCount >= 3) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_rounded,
                size: 11, color: HuddlColors.teal),
            const SizedBox(width: 4),
            Text(
              'Community Pick',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: HuddlColors.teal,
              ),
            ),
          ],
        ),
      );
    }
    // No badge — return invisible placeholder to keep layout stable
    return const SizedBox.shrink();
  }
}

// ─── Inline tag chip (compact version for card body) ─────────────────────────

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

// ─── Listing detail bottom sheet ───────────────────────────────────────────

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
            // ── Hero + name ────────────────────────────────────────────────
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
                    child: Text(listing.category.emoji,
                        style: const TextStyle(fontSize: 26)),
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
                      Text(
                        listing.category.displayName,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: hc.textSecondary),
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
            // ── Tagline ────────────────────────────────────────────────────
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
            // ── Description ────────────────────────────────────────────────
            if (listing.description.isNotEmpty) ...[
              Text(
                listing.description,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: hc.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            // ── Tags ───────────────────────────────────────────────────────
            if (listing.tags.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: listing.tags
                    .map((t) => _InlineTagChip(tag: t))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            // ── Stats row ──────────────────────────────────────────────────
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
            // ── Contact CTAs ───────────────────────────────────────────────
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
            // ── Enquire via Huddl DM ───────────────────────────────────────
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
            // ── Endorsements section ───────────────────────────────────────
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
                    child: CircularProgressIndicator(
                        color: HuddlColors.teal)),
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

// ─── Endorsement tile ──────────────────────────────────────────────────────

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
          if (endorsement.quote != null &&
              endorsement.quote!.isNotEmpty) ...[
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

// ─── Stat pill ─────────────────────────────────────────────────────────────

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

// ─── Contact row ───────────────────────────────────────────────────────────

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

// ─── Empty state ───────────────────────────────────────────────────────────

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

// ─── TAB 2: Add / AI ──────────────────────────────────────────────────────────

class _AddServiceTab extends StatefulWidget {
  final LocalServicesService service;
  final VoidCallback onListingAdded;
  const _AddServiceTab(
      {required this.service, required this.onListingAdded});

  @override
  State<_AddServiceTab> createState() => _AddServiceTabState();
}

class _AddServiceTabState extends State<_AddServiceTab> {
  final TextEditingController _chatPasteCtrl = TextEditingController();
  bool _extracting = false;
  List<ExtractedServiceRecommendation> _extracted = [];
  String? _extractError;
  bool _showManual = false;

  @override
  void dispose() {
    _chatPasteCtrl.dispose();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── AI extraction card ───────────────────────────────────────────
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: HuddlColors.aiGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Extraction',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: hc.textPrimary,
                            ),
                          ),
                          Text(
                            'Paste a WhatsApp message — AI finds the recommendation',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: hc.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _chatPasteCtrl,
                  maxLines: 5,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: hc.textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        '"Has anyone used Sandra at Clean2Perfection? She\'s insured, reliable, brilliant with our kids — 07700 900123"',
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
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
                        onSubmit: (listingId) {
                          if (listingId != null) {
                            widget.onListingAdded();
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
          // ── Manual add toggle ────────────────────────────────────────────
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
                  widget.onListingAdded();
                  setState(() => _showManual = false);
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
    );
  }
}

// ─── Extracted recommendation card ────────────────────────────────────────

class _ExtractedRecommendationCard extends StatefulWidget {
  final ExtractedServiceRecommendation rec;
  final LocalServicesService service;
  final void Function(String? listingId) onSubmit;

  const _ExtractedRecommendationCard({
    required this.rec,
    required this.service,
    required this.onSubmit,
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
              Text(rec.category.emoji,
                  style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _confidenceColor(rec.confidence)
                      .withValues(alpha: 0.12),
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

// ─── Manual add form ───────────────────────────────────────────────────────

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
      website: _websiteCtrl.text.trim().isEmpty
          ? null
          : _websiteCtrl.text.trim(),
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

// ─── TAB 3: My Listings ───────────────────────────────────────────────────────

class _MyListingsTab extends StatelessWidget {
  final LocalServicesService service;
  const _MyListingsTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ServiceListing>>(
      stream: service.myListingsStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: HuddlColors.primary));
        }
        final listings = snap.data ?? [];
        if (listings.isEmpty) {
          return const HuddlEmptyState(
            illustration: HuddlIllustration.marketplace,
            title: 'No listings yet',
            subtitle: 'Listings you add to the directory will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: listings.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) =>
              _MyListingCard(listing: listings[i], service: service),
        );
      },
    );
  }
}

class _MyListingCard extends StatelessWidget {
  final ServiceListing listing;
  final LocalServicesService service;
  const _MyListingCard({required this.listing, required this.service});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: hc.cardBorder,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _categoryColor(listing.category).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(listing.category.emoji,
                style: const TextStyle(fontSize: 20)),
          ),
        ),
        title: Text(
          listing.name,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: hc.textPrimary,
          ),
        ),
        subtitle: Text(
          '${listing.endorsementCount} endorsements · ${listing.category.displayName}',
          style: GoogleFonts.poppins(fontSize: 12, color: hc.textSecondary),
        ),
        trailing: listing.isVerified ||
                listing.verificationTier == VerificationTier.community
            ? _VerifiedBadge(tier: listing.verificationTier)
            : null,
        onTap: () => _showListingDetail(context, listing, service),
      ),
    );
  }
}

// ─── Section card ──────────────────────────────────────────────────────────

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

// ─── Category colour helper ────────────────────────────────────────────────

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
