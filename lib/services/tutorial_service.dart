import 'browser_storage.dart';

/// Manages whether the interactive tutorial has been seen and provides
/// the ordered list of tutorial steps.
class TutorialService {
  static final TutorialService _instance = TutorialService._internal();
  factory TutorialService() => _instance;
  TutorialService._internal();

  static const _storageKey = 'tutorial_completed_v1';

  bool _hasCompleted = false;
  bool _isLoaded = false;

  bool get hasCompleted => _hasCompleted;

  /// Load persisted state.
  Future<void> initialize() async {
    if (_isLoaded) return;
    final val = await BrowserStorage.getString(_storageKey);
    _hasCompleted = val == 'true';
    _isLoaded = true;
  }

  /// Mark tutorial as completed so it won't auto-show again.
  Future<void> markCompleted() async {
    _hasCompleted = true;
    await BrowserStorage.setString(_storageKey, 'true');
  }

  /// Reset so the tutorial will show again (used by "Run Tutorial").
  Future<void> reset() async {
    _hasCompleted = false;
    await BrowserStorage.setString(_storageKey, 'false');
    _isLoaded = true;
  }

  /// Ordered tutorial steps. Each maps to a tab index in MainShell plus
  /// a description of the screen's purpose and its primary CTA.
  static const List<TutorialStep> steps = [
    // 0 — MyHuddl (Home)
    TutorialStep(
      tabIndex: 0,
      title: 'MyHuddl',
      headline: 'Your personalised dashboard',
      body:
          'See everything at a glance: AI-recommended events, your groups, '
          'community updates and quick actions tailored to your stage of '
          'parenthood.',
      ctaLabel: 'Tap cards to explore',
      iconName: 'home',
    ),
    // 1 — Chat
    TutorialStep(
      tabIndex: 1,
      title: 'Chat',
      headline: 'Your groups & conversations',
      body:
          'Join local parent groups, start direct messages, and stay '
          'connected with other parents in Cambridge. Your assigned groups '
          'appear automatically based on your postcode and stage of life.',
      ctaLabel: 'Tap a group to start chatting',
      iconName: 'people',
    ),
    // 2 — Mingle (Events + Meetups)
    TutorialStep(
      tabIndex: 2,
      title: 'Mingle',
      headline: 'Events, meetups & activities',
      body:
          'Browse AI-discovered events in Cambridge, B2B partner events, '
          'and parent-organised meetups. Filter by area, date or age. '
          'The AI scans local sources daily so new events appear '
          'automatically.',
      ctaLabel: 'Tap + to create a meetup',
      iconName: 'groups',
    ),
    // 3 — Preloved (Marketplace)
    TutorialStep(
      tabIndex: 3,
      title: 'Preloved',
      headline: 'Buy, sell & give away baby items',
      body:
          'List outgrown clothes, toys and gear for other local parents. '
          'Browse categories, message sellers directly and keep baby stuff '
          'out of landfill. Free listings for all Huddl members.',
      ctaLabel: 'Tap + to list an item',
      iconName: 'storefront',
    ),
    // 4 — Trips
    TutorialStep(
      tabIndex: 4,
      title: 'Trips',
      headline: 'Family travel made easy',
      body:
          'Discover family-friendly destinations, get AI-powered packing '
          'lists, and read tips from parents who\'ve been there. Our '
          'travel concierge helps plan stress-free holidays with little ones.',
      ctaLabel: 'Tap Explore to browse destinations',
      iconName: 'flight',
    ),
    // 5 — Deals
    TutorialStep(
      tabIndex: 5,
      title: 'Deals',
      headline: 'Save money on top UK brands',
      body:
          'Browse exclusive coupons, voucher codes and daily deals from '
          'hundreds of UK stores. Find family-friendly offers on baby '
          'gear, clothing, toys and more. Every purchase through Huddl '
          'earns cashback rewards!',
      ctaLabel: 'Tap a store to see offers',
      iconName: 'local_offer',
    ),
    // 6 — Profile
    TutorialStep(
      tabIndex: 6,
      title: 'Profile',
      headline: 'Your account & settings',
      body:
          'Edit your profile, manage your subscription, adjust '
          'notifications and privacy settings. You can also run this '
          'tutorial any time from here.',
      ctaLabel: 'Scroll down for settings',
      iconName: 'person',
    ),
  ];
}

/// A single step in the onboarding tutorial.
class TutorialStep {
  final int tabIndex;
  final String title;
  final String headline;
  final String body;
  final String ctaLabel;
  final String iconName;

  const TutorialStep({
    required this.tabIndex,
    required this.title,
    required this.headline,
    required this.body,
    required this.ctaLabel,
    required this.iconName,
  });
}
