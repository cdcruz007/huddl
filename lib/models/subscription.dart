// =====================================================================================
// HUDDL CONNECT -- SUBSCRIPTION MODEL  (Updated April 2025)
// =====================================================================================
//
// PRICING ANALYST RATIONALE
// -------------------------
// Three tiers designed around the "Value-First Freemium" strategy, now expanded
// to incorporate the full AI-powered feature suite launched in Cambridge:
//
// 1. EXPLORER (Free) -- "Hook tier"
//    Deliberately tight limits that let users experience value quickly
//    (join 2 groups, attend meetups, 5 DMs) but hit friction within the
//    first week. AI features are capped to give a taste without full access.
//    Goal: force an upgrade decision within 7 days.
//
// 2. NEIGHBOURHOOD (GBP 5.99/mo | GBP 49.99/yr) -- "Sweet-spot tier"
//    Priced at the UK impulse-buy threshold (< cost of 2 coffees/mo).
//    Removes ALL social friction (unlimited groups, DMs, meetups) and
//    unlocks the core AI suite: Copilot, Event Discovery, Chat Summaries,
//    Smart Feed, and Listing Generator with generous limits.
//    This is the tier 80%+ of paying users should land on.
//    Annual plan saves 30% -- anchored as default to maximise LTV.
//
// 3. INNER CIRCLE (GBP 11.99/mo | GBP 99.99/yr) -- "Power-user tier"
//    For community leaders and super-engaged parents. Everything in
//    Neighbourhood plus unlimited AI usage, AI Matchmaker, full analytics,
//    exclusive Inner Circle features like AI Matchmaker and unlimited
//    usage across all AI tools. Targets the top ~5% of active users
//    who derive outsized value and are willing to pay 2x for premium perks.
//
// COMPETITIVE CONTEXT (UK parenting/community apps, 2025):
//   Peanut Plus:  ~GBP 8.99/mo or GBP 79.99 lifetime
//   Huckleberry:  ~GBP 7.99/mo
//   Mush:         Free (ad-supported)
//
// Huddl Neighbourhood at GBP 5.99/mo undercuts Peanut and Huckleberry by 25-33%
// while offering comparable or superior social features PLUS an AI suite no
// competitor matches, making it the highest-value option in the market.
//
// KEY CONVERSION LEVERS:
//   7-day auto-trial of Neighbourhood on sign-up (no card required)
//   Soft paywalls at "aha moments" (3rd group, 6th DM, AI limit hit)
//   Founding Member rate: GBP 3.99/mo locked for life (first 500 users)
//   Annual billing default with "Save 30%" badge
//   Day-5 trial reminder push notification
//   Day-7 exit survey + 1-month free pause on cancellation
// =====================================================================================

/// Subscription tier levels for Huddl Connect
enum SubscriptionTier { explorer, neighbourhood, innerCircle }

/// Billing period
enum BillingPeriod { monthly, annual }

/// Feature limits per tier
class TierLimits {
  // ---- Core Social Limits ----
  final int maxGroups;
  final int maxGroupsCreated;
  final int maxMeetupsPerMonth;
  final int maxDMConversations;
  final int maxMarketplaceListings;
  final int maxPhotoUploads;
  final int maxMessagesPerMonth;

  // ---- Core Social Booleans ----
  final bool canCreatePrivateGroups;
  final bool canCreateMeetups;
  final bool adFree;
  final bool customProfileBadge;
  final bool milestoneTracker;

  // ---- AI Feature Limits ----
  final int maxAiCopilotChatsPerDay;
  final int maxAiEventDiscoveriesPerWeek;
  final int maxAiChatSummariesPerDay;
  final int maxAiListingGenerationsPerMonth;
  final int maxAiMatchmakerRequestsPerMonth;
  final int maxAiSmartFeedRefreshesPerDay;

  // ---- AI Feature Booleans ----
  final bool aiCopilotAccess;
  final bool aiEventDiscovery;
  final bool aiEventRecommendations;
  final bool aiChatSummaries;
  final bool aiListingGenerator;
  final bool aiSmartFeed;
  final bool aiMeetupMatchmaker;

  // ---- Community Q&A Feature ----
  final int maxQuestionsPerWeek;
  final int maxBookmarksPerMonth;
  final bool communityBadgesEnabled;
  final bool aiSynthesisAccess;

