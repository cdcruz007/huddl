import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
                        'Groups',
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
                            icon: const Icon(Icons.add_circle_outline, color: HuddlColors.primary),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Tabs: Messages, Discover, Saved
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Messages'),
                      Tab(text: 'Discover'),
                      Tab(text: 'Saved'),
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
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MessagesTab(),
                  _DiscoverTab(),
                  _SavedTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagesTab extends StatelessWidget {
  final List<Map<String, dynamic>> _groups = const [
    {
      'name': 'New Mums Melbourne',
      'lastMessage': 'Emma: Does anyone know a good GP near Carlton?',
      'time': '2m',
      'unread': 3,
      'color': Color(0xFFFF975C),
      'icon': Icons.favorite,
    },
    {
      'name': 'Toddler Activities',
      'lastMessage': 'Sophie: Check out this new play centre!',
      'time': '15m',
      'unread': 1,
      'color': Color(0xFF3580F0),
      'icon': Icons.toys,
    },
    {
      'name': 'Sleep Training Support',
      'lastMessage': 'Lucy: We finally got 6 hours straight!',
      'time': '1h',
      'unread': 0,
      'color': Color(0xFF199A85),
      'icon': Icons.nightlight_round,
    },
    {
      'name': 'Working Parents',
      'lastMessage': 'Kate: Anyone use flexible childcare?',
      'time': '2h',
      'unread': 5,
      'color': Color(0xFFA16AE9),
      'icon': Icons.work_outline,
    },
    {
      'name': 'Baby-Led Weaning',
      'lastMessage': 'Anna: Tried avocado toast today and it was a hit!',
      'time': '3h',
      'unread': 0,
      'color': Color(0xFFE8A838),
      'icon': Icons.restaurant,
    },
    {
      'name': 'Local Playgrounds',
      'lastMessage': 'James: The new playground on Smith St is amazing',
      'time': '5h',
      'unread': 0,
      'color': Color(0xFF5B9DFF),
      'icon': Icons.park,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _groups.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 80,
        color: HuddlColors.divider,
      ),
      itemBuilder: (context, index) {
        final group = _groups[index];
        return _GroupMessageTile(group: group);
      },
    );
  }
}

class _GroupMessageTile extends StatelessWidget {
  final Map<String, dynamic> group;

  const _GroupMessageTile({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HuddlColors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: (group['color'] as Color).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            group['icon'] as IconData,
            color: group['color'] as Color,
            size: 24,
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                group['name'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: (group['unread'] as int) > 0
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: HuddlColors.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              group['time'] as String,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: (group['unread'] as int) > 0
                    ? HuddlColors.primary
                    : HuddlColors.textHint,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                group['lastMessage'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: HuddlColors.textHint,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if ((group['unread'] as int) > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HuddlColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${group['unread']}',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search
          const HuddlSearchBar(hint: 'Search groups'),
          const SizedBox(height: 20),

          // Suggested for you
          Text(
            'Suggested for you',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 12),

          ..._discoverGroups.map((group) => _DiscoverGroupCard(group: group)),

          const SizedBox(height: 24),

          // Categories
          Text(
            'Browse by category',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CategoryChip(label: 'Parenting', icon: Icons.family_restroom),
              _CategoryChip(label: 'Activities', icon: Icons.sports_soccer),
              _CategoryChip(label: 'Health', icon: Icons.medical_services_outlined),
              _CategoryChip(label: 'Education', icon: Icons.school_outlined),
              _CategoryChip(label: 'Lifestyle', icon: Icons.self_improvement),
              _CategoryChip(label: 'Local', icon: Icons.location_on_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscoverGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;

  const _DiscoverGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: (group['color'] as Color).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              group['icon'] as IconData,
              color: group['color'] as Color,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group['name'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${group['members']} members',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: HuddlColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Join',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: HuddlColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _CategoryChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HuddlColors.gray200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: HuddlColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: HuddlColors.textDark,
            ),
          ),
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
              Icons.bookmark_border,
              size: 40,
              color: HuddlColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No saved groups yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Save groups you\'re interested in\nto find them easily later.',
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

final _discoverGroups = [
  {
    'name': 'First Time Mums',
    'members': 1247,
    'color': HuddlColors.primary,
    'icon': Icons.favorite,
  },
  {
    'name': 'Dads Connect',
    'members': 834,
    'color': HuddlColors.blue,
    'icon': Icons.person,
  },
  {
    'name': 'Baby Sleep Solutions',
    'members': 2156,
    'color': HuddlColors.teal,
    'icon': Icons.nightlight_round,
  },
  {
    'name': 'Healthy Family Meals',
    'members': 1589,
    'color': const Color(0xFFE8A838),
    'icon': Icons.restaurant,
  },
  {
    'name': 'Postnatal Fitness',
    'members': 967,
    'color': HuddlColors.purple,
    'icon': Icons.fitness_center,
  },
];
