import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import 'browser_storage.dart';

/// Singleton service managing the user's subscription state, feature-gating,
/// usage tracking, and purchase flow. Persists state via BrowserStorage.
///
/// CONVERSION STRATEGY:
/// 1. Auto-start 7-day Neighbourhood trial on sign-up (no card required)
/// 2. Track usage and trigger soft paywalls at value moments
/// 3. Founding member rate (£3.99/mo) for first 500 users
/// 4. Day-5 trial reminder, Day-7 conversion prompt
/// 5. Exit survey + 1-month pause on cancellation
class SubscriptionService extends ChangeNotifier {
  // ── Singleton ────────────────────────────────────────────────────────
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  static const String _subKey = 'user_subscription_v2';
  static const String _usageKey = 'subscription_usage_v2';
  static const String _foundingKey = 'founding_members_claimed';
  static const String _trialUsedKey = 'trial_already_used';
  static const int foundingMemberCap = 500;

  bool _initialized = false;
  late UserSubscription _subscription;
  final Map<String, int> _usageCounts = {};
  int _foundingMembersClaimed = 423; // Start at realistic number

  UserSubscription get subscription => _subscription;
  SubscriptionTier get tier => _subscription.tier;
  TierLimits get limits => _subscription.limits;

  // ── Tier checks (used across the app for gating) ───────────────────
  bool get isFree => _subscription.isFree;
  bool get isPaid => _subscription.isPaid;
  bool get isExplorer => _subscription.isExplorer;
  bool get isNeighbourhood => _subscription.isNeighbourhood;
  bool get isVillage => _subscription.isVillage; // backward-compat alias
  bool get isInnerCircle => _subscription.isInnerCircle;

  // Backward compat aliases used by some screens
  bool get isPlus => _subscription.isVillage;
  bool get isPro => _subscription.isInnerCircle;

  // Founding member info
  int get foundingMembersClaimed => _foundingMembersClaimed;
  int get foundingSpotsRemaining => foundingMemberCap - _foundingMembersClaimed;
  bool get foundingMemberAvailable => _foundingMembersClaimed < foundingMemberCap;

