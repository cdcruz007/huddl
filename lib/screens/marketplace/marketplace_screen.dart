import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../services/rehome_service.dart';
import 'item_detail_screen.dart';
import '../rehome/create_listing_screen.dart';

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
  bool _showSearch = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilterBar(),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Expanded(
                child: _showSearch
                    ? _buildSearchField()
                    : Text(
                        'Rehome',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.textDark,
                        ),
                      ),
              ),
              IconButton(
                icon: Icon(
                  _showSearch ? Icons.close : Icons.search,
                  color: HuddlColors.textDark,
                ),
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                      _searchQuery = '';
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline,
                    color: HuddlColors.textDark),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Tab bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _buildTabLabel('Buy', _filteredItems.length),
              _buildTabLabel('Sell', _service.myListings.length),
              _buildTabLabel('Saved', _service.savedItems.length),
            ],
            labelColor: HuddlColors.primary,
            unselectedLabelColor: HuddlColors.textHint,
            labelStyle: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            indicatorColor: HuddlColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: HuddlColors.divider,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
        decoration: InputDecoration(
          hintText: 'Search pre-loved items...',
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
          filled: true,
          fillColor: HuddlColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          prefixIcon: const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildTabLabel(String text, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: HuddlColors.primary,
                ),
              ),
            ),
          ],
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

    if (items.isEmpty) {
      return _buildEmptyState(
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
      itemCount: items.length,
      itemBuilder: (context, index) => _ProductCard(
        item: items[index],
        onTap: () => _openItemDetail(items[index]),
        onToggleSave: () => _service.toggleSaved(items[index].id),
      ),
    );
  }

  // ── SELL TAB ──────────────────────────────────────────────────────────────

  Widget _buildSellTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        children: [
          // Create listing prompt
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF3ED), Color(0xFFFFF8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: HuddlColors.primary.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.camera_alt_outlined,
                      size: 32, color: HuddlColors.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  'List an item',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Give your pre-loved items a new home\nwith families who\u2019ll love them.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                HuddlPrimaryButton(
                  text: 'Start listing',
                  onPressed: _openCreateListing,
                ),
              ],
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
                  onDelete: () {
                    _service.deleteListing(item.id);
                  },
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

  // ── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFAB() {
    return Container(
      margin: const EdgeInsets.only(bottom: 60),
      decoration: BoxDecoration(
        gradient: HuddlColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: HuddlColors.primary.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: _openCreateListing,
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add, color: HuddlColors.white),
        label: Text(
          'Sell item',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: HuddlColors.white,
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
                          color: HuddlColors.teal,
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
                            ? HuddlColors.teal
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

  const _MyListingTile({
    required this.item,
    required this.onTap,
    required this.onMarkSold,
    required this.onDelete,
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
                              item.isFree ? HuddlColors.teal : HuddlColors.primary,
                        ),
                      ),
                      const Spacer(),
                      _TinyButton(
                        text: item.isSold ? 'Sold' : 'Mark sold',
                        color: item.isSold ? HuddlColors.textHint : HuddlColors.teal,
                        onTap: item.isSold ? () {} : onMarkSold,
                      ),
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
