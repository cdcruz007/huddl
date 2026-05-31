// =====================================================================================
// HUDDL -- SUBSCRIPTION MODEL
// =====================================================================================
//
// FOUR TIERS:
//
// 1. WELCOME (Free) — "Try the community"
//    Tight but meaningful limits so new users experience real value within
//    the first few days before hitting a natural upgrade prompt.
//
// 2. PLUS (£4.99/mo | £39.99/yr) — "Full community access"
//    Removes all social friction — unlimited groups, DMs, and meetups.
//    Unlocks the full AI suite: AI Chat Helper, AI Listing Writer,
//    Daily Events Finder, and AI Group Summaries.
//
// 3. PARTNER (£24.99/mo | £199.00/yr) — "Grow your local business"
//    Dedicated business profile, unlimited service listings, priority
//    directory placement, endorsement replies, reach analytics, and
//    promoted cards in the borough feed. Requires business verification.
//
// NOTE: No founding member / promotional pricing offered.
// =====================================================================================

/// Subscription tier levels for Huddl
// ignore: constant_identifier_names
enum SubscriptionTier { welcome, plus, innerCircle, partner }
// NOTE: `innerCircle` is a deprecated Firestore backward-compat alias only.
// It is never shown to users and maps to Huddl Plus behaviour.

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
  static const TierLimits welcome = TierLimits(
    maxGroups: 999,            // unlimited — no group join cap on free
    maxGroupsCreated: 999,     // unlimited — free users can create groups
    maxMeetupsPerMonth: 999,   // unlimited — free users can create meetups
    maxDMConversations: 999,   // unlimited
    maxMarketplaceListings: 999, // unlimited
    maxPhotoUploads: 999,      // unlimited
    maxMessagesPerMonth: 999,  // unlimited
    canCreatePrivateGroups: false,
    canCreateMeetups: true,
    customProfileBadge: false,
    maxAiCopilotChatsPerDay: 3,          // AI still gated — upgrade incentive
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
    maxQuestionsPerWeek: 999,  // unlimited
    communityBadgesEnabled: false,
    maxBookmarksPerMonth: 999, // unlimited
    aiSynthesisAccess: false,
  );

  // ---- HUDDL PLUS (£4.99/mo) ---------------------------------------------------
  // Full social access + complete AI suite at generous daily/monthly limits.
  static const TierLimits plus = TierLimits(
    maxGroups: 999,
    maxGroupsCreated: 25,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 999, // unlimited for Plus
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

  // ---- CIRCLE (legacy — kept for backward-compat; maps to innerCircle) ----------
  // Alias so existing code that references TierLimits.innerCircle still compiles.
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

  // ---- PARTNER (£24.99/mo | £199.00/yr) ------------------------------------------
  // All limits identical to innerCircle — Partner subscribers get full community
  // access in addition to business-specific features.
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
  );

  static TierLimits forTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.welcome:
        return welcome;
      case SubscriptionTier.plus:
        return plus;
      case SubscriptionTier.innerCircle:
        return innerCircle; // deprecated alias → Plus behaviour
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
    // ---- WELCOME (Free) ---------------------------------------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.welcome,
      name: 'Huddl',
      tagline: 'Join your local community',
      subtitle: 'Start connecting with Cambridge parents today',
      monthlyPrice: 0,
      annualPrice: 0,
      limits: TierLimits.welcome,
      highlights: [
        'Join every local group in Cambridge',
        'Message other parents in your borough',
        'Browse and post to the preloved market',
        'Discover local meetups and family events',
        '3 AI parenting Q&A sessions per day',
      ],
      shortBenefits: [
        'Free, always',
        'Local groups and market',
        'Discover nearby meetups',
      ],
    ),

    // ---- HUDDL PLUS (£4.99/mo | £39.99/yr) ---------------------------------------
    SubscriptionPlan(
      tier: SubscriptionTier.plus,
      name: 'Huddl Plus',
      tagline: 'Your full community, fully unlocked',
      subtitle: 'Everything Cambridge parents need, nothing held back',
      monthlyPrice: 4.99,
      annualPrice: 39.99,
      limits: TierLimits.plus,
      highlights: [
        'Every parent conversation in Cambridge — nothing blocked',
        'AI finds the Sunday walk before you think to search',
        'List preloved gear in seconds — AI writes the description',
        'Group summaries catch you up on what you missed',
        'Your Huddl Plus badge on your profile',
        'Priority support from the huddl team',
      ],
      shortBenefits: [
        'Unlimited groups, DMs and meetups',
        'Full AI suite — copilot, listings, summaries',
        'Your Huddl Plus badge',
      ],
    ),

    // ---- PARTNER (£24.99/mo | £199.00/yr) – for local businesses ------------------
    SubscriptionPlan(
      tier: SubscriptionTier.partner,
      name: 'Huddl Partner',
      tagline: 'Grow your local business with huddl',
      subtitle: 'The trust of the community, working for your business',
      monthlyPrice: 24.99,
      annualPrice: 199.00,
      limits: TierLimits.partner,
      highlights: [
        'Verified business profile that Cambridge parents trust',
        'Priority placement in the local services directory',
        'Promoted cards in the borough community feed',
        'AI writes unlimited listings and service descriptions',
        'Reach analytics — see exactly who found you',
        'Respond publicly to parent endorsements',
        'All Huddl Plus community features included',
      ],
      shortBenefits: [
        'Verified business profile + priority directory',
        'Promoted in the community feed',
        'Reach analytics + endorsement replies',
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
  /// Deprecated Firestore alias — treated as Plus
  bool get isInnerCircle => tier == SubscriptionTier.innerCircle;
  bool get isPartner => tier == SubscriptionTier.partner;
  bool get isFree => tier == SubscriptionTier.welcome;
  // Legacy aliases — kept so callers don't break mid-rename
  bool get isExplorer => isWelcome;
  bool get isNeighbourhood => isPlus;
  bool get isVillage => isPlus;
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
      case SubscriptionTier.innerCircle:
        return 'Huddl Plus'; // deprecated alias → Plus display name
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
      case SubscriptionTier.innerCircle:
        return 'Huddl Plus'; // deprecated alias
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
    // ── Normalise legacy / old Firestore tier strings ──────────────────────────
    String tierName = json['tier'] as String? ?? 'welcome';
    // Old free-tier names → welcome
    if (tierName == 'free')        tierName = 'welcome';
    if (tierName == 'explorer')    tierName = 'welcome';
    // Old Plus-tier names → plus
    if (tierName == 'neighbourhood') tierName = 'plus';
    if (tierName == 'village')     tierName = 'plus';
    if (tierName == 'neighbour')   tierName = 'plus';
    // Legacy paid-tier alias kept in Firestore → innerCircle (still in enum)
    if (tierName == 'pro')         tierName = 'innerCircle';
    if (tierName == 'circle')      tierName = 'innerCircle';
    // Canonical names pass through unchanged
    // 'welcome', 'plus', 'innerCircle', 'partner'

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

  /// Deprecated alias — use [UserSubscription.welcome] instead
  factory UserSubscription.explorer() => UserSubscription.welcome();
}
