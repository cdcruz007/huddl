/// Formalised User Journey Map data model.
///
/// Exported from the code-comment journey maps that were introduced in R2.
/// This file turns free-text comments into a type-safe, testable structure
/// that can drive an in-app "Design System" debug page or feed automated
/// accessibility / UX regression checks.
library;

/// A single stage in a user journey (e.g. Trigger, Discovery, ...).
class JourneyStage {
  final String name;
  final String description;
  final List<String> touchpoints;
  final String? emotionalState;

  const JourneyStage({
    required this.name,
    required this.description,
    this.touchpoints = const [],
    this.emotionalState,
  });
}

/// Pain-point that is mitigated somewhere in the journey.
class PainPoint {
  final String issue;
  final String mitigation;

  const PainPoint({required this.issue, required this.mitigation});
}

/// Complete user persona + journey map.
class UserJourneyMap {
  final String personaName;
  final String personaLabel;
  final String ageRange;
  final String bio;
  final List<JourneyStage> stages;
  final List<PainPoint> painPoints;
  final List<String> emotionalArc;
  final String competitorGap;

  const UserJourneyMap({
    required this.personaName,
    required this.personaLabel,
    required this.ageRange,
    required this.bio,
    required this.stages,
    required this.painPoints,
    required this.emotionalArc,
    this.competitorGap = '',
  });
}

/// Competitor entry for the analysis table.
class CompetitorEntry {
  final String name;
  final String strength;
  final String weakness;

  const CompetitorEntry({
    required this.name,
    required this.strength,
    required this.weakness,
  });
}

/// Central repository of all documented journey maps.
class HuddlJourneyMaps {
  HuddlJourneyMaps._();

  // ── Competitor Analysis ──────────────────────────────────────────────
  static const competitors = [
    CompetitorEntry(
      name: 'Huckleberry',
      strength: 'Excellent age-aware UX',
      weakness: 'No community Q&A layer',
    ),
    CompetitorEntry(
      name: 'Family Destinations Guide',
      strength: 'Strong editorial content',
      weakness: 'No personalisation or interactive checklists',
    ),
    CompetitorEntry(
      name: 'TripIt / PackPoint',
      strength: 'Good packing lists',
      weakness: 'Not family-aware',
    ),
    CompetitorEntry(
      name: 'Huddl',
      strength: 'AI + real-parent community intelligence, age-aware checklists, gamified expert badges',
      weakness: 'Differentiator (ours)',
    ),
  ];

  // ── Journey 1: New-Parent Nadia ─────────────────────────────────────
  static const nadia = UserJourneyMap(
    personaName: 'Nadia',
    personaLabel: 'New-Parent Nadia',
    ageRange: '28-35',
    bio: 'First-time mum, overwhelmed by travel logistics, needs hand-holding checklists and reassurance from peers.',
    stages: [
      JourneyStage(
        name: 'Trigger',
        description: 'Feels anxious about first holiday with baby.',
        touchpoints: ['Word-of-mouth / social ad'],
        emotionalState: 'unsure',
      ),
      JourneyStage(
        name: 'Discovery',
        description: 'Downloads app and completes onboarding.',
        touchpoints: ['Splash', 'Onboarding (name, phone, postcode, stage-of-life, children)'],
        emotionalState: 'unsure',
      ),
      JourneyStage(
        name: 'Engagement',
        description: 'Explores community feed and events on Home.',
        touchpoints: ['MainShell', 'Home - community feed, upcoming events'],
        emotionalState: 'guided',
      ),
      JourneyStage(
        name: 'Conversion',
        description: 'Lists first preloved item via AI-guided flow.',
        touchpoints: [
          'Market tab > Sell sub-tab (encouraging empty-state CTA)',
          'Taps CTA > CreateListingScreen (AI pre-fills title+description)',
          'Listing appears in "My listings" with AI insight nudges',
        ],
        emotionalState: 'confident',
      ),
      JourneyStage(
        name: 'Retention',
        description: 'Receives offer, AI summarises and guides acceptance.',
        touchpoints: [
          'Offer arrives > liveRegion announcement > AI summary ("Strong offer")',
          'Swipe-right to accept > SnackBar confirmation with Undo',
          'Item marked as Sold > celebration SnackBar',
        ],
        emotionalState: 'confident',
      ),
      JourneyStage(
        name: 'Advocacy',
        description: 'Shares experience with borough neighbours.',
        touchpoints: ['Notice Board post', 'Welcome DM to new parents'],
        emotionalState: 'delighted',
      ),
    ],
    painPoints: [
      PainPoint(issue: 'Anxiety about pricing', mitigation: 'AI suggests price based on similar items'),
      PainPoint(issue: 'Overwhelm with too many buttons', mitigation: 'Progressive disclosure: sell tab shows CTA first'),
      PainPoint(issue: 'Uncertainty about listing quality', mitigation: 'AI photo/description hints with feedback loop'),
    ],
    emotionalArc: ['unsure', 'guided', 'confident', 'delighted'],
  );