  const TierLimits({
    // Core social
    required this.maxGroups,
    required this.maxGroupsCreated,
    required this.maxMeetupsPerMonth,
    required this.maxDMConversations,
    required this.maxMarketplaceListings,
    required this.maxPhotoUploads,
    required this.maxMessagesPerMonth,
    required this.canCreatePrivateGroups,
    required this.canCreateMeetups,
    required this.adFree,
    required this.customProfileBadge,
    required this.milestoneTracker,
    // AI limits
    required this.maxAiCopilotChatsPerDay,
    required this.maxAiEventDiscoveriesPerWeek,
    required this.maxAiChatSummariesPerDay,
    required this.maxAiListingGenerationsPerMonth,
    required this.maxAiMatchmakerRequestsPerMonth,
    required this.maxAiSmartFeedRefreshesPerDay,
    // AI booleans
    required this.aiCopilotAccess,
    required this.aiEventDiscovery,
    required this.aiEventRecommendations,
    required this.aiChatSummaries,
    required this.aiListingGenerator,
    required this.aiSmartFeed,
    required this.aiMeetupMatchmaker,
    // Community Q&A
    this.maxQuestionsPerWeek = 3,
    this.communityBadgesEnabled = false,
    this.maxBookmarksPerMonth = 5,
    this.aiSynthesisAccess = false,
  });

  // ---- EXPLORER (Free) ----------------------------------------------------------
  // Tight limits: experience value fast, hit friction within 7 days.
  // 2 groups, 1 created, 2 meetups/mo, 5 DMs, 2 listings, 3 photos.
  // AI: taster access -- 3 copilot chats/day, basic event discovery,
  // basic recommendations, 1 chat summary/day, no listing generator,
  // basic smart feed, no matchmaker.
  static const TierLimits explorer = TierLimits(
    // Core social
    maxGroups: 2,
    maxGroupsCreated: 1,
    maxMeetupsPerMonth: 2,
    maxDMConversations: 5,
    maxMarketplaceListings: 2,
    maxPhotoUploads: 3,
    maxMessagesPerMonth: 30,
    canCreatePrivateGroups: false,
    canCreateMeetups: false,
    adFree: false,
    customProfileBadge: false,
    milestoneTracker: false,
    // AI limits
    maxAiCopilotChatsPerDay: 3,
    maxAiEventDiscoveriesPerWeek: 1,
    maxAiChatSummariesPerDay: 1,
    maxAiListingGenerationsPerMonth: 0,
    maxAiMatchmakerRequestsPerMonth: 0,
    maxAiSmartFeedRefreshesPerDay: 2,
    // AI booleans
    aiCopilotAccess: true,
    aiEventDiscovery: true,
    aiEventRecommendations: true,
    aiChatSummaries: true,
    aiListingGenerator: false,
    aiSmartFeed: true,
    aiMeetupMatchmaker: false,
    // Community Q&A
    maxQuestionsPerWeek: 3,
    communityBadgesEnabled: false,
    maxBookmarksPerMonth: 5,
    aiSynthesisAccess: false,
  );

  // ---- NEIGHBOURHOOD (GBP 5.99/mo) -----------------------------------------------
  // Removes all social friction. Full AI suite with generous daily limits.
  // Unlocks: AI Listing Generator, full Chat Summaries,
  // unlimited Smart Feed, and increased Copilot usage.
  static const TierLimits neighbourhood = TierLimits(
    // Core social
    maxGroups: 999,
    maxGroupsCreated: 25,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 15,
    maxPhotoUploads: 15,
    maxMessagesPerMonth: 999,
    canCreatePrivateGroups: true,
    canCreateMeetups: true,
    adFree: true,
    customProfileBadge: true,
    milestoneTracker: true,
    // AI limits
    maxAiCopilotChatsPerDay: 25,
    maxAiEventDiscoveriesPerWeek: 7,
    maxAiChatSummariesPerDay: 10,
    maxAiListingGenerationsPerMonth: 10,
    maxAiMatchmakerRequestsPerMonth: 0,
    maxAiSmartFeedRefreshesPerDay: 999,
    // AI booleans
    aiCopilotAccess: true,
    aiEventDiscovery: true,
    aiEventRecommendations: true,
    aiChatSummaries: true,
    aiListingGenerator: true,
    aiSmartFeed: true,
    aiMeetupMatchmaker: false,
    // Community Q&A
    maxQuestionsPerWeek: 15,
    communityBadgesEnabled: true,
    maxBookmarksPerMonth: 50,
    aiSynthesisAccess: true,
  );

