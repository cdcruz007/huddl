// =====================================================================================
// HUDDL CONNECT -- SUBSCRIPTION MODEL
// =====================================================================================
//
// THREE TIERS:
//
// 1. WELCOME (Free) — "Try the community"
//    Tight but meaningful limits so new users experience real value within
//    the first few days before hitting a natural upgrade prompt.
//
// 2. NEIGHBOUR (£5.99/mo | £49.99/yr) — "Full community access"
//    Removes all social friction — unlimited groups, DMs, and meetups.
//    Unlocks the full AI suite: AI Chat Helper, AI Listing Writer,
//    Daily Events Finder, and AI Group Summaries.
//
// 3. CIRCLE (£12.99/mo | £99.99/yr) — "Lead your community"
//    Everything in Neighbour, plus truly unlimited AI usage,
//    AI Meetup Matchmaker, unlimited listings, and 50 photo uploads.
//
// NOTE: No founding member / promotional pricing offered.
// =====================================================================================

/// Subscription tier levels for Huddl Connect
enum SubscriptionTier { explorer, neighbourhood, innerCircle }

/// Billing period
enum BillingPeriod { monthly, annual }

/// Feature limits per tier
class TierLimits {
  // ---- Core Social Limits ----
  final int maxGroups;           // how many groups a user can join
  final int maxGroupsCreated;    // how many groups a user can create
  final int maxMeetupsPerMonth;  // meetups user can attend per month
  final int maxDMConversations;  // open DM threads at once
  final int maxMarketplaceListings;
  final int maxPhotoUploads;     // photos that can be uploaded in total
  final int maxMessagesPerMonth; // messages sent across all chats

  // ---- Core Social Booleans ----
  final bool canCreatePrivateGroups;
  final bool canCreateMeetups;
  final bool customProfileBadge;

  // ---- AI Feature Limits ----
  final int maxAiCopilotChatsPerDay;           // AI Chat Helper sessions/day
  final int maxAiEventDiscoveriesPerWeek;      // AI-found local events/week
  final int maxAiChatSummariesPerDay;          // AI group summaries/day
  final int maxAiListingGenerationsPerMonth;   // AI listing drafts/month
  final int maxAiMatchmakerRequestsPerMonth;   // AI meetup suggestions/month
  final int maxAiSmartFeedRefreshesPerDay;     // personalised feed refreshes/day

  // ---- AI Feature Booleans ----
  final bool aiCopilotAccess;
  final bool aiEventDiscovery;
  final bool aiEventRecommendations;
  final bool aiChatSummaries;
  final bool aiListingGenerator;
  final bool aiSmartFeed;
  final bool aiMeetupMatchmaker;

  // ---- Community Q&A & Bookmarks ----
  final int maxQuestionsPerWeek;   // questions posted to community Q&A board
  final int maxBookmarksPerMonth;  // messages/posts saved to bookmarks
  final bool communityBadgesEnabled;
  final bool aiSynthesisAccess;    // AI-generated answer summaries in Q&A

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
    required this.customProfileBadge,
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

  // ---- WELCOME (Free) -----------------------------------------------------------
  // Enough to genuinely engage — 2 groups, attend meetups, send DMs, list items.
  // AI features are taster-level: 3 AI chats/day and weekly events discovery.
  static const TierLimits explorer = TierLimits(
    maxGroups: 2,
    maxGroupsCreated: 1,
    maxMeetupsPerMonth: 2,
    maxDMConversations: 5,
    maxMarketplaceListings: 2,
    maxPhotoUploads: 3,
    maxMessagesPerMonth: 30,
    canCreatePrivateGroups: false,
    canCreateMeetups: false,
    customProfileBadge: false,
    maxAiCopilotChatsPerDay: 3,
    maxAiEventDiscoveriesPerWeek: 1,
    maxAiChatSummariesPerDay: 0,
    maxAiListingGenerationsPerMonth: 0,
    maxAiMatchmakerRequestsPerMonth: 0,
    maxAiSmartFeedRefreshesPerDay: 2,
    aiCopilotAccess: true,
    aiEventDiscovery: true,
    aiEventRecommendations: false,
    aiChatSummaries: false,
    aiListingGenerator: false,
    aiSmartFeed: true,
    aiMeetupMatchmaker: false,
    maxQuestionsPerWeek: 3,
    communityBadgesEnabled: false,
    maxBookmarksPerMonth: 10,
    aiSynthesisAccess: false,
  );

  // ---- NEIGHBOUR (£5.99/mo) -----------------------------------------------------
  // Full social access + complete AI suite at generous daily/monthly limits.
  static const TierLimits neighbourhood = TierLimits(
    maxGroups: 999,
    maxGroupsCreated: 25,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 15,
    maxPhotoUploads: 15,
    maxMessagesPerMonth: 999,
    canCreatePrivateGroups: true,
    canCreateMeetups: true,
    customProfileBadge: true,
    maxAiCopilotChatsPerDay: 25,
    maxAiEventDiscoveriesPerWeek: 7,
    maxAiChatSummariesPerDay: 10,
    maxAiListingGenerationsPerMonth: 10,
    maxAiMatchmakerRequestsPerMonth: 0,
    maxAiSmartFeedRefreshesPerDay: 999,
    aiCopilotAccess: true,
    aiEventDiscovery: true,
    aiEventRecommendations: true,
    aiChatSummaries: true,
    aiListingGenerator: true,
    aiSmartFeed: true,
    aiMeetupMatchmaker: false,
    maxQuestionsPerWeek: 15,
    communityBadgesEnabled: true,
    maxBookmarksPerMonth: 50,
    aiSynthesisAccess: true,
  );

