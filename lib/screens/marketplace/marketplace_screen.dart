import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pass It On',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.search, color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline, color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Tabs
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(text: 'Buy'),
                      Tab(text: 'Sell'),
                      Tab(text: 'Saved'),
                      Tab(text: 'Offers'),
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
                  ),
                ],
              ),
            ),
            // Category filters
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: ['All', 'Clothing', 'Toys', 'Prams', 'Furniture', 'Books', 'Other']
                      .map((cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: HuddlChip(
                              label: cat,
                              isSelected: _selectedCategory == cat,
                              onTap: () {
                                setState(() => _selectedCategory = cat);
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            // Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _BuyTab(),
                  _SellTab(),
                  _SavedTab(),
                  _OffersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: HuddlColors.primaryGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: HuddlColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () {},
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
      ),
    );
  }
}

class _BuyTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _marketplaceItems.length,
      itemBuilder: (context, index) {
        final item = _marketplaceItems[index];
        return _ProductCard(item: item);
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ProductCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  color: item['bgColor'] as Color,
                  child: Center(
                    child: Icon(
                      item['icon'] as IconData,
                      size: 48,
                      color: (item['iconColor'] as Color).withValues(alpha: 0.6),
                    ),
                  ),
                ),
                // Favorite
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: HuddlColors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite_border,
                      size: 16,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Details
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item['price'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                      Text(
                        item['condition'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: HuddlColors.textHint,
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
    );
  }
}

class _SellTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Create listing prompt
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: HuddlColors.peachLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 32,
                    color: HuddlColors.primary,
                  ),
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
                const SizedBox(height: 8),
                Text(
                  'Take a photo to start selling your pre-loved items to the huddl community.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                HuddlPrimaryButton(
                  text: 'Take a photo',
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // My listings
          HuddlSectionHeader(
            title: 'My listings',
            actionText: 'See all',
            onAction: () {},
          ),
          const SizedBox(height: 12),
          ..._myListings.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HuddlColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: HuddlColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        item['icon'] as IconData,
                        color: HuddlColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item['views']} views  ${item['offers']} offers',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item['price'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _SavedTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: HuddlColors.peachLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.favorite_border,
              size: 40,
              color: HuddlColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No saved items',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Items you save will appear here for\neasy access later.',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textHint,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OffersTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _offers.length,
      itemBuilder: (context, index) {
        final offer = _offers[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: HuddlColors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const HuddlAvatar(size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textDark,
                        ),
                        children: [
                          TextSpan(
                            text: offer['from'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' offered '),
                          TextSpan(
                            text: offer['amount'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'for ${offer['item']}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  _MiniButton(
                    text: 'Accept',
                    color: HuddlColors.teal,
                    onTap: () {},
                  ),
                  const SizedBox(height: 4),
                  _MiniButton(
                    text: 'Decline',
                    color: HuddlColors.error,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _MiniButton({
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

// Sample data
final _marketplaceItems = [
  {
    'title': 'Baby Jogger City Mini',
    'price': '\$180',
    'condition': 'Like new',
    'bgColor': HuddlColors.peachLight,
    'icon': Icons.child_friendly,
    'iconColor': HuddlColors.primary,
  },
  {
    'title': 'Wooden Toy Set',
    'price': '\$25',
    'condition': 'Good',
    'bgColor': HuddlColors.blueBackground,
    'icon': Icons.extension,
    'iconColor': HuddlColors.blue,
  },
  {
    'title': 'Baby Clothes Bundle 0-3m',
    'price': '\$40',
    'condition': 'Excellent',
    'bgColor': const Color(0xFFF0FFF0),
    'icon': Icons.checkroom,
    'iconColor': HuddlColors.teal,
  },
  {
    'title': 'Ergobaby Carrier',
    'price': '\$95',
    'condition': 'Good',
    'bgColor': HuddlColors.yellowLight,
    'icon': Icons.backpack,
    'iconColor': const Color(0xFFE8A838),
  },
  {
    'title': 'High Chair - Stokke Tripp',
    'price': '\$150',
    'condition': 'Like new',
    'bgColor': const Color(0xFFF5F0FF),
    'icon': Icons.chair,
    'iconColor': HuddlColors.purple,
  },
  {
    'title': 'Nursery Bookshelf',
    'price': '\$60',
    'condition': 'Good',
    'bgColor': HuddlColors.peachLight,
    'icon': Icons.menu_book,
    'iconColor': HuddlColors.primary,
  },
];

final _myListings = [
  {
    'title': 'Maxi-Cosi Car Seat',
    'price': '\$120',
    'views': 45,
    'offers': 2,
    'icon': Icons.airline_seat_recline_normal,
  },
  {
    'title': 'Baby Monitor (Owlet)',
    'price': '\$80',
    'views': 23,
    'offers': 1,
    'icon': Icons.monitor,
  },
];

final _offers = [
  {
    'from': 'Emma J.',
    'amount': '\$100',
    'item': 'Maxi-Cosi Car Seat',
  },
  {
    'from': 'Sophie B.',
    'amount': '\$110',
    'item': 'Maxi-Cosi Car Seat',
  },
  {
    'from': 'Lucy W.',
    'amount': '\$70',
    'item': 'Baby Monitor (Owlet)',
  },
];