  // ── Journey 2: Seasoned-Dad Sam ──────────────────────────────────────
  static const sam = UserJourneyMap(
    personaName: 'Sam',
    personaLabel: 'Seasoned-Dad Sam',
    ageRange: '32-40',
    bio: 'Father of two, confident traveller but wants child-age-specific tips and community shortcuts.',
    stages: [
      JourneyStage(
        name: 'Trigger',
        description: 'Needs a specific item for upcoming family trip.',
        touchpoints: ['App launch / notification nudge'],
        emotionalState: 'purposeful',
      ),
      JourneyStage(
        name: 'Discovery',
        description: 'Goes straight to Buy tab with clear intent.',
        touchpoints: ['MainShell > Market tab > Buy sub-tab'],
        emotionalState: 'purposeful',
      ),
      JourneyStage(
        name: 'Engagement',
        description: 'Uses AI-adapted search and quick filters.',
        touchpoints: [
          'AI-adapted search placeholder reflects previous browsing',
          'Filters (age stage, category, condition, price) - one-tap chips',
          'AI-ranked grid > taps item > ItemDetailScreen',
        ],
        emotionalState: 'efficient',
      ),
      JourneyStage(
        name: 'Conversion',
        description: 'Saves item and makes an offer.',
        touchpoints: [
          'Saves item (animated heart) > Saved tab',
          'Makes offer > waits for seller response',
        ],
        emotionalState: 'efficient',
      ),
      JourneyStage(
        name: 'Retention',
        description: 'Notified when offer accepted.',
        touchpoints: ['Notification > offer accepted'],
        emotionalState: 'satisfied',
      ),
    ],
    painPoints: [
      PainPoint(issue: 'Irrelevant search results', mitigation: 'Invisible AI ranking surfaces relevant items first'),
      PainPoint(issue: 'Slow filter workflow', mitigation: 'Bottom-sheet filters with haptic feedback'),
      PainPoint(issue: 'Information overload', mitigation: 'Clean card with essentials only'),
    ],
    emotionalArc: ['purposeful', 'efficient', 'satisfied'],
  );

  // ── Journey 3: Expert-Grandparent Grace ──────────────────────────────
  static const grace = UserJourneyMap(
    personaName: 'Grace',
    personaLabel: 'Expert-Grandparent Grace',
    ageRange: '55+',
    bio: 'Travels with grandchildren, wants to share knowledge and earn badges -- motivated by altruism.',
    stages: [
      JourneyStage(
        name: 'Trigger',
        description: 'Wants to help community and stay connected with family.',
        touchpoints: ['Grandparent group recommendation'],
        emotionalState: 'curious',
      ),
      JourneyStage(
        name: 'Discovery',
        description: 'Browses Chat groups and community features.',
        touchpoints: ['MainShell > Chat (groups for grandparents)'],
        emotionalState: 'curious',
      ),
      JourneyStage(
        name: 'Engagement',
        description: 'Searches age-aware items and uses AI assistant.',
        touchpoints: [
          'Market tab > Buy tab > searches age-aware items (toddler, kids)',
          'Long-press to dismiss irrelevant items > AI learns preferences',
          'Sparkle icon > AI assistant > "Chat with Huddl" copilot',
        ],
        emotionalState: 'engaged',
      ),
      JourneyStage(
        name: 'Conversion',
        description: 'Earns badges and lists curated items for community.',
        touchpoints: [
          'Profile > My Groups > badges/achievements',
          'Market > Sell tab > lists curated items for community',
        ],
        emotionalState: 'rewarded',
      ),
      JourneyStage(
        name: 'Advocacy',
        description: 'Becomes a trusted community contributor.',
        touchpoints: ['Expert badge', 'Community Q&A answers'],
        emotionalState: 'altruistic',
      ),
    ],
    painPoints: [
      PainPoint(issue: 'Small text', mitigation: '48dp touch targets, legible 14pt+ body text'),
      PainPoint(issue: 'Complex navigation', mitigation: 'Bottom nav with clear labels'),
      PainPoint(issue: 'Technology frustration', mitigation: 'Simple CTA, AI handles complexity behind the scenes'),
    ],
    emotionalArc: ['curious', 'engaged', 'rewarded', 'altruistic'],
  );

  /// All journeys in display order.
  static const all = [nadia, sam, grace];
}
