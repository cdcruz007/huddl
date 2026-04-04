/// Subscription tier levels for Huddl Connect
enum SubscriptionTier { free, plus, pro }

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
  final bool canCreatePrivateGroups;
  final bool canCreateEvents;
  final bool prioritySupport;
  final bool adFree;
  final bool customProfileBadge;
  final bool analyticsAccess;
  final bool promotedListings;
  final bool earlyAccess;

  const TierLimits({
    required this.maxGroups,
    required this.maxGroupsCreated,
    required this.maxMeetupsPerMonth,
    required this.maxDMConversations,
    required this.maxMarketplaceListings,
    required this.maxPhotoUploads,
    required this.canCreatePrivateGroups,
    required this.canCreateEvents,
    required this.prioritySupport,
    required this.adFree,
    required this.customProfileBadge,
    required this.analyticsAccess,
    required this.promotedListings,
    required this.earlyAccess,
  });

  /// Free tier defaults
  static const TierLimits free = TierLimits(
    maxGroups: 5,
    maxGroupsCreated: 2,
    maxMeetupsPerMonth: 3,
    maxDMConversations: 10,
    maxMarketplaceListings: 5,
    maxPhotoUploads: 3,
    canCreatePrivateGroups: false,
    canCreateEvents: false,
    prioritySupport: false,
    adFree: false,
    customProfileBadge: false,
    analyticsAccess: false,
    promotedListings: false,
    earlyAccess: false,
  );

  /// Plus tier
  static const TierLimits plus = TierLimits(
    maxGroups: 20,
    maxGroupsCreated: 10,
    maxMeetupsPerMonth: 15,
    maxDMConversations: 50,
    maxMarketplaceListings: 25,
    maxPhotoUploads: 10,
    canCreatePrivateGroups: true,
    canCreateEvents: true,
    prioritySupport: false,
    adFree: true,
    customProfileBadge: true,
    analyticsAccess: false,
    promotedListings: false,
    earlyAccess: false,
  );

  /// Pro tier
  static const TierLimits pro = TierLimits(
    maxGroups: 999,
    maxGroupsCreated: 999,
    maxMeetupsPerMonth: 999,
    maxDMConversations: 999,
    maxMarketplaceListings: 999,
    maxPhotoUploads: 50,
    canCreatePrivateGroups: true,
    canCreateEvents: true,
    prioritySupport: true,
    adFree: true,
    customProfileBadge: true,
    analyticsAccess: true,
    promotedListings: true,
    earlyAccess: true,
  );

  static TierLimits forTier(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.free:
        return free;
      case SubscriptionTier.plus:
        return plus;
      case SubscriptionTier.pro:
        return pro;
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
  final double monthlyPrice;
  final double annualPrice;
  final TierLimits limits;
  final List<String> highlights;

  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.tagline,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.limits,
    required this.highlights,
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
    SubscriptionPlan(
      tier: SubscriptionTier.free,
      name: 'Free',
      tagline: 'Get started with the essentials',
      monthlyPrice: 0,
      annualPrice: 0,
      limits: TierLimits.free,
      highlights: [
        'Join up to 5 groups',
        'Create 2 groups',
        'Host 3 meetups/month',
        '10 direct conversations',
        '5 marketplace listings',
        'Community feed access',
      ],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.plus,
      name: 'Plus',
      tagline: 'More connections, more features',
      monthlyPrice: 4.99,
      annualPrice: 39.99,
      limits: TierLimits.plus,
      highlights: [
        'Join up to 20 groups',
        'Create 10 groups',
        'Host 15 meetups/month',
        '50 direct conversations',
        '25 marketplace listings',
        'Create private groups',
        'Create community events',
        'Ad-free experience',
        'Profile badge',
      ],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.pro,
      name: 'Pro',
      tagline: 'The ultimate parent community experience',
      monthlyPrice: 9.99,
      annualPrice: 79.99,
      limits: TierLimits.pro,
      highlights: [
        'Unlimited groups',
        'Unlimited meetups',
        'Unlimited conversations',
        'Unlimited listings',
        'Private groups & events',
        'Ad-free experience',
        'Priority support',
        'Analytics dashboard',
        'Promoted listings',
        'Early access to features',
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

  const UserSubscription({
    required this.tier,
    required this.billingPeriod,
    required this.startDate,
    this.renewalDate,
    this.isActive = true,
    this.isTrial = false,
    this.trialDaysRemaining = 0,
  });

  TierLimits get limits => TierLimits.forTier(tier);

  bool get isFree => tier == SubscriptionTier.free;
  bool get isPlus => tier == SubscriptionTier.plus;
  bool get isPro => tier == SubscriptionTier.pro;
  bool get isPaid => !isFree;

  String get tierDisplayName {
    switch (tier) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.plus:
        return 'Huddl Plus';
      case SubscriptionTier.pro:
        return 'Huddl Pro';
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
      };

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == json['tier'],
        orElse: () => SubscriptionTier.free,
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
    );
  }

  /// Default free subscription
  factory UserSubscription.free() => UserSubscription(
        tier: SubscriptionTier.free,
        billingPeriod: BillingPeriod.monthly,
        startDate: DateTime.now(),
        isActive: true,
      );
}
