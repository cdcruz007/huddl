import 'dart:async';
import '../theme/huddl_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../theme/huddl_colors.dart';
import 'home/home_screen.dart';
import 'groups/groups_screen.dart';
import 'events/events_screen.dart';
import 'marketplace/marketplace_screen.dart';
import 'profile/profile_screen.dart';
import '../services/tutorial_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/voice_message_service.dart';
import '../widgets/tutorial/tutorial_overlay.dart';
import '../constants/app_text_styles.dart';
// huddl_spring_animations used via home_screen.dart (HuddlSpringPageRoute on nav pushes)

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Global key to allow switching tabs from child screens.
  static final GlobalKey<MainShellState> shellKey =
      GlobalKey<MainShellState>();

  /// Navigator key passed to MaterialApp so NotificationCopyService can push
  /// named routes from outside the widget tree (e.g. from FCM tap handlers).
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  // Track which tabs have been activated at least once.
  // Only activated tabs are built — this prevents ALL screens initialising
  // simultaneously on first launch, which was causing setState-during-build
  // because every screen's initState async work raced with the build phase.
  final Set<int> _activatedTabs = {0}; // Home is always pre-activated

  /// Key to reach EventsScreen (Discover tab) so we can reset Services search
  /// whenever the user leaves the Discover tab via the bottom nav.
  final GlobalKey<EventsScreenState> _eventsKey = GlobalKey<EventsScreenState>();

  // ── Active chat tracking (used to suppress duplicate foreground banners) ──
  // When the user is already inside a group chat or DM, the OS shows the FCM
  // heads-up banner AND our SnackBar would fire simultaneously.  By tracking
  // the currently-open chat we can skip the SnackBar for that conversation.
  String? _activeGroupId;       // non-null while a group chat is open
  String? _activeDmRecipientId; // non-null while a DM screen is open

  /// Called by group chat screen on push/pop so we know when it's visible.
  void setActiveGroupChat(String? groupId) => _activeGroupId = groupId;

  /// Called by DM chat screen on push/pop so we know when it's visible.
  void setActiveDmChat(String? recipientId) => _activeDmRecipientId = recipientId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer tutorial check until after the first frame so it never
    // calls setState while MainShell itself is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkTutorial();
        _initialisePushNotifications();
        // Initialise voice playback engine once at app-level so the
        // AudioPlayer listeners and iOS/Android audio session are ready
        // before any chat screen tries to play a voice message.
        VoiceMessageService.instance.init();
      }
    });
  }

  // ── Push notifications ───────────────────────────────────────────────────

  void _initialisePushNotifications() {
    final push = PushNotificationService();

    // Register the navigator key so NotificationCopyService.handleTap() can
    // route tapped notifications to the correct named route without a BuildContext.
    // We expose a static GlobalKey<NavigatorState> so deep-link routing works
    // even after the shell is rebuilt (key is stable for the app lifetime).
    push.navigatorKey = MainShell.navigatorKey;

    // Show an in-app banner when a message arrives while the app is open.
    push.onForegroundMessage = (RemoteMessage message) {
      if (!mounted) return;
      final title = message.notification?.title ?? '';
      final body  = message.notification?.body  ?? '';
      if (title.isEmpty && body.isEmpty) return;

      // Suppress SnackBar if the user is already viewing the conversation
      // that triggered this notification — the OS heads-up is sufficient.
      final data            = message.data;
      final notifType       = data['type'] as String? ?? '';
      final notifGroupId    = data['groupId'] as String? ?? '';
      final notifRecipId    = data['recipientId'] as String? ?? '';
      final alreadyInGroup  = notifType == 'new_group_message' &&
          notifGroupId.isNotEmpty &&
          notifGroupId == _activeGroupId;
      final alreadyInDm     = (notifType == 'new_dm' || notifType == 'voice_message_dm') &&
          notifRecipId.isNotEmpty &&
          notifRecipId == _activeDmRecipientId;
      if (alreadyInGroup || alreadyInDm) return;

      // Only surface FCM messages that have a recognised user-facing type.
      // Backend operational/error messages (e.g. duplicate-email conflicts,
      // welcome-email idempotency failures) arrive with no type or an unknown
      // type and must never be shown verbatim to the user.
      const kUserFacingTypes = {
        'new_group_message',
        'new_dm',
        'voice_message_dm',
        'group_event',
        'meetup_cancelled',
        'marketplace_offer',
        'marketplace_offer_response',
        'marketplace_item_sold',
        'group_join_request',
        'group_joined',
        'mention',
        'reaction',
        'new_follower',
      };
      if (!kUserFacingTypes.contains(notifType)) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: HuddlColors.primary,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(HuddlIcons.bellFill, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    if (body.isNotEmpty)
                      Text(body,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () => _handleNotificationTap(message),
          ),
        ),
      );
    };

    // Navigate when the user taps a notification (background or terminated).
    push.onNotificationTap = _handleNotificationTap;

    // Ensure FCM is initialised (safe to call again — idempotent)
    unawaited(push.initialise());

    // Sync notification prefs to Firestore so the backend has up-to-date
    // preferences immediately after the shell mounts.
    unawaited(push.syncPrefsToFirestore());
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (!mounted) return;
    final data           = message.data;
    final type           = data['type'] as String? ?? '';
    final route          = data['route'] as String? ?? '';
    final groupId        = data['groupId'] as String? ?? '';
    final groupName      = data['groupName'] as String? ?? 'Group';
    final conversationId = data['conversationId'] as String? ?? '';
    final recipientId    = data['recipientId'] as String? ?? '';
    final recipientName  = data['recipientName'] as String? ?? '';

    // Always switch to Connect tab first so the user lands on the right tab
    _switchTab(1);

    // Then navigate to the specific chat screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (type == 'new_group_message' && groupId.isNotEmpty) {
        Navigator.of(context).pushNamed(
          '/group_chat',
          arguments: {
            'groupId':       groupId,
            'groupName':     groupName,
            'groupImageUrl': '',
          },
        );
      } else if (type == 'new_dm' &&
          (conversationId.isNotEmpty || recipientId.isNotEmpty)) {
        Navigator.of(context).pushNamed(
          '/dm_chat',
          arguments: {
            'recipientId':          recipientId,
            'recipientName':        recipientName,
            'recipientAvatarColor': '#FF975C',
            'conversationId':       conversationId,
          },
        );
      } else if (route.isNotEmpty) {
        Navigator.of(context).pushNamed(route);
      }
    });
  }

  // ── G6: Refresh subscription state when app returns to foreground ────────
  // This ensures a user who subscribes on another device (or whose subscription
  // was updated by the backend webhook) sees the correct tier after switching
  // away from the app and back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSubscriptionInBackground();
    }
  }

  /// Non-blocking Firestore subscription sync — runs silently in the background
  /// so it never delays the UI.  Any error is logged in debug mode only.
  Future<void> _syncSubscriptionInBackground() async {
    try {
      await FirebaseAuthService()
          .restoreProfileFromFirestore()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MainShell: background subscription sync failed: $e');
      }
    }
  }

  Future<void> _checkTutorial() async {
    final svc = TutorialService();
    await svc.initialize();

    // IMPORTANT: Do NOT show the tutorial if the user was already signed in
    // before the shell mounted. A returning user either:
    //  (a) has already seen the tutorial and SharedPreferences was cleared
    //      (e.g. app reinstall, cache wipe, Firebase Test Lab fresh device), or
    //  (b) is a Firebase Test Lab automated test account.
    // In both cases the tutorial overlay would block all navigation and cause
    // UiAutomator/Robo to report "Outside of app" → "Test failed to run".
    //
    // Tutorial is only shown when hasCompleted==false AND the user arrived
    // here via the normal onboarding flow (new registration), not a cold-start
    // sign-in. We detect a cold-start returning user by checking if there was
    // already a Firebase Auth session when main() ran — if BrowserStorage
    // already has profile data, the user is not new.
    if (!svc.hasCompleted) {
      // Auto-mark completed for returning Firebase users so the tutorial never
      // blocks navigation on reinstalls, cache wipes, or automated tests.
      // On Android, Firebase Auth session restoration can be slightly delayed
      // on cold-start — wait up to 3 seconds before concluding the user is new.
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        try {
          currentUser = await FirebaseAuth.instance
              .authStateChanges()
              .first
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          currentUser = null;
        }
      }
      if (currentUser != null) {
        await svc.markCompleted();
        return;
      }
    }

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
        if (index >= 0 && index < 6) {
          _switchTab(index);
        }
      },
      onComplete: () {
        _switchTab(0);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Switch to a specific tab by index.
  /// 0=Home, 1=Connect, 2=Discover, 3=Market, 4=Profile
  void switchTab(int index) => _switchTab(index);

  /// Switch to the Discover tab AND jump to a specific sub-tab within it.
  /// subIndex: 0=Groups, 1=Nearby (meetups+events), 2=Services, 3=Insights
  void switchDiscoverTab(int subIndex) {
    _switchTab(2); // Discover is always tab 2
    // Give the Discover screen one frame to build before animating sub-tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _eventsKey.currentState?.switchToSubTab(subIndex);
    });
  }

  void _switchTab(int index) {
    if (index < 0 || index >= 5) return;
    if (!mounted) return;
    // Reset Services search mode whenever the user leaves the Discover tab (2).
    if (_currentIndex == 2 && index != 2) {
      _eventsKey.currentState?.resetServicesSearch();
    }
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
      case 2: return EventsScreen(key: _eventsKey);
      case 3: return const MarketplaceScreen();
      case 4: return const ProfileScreen();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: List.generate(5, (index) {
          return Offstage(
            offstage: _currentIndex != index,
            child: _buildScreen(index),
          );
        }),
      ),
      bottomNavigationBar: _HuddlNavBar(
        currentIndex: _currentIndex,
        onTap: _switchTab,
      ),
    );
  }
}

