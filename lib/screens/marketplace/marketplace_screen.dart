import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/rehome_service.dart';
import 'item_detail_screen.dart';
import '../rehome/create_listing_screen.dart';
import '../ai/ai_listing_generator_sheet.dart';
import '../ai/ai_copilot_screen.dart';


// ═══════════════════════════════════════════════════════════════════════════════
// REHOME MARKETPLACE SCREEN — age-first, category-second browsing
// ═══════════════════════════════════════════════════════════════════════════════

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = RehomeService();

  // Filters
  AgeStage? _selectedAge;
  ItemCategory? _selectedCategory;
  PriceType? _selectedPriceType;
  ItemCondition? _selectedCondition;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _service.addListener(_onServiceChange);
  }

  void _onServiceChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _service.removeListener(_onServiceChange);
    _tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    // Always rebuild to update filter bar visibility across tabs
    setState(() {});
  }

  List<RehomeItem> get _filteredItems => _service.filter(
        ageStage: _selectedAge,
        category: _selectedCategory,
        condition: _selectedCondition,
        priceType: _selectedPriceType,
        query: _searchQuery,
      );

  bool get _hasActiveFilters =>
      _selectedAge != null ||
      _selectedCategory != null ||
      _selectedPriceType != null ||
      _selectedCondition != null;

  void _clearAllFilters() {
    setState(() {
      _selectedAge = null;
      _selectedCategory = null;
      _selectedPriceType = null;
      _selectedCondition = null;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _openCreateListing() async {
    final result = await Navigator.push<RehomeItem>(
      context,
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );
    if (result != null && mounted) {
      _tabController.animateTo(1); // Switch to Sell tab
    }
  }

  void _openItemDetail(RehomeItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailScreen(item: item)),
    );
  }

  void _openEditListing(RehomeItem item) async {
    final result = await Navigator.push<RehomeItem>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(existingItem: item),
      ),
    );
    if (result != null && mounted) {
      setState(() {}); // refresh to show updated listing
    }
  }

  void _confirmDelistItem(RehomeItem item) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline,
                    size: 28, color: HuddlColors.error),
              ),
              const SizedBox(height: 16),
              Text(
                'Delist this item?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to delist "${item.title}"? This will remove it from the marketplace.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: HuddlColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: HuddlColors.gray300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.textDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _service.deleteListing(item.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        '"${item.title}" has been delisted')),
                              ],
                            ),
                            backgroundColor: HuddlColors.teal,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.error,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: Text(
                        'Delist',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            // Only show filter bar on Buy tab (index 0)
            if (_tabController.index == 0) _buildFilterBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBuyTab(),
                  _buildSellTab(),
                  _buildSavedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: HuddlColors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with AI Copilot icon (top-right, same as Chat)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Preloved',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AiCopilotScreen(),
                  ),
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: HuddlColors.aiGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: HuddlColors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Tab bar — same style as Messages, Discover, Nearby, I'm Going
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Buy'),
              Tab(text: 'Sell'),
              Tab(text: 'Saved'),
            ],
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textHint,
            labelStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            indicatorColor: HuddlColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: HuddlColors.divider,
          ),
        ],
      ),
    );
  }

  // ── FILTER BAR ────────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      color: HuddlColors.white,
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            // Age filter (primary — always first)
            _FilterChip(
              label: _selectedAge?.shortLabel ?? 'For age',
              icon: Icons.child_care,
              isActive: _selectedAge != null,
              onTap: () => _showAgeSheet(),
            ),
            const SizedBox(width: 6),
            // Category filter
            _FilterChip(
              label: _selectedCategory?.label ?? 'Category',
              icon: Icons.category_outlined,
              isActive: _selectedCategory != null,
              onTap: () => _showCategorySheet(),
            ),
            const SizedBox(width: 6),
            // Price filter
            _FilterChip(
              label: _selectedPriceType == PriceType.free
                  ? 'Free'
                  : _selectedPriceType == PriceType.paid
                      ? 'Paid'
                      : 'Price',
              icon: Icons.sell_outlined,
              isActive: _selectedPriceType != null,
              onTap: () => _showPriceSheet(),
            ),
            const SizedBox(width: 6),
            // Condition filter
            _FilterChip(
              label: _selectedCondition?.label ?? 'Condition',
              icon: Icons.star_outline,
              isActive: _selectedCondition != null,
              onTap: () => _showConditionSheet(),
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Clear all',
                icon: Icons.clear_all,
                isActive: false,
                isDestructive: true,
                onTap: _clearAllFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── FILTER BOTTOM SHEETS ──────────────────────────────────────────────────

  void _showAgeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AgeFilterSheet(
        selected: _selectedAge,
        onSelect: (age) {
          setState(() => _selectedAge = age);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showCategorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategoryFilterSheet(
        selected: _selectedCategory,
        onSelect: (cat) {
          setState(() => _selectedCategory = cat);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showPriceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HuddlBottomSheetHandle(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Price',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _sheetOption('All prices', _selectedPriceType == null, () {
                setState(() => _selectedPriceType = null);
                Navigator.pop(context);
              }),
              _sheetOption(
                  'Free only', _selectedPriceType == PriceType.free, () {
                setState(() => _selectedPriceType = PriceType.free);
                Navigator.pop(context);
              }),
              _sheetOption('Paid only', _selectedPriceType == PriceType.paid,
                  () {
                setState(() => _selectedPriceType = PriceType.paid);
                Navigator.pop(context);
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showConditionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HuddlBottomSheetHandle(),
              Text(
                'Condition',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              _sheetOption('All conditions', _selectedCondition == null, () {
                setState(() => _selectedCondition = null);
                Navigator.pop(context);
              }),
              ...ItemCondition.values.map((c) => _sheetOption(
                    c.label,
                    _selectedCondition == c,
                    () {
                      setState(() => _selectedCondition = c);
                      Navigator.pop(context);
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetOption(String label, bool isSelected, VoidCallback onTap) {
    return ListTile(
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? HuddlColors.primary : HuddlColors.textDark,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: HuddlColors.primary, size: 22)
          : null,
      onTap: onTap,
    );
  }

  // ── BUY TAB ───────────────────────────────────────────────────────────────

  Widget _buildBuyTab() {
    final items = _filteredItems;

    return Column(
      children: [
        // ── Inline search bar (always visible on Buy tab, same style as Messages tab) ──
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: HuddlColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: HuddlColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search pre-loved items...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 14,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.close,
                          size: 18, color: HuddlColors.textHint),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
        // ── Grid or empty state ──
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(
                  icon: Icons.search_off,
                  title: 'No items found',
                  subtitle: _hasActiveFilters
                      ? 'Try adjusting your filters to see more results.'
                      : 'Nothing listed yet. Check back soon!',
                  action: _hasActiveFilters
                      ? TextButton.icon(
                          onPressed: _clearAllFilters,
                          icon: const Icon(Icons.filter_list_off, size: 18),
                          label: Text('Clear filters',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                        )
                      : null,
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ProductCard(
                    item: items[index],
                    onTap: () => _openItemDetail(items[index]),
                    onToggleSave: () => _service.toggleSaved(items[index].id),
                  ),
                ),
        ),
      ],
    );
  }

  // ── SELL TAB ──────────────────────────────────────────────────────────────

  Widget _buildSellTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        children: [
          // ── AI Listing Generator CTA ──────────────────────
          GestureDetector(
            onTap: () async {
              final result = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const AiListingGeneratorSheet(),
              );
              if (result == true && mounted) setState(() {});
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEDF4FF), Color(0xFFDBEAFF)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: HuddlColors.aiBlue.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: HuddlColors.aiGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Listing Generator',
                          style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            color: HuddlColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Take a photo → AI creates title, description & smart pricing in 15 seconds',
                          style: GoogleFonts.poppins(
                            fontSize: 11, color: HuddlColors.textSecondary, height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: HuddlColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'NEW',
                      style: GoogleFonts.poppins(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: HuddlColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Create listing CTA card — same size/style as Create New Group CTA
          GestureDetector(
            onTap: _openCreateListing,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: HuddlColors.peachLight,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Positioned(
                          left: 0, top: 4,
                          child: Container(
                            width: 10, height: 10,
                            decoration: const BoxDecoration(
                              color: HuddlColors.accentAmber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0, bottom: 6,
                          child: Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: HuddlColors.paleBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const Icon(Icons.sell_outlined,
                            size: 30, color: HuddlColors.primary),
                        Positioned(
                          right: 4, top: 4,
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: HuddlColors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: HuddlColors.white, width: 2),
                            ),
                            child: const Icon(Icons.add,
                                size: 11, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Got items to pass on?',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Give them a new home with families who\'ll love them!',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.textHint,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 38,
                          child: ElevatedButton(
                            onPressed: _openCreateListing,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HuddlColors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              'List an Item',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.white,
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
          ),
          const SizedBox(height: 24),
          // My listings
          if (_service.myListings.isNotEmpty) ...[
            HuddlSectionHeader(
              title: 'My listings',
              actionText: '${_service.myListings.length} items',
            ),
            const SizedBox(height: 12),
            ..._service.myListings.map((item) => _MyListingTile(
                  item: item,
                  onTap: () => _openItemDetail(item),
                  onEdit: () => _openEditListing(item),
                  onMarkSold: () {
                    _service.markSold(item.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${item.title} marked as sold'),
                        backgroundColor: HuddlColors.teal,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  onRelist: () {
                    _service.relistItem(item.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text('"${item.title}" is back on sale')),
                          ],
                        ),
                        backgroundColor: HuddlColors.teal,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                  onDelete: () => _confirmDelistItem(item),
                )),
          ],
          // Offers section
          if (_service.pendingOffers.isNotEmpty) ...[
            const SizedBox(height: 24),
            HuddlSectionHeader(
              title: 'Incoming offers',
              actionText: '${_service.pendingOffers.length} pending',
            ),
            const SizedBox(height: 12),
            ..._service.pendingOffers.map((offer) => _OfferTile(
                  offer: offer,
                  onAccept: () => _service.acceptOffer(offer.id),
                  onDecline: () => _service.declineOffer(offer.id),
                )),
          ],
        ],
      ),
    );
  }

  // ── SAVED TAB ─────────────────────────────────────────────────────────────

  Widget _buildSavedTab() {
    final saved = _service.savedItems;
    if (saved.isEmpty) {
      return _buildEmptyState(
        icon: Icons.favorite_outline,
        title: 'No saved items',
        subtitle: 'Tap the heart on items you love\nto save them here.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62,
      ),
      itemCount: saved.length,
      itemBuilder: (context, index) => _ProductCard(
        item: saved[index],
        onTap: () => _openItemDetail(saved[index]),
        onToggleSave: () => _service.toggleSaved(saved[index].id),
      ),
    );
  }

  // ── EMPTY STATE ───────────────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: HuddlColors.peachLight,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 40, color: HuddlColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: HuddlColors.textHint,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }

  // ── FAB — circular + button like Discover Groups ─────────────────────────

  Widget? _buildFAB() {
    // Only show FAB on Buy tab (index 0)
    if (_tabController.index != 0) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 60),
      child: Material(
        elevation: 6,
        shadowColor: HuddlColors.primary.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        color: HuddlColors.primary,
        child: InkWell(
          onTap: _openCreateListing,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.add, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILTER CHIP WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDestructive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isDestructive
        ? HuddlColors.error.withValues(alpha: 0.08)
        : isActive
            ? HuddlColors.primary.withValues(alpha: 0.1)
            : HuddlColors.background;
    final Color fgColor = isDestructive
        ? HuddlColors.error
        : isActive
            ? HuddlColors.primary
            : HuddlColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? HuddlColors.primary.withValues(alpha: 0.3)
                : HuddlColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fgColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: fgColor,
              ),
            ),
            if (isActive && !isDestructive) ...[
              const SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down, size: 16, color: fgColor),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCT CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _ProductCard extends StatelessWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onToggleSave;

  const _ProductCard({
    required this.item,
    required this.onTap,
    required this.onToggleSave,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  SizedBox.expand(
                    child: Image.network(
                      item.imageUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: HuddlColors.peachLight,
                        child: Center(
                          child: Icon(item.category.icon,
                              size: 44,
                              color: item.category.color.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  ),
                  // Save button
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onToggleSave,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: HuddlColors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          item.isSaved ? Icons.favorite : Icons.favorite_border,
                          size: 16,
                          color: item.isSaved
                              ? HuddlColors.error
                              : HuddlColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  // Free badge
                  if (item.isFree)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: HuddlColors.accentAmber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Free',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  // Condition badge
                  if (!item.isFree)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.condition.label,
                          style: GoogleFonts.poppins(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Details
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.textDark,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    // Price
                    Text(
                      item.priceDisplay,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: item.isFree
                            ? HuddlColors.blue
                            : HuddlColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Age + Location
                    Row(
                      children: [
                        Icon(Icons.child_care,
                            size: 12, color: HuddlColors.textHint),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '${item.ageStage.shortLabel} \u2022 ${item.sellerLocation}',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: HuddlColors.textHint,
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
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MY LISTING TILE (Sell tab)
// ═══════════════════════════════════════════════════════════════════════════════

class _MyListingTile extends StatelessWidget {
  final RehomeItem item;
  final VoidCallback onTap;
  final VoidCallback onMarkSold;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onRelist;

  const _MyListingTile({
    required this.item,
    required this.onTap,
    required this.onMarkSold,
    required this.onDelete,
    this.onEdit,
    this.onRelist,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 68,
                height: 68,
                child: Image.network(
                  item.imageUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: HuddlColors.peachLight,
                    child: Icon(item.category.icon,
                        color: HuddlColors.primary, size: 28),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.viewCount} views \u2022 ${item.offerCount} offers \u2022 ${item.timeAgo}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        item.priceDisplay,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color:
                              item.isFree ? HuddlColors.blue : HuddlColors.primary,
                        ),
                      ),
                      const Spacer(),
                      if (onEdit != null && !item.isSold)
                        _TinyButton(
                          text: 'Edit',
                          color: HuddlColors.primary,
                          onTap: onEdit!,
                        ),
                      if (onEdit != null && !item.isSold)
                        const SizedBox(width: 6),
                      if (item.isSold && onRelist != null) ...[
                        _TinyButton(
                          text: 'Relist',
                          color: HuddlColors.teal,
                          onTap: onRelist!,
                        ),
                      ] else if (!item.isSold) ...[
                        _TinyButton(
                          text: 'Mark sold',
                          color: HuddlColors.blue,
                          onTap: onMarkSold,
                        ),
                      ],
                      const SizedBox(width: 6),
                      _TinyButton(
                        text: 'Delete',
                        color: HuddlColors.error,
                        onTap: onDelete,
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

class _TinyButton extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _TinyButton({
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// OFFER TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _OfferTile extends StatelessWidget {
  final RehomeOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _OfferTile({
    required this.offer,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HuddlColors.white,
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
        children: [
          MemberAvatar(name: offer.buyerName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      color: HuddlColors.textDark,
                    ),
                    children: [
                      TextSpan(
                        text: offer.buyerName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' offered '),
                      TextSpan(
                        text: offer.amountDisplay,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'for ${offer.itemTitle}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textHint,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            children: [
              _TinyButton(text: 'Accept', color: HuddlColors.teal, onTap: onAccept),
              const SizedBox(height: 4),
              _TinyButton(text: 'Decline', color: HuddlColors.error, onTap: onDecline),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AGE FILTER SHEET — "Who is this for?"
// ═══════════════════════════════════════════════════════════════════════════════

class _AgeFilterSheet extends StatelessWidget {
  final AgeStage? selected;
  final ValueChanged<AgeStage?> onSelect;

  const _AgeFilterSheet({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.child_care,
                    color: HuddlColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Who is this for?',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Choose an age group to see items suited for that stage.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: HuddlColors.textHint),
            ),
          ),
          const SizedBox(height: 12),
          // "All ages" clear option
          _sheetOptionTile(
            label: 'All ages',
            emoji: '\u{2B50}',
            isSelected: selected == null,
            onTap: () => onSelect(null),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: AgeStage.values.map((age) {
                  return _sheetOptionTile(
                    label: age.label,
                    emoji: age.emoji,
                    isSelected: selected == age,
                    onTap: () => onSelect(age),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sheetOptionTile({
    required String label,
    required String emoji,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 22)),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? HuddlColors.primary : HuddlColors.textDark,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle,
              color: HuddlColors.primary, size: 22)
          : null,
      onTap: onTap,
      dense: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CATEGORY FILTER SHEET — "What are you looking for?"
// ═══════════════════════════════════════════════════════════════════════════════

class _CategoryFilterSheet extends StatelessWidget {
  final ItemCategory? selected;
  final ValueChanged<ItemCategory?> onSelect;

  const _CategoryFilterSheet({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlBottomSheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.category_outlined,
                    color: HuddlColors.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'What are you looking for?',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // "All categories" clear option
          ListTile(
            leading: const Icon(Icons.apps, color: HuddlColors.textHint),
            title: Text(
              'All categories',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: selected == null ? FontWeight.w600 : FontWeight.w400,
                color: selected == null ? HuddlColors.primary : HuddlColors.textDark,
              ),
            ),
            trailing: selected == null
                ? const Icon(Icons.check_circle,
                    color: HuddlColors.primary, size: 22)
                : null,
            onTap: () => onSelect(null),
            dense: true,
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: ItemCategory.values.map((cat) {
                  final isSelected = selected == cat;
                  return ListTile(
                    leading: Icon(cat.icon, color: cat.color, size: 22),
                    title: Text(
                      cat.label,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? HuddlColors.primary
                            : HuddlColors.textDark,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: HuddlColors.primary, size: 22)
                        : null,
                    onTap: () => onSelect(cat),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
