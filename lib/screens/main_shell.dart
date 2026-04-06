import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import 'home/home_screen.dart';
import 'groups/groups_screen.dart';
import 'events/events_screen.dart';
import 'marketplace/marketplace_screen.dart';
import 'travel/travel_screen.dart';
import 'offers/offers_screen.dart';
import 'profile/profile_screen.dart';
import '../services/tutorial_service.dart';
import '../widgets/tutorial/tutorial_overlay.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Global key to allow switching tabs from child screens.
  static final GlobalKey<MainShellState> shellKey =
      GlobalKey<MainShellState>();

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),    // 0 – MyHuddl
    GroupsScreen(),  // 1 – Chat
    EventsScreen(),  // 2 – Mingle
    MarketplaceScreen(), // 3 – Preloved
    TravelScreen(),  // 4 – Travel
    OffersScreen(),  // 5 – Offers
    ProfileScreen(), // 6 – Profile
  ];

  @override
  void initState() {
    super.initState();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final svc = TutorialService();
    await svc.initialize();
    if (!svc.hasCompleted && mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _launchTutorial();
    }
  }

  /// Public so Profile screen can re-trigger it.
  void launchTutorial() => _launchTutorial();

  void _launchTutorial() {
    TutorialOverlay.show(
      context,
      onTabSwitch: (index) {
        if (index >= 0 && index < _screens.length) {
          setState(() => _currentIndex = index);
        }
      },
      onComplete: () {
        setState(() => _currentIndex = 0);
      },
    );
  }

  /// Switch to a specific tab by index
  /// 0=MyHuddl, 1=Chat, 2=Mingle, 3=Preloved, 4=Travel, 5=Offers, 6=Profile
  void switchTab(int index) {
    if (index >= 0 && index < _screens.length) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: HuddlColors.gray900.withValues(alpha: 0.10),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: HuddlColors.gray900.withValues(alpha: 0.04),
                  blurRadius: 8,
                  spreadRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'MyHuddl',
                    isActive: _currentIndex == 0,
                    onTap: () => setState(() => _currentIndex = 0),
                  ),
                  _NavItem(
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Chat',
                    isActive: _currentIndex == 1,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                  _NavItem(
                    icon: Icons.groups_outlined,
                    activeIcon: Icons.groups,
                    label: 'Mingle',
                    isActive: _currentIndex == 2,
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                  _NavItem(
                    icon: Icons.storefront_outlined,
                    activeIcon: Icons.storefront,
                    label: 'Preloved',
                    isActive: _currentIndex == 3,
                    onTap: () => setState(() => _currentIndex = 3),
                  ),
                  _NavItem(
                    icon: Icons.flight_outlined,
                    activeIcon: Icons.flight,
                    label: 'Travel',
                    isActive: _currentIndex == 4,
                    onTap: () => setState(() => _currentIndex = 4),
                  ),
                  _NavItem(
                    icon: Icons.local_offer_outlined,
                    activeIcon: Icons.local_offer,
                    label: 'Offers',
                    isActive: _currentIndex == 5,
                    onTap: () => setState(() => _currentIndex = 5),
                  ),
                  _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: 'Profile',
                    isActive: _currentIndex == 6,
                    onTap: () => setState(() => _currentIndex = 6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  size: 22,
                  color: isActive
                      ? HuddlColors.primary
                      : (Theme.of(context).textTheme.bodySmall?.color ??
                          HuddlColors.textHint),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? HuddlColors.primary
                        : (Theme.of(context).textTheme.bodySmall?.color ??
                            HuddlColors.textHint),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
