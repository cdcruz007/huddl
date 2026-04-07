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
          'tailored to your children\'s ages, your area, and your family\'s needs. '
          'Powered by insights from 40+ trusted UK sources including NHS, NCT, '
          'BBC Bitesize, Gingerbread, Contact, and more.',
      ctaLabel: 'Tap cards to explore',
      iconName: 'home',
    ),
    // 1 — Connect
    TutorialStep(
      tabIndex: 1,
      title: 'CONNECT',
      headline: 'Groups & conversations',
      body:
          'Your auto-assigned local groups and DMs. From Bumps & Babies to '
          'Single Parents Connect, SEN Support, and Blended Families Hub \u2014 '
          'all within your borough.',
      ctaLabel: 'Tap a group to start chatting',
      iconName: 'people',
    ),
    // 2 — Discover
    TutorialStep(
      tabIndex: 2,
      title: 'DISCOVER',
      headline: 'Events, meetups & activities',
      body:
          'AI discovers local events daily. Browse borough meetups and UK-wide '
          'charity events from NCT, Adoption UK, Gingerbread, Home for Good, '
          'Barnardo\'s, Care for the Family, and Parentkind. '
          'Create your own meetup with the + button.',
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
          'exclusive offers. Safety recalls checked automatically. '
          'All transactions are hyperlocal to your borough.',
      ctaLabel: 'Tap + to list an item',
      iconName: 'storefront',
    ),
    // 4 — Profile
    TutorialStep(
      tabIndex: 4,
      title: 'PROFILE',
      headline: 'Your account & settings',
      body:
          'Manage your family structure (single, blended, adoptive, foster), '
          'support needs (SEN, digital safety, eco), subscription, '
          'notifications and privacy. Re-run this tour any time from here.',
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