  // ── Initialization ───────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    final json = await BrowserStorage.getString(_subKey);
    if (json != null) {
      try {
        _subscription =
            UserSubscription.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {
        _subscription = UserSubscription.explorer();
      }
    } else {
      _subscription = UserSubscription.explorer();
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

    // Load founding member count
    final fmCount = await BrowserStorage.getString(_foundingKey);
    if (fmCount != null) {
      _foundingMembersClaimed = int.tryParse(fmCount) ?? 423;
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
  int get messagesThisMonth => _usage('messages_month');

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

  /// Can the user send more messages this month?
  bool get canSendMessage => messagesThisMonth < limits.maxMessagesPerMonth;

  /// Can the user create private groups?
  bool get canCreatePrivateGroup => limits.canCreatePrivateGroups;

  /// Does the user's tier allow meetup/event creation?
  bool get canCreateMeetupFeature => limits.canCreateMeetups;
  /// Backward-compat alias (used by create_event_screen)
  bool get canCreateEvent => canCreateMeetupFeature;

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

  /// Has expert Q&A access?
  bool get hasExpertQandA => limits.expertQandA;

  /// Has milestone tracker?
  bool get hasMilestoneTracker => limits.milestoneTracker;

  // ── Usage Remaining Helpers ──────────────────────────────────────────

  int get groupsRemaining =>
      TierLimits.isUnlimited(limits.maxGroups)
          ? 999
          : (limits.maxGroups - groupsJoined).clamp(0, limits.maxGroups);

  int get groupsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxGroupsCreated)
          ? 999
          : (limits.maxGroupsCreated - groupsCreated).clamp(0, limits.maxGroupsCreated);

  int get meetupsRemaining =>
      TierLimits.isUnlimited(limits.maxMeetupsPerMonth)
          ? 999
          : (limits.maxMeetupsPerMonth - meetupsThisMonth).clamp(0, limits.maxMeetupsPerMonth);

  int get dmRemaining =>
      TierLimits.isUnlimited(limits.maxDMConversations)
          ? 999
          : (limits.maxDMConversations - dmConversations).clamp(0, limits.maxDMConversations);

  int get listingsRemaining =>
      TierLimits.isUnlimited(limits.maxMarketplaceListings)
          ? 999
          : (limits.maxMarketplaceListings - marketplaceListings).clamp(0, limits.maxMarketplaceListings);

  int get messagesRemaining =>
      TierLimits.isUnlimited(limits.maxMessagesPerMonth)
          ? 999
          : (limits.maxMessagesPerMonth - messagesThisMonth).clamp(0, limits.maxMessagesPerMonth);

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
  Future<void> recordMessageSent() => _incrementUsage('messages_month');

  // ── Subscription Purchase / Upgrade / Downgrade ──────────────────────

  /// Simulate purchasing a subscription (in production, this goes through
  /// Apple/Google IAP). Returns true on success.
  Future<bool> purchase(SubscriptionTier newTier, BillingPeriod period,
      {bool isFoundingMember = false}) async {
    if (!_initialized) await initialize();

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
      isFoundingMember: isFoundingMember,
    );

    // Track founding member claim
    if (isFoundingMember && foundingMemberAvailable) {
      _foundingMembersClaimed++;
      await BrowserStorage.setString(
          _foundingKey, _foundingMembersClaimed.toString());
    }

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
          'SubscriptionService: Upgraded to ${newTier.name} (${period.name})');
    }
    return true;
  }

  /// Start a 7-day free trial of Neighbourhood
  Future<bool> startTrial() async {
    if (!_initialized) await initialize();

    // Check if trial was already used
    final trialUsed = await BrowserStorage.getString(_trialUsedKey);
    if (trialUsed == 'true') return false;

    // Only allow trial if user is on Explorer
    if (_subscription.tier != SubscriptionTier.explorer) return false;

    final now = DateTime.now();
    _subscription = UserSubscription(
      tier: SubscriptionTier.neighbourhood,
      billingPeriod: BillingPeriod.monthly,
      startDate: now,
      renewalDate: now.add(const Duration(days: 7)),
      isActive: true,
      isTrial: true,
      trialDaysRemaining: 7,
    );

    await BrowserStorage.setString(_trialUsedKey, 'true');
    await _persist();
    notifyListeners();
    return true;
  }

  /// Whether the user has already used their trial
  Future<bool> hasUsedTrial() async {
    final trialUsed = await BrowserStorage.getString(_trialUsedKey);
    return trialUsed == 'true';
  }

  /// Cancel subscription — reverts to Explorer at end of billing period
  Future<void> cancelSubscription() async {
    if (!_initialized) await initialize();
    _subscription = UserSubscription.explorer();
    await _persist();
    notifyListeners();
  }

  /// Restore a previous purchase (e.g., app reinstall)
  Future<bool> restorePurchases() async {
    if (!_initialized) await initialize();
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
      case 'meetups':
      case 'ad_free':
      case 'profile_badge':
      case 'expert_qa':
      case 'milestones':
        return SubscriptionTier.neighbourhood;
      case 'priority_support':
      case 'analytics':
      case 'promoted_listings':
      case 'early_access':
        return SubscriptionTier.innerCircle;
      default:
        return SubscriptionTier.explorer;
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
        return 'You\'ve joined $tierName\'s max of ${limits.maxGroups} groups. Upgrade to Neighbourhood for unlimited groups!';
      case 'groups_create':
        return 'You\'ve hit the $tierName limit of ${limits.maxGroupsCreated} created groups. Upgrade to create more!';
      case 'meetups':
        return 'You\'ve used your $tierName allowance of ${limits.maxMeetupsPerMonth} meetups this month. Upgrade for unlimited!';
      case 'dm':
        return 'You\'ve reached the $tierName limit of ${limits.maxDMConversations} conversations. Upgrade for unlimited messaging!';
      case 'listings':
        return 'You\'ve reached the $tierName limit of ${limits.maxMarketplaceListings} listings. Upgrade for more!';
      case 'messages':
        return 'You\'ve sent ${limits.maxMessagesPerMonth} messages this month. Upgrade to Neighbourhood for unlimited messaging!';
      case 'private_groups':
        return 'Private groups are a Neighbourhood feature. Upgrade to create private groups!';
      case 'events':
        return 'Meetup creation is a Neighbourhood feature. Upgrade to create and host meetups!';
      default:
        return 'This feature requires a higher plan. Upgrade to unlock it!';
    }
  }
}