  // ---- CIRCLE (£12.99/mo) -------------------------------------------------------
  // Everything in Neighbour + unlimited AI, AI Meetup Matchmaker, unlimited listings.
  static const TierLimits innerCircle = TierLimits(
    maxGroups: 999,
    maxGroupsCreated: 999,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 999,
    maxPhotoUploads: 50,
    maxMessagesPerMonth: 999,
    canCreatePrivateGroups: true,
    canCreateMeetups: true,
    customProfileBadge: true,
    maxAiCopilotChatsPerDay: 999,
    maxAiEventDiscoveriesPerWeek: 999,
    maxAiChatSummariesPerDay: 999,
    maxAiListingGenerationsPerMonth: 999,
    maxAiMatchmakerRequestsPerMonth: 999,
    maxAiSmartFeedRefreshesPerDay: 999,
    aiCopilotAccess: true,
    aiEventDiscovery: true,
    aiEventRecommendations: true,
    aiChatSummaries: true,
    aiListingGenerator: true,
    aiSmartFeed: true,
    aiMeetupMatchmaker: true,
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
    // ---- WELCOME (Free) ---------------------------------------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.explorer,
      name: 'Welcome',
      tagline: 'Try Huddl with your local parent community',
      subtitle: 'Free forever — no card required',
      monthlyPrice: 0,
      annualPrice: 0,
      limits: TierLimits.explorer,
      highlights: [
        'Join up to 2 local parent groups',
        'Create 1 group of your own',
        'Attend up to 2 meetups per month',
        'Message up to 5 other parents directly',
        'Post up to 2 items on the marketplace',
        'Send up to 30 messages per month',
        'Upload up to 3 photos',
        'Ask up to 3 questions on the community Q&A board per week',
        'Save up to 10 posts or messages to bookmarks',
        'AI Chat Helper — 3 conversations per day',
        'AI Events Finder — discover 1 local event per week',
        'Personalised home feed (2 refreshes per day)',
      ],
      shortBenefits: [
        'Join 2 groups, message 5 parents, attend 2 meetups/mo',
        'AI Chat Helper (3/day) + weekly events discovery',
        'Community Q&A board + marketplace listings',
      ],
    ),

