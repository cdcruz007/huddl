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

  /// Ordered tutorial steps. Each maps to a tab index in MainShell:
  ///   0 = Home  1 = Connect  2 = Discover  3 = Market  4 = Insights  5 = Profile
  static const List<TutorialStep> steps = [
    // 0 — Home (tab 0)
    TutorialStep(
      tabIndex: 0,
      title: 'HOME',
      headline: 'Your neighbourhood, at a glance',
      body:
          'Every morning you\'ll see what\'s happening nearby \u2014 new meetups, '
          'local events, and groups worth joining. All picked for your '
          'family\'s age and stage. No scrolling through irrelevant noise.',
      ctaLabel: 'Tap cards to explore',
      iconName: 'home',
    ),
    // 1 — Connect (tab 1)
    TutorialStep(
      tabIndex: 1,
      title: 'CONNECT',
      headline: 'Your local parent network, ready and waiting',
      body:
          'You\'ve already been added to groups in Cambridge that match your '
          'stage \u2014 expecting, toddler years, school age. Jump in, ask a '
          'question, or just say hi. These are the parents on your street.',
      ctaLabel: 'Tap a group to start chatting',
      iconName: 'people',
    ),
    // 2 — Discover (tab 2)
    TutorialStep(
      tabIndex: 2,
      title: 'DISCOVER',
      headline: 'Never miss the good stuff again',
      body:
          'We scan local listings, NHS boards, and community pages every day '
          'so you don\'t have to. Free baby groups, NCT events, toddler classes '
          '\u2014 filtered to what actually suits your child\'s age.',
      ctaLabel: 'Tap + to create a meetup',
      iconName: 'groups',
    ),
    // 3 — Market (tab 3)
    TutorialStep(
      tabIndex: 3,
      title: 'MARKET',
      headline: 'Give outgrown gear a second life',
      body:
          'List that barely-used bouncer in 60 seconds. Buy a pram from a '
          'parent two streets away. Everything is local, trusted, and safe \u2014 '
          'because you already know who you\'re buying from.',
      ctaLabel: 'Tap + to list an item',
      iconName: 'storefront',
    ),
    // 4 — Profile (tab 5)
    TutorialStep(
      tabIndex: 5,
      title: 'PROFILE',
      headline: 'It gets better the more it knows you',
      body:
          'Add your children\'s names and ages, set your interests, and Huddl '
          'tailors everything to your family. Update as your kids grow \u2014 '
          'your feed grows with them.',
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