  // ---- INNER CIRCLE (GBP 11.99/mo) -----------------------------------------------
  // Everything in Neighbourhood + unlimited AI, AI Matchmaker,
  // unlimited photos, and exclusive Inner Circle badge.
  static const TierLimits innerCircle = TierLimits(
    // Core social
    maxGroups: 999,
    maxGroupsCreated: 999,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 999,
    maxPhotoUploads: 50,
    maxMessagesPerMonth: 999,
    canCreatePrivateGroups: true,
    canCreateMeetups: true,
    adFree: true,
    customProfileBadge: true,
    milestoneTracker: true,
    // AI limits -- effectively unlimited
    maxAiCopilotChatsPerDay: 999,
    maxAiEventDiscoveriesPerWeek: 999,
    maxAiChatSummariesPerDay: 999,
    maxAiListingGenerationsPerMonth: 999,
    maxAiMatchmakerRequestsPerMonth: 999,
    maxAiSmartFeedRefreshesPerDay: 999,
    // AI booleans -- everything unlocked
    aiCopilotAccess: true,
    aiEventDiscovery: true,
    aiEventRecommendations: true,
    aiChatSummaries: true,
    aiListingGenerator: true,
    aiSmartFeed: true,
    aiMeetupMatchmaker: true,
    // Community Q&A -- unlimited
    maxQuestionsPerWeek: 999,
    communityBadgesEnabled: true,
    maxBookmarksPerMonth: 999,
    aiSynthesisAccess: true,
  );

  static TierLimits forTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.explorer:
        return explorer;
      case SubscriptionTier.neighbourhood:
        return neighbourhood;
      case SubscriptionTier.innerCircle:
        return innerCircle;
    }
  }

  /// Whether a value is effectively "unlimited"
  static bool isUnlimited(int val) => val >= 999;
}

/// Plan pricing info
class SubscriptionPlan {
  final SubscriptionTier tier;
  final String name;
  final String tagline;
  final String subtitle;
  final double monthlyPrice;
  final double annualPrice;
  final double? foundingMonthlyPrice; // locked rate for first 500
  final TierLimits limits;
  final List<String> highlights;
  final List<String> shortBenefits; // for upgrade prompt previews

  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.tagline,
    required this.subtitle,
    required this.monthlyPrice,
    required this.annualPrice,
    this.foundingMonthlyPrice,
    required this.limits,
    required this.highlights,
    required this.shortBenefits,
  });

  double priceFor(BillingPeriod period) =>
      period == BillingPeriod.monthly ? monthlyPrice : annualPrice;

  double get annualMonthlySavings =>
      (monthlyPrice * 12 - annualPrice) / 12;

  int get annualSavingsPercent =>
      monthlyPrice > 0
          ? ((monthlyPrice * 12 - annualPrice) / (monthlyPrice * 12) * 100)
              .round()
          : 0;

  static const List<SubscriptionPlan> allPlans = [
    // ---- EXPLORER (Free) --------------------------------------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.explorer,
      name: 'Explorer',
      tagline: 'Discover your local parent community',
      subtitle: 'Free forever',
      monthlyPrice: 0,
      annualPrice: 0,
      limits: TierLimits.explorer,
      highlights: [
        'Join up to 2 local groups',
        'Create 1 group',
        'Attend 2 meetups/month',
        '5 direct conversations',
        '2 marketplace listings',
        '30 messages/month',
        'AI Copilot (3 chats/day)',
        'AI event discovery (weekly)',
        'Basic smart feed',
        'Ask Parents Q&A (3 questions/week)',
        'Browse offers & community tips',
      ],
      shortBenefits: [
        '2 groups, 5 DMs, 2 meetups/mo',
        'Basic AI features',
        'Community Q&A + offers',
      ],
    ),

    // ---- NEIGHBOURHOOD (GBP 5.99/mo | GBP 49.99/yr) ----------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.neighbourhood,
      name: 'Neighbourhood',
      tagline: 'Your full community + AI, unlocked',
      subtitle: 'Less than 2 coffees a month',
      monthlyPrice: 5.99,
      annualPrice: 49.99,
      foundingMonthlyPrice: 3.99,
      limits: TierLimits.neighbourhood,
      highlights: [
        'Unlimited groups & messaging',
        'Create up to 25 groups',
        'Unlimited meetups & DMs',
        'Create private groups & meetups',
        'Ad-free experience',
        'Neighbourhood member badge',
        'AI Copilot (25 chats/day)',
        'AI Chat Summaries (10/day)',
        'AI Listing Generator (10/mo)',
        'Daily AI event discovery',
        'Unlimited smart feed',
        'Up to 15 photo uploads',
        'Child milestone tracker',
        'Ask Parents Q&A (15 questions/week)',
        'AI answer synthesis',
        'Community badges & leaderboard',
        '50 bookmarks/month',
      ],
      shortBenefits: [
        'Unlimited groups, DMs & meetups',
        'Full AI suite + community Q&A',
        'Ad-free + badges + milestone tracker',
      ],
    ),

    // ---- INNER CIRCLE (GBP 11.99/mo | GBP 99.99/yr) ----------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.innerCircle,
      name: 'Inner Circle',
      tagline: 'Lead your community with AI superpowers',
      subtitle: 'For active community builders',
      monthlyPrice: 11.99,
      annualPrice: 99.99,
      limits: TierLimits.innerCircle,
      highlights: [
        'Everything in Neighbourhood',
        'Unlimited group creation',
        'Unlimited marketplace listings',
        'Unlimited AI Copilot',
        'AI Meetup Matchmaker',
        'Unlimited AI Chat Summaries',
        'Unlimited AI Listing Generator',
        'Up to 50 photo uploads',
        'Inner Circle badge',
        'Unlimited Ask Parents Q&A',
        'Unlimited bookmarks & AI synthesis',
      ],
      shortBenefits: [
        'Everything in Neighbourhood',
        'Unlimited AI + Matchmaker + Q&A',
        'Unlimited listings & 50 photos',
      ],
    ),
  ];
}

