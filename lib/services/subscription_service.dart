import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import 'browser_storage.dart';

/// Singleton service managing the user's subscription state, feature-gating,
/// usage tracking, and purchase flow. Persists state via BrowserStorage.
class SubscriptionService extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────────────────
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  static const String _subKey = 'user_subscription_v1';
  static const String _usageKey = 'subscription_usage_v1';

  bool _initialized = false;
  late UserSubscription _subscription;
  final Map<String, int> _usageCounts = {};

  UserSubscription get subscription => _subscription;
  SubscriptionTier get tier => _subscription.tier;
  TierLimits get limits => _subscription.limits;
  bool get isFree => _subscription.isFree;
  bool get isPaid => _subscription.isPaid;
  bool get isPlus => _subscription.isPlus;
  bool get isPro => _subscription.isPro;

  // ── Initialization ───────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    final json = await BrowserStorage.getString(_subKey);
    if (json != null) {
      try {
        _subscription =
            UserSubscription.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {
        _subscription = UserSubscription.free();
      }
    } else {
      _subscription = UserSubscription.free();
    }

    // Load usage counts
    final usageJson = await BrowserStorage.getString(_usageKey);
    if (usageJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(usageJson);
        _usageCounts.clear();
        for (final e in decoded.entries) {
          _usageCounts[e.key] = e.value as int;
        }
      } catch (_) {
        // ignore
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await BrowserStorage.setString(_subKey, jsonEncode(_subscription.toJson()));
    await BrowserStorage.setString(_usageKey, jsonEncode(_usageCounts));
  }

  // ── Usage Tracking ───────────────────────────────────────────────────
  int _usage(String key) => _usageCounts[key] ?? 0;

  Future<void> _incrementUsage(String key) async {
    _usageCounts[key] = (_usageCounts[key] ?? 0) + 1;
    await _persist();
    notifyListeners();
  }

  Future<void> _decrementUsage(String key) async {
    final current = _usageCounts[key] ?? 0;
    if (current > 0) {
      _usageCounts[key] = current - 1;
      await _persist();
      notifyListeners();
    }
  }

  // ── Usage Getters ────────────────────────────────────────────────────
  int get groupsJoined => _usage('groups_joined');
  int get groupsCreated => _usage('groups_created');
  int get meetupsThisMonth => _usage('meetups_month');
  int get dmConversations => _usage('dm_conversations');
  int get marketplaceListings => _usage('marketplace_listings');

  // ── Feature Gating — can the user do X? ──────────────────────────────

  /// Can the user join another group?
  bool get canJoinGroup => groupsJoined < limits.maxGroups;

  /// Can the user create another group?
  bool get canCreateGroup => groupsCreated < limits.maxGroupsCreated;

  /// Can the user create a meetup?
  bool get canCreateMeetup => meetupsThisMonth < limits.maxMeetupsPerMonth;

  /// Can the user start a new DM conversation?
  bool get canStartDM => dmConversations < limits.maxDMConversations;

  /// Can the user create a marketplace listing?
  bool get canCreateListing =>
      marketplaceListings < limits.maxMarketplaceListings;

  /// Can the user create private groups?
  bool get canCreatePrivateGroup => limits.canCreatePrivateGroups;

  /// Can the user create events?
  bool get canCreateEvent => limits.canCreateEvents;

  /// Is the user ad-free?
  bool get isAdFree => limits.adFree;

  /// Has a custom badge?
  bool get hasBadge => limits.customProfileBadge;

  /// Has priority support?
  bool get hasPrioritySupport => limits.prioritySupport;

  /// Has analytics access?
  bool get hasAnalytics => limits.analyticsAccess;

  /// Has promoted listings?
  bool get hasPromotedListings => limits.promotedListings;

  // ── Usage Remaining Helpers ──────────────────────────────────────────

  int get groupsRemaining =>
      TierLimits.isUnlimited(limits.maxGroups)
          ? 999
          : limits.maxGroups - groupsJoined;

  int get groupsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxGroupsCreated)
          ? 999
          : limits.maxGroupsCreated - groupsCreated;

  int get meetupsRemaining =>
      TierLimits.isUnlimited(limits.maxMeetupsPerMonth)
          ? 999
          : limits.maxMeetupsPerMonth - meetupsThisMonth;

  int get dmRemaining =>
      TierLimits.isUnlimited(limits.maxDMConversations)
          ? 999
          : limits.maxDMConversations - dmConversations;

  int get listingsRemaining =>
      TierLimits.isUnlimited(limits.maxMarketplaceListings)
          ? 999
          : limits.maxMarketplaceListings - marketplaceListings;

  // ── Usage Recording (called when user takes action) ──────────────────

  Future<void> recordGroupJoin() => _incrementUsage('groups_joined');
  Future<void> recordGroupLeave() => _decrementUsage('groups_joined');
  Future<void> recordGroupCreate() => _incrementUsage('groups_created');
  Future<void> recordMeetupCreate() => _incrementUsage('meetups_month');
  Future<void> recordDMStart() => _incrementUsage('dm_conversations');
  Future<void> recordListingCreate() =>
      _incrementUsage('marketplace_listings');
  Future<void> recordListingRemove() =>
      _decrementUsage('marketplace_listings');

  // ── Subscription Purchase / Upgrade / Downgrade ──────────────────────

  /// Simulate purchasing a subscription (in production, this goes through
  /// Apple/Google IAP). Returns true on success.
  Future<bool> purchase(SubscriptionTier newTier, BillingPeriod period) async {
    if (!_initialized) await initialize();

    final plan = SubscriptionPlan.allPlans.firstWhere(
      (p) => p.tier == newTier,
    );

    final now = DateTime.now();
    final renewal = period == BillingPeriod.monthly
        ? now.add(const Duration(days: 30))
        : now.add(const Duration(days: 365));

    _subscription = UserSubscription(
      tier: newTier,
      billingPeriod: period,
      startDate: now,
      renewalDate: renewal,
      isActive: true,
      isTrial: false,
    );

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
          'SubscriptionService: Upgraded to ${plan.name} (${period.name})');
    }
    return true;
  }

  /// Start a 14-day free trial of Plus
  Future<bool> startTrial() async {
    if (!_initialized) await initialize();
    // Only allow trial if user has never subscribed
    if (_subscription.tier != SubscriptionTier.free) return false;

    final now = DateTime.now();
    _subscription = UserSubscription(
      tier: SubscriptionTier.plus,
      billingPeriod: BillingPeriod.monthly,
      startDate: now,
      renewalDate: now.add(const Duration(days: 14)),
      isActive: true,
      isTrial: true,
      trialDaysRemaining: 14,
    );

    await _persist();
    notifyListeners();
    return true;
  }

  /// Cancel subscription — reverts to free at end of billing period
  Future<void> cancelSubscription() async {
    if (!_initialized) await initialize();
    // In production, this would schedule cancellation at period end.
    // For now, revert immediately.
    _subscription = UserSubscription.free();
    await _persist();
    notifyListeners();
  }

  /// Restore a previous purchase (e.g., app reinstall)
  Future<bool> restorePurchases() async {
    if (!_initialized) await initialize();
    // In production, verify with Apple/Google receipt servers
    // For now, just reload from local storage
    final json = await BrowserStorage.getString(_subKey);
    if (json != null) {
      try {
        _subscription =
            UserSubscription.fromJson(jsonDecode(json) as Map<String, dynamic>);
        notifyListeners();
        return _subscription.isPaid;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  // ── Gate Helpers (for UI) ────────────────────────────────────────────

  /// Returns the minimum tier required for a feature
  SubscriptionTier minimumTierFor(String feature) {
    switch (feature) {
      case 'private_groups':
      case 'events':
      case 'ad_free':
      case 'profile_badge':
        return SubscriptionTier.plus;
      case 'priority_support':
      case 'analytics':
      case 'promoted_listings':
      case 'early_access':
        return SubscriptionTier.pro;
      default:
        return SubscriptionTier.free;
    }
  }

  /// Check if user can access a premium feature
  bool canAccess(String feature) {
    final required = minimumTierFor(feature);
    return tier.index >= required.index;
  }

  /// Description of the limit the user has hit
  String limitReachedMessage(String limitType) {
    final tierName = _subscription.tierDisplayName;
    switch (limitType) {
      case 'groups_join':
        return 'You\'ve reached the $tierName limit of ${limits.maxGroups} groups. Upgrade to join more!';
      case 'groups_create':
        return 'You\'ve reached the $tierName limit of ${limits.maxGroupsCreated} created groups. Upgrade to create more!';
      case 'meetups':
        return 'You\'ve reached the $tierName limit of ${limits.maxMeetupsPerMonth} meetups this month. Upgrade for more!';
      case 'dm':
        return 'You\'ve reached the $tierName limit of ${limits.maxDMConversations} conversations. Upgrade for more!';
      case 'listings':
        return 'You\'ve reached the $tierName limit of ${limits.maxMarketplaceListings} listings. Upgrade for more!';
      case 'private_groups':
        return 'Private groups are a $tierName feature. Upgrade to Plus or Pro to create private groups!';
      case 'events':
        return 'Events are a premium feature. Upgrade to Plus or Pro to create events!';
      default:
        return 'This feature requires a higher plan. Upgrade to unlock it!';
    }
  }
}
