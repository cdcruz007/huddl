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

  /// Ordered tutorial steps — emotionally-driven, not feature-spec.
  /// Each headline answers "what does this mean for me as a parent?"
  /// Each body sentence is one line. Each CTA is a specific invitation.
  ///
  /// Tab indices map to MainShell:
  ///   0 = Home  1 = Connect  2 = Discover  3 = Market  4 = Insights  5 = Profile
  static const List<TutorialStep> steps = [

    // STEP 0 — The founding moment
    // Emotional job: make the parent feel understood before explaining anything
    TutorialStep(
      tabIndex: 0,
      stepKey: 'welcome',
      headline: 'You just found your village',
      body: 'Every parent nearby has been where you are right now. Huddl connects you to them.',
      ctaLabel: "Let's meet them →",
      illustrationMood: 'waving',
      accentColor: 0xFFFF965C, // HuddlColors.primary
    ),

    // STEP 1 — Connect (the core value proposition)
    TutorialStep(
      tabIndex: 1,
      stepKey: 'connect',
      headline: 'Your neighbours are already here',
      body: "You've been added to groups in Cambridge that match where you are right now.",
      ctaLabel: "See who's in your groups →",
      illustrationMood: 'community',
      accentColor: 0xFF347FEF, // HuddlColors.infoBlue
    ),

    // STEP 2 — Discover (meetups and events)
    TutorialStep(
      tabIndex: 2,
      stepKey: 'discover',
      headline: 'Never miss the good stuff again',
      body: "Sunday walks, free baby groups, NCT events — filtered to your child's age, right now.",
      ctaLabel: "See what's on this week →",
      illustrationMood: 'exploring',
      accentColor: 0xFF347FEF, // HuddlColors.infoBlue
    ),

    // STEP 3 — Market (practical, celebratory)
    TutorialStep(
      tabIndex: 3,
      stepKey: 'market',
      headline: 'The street sale that never ends',
      body: 'Buy from a parent two streets away. List that bouncer in 60 seconds.',
      ctaLabel: "See what's nearby →",
      illustrationMood: 'market',
      accentColor: 0xFFF3C54F, // HuddlColors.accentAmber
    ),

    // STEP 4 — The close — celebratory, not informational
    TutorialStep(
      tabIndex: 0,
      stepKey: 'ready',
      headline: 'Cambridge is waiting for you',
      body: 'Your community, your neighbours, your feed. Everything is ready.',
      ctaLabel: "I'm ready — let's go 🏡",
      illustrationMood: 'celebrating',
      accentColor: 0xFFFF965C, // HuddlColors.primary
    ),
  ];
}

/// A single step in the onboarding tutorial.
class TutorialStep {
  final int tabIndex;
  final String stepKey;
  final String headline;
  final String body;
  final String ctaLabel;
  final String illustrationMood;
  final int accentColor;

  const TutorialStep({
    required this.tabIndex,
    required this.stepKey,
    required this.headline,
    required this.body,
    required this.ctaLabel,
    required this.illustrationMood,
    this.accentColor = 0xFFFF965C, // HuddlColors.primary
  });
}
