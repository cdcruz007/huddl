// =====================================================================================
// HUDDL -- SUBSCRIPTION MODEL
// =====================================================================================
//
// THREE TIERS (user-facing):
//
// 1. WELCOME (Free) — "Discover your parent community"
//    Meaningful taster limits across every feature — enough to get value,
//    tight enough to motivate upgrade.
//
// 2. HUDDL PLUS (£4.99/mo | £39.99/yr) — "Full community access"
//    Removes all friction — unlimited everything. Full AI suite.
//    60-day listing duration. Own a service listing (with verification).
//
// 3. HUDDL PARTNER (£24.99/mo | £199.00/yr) — "Grow your local business"
//    Dedicated business profile, unlimited service listings, priority
//    directory placement, endorsement replies, reach analytics, and
//    promoted cards in the borough feed. Requires business verification.
//
// =====================================================================================

/// Subscription tier levels for Huddl
enum SubscriptionTier { welcome, plus, partner }

/// Billing period
enum BillingPeriod { monthly, annual }

/// Feature limits per tier
class TierLimits {
  // ---- Core Social Limits ----
  final int maxGroups;           // how many groups a user can join
  final int maxGroupsCreated;    // how many groups a user can create (legacy field)
  final int maxMeetupsPerMonth;  // meetups user can attend per month
  final int maxDMConversations;  // open DM threads at once
  final int maxMarketplaceListings;  // legacy field — new gate uses maxListingsCreatedLifetime
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

  // ---- Community Q&A & Bookmarks (legacy fields — kept for backward compat) ----
  final int maxQuestionsPerWeek;   // legacy — new gate uses maxQuestionsLifetime
  final int maxBookmarksPerMonth;  // legacy — new gate uses maxSavedItemsLifetime
  final bool communityBadgesEnabled;
  final bool aiSynthesisAccess;    // AI-generated answer summaries in Q&A

  // ── Lifetime gates — free tier only (999 = unlimited on paid tiers) ───────────
  final int maxListingsCreatedLifetime;   // marketplace listings ever created
  final int maxBuyerContactsLifetime;     // seller message + offer attempts combined
  final int maxUserCreatedGroupsLifetime; // public hobby/interest groups created
  final int maxFreeMeetupsLifetime;       // free (non-paid) meetups created
  final int maxPollsCreatedLifetime;      // polls created across all groups
  final int maxQuestionsLifetime;         // Q&A questions posted
  final int maxSavedItemsLifetime;        // saved messages + posts + listings combined
  final int maxAiSavedSummariesLifetime;  // AI summaries of saved items

