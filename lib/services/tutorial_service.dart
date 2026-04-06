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
    // 0 — Home
    TutorialStep(
      tabIndex: 0,
      title: 'HOME',
      headline: 'Your personalised dashboard',
      body:
          'AI-curated feed with events, groups and community updates '
          'tailored to your children\'s ages and your area.',
      ctaLabel: 'Tap cards to explore',
      iconName: 'home',
    ),
    // 1 — Connect
    TutorialStep(
      tabIndex: 1,
      title: 'CONNECT',
      headline: 'Groups & conversations',
      body:
          'Your auto-assigned local groups and DMs. Tap any group to '
          'chat with parents nearby.',
      ctaLabel: 'Tap a group to start chatting',
      iconName: 'people',
    ),
    // 2 — Discover
    TutorialStep(
      tabIndex: 2,
      title: 'DISCOVER',
      headline: 'Events, meetups & activities',
      body:
          'AI discovers local events daily. Browse, filter by age and '
          'area, or create your own meetup with the + button.',
      ctaLabel: 'Tap + to create a meetup',
      iconName: 'groups',
    ),
    // 3 — Market
    TutorialStep(
      tabIndex: 3,
      title: 'MARKET',
      headline: 'Buy, sell & give away',
      body:
          'List outgrown baby gear, browse bargains, and discover '
          'exclusive offers from top UK brands.',
      ctaLabel: 'Tap + to list an item',
      iconName: 'storefront',
    ),
    // 4 — Profile
    TutorialStep(
      tabIndex: 4,
      title: 'PROFILE',
      headline: 'Your account & settings',
      body:
          'Manage your subscription, notifications and privacy. '
          'Re-run this tour any time from here.',
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