    // ---- NEIGHBOUR (£5.99/mo | £49.99/yr) --------------------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.neighbourhood,
      name: 'Neighbour',
      tagline: 'Full community access with AI tools',
      subtitle: 'Less than 2 coffees a month',
      monthlyPrice: 5.99,
      annualPrice: 49.99,
      limits: TierLimits.neighbourhood,
      highlights: [
        'Join unlimited local parent groups',
        'Create up to 25 groups — including private, invite-only groups',
        'Attend unlimited meetups and organise your own',
        'Message any parent directly — unlimited conversations',
        'Send unlimited messages across all groups and chats',
        'Post up to 15 items for sale or free on the marketplace',
        'Upload up to 15 photos across all your posts',
        'Neighbour profile badge visible to your community',
        'AI Chat Helper — 25 conversations per day',
        'AI Group Summaries — catch up on missed chat in one tap (10/day)',
        'AI Listing Writer — AI drafts your marketplace listings (10/month)',
        'AI Events Finder — discover new local events every day',
        'Personalised home feed with unlimited daily refreshes',
        'Ask up to 15 questions on the community Q&A board per week',
        'AI-generated answer summaries on Q&A (synthesises top replies)',
        'Save up to 50 posts or messages to bookmarks per month',
        'Community badges for participation milestones',
      ],
      shortBenefits: [
        'Unlimited groups, DMs, meetups & messaging',
        'Full AI suite — Chat Helper, Summaries, Listing Writer & Events',
        'Community Q&A with AI summaries + 50 bookmarks/month',
      ],
    ),

    // ---- CIRCLE (£12.99/mo | £99.99/yr) ----------------------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.innerCircle,
      name: 'Circle',
      tagline: 'Lead your community with unlimited AI',
      subtitle: 'For active community builders',
      monthlyPrice: 12.99,
      annualPrice: 99.99,
      limits: TierLimits.innerCircle,
      highlights: [
        'Everything included in the Neighbour plan',
        'Create unlimited groups — no cap on group creation',
        'Post unlimited items on the marketplace',
        'Upload up to 50 photos across your posts',
        'Circle profile badge — exclusive to top-tier members',
        'AI Chat Helper — unlimited conversations per day',
        'AI Group Summaries — unlimited, catch up on any chat instantly',
        'AI Listing Writer — unlimited marketplace listing drafts',
        'AI Events Finder — unlimited daily local event discovery',
        'AI Meetup Matchmaker — AI suggests the best local meetups for you based on your interests and location',
        'Unlimited home feed personalisation',
        'Ask unlimited questions on the community Q&A board',
        'Unlimited AI-generated answer summaries on Q&A',
        'Save unlimited posts and messages to bookmarks',
      ],
      shortBenefits: [
        'Everything in Neighbour, fully unlimited',
        'AI Meetup Matchmaker + unlimited AI tools',
        'Unlimited listings, 50 photos & unlimited bookmarks',
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

  // ── Scheduled plan change (upgrade / downgrade) ─────────────────────
  final SubscriptionTier? scheduledTier;
  final BillingPeriod? scheduledPeriod;

  // ── Pending cancellation ────────────────────────────────────────────
  final bool cancelledAtPeriodEnd;

  const UserSubscription({
    required this.tier,
    required this.billingPeriod,
    required this.startDate,
    this.renewalDate,
    this.isActive = true,
    this.isTrial = false,
    this.trialDaysRemaining = 0,
    this.scheduledTier,
    this.scheduledPeriod,
    this.cancelledAtPeriodEnd = false,
  });

  TierLimits get limits => TierLimits.forTier(tier);

  bool get isExplorer => tier == SubscriptionTier.explorer;
  bool get isNeighbourhood => tier == SubscriptionTier.neighbourhood;
  /// Backward-compat alias
  bool get isVillage => isNeighbourhood;
  bool get isInnerCircle => tier == SubscriptionTier.innerCircle;
  bool get isFree => tier == SubscriptionTier.explorer;
  bool get isPaid => !isFree;
  // Legacy compat — no founding members
  bool get isFoundingMember => false;

  bool get hasScheduledChange => scheduledTier != null;
  bool get isPendingCancellation => cancelledAtPeriodEnd && isActive;

  int get daysUntilRenewal {
    if (renewalDate == null) return 0;
    final diff = renewalDate!.difference(DateTime.now()).inDays;
    return diff.clamp(0, 365);
  }

  String? get scheduledChangeSummary {
    if (cancelledAtPeriodEnd) {
      return 'Cancels on ${_formatDate(renewalDate)}';
    }
    if (scheduledTier != null) {
      final name = _tierDisplayName(scheduledTier!);
      final periodLabel = scheduledPeriod == BillingPeriod.annual
          ? 'annual'
          : 'monthly';
      return 'Changing to $name ($periodLabel) on ${_formatDate(renewalDate)}';
    }
    return null;
  }

  // ignore: library_private_types_in_public_api
  static String formatDate(DateTime? d) => _formatDate(d);

  static String _tierDisplayName(SubscriptionTier t) {
    switch (t) {
      case SubscriptionTier.explorer:
        return 'Welcome';
      case SubscriptionTier.neighbourhood:
        return 'Neighbour';
      case SubscriptionTier.innerCircle:
        return 'Circle';
    }
  }

  static String _formatDate(DateTime? d) {
    if (d == null) return 'end of period';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get tierDisplayName {
    switch (tier) {
      case SubscriptionTier.explorer:
        return 'Welcome';
      case SubscriptionTier.neighbourhood:
        return 'Neighbour';
      case SubscriptionTier.innerCircle:
        return 'Circle';
    }
  }

  String get tierShortName => tierDisplayName;

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'billingPeriod': billingPeriod.name,
        'startDate': startDate.toIso8601String(),
        'renewalDate': renewalDate?.toIso8601String(),
        'isActive': isActive,
        'isTrial': isTrial,
        'trialDaysRemaining': trialDaysRemaining,
        'scheduledTier': scheduledTier?.name,
        'scheduledPeriod': scheduledPeriod?.name,
        'cancelledAtPeriodEnd': cancelledAtPeriodEnd,
      };

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    // Handle migration from old tier names
    String tierName = json['tier'] as String? ?? 'explorer';
    if (tierName == 'free') tierName = 'explorer';
    if (tierName == 'plus') tierName = 'neighbourhood';
    if (tierName == 'village') tierName = 'neighbourhood';
    if (tierName == 'pro') tierName = 'innerCircle';
    if (tierName == 'welcome') tierName = 'explorer';
    if (tierName == 'neighbour') tierName = 'neighbourhood';
    if (tierName == 'circle') tierName = 'innerCircle';

    SubscriptionTier? schedTier;
    final schedTierName = json['scheduledTier'] as String?;
    if (schedTierName != null) {
      schedTier = SubscriptionTier.values.firstWhere(
        (t) => t.name == schedTierName,
        orElse: () => SubscriptionTier.explorer,
      );
    }

    BillingPeriod? schedPeriod;
    final schedPeriodName = json['scheduledPeriod'] as String?;
    if (schedPeriodName != null) {
      schedPeriod = BillingPeriod.values.firstWhere(
        (b) => b.name == schedPeriodName,
        orElse: () => BillingPeriod.monthly,
      );
    }

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
      scheduledTier: schedTier,
      scheduledPeriod: schedPeriod,
      cancelledAtPeriodEnd: json['cancelledAtPeriodEnd'] as bool? ?? false,
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
