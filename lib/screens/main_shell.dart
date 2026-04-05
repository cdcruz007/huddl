import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import 'home/home_screen.dart';
import 'groups/groups_screen.dart';
import 'events/events_screen.dart';
import 'events/create_meetup_screen.dart';
import 'marketplace/marketplace_screen.dart';
import 'trips/trips_screen.dart';
import 'deals/deals_screen.dart';
import 'profile/profile_screen.dart';
import 'ai/ai_copilot_screen.dart';
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
    HomeScreen(),
    GroupsScreen(),
    EventsScreen(),
    MarketplaceScreen(),
    TripsScreen(),
    DealsScreen(),
    ProfileScreen(),
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
      // Slight delay to let MainShell finish its first build
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
        // Return to MyHuddl tab after tutorial
        setState(() => _currentIndex = 0);
      },
    );
  }

  /// Switch to a specific tab by index (0=MyHuddl, 1=Chat, 2=Mingle, 3=Preloved, 4=Trips, 5=Deals, 6=Profile)
  void switchTab(int index) {
    if (index >= 0 && index < _screens.length) {
      setState(() => _currentIndex = index);
    }
  }

  void _navigateToCreateMeetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateMeetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      // ── FAB — Mingle = create, others = AI Copilot ──────────────────
      floatingActionButton: _currentIndex == 2 // Mingle tab
          ? Container(
              width: 60,
              height: 60,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: HuddlColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: FloatingActionButton(
                onPressed: _navigateToCreateMeetup,
                backgroundColor: HuddlColors.white.withValues(alpha: 0.0),
                elevation: 0,
                shape: const CircleBorder(),
                child: const Icon(Icons.add, color: HuddlColors.white, size: 30),
              ),
            )
          : (_currentIndex != 5 && _currentIndex != 6) // Hide on Deals & Profile
              ? Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF9D4EDD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: FloatingActionButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AiCopilotScreen()),
                    ),
                    backgroundColor: const Color(0x00FFFFFF),
                    elevation: 0,
                    shape: const CircleBorder(),
                    heroTag: 'ai_copilot_fab',
                    child: const Icon(Icons.auto_awesome, color: HuddlColors.white, size: 24),
                  ),
                )
              : null,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: HuddlColors.white,
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
                    label: 'Trips',
                    isActive: _currentIndex == 4,
                    onTap: () => setState(() => _currentIndex = 4),
                  ),
                  _NavItem(
                    icon: Icons.local_offer_outlined,
                    activeIcon: Icons.local_offer,
                    label: 'Deals',
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              size: 22,
              color: isActive ? HuddlColors.primary : HuddlColors.textHint,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? HuddlColors.primary : HuddlColors.textHint,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
