// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL CONNECT — SUBSCRIPTION MODEL
// ═══════════════════════════════════════════════════════════════════════════════
//
// PRICING ANALYST RATIONALE
// ─────────────────────────
// Three tiers designed around the "Value-First Freemium" strategy:
//
// 1. EXPLORER (Free) — "Hook tier"
//    Deliberately tight limits that let users experience value quickly
//    (join 2 groups, attend meetups, 5 DMs) but hit friction within the
//    first week. Goal: force an upgrade decision within 7 days.
//
// 2. NEIGHBOURHOOD (£5.99/mo | £49.99/yr) — "Sweet-spot tier"
//    Priced at the UK impulse-buy threshold (< cost of 2 coffees/mo).
//    Removes ALL social friction (unlimited groups, DMs, meetups) and
//    adds private groups, meetup creation, ad-free, and a profile badge.
//    This is the tier 80%+ of paying users should land on.
//    Annual plan saves 30% — anchored as default to maximise LTV.
//
// 3. INNER CIRCLE (£11.99/mo | £99.99/yr) — "Power-user tier"
//    For community leaders and super-engaged parents. Adds analytics,
//    promoted marketplace listings, priority support, unlimited photos,
//    and early access. Targets the top ~5% of active users who derive
//    outsized value and are willing to pay 2× for premium perks.
//
// COMPETITIVE CONTEXT (UK parenting/community apps, 2025):
//   Peanut Plus:  ~£8.99/mo or £79.99 lifetime
//   Huckleberry:  ~£7.99/mo
//   Mush:         Free (ad-supported)
//
// Huddl Neighbourhood at £5.99/mo undercuts Peanut and Huckleberry by 25-33%
// while offering comparable or superior social features, making it the
// highest-value option in the market.
//
// KEY CONVERSION LEVERS:
//   7-day auto-trial of Neighbourhood on sign-up (no card required)
//   Soft paywalls at "aha moments" (3rd group, 6th DM, private group)
//   Founding Member rate: £3.99/mo locked for life (first 500 users)
//   Annual billing default with "Save 30%" badge
//   Day-5 trial reminder push notification
//   Day-7 exit survey + 1-month free pause on cancellation
// ═══════════════════════════════════════════════════════════════════════════════

/// Subscription tier levels for Huddl Connect
enum SubscriptionTier { explorer, neighbourhood, innerCircle }

/// Billing period
enum BillingPeriod { monthly, annual }

/// Feature limits per tier
class TierLimits {
  final int maxGroups;
  final int maxGroupsCreated;
  final int maxMeetupsPerMonth;
  final int maxDMConversations;
  final int maxMarketplaceListings;
  final int maxPhotoUploads;
  final int maxMessagesPerMonth;
  final bool canCreatePrivateGroups;
  final bool canCreateMeetups;
  final bool prioritySupport;
  final bool adFree;
  final bool customProfileBadge;
  final bool analyticsAccess;
  final bool promotedListings;
  final bool earlyAccess;
  final bool expertQandA;
  final bool milestoneTracker;

  const TierLimits({
    required this.maxGroups,
    required this.maxGroupsCreated,
    required this.maxMeetupsPerMonth,
    required this.maxDMConversations,
    required this.maxMarketplaceListings,
    required this.maxPhotoUploads,
    required this.maxMessagesPerMonth,
    required this.canCreatePrivateGroups,
    required this.canCreateMeetups,
    required this.prioritySupport,
    required this.adFree,
    required this.customProfileBadge,
    required this.analyticsAccess,
    required this.promotedListings,
    required this.earlyAccess,
    required this.expertQandA,
    required this.milestoneTracker,
  });

  // ── EXPLORER (Free) ─────────────────────────────────────────────────
  // Tight limits: experience value fast, hit friction within 7 days.
  // 2 groups, 1 created, 2 meetups/mo, 5 DMs, 2 listings, 3 photos.
  // No private groups, no meetup creation, no ad-free.
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
    prioritySupport: false,
    adFree: false,
    customProfileBadge: false,
    analyticsAccess: false,
    promotedListings: false,
    earlyAccess: false,
    expertQandA: false,
    milestoneTracker: false,
  );

  // ── NEIGHBOURHOOD (£5.99/mo) ─────────────────────────────────────────
  // Removes all social friction. Unlimited core features.
  // Private groups, meetup creation, ad-free, badge, expert Q&A, milestones.
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
    prioritySupport: false,
    adFree: true,
    customProfileBadge: true,
    analyticsAccess: false,
    promotedListings: false,
    earlyAccess: false,
    expertQandA: true,
    milestoneTracker: true,
  );

  // ── INNER CIRCLE (£11.99/mo) ────────────────────────────────────────
  // Everything in Neighbourhood + analytics, promoted listings, priority
  // support, unlimited photos, early access.
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
    prioritySupport: true,
    adFree: true,
    customProfileBadge: true,
    analyticsAccess: true,
    promotedListings: true,
    earlyAccess: true,
    expertQandA: true,
    milestoneTracker: true,
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
    // ── EXPLORER (Free) ───────────────────────────────────────────────
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
        'View community feed & meetups',
        'Basic parent profile',
      ],
      shortBenefits: [
        '2 groups, 5 DMs, 2 meetups/mo',
        'Basic community access',
      ],
    ),

    // ── NEIGHBOURHOOD (£5.99/mo | £49.99/yr) ─────────────────────────
    SubscriptionPlan(
      tier: SubscriptionTier.neighbourhood,
      name: 'Neighbourhood',
      tagline: 'Your full parent community, unlocked',
      subtitle: 'Less than 2 coffees a month',
      monthlyPrice: 5.99,
      annualPrice: 49.99,
      foundingMonthlyPrice: 3.99,
      limits: TierLimits.neighbourhood,
      highlights: [
        'Unlimited groups & messaging',
        'Create up to 25 groups',
        'Unlimited meetups',
        'Unlimited direct conversations',
        '15 marketplace listings',
        'Create private groups',
        'Create & host meetups',
        'Ad-free experience',
        'Neighbourhood member badge',
        'Weekly expert Q&A access',
        'Child milestone tracker',
      ],
      shortBenefits: [
        'Unlimited groups, DMs & meetups',
        'Private groups & meetups',
        'Ad-free + expert Q&A',
      ],
    ),

    // ── INNER CIRCLE (£11.99/mo | £99.99/yr) ──────────────────────────
    SubscriptionPlan(
      tier: SubscriptionTier.innerCircle,
      name: 'Inner Circle',
      tagline: 'Lead your community with superpowers',
      subtitle: 'For active community builders',
      monthlyPrice: 11.99,
      annualPrice: 99.99,
      limits: TierLimits.innerCircle,
      highlights: [
        'Everything in Neighbourhood',
        'Unlimited group creation',
        'Unlimited marketplace listings',
        'Promoted listings (2\u00D7 visibility)',
        'Community analytics dashboard',
        'Priority support (< 2h response)',
        'Up to 50 photo uploads',
        'Early access to new features',
        'Inner Circle badge',
      ],
      shortBenefits: [
        'Everything in Neighbourhood',
        'Analytics, promoted listings',
        'Priority support & early access',
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
