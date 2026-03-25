import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverToBoxAdapter(
              child: Container(
                color: HuddlColors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    // Logo
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: HuddlColors.peachLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'H',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: HuddlColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'huddl',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.primary,
                      ),
                    ),
                    const Spacer(),
                    // Notification bell
                    HuddlBadge(
                      count: 3,
                      child: IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        color: HuddlColors.textDark,
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Profile avatar
                    const HuddlAvatar(size: 32, hasBorder: true),
                  ],
                ),
              ),
            ),

            // Greeting card
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3ED), Color(0xFFFFF8F0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good morning, Sarah!',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Here\'s what\'s happening in your community today.',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: HuddlColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Quick Actions
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _QuickAction(
                      icon: Icons.people,
                      label: 'My Groups',
                      color: HuddlColors.primary,
                      bgColor: HuddlColors.peachLight,
                      onTap: () {},
                    ),
                    const SizedBox(width: 12),
                    _QuickAction(
                      icon: Icons.event,
                      label: 'Events',
                      color: HuddlColors.blue,
                      bgColor: HuddlColors.blueBackground,
                      onTap: () {},
                    ),
                    const SizedBox(width: 12),
                    _QuickAction(
                      icon: Icons.storefront,
                      label: 'Marketplace',
                      color: HuddlColors.teal,
                      bgColor: const Color(0xFFE6F5F3),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Upcoming Events
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: HuddlSectionHeader(
                  title: 'Upcoming events',
                  actionText: 'See all',
                  onAction: () {},
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _upcomingEvents.length,
                  itemBuilder: (context, index) {
                    final event = _upcomingEvents[index];
                    return Container(
                      width: 240,
                      margin: EdgeInsets.only(right: index < _upcomingEvents.length - 1 ? 12 : 0),
                      child: _EventCard(event: event),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Your Groups
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: HuddlSectionHeader(
                  title: 'Your groups',
                  actionText: 'See all',
                  onAction: () {},
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _userGroups.length,
                  itemBuilder: (context, index) {
                    final group = _userGroups[index];
                    return Container(
                      width: 64,
                      margin: EdgeInsets.only(right: index < _userGroups.length - 1 ? 16 : 0),
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: group['color'] as Color,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              group['icon'] as IconData,
                              color: HuddlColors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            group['name'] as String,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: HuddlColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Recent Posts / Activity
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: HuddlSectionHeader(
                  title: 'Community updates',
                  actionText: 'See all',
                  onAction: () {},
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final post = _communityPosts[index];
                  return _PostCard(post: post);
                },
                childCount: _communityPosts.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event image placeholder
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: event['color'] as Color,
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    event['icon'] as IconData,
                    size: 40,
                    color: HuddlColors.white.withValues(alpha: 0.7),
                  ),
                ),
                // Date badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: HuddlColors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      event['date'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['title'] as String,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: HuddlColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      event['time'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people_outline, size: 14, color: HuddlColors.textHint),
                    const SizedBox(width: 4),
                    Text(
                      '${event['attendees']} going',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;

  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HuddlAvatar(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post['author'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    Text(
                      post['time'] as String,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_horiz, color: HuddlColors.textHint),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            post['content'] as String,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: HuddlColors.textDark,
              height: 1.5,
            ),
          ),
          if (post['group'] != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: HuddlColors.peachLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                post['group'] as String,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: HuddlColors.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _PostAction(icon: Icons.favorite_border, label: '${post['likes']}'),
              const SizedBox(width: 20),
              _PostAction(icon: Icons.chat_bubble_outline, label: '${post['comments']}'),
              const SizedBox(width: 20),
              _PostAction(icon: Icons.share_outlined, label: 'Share'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PostAction({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: HuddlColors.textHint),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: HuddlColors.textHint,
          ),
        ),
      ],
    );
  }
}

// Sample data
final _upcomingEvents = [
  {
    'title': 'Baby Sensory Play',
    'date': 'MAR 15',
    'time': '10:00 AM',
    'attendees': 12,
    'icon': Icons.child_care,
    'color': HuddlColors.primary,
  },
  {
    'title': 'Parents Coffee Morning',
    'date': 'MAR 17',
    'time': '9:30 AM',
    'attendees': 8,
    'icon': Icons.coffee,
    'color': HuddlColors.blue,
  },
  {
    'title': 'Toddler Playdate',
    'date': 'MAR 20',
    'time': '2:00 PM',
    'attendees': 15,
    'icon': Icons.toys,
    'color': HuddlColors.teal,
  },
];

final _userGroups = [
  {'name': 'New Mums', 'icon': Icons.favorite, 'color': HuddlColors.primary},
  {'name': 'Local Area', 'icon': Icons.location_on, 'color': HuddlColors.blue},
  {'name': 'Expecting', 'icon': Icons.pregnant_woman, 'color': HuddlColors.teal},
  {'name': 'Fitness', 'icon': Icons.fitness_center, 'color': HuddlColors.purple},
  {'name': 'Cooking', 'icon': Icons.restaurant, 'color': const Color(0xFFE8A838)},
];

final _communityPosts = [
  {
    'author': 'Emma Johnson',
    'time': '2 hours ago',
    'content': 'Just had the best playdate at the park! Who else is free this Thursday for another one? The weather is supposed to be lovely.',
    'group': 'Toddler Parents',
    'likes': 14,
    'comments': 6,
  },
  {
    'author': 'Lucy Williams',
    'time': '4 hours ago',
    'content': 'Does anyone have recommendations for a good baby sleep consultant? My 4-month-old is still waking every 2 hours.',
    'group': 'Baby Sleep Tips',
    'likes': 23,
    'comments': 18,
  },
  {
    'author': 'Sophie Brown',
    'time': '6 hours ago',
    'content': 'Selling a Bugaboo Fox 3 in excellent condition. Only used for 8 months. DM me for details!',
    'group': 'Marketplace',
    'likes': 8,
    'comments': 3,
  },
];