// =============================================================================
// HUDDL BOTTOM NAV BAR
// =============================================================================
// Full-width flush navigation bar — no pill, no margins, no shadow.
// Same icons, labels, orange active state, and spring animation as before.
// A single 0.5px top border provides the only visual separation from content.
// =============================================================================

class _HuddlNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _HuddlNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  static const _tabs = [
    _TabDef(HuddlIcons.home,            HuddlIcons.home,            'Home'),
    _TabDef(HuddlIcons.usersThree,      HuddlIcons.usersThree,      'Connect'),
    _TabDef(HuddlIcons.exploreOutlined, HuddlIcons.explore,         'Discover'),
    _TabDef(HuddlIcons.storefront,      HuddlIcons.storefront,      'Market'),
    _TabDef(HuddlIcons.user,            HuddlIcons.user,            'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? HuddlColors.darkSurface : Colors.white;
    final divider = isDark ? HuddlColors.darkDivider : HuddlColors.divider;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: divider, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              return Expanded(
                child: _NavItem(
                  tab: _tabs[i],
                  index: i,
                  currentIndex: currentIndex,
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ── Individual nav item ───────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final _TabDef tab;
  final int index;
  final int currentIndex;
  final bool isDark;
  final VoidCallback onTap;
  final bool hasUnread;

  const _NavItem({
    required this.tab,
    required this.index,
    required this.currentIndex,
    required this.isDark,
    required this.onTap,
    this.hasUnread = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _iconOpacity;

  bool get _isActive => widget.index == widget.currentIndex;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: _isActive ? 1.0 : 0.0,
    );
    // Spring-pop scale: grow to 1.18 then settle at 1.0
    _scale = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.18), weight: 35),
      TweenSequenceItem(
          tween: Tween(begin: 1.18, end: 1.0), weight: 65),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _iconOpacity =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    final wasActive = old.index == old.currentIndex;
    final isNowActive = widget.index == widget.currentIndex;
    if (!wasActive && isNowActive) _ctrl.forward(from: 0);
    else if (wasActive && !isNowActive) _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = HuddlColors.primary;
    final inactiveColor = widget.isDark
        ? HuddlColors.darkTextTertiary
        : HuddlColors.textHint;

    return Semantics(
      label: widget.tab.label,
      button: true,
      selected: _isActive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final labelColor =
                Color.lerp(inactiveColor, activeColor, _ctrl.value)!;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon with soft orange pill background when active
                Transform.scale(
                  scale: _scale.value,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 42,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _isActive
                          ? HuddlColors.primary.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Inactive icon fades out
                        Opacity(
                          opacity:
                              (1.0 - _iconOpacity.value).clamp(0.0, 1.0),
                          child: Icon(widget.tab.icon,
                              size: 22, color: inactiveColor),
                        ),
                        // Active icon fades in
                        Opacity(
                          opacity: _iconOpacity.value.clamp(0.0, 1.0),
                          child: Icon(widget.tab.activeIcon,
                              size: 22, color: activeColor),
                        ),
                        // Unread badge — top right of icon
                        if (widget.hasUnread)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: HuddlColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Label — colour transitions with animation
                Text(
                  widget.tab.label,
                  style: HuddlText.label(color: labelColor),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Tab definition ────────────────────────────────────────────────────────────

class _TabDef {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TabDef(this.icon, this.activeIcon, this.label);
}