/// Active subscription state
class UserSubscription {
  final SubscriptionTier tier;
  final BillingPeriod billingPeriod;
  final DateTime startDate;
  final DateTime? renewalDate;
  final bool isActive;
  final bool isTrial;
  final int trialDaysRemaining;
  final bool isFoundingMember;

  const UserSubscription({
    required this.tier,
    required this.billingPeriod,
    required this.startDate,
    this.renewalDate,
    this.isActive = true,
    this.isTrial = false,
    this.trialDaysRemaining = 0,
    this.isFoundingMember = false,
  });

  TierLimits get limits => TierLimits.forTier(tier);

  bool get isExplorer => tier == SubscriptionTier.explorer;
  bool get isNeighbourhood => tier == SubscriptionTier.neighbourhood;
  /// Backward-compat alias
  bool get isVillage => isNeighbourhood;
  bool get isInnerCircle => tier == SubscriptionTier.innerCircle;
  bool get isFree => tier == SubscriptionTier.explorer;
  bool get isPaid => !isFree;

  String get tierDisplayName {
    switch (tier) {
      case SubscriptionTier.explorer:
        return 'Explorer';
      case SubscriptionTier.neighbourhood:
        return 'Huddl Neighbourhood';
      case SubscriptionTier.innerCircle:
        return 'Inner Circle';
    }
  }

  String get tierShortName {
    switch (tier) {
      case SubscriptionTier.explorer:
        return 'Explorer';
      case SubscriptionTier.neighbourhood:
        return 'Neighbourhood';
      case SubscriptionTier.innerCircle:
        return 'Inner Circle';
    }
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'billingPeriod': billingPeriod.name,
        'startDate': startDate.toIso8601String(),
        'renewalDate': renewalDate?.toIso8601String(),
        'isActive': isActive,
        'isTrial': isTrial,
        'trialDaysRemaining': trialDaysRemaining,
        'isFoundingMember': isFoundingMember,
      };

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    // Handle migration from old tier names
    String tierName = json['tier'] as String? ?? 'explorer';
    if (tierName == 'free') tierName = 'explorer';
    if (tierName == 'plus') tierName = 'neighbourhood';
    if (tierName == 'village') tierName = 'neighbourhood';
    if (tierName == 'pro') tierName = 'innerCircle';

    return UserSubscription(
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => SubscriptionTier.explorer,
      ),
      billingPeriod: BillingPeriod.values.firstWhere(
        (b) => b.name == json['billingPeriod'],
        orElse: () => BillingPeriod.monthly,
      ),
      startDate: DateTime.parse(json['startDate'] as String),
      renewalDate: json['renewalDate'] != null
          ? DateTime.parse(json['renewalDate'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
      isTrial: json['isTrial'] as bool? ?? false,
      trialDaysRemaining: json['trialDaysRemaining'] as int? ?? 0,
      isFoundingMember: json['isFoundingMember'] as bool? ?? false,
    );
  }

  /// Default free subscription
  factory UserSubscription.explorer() => UserSubscription(
        tier: SubscriptionTier.explorer,
        billingPeriod: BillingPeriod.monthly,
        startDate: DateTime.now(),
        isActive: true,
      );
}
