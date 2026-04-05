import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../services/revglue_service.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';

class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key});

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> with SingleTickerProviderStateMixin {
  final _service = RevGlueService();
  final _subService = SubscriptionService();

  List<RevGlueStore> _stores = [];
  List<RevGlueCategory> _categories = [];
  List<RevGlueBanner> _banners = [];
  bool _isLoading = true;
  String? _error;

  // Store detail view
  RevGlueStore? _selectedStore;
  List<RevGlueCoupon> _storeCoupons = [];
  bool _loadingCoupons = false;

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Tab
  late TabController _tabController;

  // Subscription gating
  int _dealsViewedToday = 0;
  static const int _freeViewLimit = 10;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _subService.initialize();
      final results = await Future.wait([
        _service.getTopStores(),
        _service.getCategories(),
        _service.getHomeBanners(),
      ]);
      if (!mounted) return;
      setState(() {
        _stores = results[0] as List<RevGlueStore>;
        _categories = results[1] as List<RevGlueCategory>;
        _banners = results[2] as List<RevGlueBanner>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load deals. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  bool get _isExplorer =>
      _subService.subscription.tier == SubscriptionTier.explorer;

  bool get _canViewMoreDeals => !_isExplorer || _dealsViewedToday < _freeViewLimit;

  Future<void> _openStore(RevGlueStore store) async {
    if (!_canViewMoreDeals) {
      _showUpgradeDialog();
      return;
    }
    setState(() {
      _selectedStore = store;
      _loadingCoupons = true;
      _dealsViewedToday++;
    });
    final coupons = await _service.getStoreVouchers(store.id);
    if (!mounted) return;
    setState(() {
      _storeCoupons = coupons;
      _loadingCoupons = false;
    });
  }

  Future<void> _openDealLink(String storeId) async {
    final url = RevGlueService.couponExitUrl(storeId);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock, color: HuddlColors.primary, size: 24),
            const SizedBox(width: 8),
            Text('Unlock More Deals', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        content: Text(
          'You\'ve reached your daily deal limit on the Explorer plan. '
          'Upgrade to Neighbourhood for unlimited deals, cashback access, '
          'and exclusive offers!',
          style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Maybe Later', style: GoogleFonts.poppins(color: HuddlColors.textHint)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/subscription_plans', arguments: {
                'highlightTier': 'neighbourhood',
                'gateMessage': 'Upgrade to access unlimited deals and cashback offers!',
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Upgrade Now', style: GoogleFonts.poppins(color: HuddlColors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showCouponCode(RevGlueCoupon coupon) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            if (coupon.storeIcon.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(coupon.storeIcon, height: 50, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            const SizedBox(height: 16),
            Text(coupon.storeTitle, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(coupon.title, style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (coupon.hasCode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: HuddlColors.peachLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.3), width: 1.5, style: BorderStyle.solid),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      coupon.voucherCode,
                      style: GoogleFonts.sourceCodePro(fontSize: 20, fontWeight: FontWeight.w700, color: HuddlColors.primaryDark, letterSpacing: 2),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: coupon.voucherCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Code copied!', style: GoogleFonts.poppins()),
                            backgroundColor: HuddlColors.success,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy_rounded, color: HuddlColors.primary, size: 22),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openDealLink(coupon.storeId);
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(coupon.hasCode ? 'Use Code & Shop' : 'Get Offer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  foregroundColor: HuddlColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (coupon.expiryDate.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Expires: ${coupon.expiryDate}', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<RevGlueStore> get _filteredStores {
    if (_searchQuery.isEmpty) return _stores;
    final q = _searchQuery.toLowerCase();
    return _stores.where((s) => s.title.toLowerCase().contains(q)).toList();
  }

  List<RevGlueCategory> get _familyCategories {
    // Prioritise family-relevant categories at top
    const priorityIds = ['3', '11', '15', '9', '1', '12', '4', '14']; // Baby, Home, Travel, Food, Fashion, Sport, Electronics, Gifts
    final sorted = List<RevGlueCategory>.from(_categories);
    sorted.sort((a, b) {
      final aPri = priorityIds.indexOf(a.id);
      final bPri = priorityIds.indexOf(b.id);
      if (aPri >= 0 && bPri >= 0) return aPri.compareTo(bPri);
      if (aPri >= 0) return -1;
      if (bPri >= 0) return 1;
      return a.title.compareTo(b.title);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: _selectedStore != null ? _buildStoreDetail() : _buildMainView(),
    );
  }

  // ── MAIN VIEW ────────────────────────────────────────────────────
  Widget _buildMainView() {
    return SafeArea(
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildSearchBar()),
          if (!_isLoading && _error == null)
            SliverToBoxAdapter(child: _buildBannerCarousel()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: HuddlColors.primary,
                unselectedLabelColor: HuddlColors.textHint,
                labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400),
                indicatorColor: HuddlColors.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Popular Stores'),
                  Tab(text: 'Categories'),
                  Tab(text: 'For Families'),
                ],
              ),
            ),
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
            : _error != null
                ? _buildError()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildStoresGrid(),
                      _buildCategoriesList(),
                      _buildFamilyPicks(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFFF975C)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_offer_rounded, color: HuddlColors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deals', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: HuddlColors.textPrimary)),
                Text(
                  'Save money on top UK brands',
                  style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_isExplorer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: HuddlColors.yellowBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 14, color: HuddlColors.yellowDark),
                  const SizedBox(width: 4),
                  Text(
                    '${_freeViewLimit - _dealsViewedToday} left',
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: HuddlColors.yellowDark),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search stores, brands...',
            hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
            prefixIcon: const Icon(Icons.search, color: HuddlColors.textHint, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                    child: const Icon(Icons.close, color: HuddlColors.textHint, size: 18),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerCarousel() {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        itemCount: _banners.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final banner = _banners[i];
          return GestureDetector(
            onTap: () {
              // Find the store in our list
              final store = _stores.where((s) => s.id == banner.storeId).toList();
              if (store.isNotEmpty) {
                _openStore(store.first);
              } else {
                _openDealLink(banner.storeId);
              }
            },
            child: Container(
              width: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: NetworkImage(banner.src),
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                ),
                boxShadow: [
                  BoxShadow(
                    color: HuddlColors.gray900.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(16),
                alignment: Alignment.centerLeft,
                child: Text(
                  banner.title,
                  style: GoogleFonts.poppins(color: HuddlColors.white, fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── STORES GRID ──────────────────────────────────────────────────
  Widget _buildStoresGrid() {
    final stores = _filteredStores;
    if (stores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 56, color: HuddlColors.gray300),
            const SizedBox(height: 12),
            Text('No stores found', style: GoogleFonts.poppins(color: HuddlColors.textHint, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      color: HuddlColors.primary,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        itemCount: stores.length,
        itemBuilder: (_, i) => _StoreCard(
          store: stores[i],
          onTap: () => _openStore(stores[i]),
        ),
      ),
    );
  }

  // ── CATEGORIES LIST ──────────────────────────────────────────────
  Widget _buildCategoriesList() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: HuddlColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _familyCategories.length,
        itemBuilder: (_, i) {
          final cat = _familyCategories[i];
          return _CategoryTile(
            category: cat,
            onTap: () {
              if (!_canViewMoreDeals && _isExplorer) {
                _showUpgradeDialog();
                return;
              }
              _showCategoryStores(cat);
            },
          );
        },
      ),
    );
  }

  void _showCategoryStores(RevGlueCategory cat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                children: [
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: HuddlColors.gray300, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.category_rounded, color: HuddlColors.primary),
                      const SizedBox(width: 8),
                      Text(cat.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (cat.offerCouponStr.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 32, top: 4),
                        child: Text(cat.offerCouponStr, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.success)),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: cat.subCategories.isNotEmpty
                  ? ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: cat.subCategories.length,
                      itemBuilder: (_, i) {
                        final sub = cat.subCategories[i];
                        return ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: HuddlColors.peachLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.local_offer, color: HuddlColors.primary, size: 18),
                          ),
                          title: Text(sub.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: sub.offerCouponStr.isNotEmpty
                              ? Text(sub.offerCouponStr, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.success))
                              : null,
                          trailing: const Icon(Icons.chevron_right, color: HuddlColors.textHint),
                        );
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Browse ${cat.title} deals by visiting our partner stores above!',
                          style: GoogleFonts.poppins(color: HuddlColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FAMILY PICKS ─────────────────────────────────────────────────
  Widget _buildFamilyPicks() {
    // Curated family-friendly stores
    const familyKeywords = ['baby', 'child', 'kids', 'toys', 'family', 'school', 'my 1st', 'vertbaudet', 'scholastic', 'hamleys', 'baker ross', 'start rite', 'picniq', 'mountain warehouse'];
    final familyStores = _stores.where((s) {
      final t = s.title.toLowerCase();
      return familyKeywords.any((kw) => t.contains(kw));
    }).toList();

    // Also show family categories
    final familyCats = _categories.where((c) {
      final t = c.title.toLowerCase();
      return t.contains('baby') || t.contains('child') || t.contains('toy') || t.contains('education') || t.contains('sport');
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      color: HuddlColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          // Family highlight banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF3ED), Color(0xFFFFF8F0)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: HuddlColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.family_restroom, color: HuddlColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Family Favourites', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.textPrimary)),
                      Text(
                        'Handpicked deals for parents & kids',
                        style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Family stores
          if (familyStores.isNotEmpty) ...[
            Text('Family Stores', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textPrimary)),
            const SizedBox(height: 10),
            ...familyStores.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StoreListTile(store: s, onTap: () => _openStore(s)),
            )),
            const SizedBox(height: 20),
          ],

          // Family categories
          if (familyCats.isNotEmpty) ...[
            Text('Family Categories', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: HuddlColors.textPrimary)),
            const SizedBox(height: 10),
            ...familyCats.map((c) => _CategoryTile(
              category: c,
              onTap: () => _showCategoryStores(c),
            )),
          ],

          if (familyStores.isEmpty && familyCats.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.child_care, size: 56, color: HuddlColors.gray300),
                    const SizedBox(height: 12),
                    Text('Family deals coming soon!', style: GoogleFonts.poppins(color: HuddlColors.textHint)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── STORE DETAIL ─────────────────────────────────────────────────
  Widget _buildStoreDetail() {
    final store = _selectedStore!;
    return SafeArea(
      child: Column(
        children: [
          // App bar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                  onPressed: () => setState(() {
                    _selectedStore = null;
                    _storeCoupons = [];
                  }),
                ),
                if (store.storeIcon.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(store.storeIcon, height: 32, width: 60, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      Text(store.offerCouponStr, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.success)),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _openDealLink(store.id),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text('Shop', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    foregroundColor: HuddlColors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          // Coupons list
          Expanded(
            child: _loadingCoupons
                ? const Center(child: CircularProgressIndicator(color: HuddlColors.primary))
                : _storeCoupons.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.local_offer_outlined, size: 48, color: HuddlColors.gray300),
                            const SizedBox(height: 12),
                            Text('No coupons available right now', style: GoogleFonts.poppins(color: HuddlColors.textHint)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _openDealLink(store.id),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: Text('Visit ${store.title}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: HuddlColors.primary,
                                foregroundColor: HuddlColors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _storeCoupons.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _CouponCard(
                          coupon: _storeCoupons[i],
                          onTap: () => _showCouponCode(_storeCoupons[i]),
                          onShop: () => _openDealLink(_storeCoupons[i].storeId),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: HuddlColors.gray300),
            const SizedBox(height: 16),
            Text(_error!, style: GoogleFonts.poppins(color: HuddlColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                foregroundColor: HuddlColors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Retry', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  Sub-widgets
// ══════════════════════════════════════════════════════════════════

class _StoreCard extends StatelessWidget {
  final RevGlueStore store;
  final VoidCallback onTap;
  const _StoreCard({required this.store, required this.onTap});

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
              color: HuddlColors.gray900.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 60, height: 36,
              padding: const EdgeInsets.all(4),
              child: store.storeIcon.isNotEmpty
                  ? Image.network(store.storeIcon, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.store, color: HuddlColors.gray400))
                  : const Icon(Icons.store, color: HuddlColors.gray400),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                store.title,
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: HuddlColors.textPrimary),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: HuddlColors.successBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                store.offerCouponStr,
                style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w600, color: HuddlColors.success),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _StoreListTile extends StatelessWidget {
  final RevGlueStore store;
  final VoidCallback onTap;
  const _StoreListTile({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: store.storeIcon.isNotEmpty
                  ? Image.network(store.storeIcon, width: 48, height: 28, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.store))
                  : const Icon(Icons.store, color: HuddlColors.gray400),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                  Text(store.offerCouponStr, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.success)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: HuddlColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final RevGlueCategory category;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _categoryColor(category.title).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_categoryIcon(category.title), color: _categoryColor(category.title), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textPrimary)),
                  if (category.offerCouponStr.isNotEmpty)
                    Text(category.offerCouponStr, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.success)),
                  if (category.subCategories.isNotEmpty)
                    Text('${category.subCategories.length} subcategories', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: HuddlColors.textHint),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(String title) {
    final t = title.toLowerCase();
    if (t.contains('baby') || t.contains('child')) return const Color(0xFFFF6B9D);
    if (t.contains('travel') || t.contains('holiday')) return const Color(0xFF3580F0);
    if (t.contains('food') || t.contains('grocery')) return const Color(0xFF22C55E);
    if (t.contains('fashion') || t.contains('cloth')) return const Color(0xFF9D4EDD);
    if (t.contains('home') || t.contains('garden')) return const Color(0xFFF59E0B);
    if (t.contains('health') || t.contains('beauty')) return const Color(0xFFFF6B6B);
    if (t.contains('sport') || t.contains('fitness')) return const Color(0xFF10B981);
    if (t.contains('tech') || t.contains('electronic')) return const Color(0xFF6366F1);
    return HuddlColors.primary;
  }

  IconData _categoryIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('baby') || t.contains('child')) return Icons.child_care;
    if (t.contains('travel') || t.contains('holiday')) return Icons.flight;
    if (t.contains('food') || t.contains('grocery')) return Icons.restaurant;
    if (t.contains('fashion') || t.contains('cloth')) return Icons.checkroom;
    if (t.contains('home') || t.contains('garden')) return Icons.home;
    if (t.contains('health') || t.contains('beauty')) return Icons.spa;
    if (t.contains('sport') || t.contains('fitness')) return Icons.fitness_center;
    if (t.contains('tech') || t.contains('electronic')) return Icons.devices;
    if (t.contains('pet')) return Icons.pets;
    if (t.contains('gift')) return Icons.card_giftcard;
    if (t.contains('book') || t.contains('education')) return Icons.menu_book;
    if (t.contains('entertain')) return Icons.movie;
    if (t.contains('auto')) return Icons.directions_car;
    return Icons.local_offer;
  }
}

class _CouponCard extends StatelessWidget {
  final RevGlueCoupon coupon;
  final VoidCallback onTap;
  final VoidCallback onShop;
  const _CouponCard({required this.coupon, required this.onTap, required this.onShop});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.gray900.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Type badge
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: coupon.hasCode ? HuddlColors.primary.withValues(alpha: 0.1) : HuddlColors.successBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    coupon.hasCode ? Icons.confirmation_number_outlined : Icons.local_offer_outlined,
                    color: coupon.hasCode ? HuddlColors.primary : HuddlColors.success,
                    size: 22,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    coupon.hasCode ? 'CODE' : 'OFFER',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: coupon.hasCode ? HuddlColors.primary : HuddlColors.success,
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
                    coupon.title,
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: HuddlColors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (coupon.expiryDate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Expires: ${coupon.expiryDate}',
                        style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: HuddlColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                coupon.hasCode ? 'View' : 'Get',
                style: GoogleFonts.poppins(color: HuddlColors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pinned tab bar delegate ─────────────────────────────────────
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: HuddlColors.background,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
