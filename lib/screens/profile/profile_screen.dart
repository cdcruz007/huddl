import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../auth/welcome_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Profile header
              Container(
                color: HuddlColors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  children: [
                    // Top bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Profile',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined,
                              color: HuddlColors.textDark),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Avatar
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        const HuddlAvatar(size: 88, hasBorder: true),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: HuddlColors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: HuddlColors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sarah Mitchell',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Melbourne, VIC',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: HuddlColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: HuddlColors.peachLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Baby (6 months)',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatItem(count: '5', label: 'Groups'),
                        Container(
                          width: 1,
                          height: 32,
                          color: HuddlColors.divider,
                        ),
                        _StatItem(count: '12', label: 'Events'),
                        Container(
                          width: 1,
                          height: 32,
                          color: HuddlColors.divider,
                        ),
                        _StatItem(count: '3', label: 'Listings'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Menu sections
              _MenuSection(
                title: 'Account',
                items: [
                  _MenuItem(
                    icon: Icons.person_outline,
                    title: 'Edit profile',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.child_care,
                    title: 'Stage of life',
                    subtitle: 'Baby (6 months)',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.interests_outlined,
                    title: 'Interests',
                    subtitle: '6 selected',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.location_on_outlined,
                    title: 'Location',
                    subtitle: 'Melbourne, VIC',
                    onTap: () {},
                  ),
                ],
              ),

              const SizedBox(height: 8),

              _MenuSection(
                title: 'Activity',
                items: [
                  _MenuItem(
                    icon: Icons.people_outline,
                    title: 'My groups',
                    trailing: _CountBadge(count: 5),
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.event_outlined,
                    title: 'My events',
                    trailing: _CountBadge(count: 3),
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.storefront_outlined,
                    title: 'My listings',
                    trailing: _CountBadge(count: 2),
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.bookmark_border,
                    title: 'Saved',
                    onTap: () {},
                  ),
                ],
              ),

              const SizedBox(height: 8),

              _MenuSection(
                title: 'Settings',
                items: [
                  _MenuItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.lock_outline,
                    title: 'Privacy',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.info_outline,
                    title: 'About huddl',
                    onTap: () {},
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Logout
              Container(
                color: HuddlColors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.logout, color: HuddlColors.error),
                  title: Text(
                    'Log out',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const WelcomeScreen()),
                      (route) => false,
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Version
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Version 1.0.0',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.textHint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String count;
  final String label;

  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
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

class _MenuSection extends StatelessWidget {
  final String title;
  final List<_MenuItem> items;

  const _MenuSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HuddlColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textHint,
              ),
            ),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HuddlColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: HuddlColors.textDark),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: HuddlColors.textDark,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: HuddlColors.textHint,
              ),
            )
          : null,
      trailing: trailing ??
          const Icon(
            Icons.chevron_right,
            color: HuddlColors.textHint,
          ),
      onTap: onTap,
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: HuddlColors.peachLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: HuddlColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: HuddlColors.textHint),
      ],
    );
  }
}