  // ── Listing duration ──────────────────────────────────────────────────────────
  final int listingDurationDays; // 7 free, 60 Plus, 999 (unlimited) Partner

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
    // Community Q&A (legacy defaults)
    this.maxQuestionsPerWeek = 3,
    this.communityBadgesEnabled = false,
    this.maxBookmarksPerMonth = 5,
    this.aiSynthesisAccess = false,
    // Lifetime gates — default unlimited
    this.maxListingsCreatedLifetime = 999,
    this.maxBuyerContactsLifetime = 999,
    this.maxUserCreatedGroupsLifetime = 999,
    this.maxFreeMeetupsLifetime = 999,
    this.maxPollsCreatedLifetime = 999,
    this.maxQuestionsLifetime = 999,
    this.maxSavedItemsLifetime = 999,
    this.maxAiSavedSummariesLifetime = 999,
    this.listingDurationDays = 999,
  });

  // ---- WELCOME (Free) -----------------------------------------------------------
  // Taster limits: enough to get genuine value, tight enough to upgrade.
  static const TierLimits welcome = TierLimits(
    // ── Core social (legacy fields — kept for backward compat) ──
    maxGroups: 999,             // join unlimited groups
    maxGroupsCreated: 999,      // legacy — new gate uses maxUserCreatedGroupsLifetime
    maxMeetupsPerMonth: 999,    // attending meetups is unlimited
    maxDMConversations: 999,    // DMs unlimited
    maxMarketplaceListings: 999, // legacy — new gate uses maxListingsCreatedLifetime
    // Photo cap is intentionally unlimited on free — free users are capped
    // to 3 lifetime listings anyway, so photo volume is naturally low.
    // Do NOT reduce this: it would break free users' existing uploads.
    maxPhotoUploads: 999,
    maxMessagesPerMonth: 999,
    canCreatePrivateGroups: false,
    canCreateMeetups: true,
    customProfileBadge: false,
    // ── AI feature limits ──
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
    maxQuestionsPerWeek: 999,   // legacy unlimited
    communityBadgesEnabled: false,
    maxBookmarksPerMonth: 999,  // legacy unlimited
    aiSynthesisAccess: false,
    // ── Lifetime gates ──
    maxListingsCreatedLifetime: 3,
    maxBuyerContactsLifetime: 3,
    maxUserCreatedGroupsLifetime: 3,
    maxFreeMeetupsLifetime: 3,
    maxPollsCreatedLifetime: 3,
    maxQuestionsLifetime: 3,
    maxSavedItemsLifetime: 6,
    maxAiSavedSummariesLifetime: 2,
    listingDurationDays: 7,
  );

  // ---- HUDDL PLUS (£4.99/mo) ---------------------------------------------------
  // Full social access + complete AI suite at generous daily/monthly limits.
  static const TierLimits plus = TierLimits(
    maxGroups: 999,
    maxGroupsCreated: 999,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 999,
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
    // ── Lifetime gates — unlimited for Plus ──
    maxListingsCreatedLifetime: 999,
    maxBuyerContactsLifetime: 999,
    maxUserCreatedGroupsLifetime: 999,
    maxFreeMeetupsLifetime: 999,
    maxPollsCreatedLifetime: 999,
    maxQuestionsLifetime: 999,
    maxSavedItemsLifetime: 999,
    maxAiSavedSummariesLifetime: 999,
    listingDurationDays: 60,
  );

  // ---- PARTNER (£24.99/mo | £199.00/yr) ----------------------------------------
  // All community limits identical to Plus; adds business features.
  static const TierLimits partner = TierLimits(
    maxGroups: 999, maxGroupsCreated: 999, maxMeetupsPerMonth: 999,
    maxDMConversations: 999, maxMarketplaceListings: 999, maxPhotoUploads: 50,
    maxMessagesPerMonth: 999, canCreatePrivateGroups: true, canCreateMeetups: true,
    customProfileBadge: true,
    maxAiCopilotChatsPerDay: 999, maxAiEventDiscoveriesPerWeek: 999,
    maxAiChatSummariesPerDay: 999, maxAiListingGenerationsPerMonth: 999,
    maxAiMatchmakerRequestsPerMonth: 999, maxAiSmartFeedRefreshesPerDay: 999,
    aiCopilotAccess: true, aiEventDiscovery: true, aiEventRecommendations: true,
    aiChatSummaries: true, aiListingGenerator: true, aiSmartFeed: true,
    aiMeetupMatchmaker: true,
    maxQuestionsPerWeek: 999, communityBadgesEnabled: true,
    maxBookmarksPerMonth: 999, aiSynthesisAccess: true,
    // ── Lifetime gates — unlimited for Partner ──
    maxListingsCreatedLifetime: 999,
    maxBuyerContactsLifetime: 999,
    maxUserCreatedGroupsLifetime: 999,
    maxFreeMeetupsLifetime: 999,
    maxPollsCreatedLifetime: 999,
    maxQuestionsLifetime: 999,
    maxSavedItemsLifetime: 999,
    maxAiSavedSummariesLifetime: 999,
    listingDurationDays: 999,
  );

  static TierLimits forTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.welcome:
        return welcome;
      case SubscriptionTier.plus:
        return plus;
      case SubscriptionTier.partner:
        return partner;
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

    // ── FREE ──────────────────────────────────────────────────────────────────
    SubscriptionPlan(
      tier: SubscriptionTier.welcome,
      name: 'Huddl',
      tagline: 'Discover your parent community',
      subtitle: 'Free forever — no card required',
      monthlyPrice: 0,
      annualPrice: 0,
      limits: TierLimits.welcome,
      highlights: [
        'Join your year-of-birth Cambridge parents group automatically',
        'Join unlimited local hobby and interest groups',
        'Message any parent directly — no limits',
        'Browse the full services directory and read endorsements',
        'Create up to 3 marketplace listings (7-day duration)',
        'Buy from 3 sellers — contact and make offers',
        'Create up to 3 public hobby groups',
        'Create up to 3 free community meetups',
        'Create up to 3 group polls',
        'Ask up to 3 community Q&A questions',
        'Save up to 6 recommendations, posts or listings',
        'AI Chat Helper — 3 conversations per day',
        'AI Events Finder — 1 local event per week',
        'Personalised home feed',
      ],
      shortBenefits: [
        'Your Cambridge parents group — automatic on joining',
        'Message parents, browse services & join groups — unlimited',
        'Marketplace, groups, meetups & Q\u0026A — up to 3 each',
      ],
    ),

    // ── PLUS ──────────────────────────────────────────────────────────────────
    SubscriptionPlan(
      tier: SubscriptionTier.plus,
      name: 'Huddl Plus',
      tagline: 'Full access — marketplace, services and community',
      subtitle: 'Less than 2 coffees a month',
      monthlyPrice: 4.99,
      annualPrice: 39.99,
      limits: TierLimits.plus,
      highlights: [
        'Unlimited marketplace listings — 60-day duration',
        'Contact any seller — unlimited messages and offers',
        'Contact any service provider directly — childminders, tutors, classes',
        'Create unlimited public and private groups',
        'Create unlimited polls and free meetups',
        'Create paid meetups — cost-share with other parents',
        'Unlimited Q\u0026A questions + AI answer synthesis',
        'Unlimited saves + AI summary of your saved items',
        '1 free listing bump per week',
        'Full AI suite — Chat Helper (25/day), Summaries (10/day), Listing Writer (10/month), Events (7/week)',
        'Neighbourhood badge on your profile',
        'Community badges unlocked',
        'Own a service listing — verified businesses (see verification)',
      ],
      shortBenefits: [
        'Unlimited listings, contacts & service provider access',
        'Unlimited groups, polls, meetups & Q\u0026A',
        'Full AI suite + unlimited saves',
      ],
    ),

    // ── PARTNER ───────────────────────────────────────────────────────────────
    SubscriptionPlan(
      tier: SubscriptionTier.partner,
      name: 'Huddl Partner',
      tagline: 'Reach local parents as customers',
      subtitle: 'For local businesses and service providers',
      monthlyPrice: 24.99,
      annualPrice: 199.00,
      limits: TierLimits.partner,
      highlights: [
        'Everything in Huddl Plus — fully unlimited',
        'Dedicated business profile page — separate from personal profile',
        'Unlimited service listings — nurseries, classes, multiple offerings',
        'Priority pinned placement in the borough service directory',
        'HMRC-verified Partner badge on all listings',
        'Promoted cards in the borough home feed (1:7 ratio)',
        '1 free promoted event slot per month',
        'Respond publicly to parent endorsements on your listings',
        'Reach analytics — impressions, profile views, booking link clicks',
        'External booking URL on all listings',
        'Post as your verified business on the noticeboard',
        'AI Meetup Matchmaker — find compatible parents nearby',
      ],
      shortBenefits: [
        'Business profile + unlimited listings + priority directory placement',
        'Borough feed promotion + endorsement replies + reach analytics',
        'All Plus features unlimited + AI Matchmaker',
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
    this.scheduledTier,
    this.scheduledPeriod,
    this.cancelledAtPeriodEnd = false,
  });

  TierLimits get limits => TierLimits.forTier(tier);

  bool get isWelcome => tier == SubscriptionTier.welcome;
  bool get isPlus => tier == SubscriptionTier.plus;
  bool get isPartner => tier == SubscriptionTier.partner;
  bool get isFree => tier == SubscriptionTier.welcome;
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
      case SubscriptionTier.welcome:
        return 'Welcome';
      case SubscriptionTier.plus:
        return 'Huddl Plus';
      case SubscriptionTier.partner:
        return 'Huddl Partner';
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
      case SubscriptionTier.welcome:
        return 'Welcome';
      case SubscriptionTier.plus:
        return 'Huddl Plus';
      case SubscriptionTier.partner:
        return 'Huddl Partner';
    }
  }


  String get tierShortName => tierDisplayName;

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'billingPeriod': billingPeriod.name,
        'startDate': startDate.toIso8601String(),
        'renewalDate': renewalDate?.toIso8601String(),
        'isActive': isActive,
        'scheduledTier': scheduledTier?.name,
        'scheduledPeriod': scheduledPeriod?.name,
        'cancelledAtPeriodEnd': cancelledAtPeriodEnd,
      };

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    // ── Normalise legacy Firestore tier strings → canonical 3-tier values ──────
    String tierName = json['tier'] as String? ?? 'welcome';
    // All legacy free names → welcome
    const _toWelcome = ['free', 'explorer'];
    if (_toWelcome.contains(tierName)) tierName = 'welcome';
    // All legacy Plus names → plus
    const _toPlus = ['neighbourhood', 'village', 'neighbour'];
    if (_toPlus.contains(tierName)) tierName = 'plus';
    // All legacy paid names → plus (innerCircle was a Plus-equivalent)
    const _toLegacyPlus = ['pro', 'circle', 'innerCircle'];
    if (_toLegacyPlus.contains(tierName)) tierName = 'plus';
    // Canonical names pass through unchanged: 'welcome', 'plus', 'partner'

    SubscriptionTier? schedTier;
    final schedTierName = json['scheduledTier'] as String?;
    if (schedTierName != null) {
      schedTier = SubscriptionTier.values.firstWhere(
        (t) => t.name == schedTierName,
        orElse: () => SubscriptionTier.welcome,
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
        orElse: () => SubscriptionTier.welcome,
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
      scheduledTier: schedTier,
      scheduledPeriod: schedPeriod,
      cancelledAtPeriodEnd: json['cancelledAtPeriodEnd'] as bool? ?? false,
    );
  }

  /// Default free subscription
  factory UserSubscription.welcome() => UserSubscription(
        tier: SubscriptionTier.welcome,
        billingPeriod: BillingPeriod.monthly,
        startDate: DateTime.now(),
        isActive: true,
      );

}
