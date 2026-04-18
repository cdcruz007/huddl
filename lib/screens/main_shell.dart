import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/huddl_colors.dart';
import 'home/home_screen.dart';
import 'groups/groups_screen.dart';
import 'events/events_screen.dart';
import 'marketplace/marketplace_screen.dart';
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

  // Track which tabs have been activated at least once.
  // Only activated tabs are built — this prevents ALL screens initialising
  // simultaneously on first launch, which was causing setState-during-build
  // because every screen's initState async work raced with the build phase.
  final Set<int> _activatedTabs = {0}; // Home is always pre-activated

  @override
  void initState() {
    super.initState();
    // Defer tutorial check until after the first frame so it never
    // calls setState while MainShell itself is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkTutorial();
    });
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
        if (index >= 0 && index < 5) {
          _switchTab(index);
        }
      },
      onComplete: () {
        _switchTab(0);
      },
    );
  }

  /// Switch to a specific tab by index.
  /// 0=Home, 1=Connect, 2=Discover, 3=Market, 4=Profile
  void switchTab(int index) => _switchTab(index);

  void _switchTab(int index) {
    if (index < 0 || index >= 5) return;
    if (!mounted) return;
    setState(() {
      _activatedTabs.add(index);
      _currentIndex = index;
    });
  }

  Widget _buildScreen(int index) {
    // Only build a screen once it has been activated.
    // Before activation, show an empty box — zero build cost,
    // zero initState work, zero listener registrations.
    if (!_activatedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0: return const HomeScreen();
      case 1: return const GroupsScreen();
      case 2: return const EventsScreen();
      case 3: return const MarketplaceScreen();
      case 4: return const ProfileScreen();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: List.generate(5, (index) {
          return Offstage(
            offstage: _currentIndex != index,
            child: _buildScreen(index),
          );
        }),
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
                    label: 'Home',
                    isActive: _currentIndex == 0,
                    onTap: () => _switchTab(0),
                  ),
                  _NavItem(
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Connect',
                    isActive: _currentIndex == 1,
                    onTap: () => _switchTab(1),
                  ),
                  _NavItem(
                    icon: Icons.explore_outlined,
                    activeIcon: Icons.explore,
                    label: 'Discover',
                    isActive: _currentIndex == 2,
                    onTap: () => _switchTab(2),
                  ),
                  _NavItem(
                    icon: Icons.storefront_outlined,
                    activeIcon: Icons.storefront,
                    label: 'Market',
                    isActive: _currentIndex == 3,
                    onTap: () => _switchTab(3),
                  ),
                  _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: 'Profile',
                    isActive: _currentIndex == 4,
                    onTap: () => _switchTab(4),
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
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: 56,
            height: 56,
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
