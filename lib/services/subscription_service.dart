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
/// 3. Founding member rate (GBP 3.99/mo) for first 500 users
/// 4. Day-5 trial reminder, Day-7 conversion prompt
/// 5. Exit survey + 1-month pause on cancellation
///
/// AI FEATURE GATING STRATEGY:
/// - Explorer gets a taster of AI (3 copilot chats/day, basic discovery)
/// - Neighbourhood unlocks full AI suite with generous daily caps
/// - Inner Circle gets unlimited AI plus exclusive Matchmaker
/// - AI limits reset daily/weekly/monthly depending on the feature
class SubscriptionService extends ChangeNotifier {
  // ---- Singleton ----
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

  // ---- Tier checks (used across the app for gating) ----
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

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

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

  // ===========================================================================
  // USAGE TRACKING (internal)
  // ===========================================================================

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

  // ===========================================================================
  // CORE SOCIAL -- USAGE GETTERS
  // ===========================================================================

  int get groupsJoined => _usage('groups_joined');
  int get groupsCreated => _usage('groups_created');
  int get meetupsThisMonth => _usage('meetups_month');
  int get dmConversations => _usage('dm_conversations');
  int get marketplaceListings => _usage('marketplace_listings');
  int get messagesThisMonth => _usage('messages_month');

  // ===========================================================================
  // AI FEATURE -- USAGE GETTERS
  // ===========================================================================

  int get aiCopilotChatsToday => _usage('ai_copilot_today');
  int get aiEventDiscoveriesThisWeek => _usage('ai_event_disc_week');
  int get aiChatSummariesToday => _usage('ai_chat_sum_today');
  int get aiListingGenerationsThisMonth => _usage('ai_listing_gen_month');
  int get aiTravelConciergeChatsToday => _usage('ai_travel_today');
  int get aiMatchmakerRequestsThisMonth => _usage('ai_matchmaker_month');
  int get aiSmartFeedRefreshesToday => _usage('ai_feed_today');

  // ===========================================================================
  // CORE SOCIAL -- FEATURE GATING (can the user do X?)
  // ===========================================================================

  bool get canJoinGroup => groupsJoined < limits.maxGroups;
  bool get canCreateGroup => groupsCreated < limits.maxGroupsCreated;
  bool get canCreateMeetup => meetupsThisMonth < limits.maxMeetupsPerMonth;
  bool get canStartDM => dmConversations < limits.maxDMConversations;
  bool get canCreateListing =>
      marketplaceListings < limits.maxMarketplaceListings;
  bool get canSendMessage => messagesThisMonth < limits.maxMessagesPerMonth;
  bool get canCreatePrivateGroup => limits.canCreatePrivateGroups;
  bool get canCreateMeetupFeature => limits.canCreateMeetups;
  bool get canCreateEvent => canCreateMeetupFeature; // backward-compat
  bool get isAdFree => limits.adFree;
  bool get hasBadge => limits.customProfileBadge;
  bool get hasMilestoneTracker => limits.milestoneTracker;

  // ===========================================================================
  // AI FEATURE -- FEATURE GATING
  // ===========================================================================

  /// AI Copilot: conversational parenting assistant
  bool get hasAiCopilot => limits.aiCopilotAccess;
  bool get canUseAiCopilot =>
      limits.aiCopilotAccess &&
      aiCopilotChatsToday < limits.maxAiCopilotChatsPerDay;
  int get aiCopilotChatsRemaining =>
      TierLimits.isUnlimited(limits.maxAiCopilotChatsPerDay)
          ? 999
          : (limits.maxAiCopilotChatsPerDay - aiCopilotChatsToday)
              .clamp(0, limits.maxAiCopilotChatsPerDay);

  /// AI Event Discovery: daily crawl of local events
  bool get hasAiEventDiscovery => limits.aiEventDiscovery;
  bool get canRunAiEventDiscovery =>
      limits.aiEventDiscovery &&
      aiEventDiscoveriesThisWeek < limits.maxAiEventDiscoveriesPerWeek;

  /// AI Event Recommendations: personalised event scoring
  bool get hasAiEventRecommendations => limits.aiEventRecommendations;

  /// AI Chat Summaries: summarise unread group messages
  bool get hasAiChatSummaries => limits.aiChatSummaries;
  bool get canUseAiChatSummary =>
      limits.aiChatSummaries &&
      aiChatSummariesToday < limits.maxAiChatSummariesPerDay;
  int get aiChatSummariesRemaining =>
      TierLimits.isUnlimited(limits.maxAiChatSummariesPerDay)
          ? 999
          : (limits.maxAiChatSummariesPerDay - aiChatSummariesToday)
              .clamp(0, limits.maxAiChatSummariesPerDay);

  /// AI Listing Generator: auto-generate marketplace listing content
  bool get hasAiListingGenerator => limits.aiListingGenerator;
  bool get canUseAiListingGenerator =>
      limits.aiListingGenerator &&
      aiListingGenerationsThisMonth < limits.maxAiListingGenerationsPerMonth;
  int get aiListingGenerationsRemaining =>
      TierLimits.isUnlimited(limits.maxAiListingGenerationsPerMonth)
          ? 999
          : (limits.maxAiListingGenerationsPerMonth -
                  aiListingGenerationsThisMonth)
              .clamp(0, limits.maxAiListingGenerationsPerMonth);

  /// AI Smart Feed: personalised feed curation & nudge cards
  bool get hasAiSmartFeed => limits.aiSmartFeed;
  bool get canRefreshAiSmartFeed =>
      limits.aiSmartFeed &&
      aiSmartFeedRefreshesToday < limits.maxAiSmartFeedRefreshesPerDay;

  /// AI Travel Concierge: chat-based family travel assistant
  bool get hasAiTravelConcierge => limits.aiTravelConcierge;
  bool get canUseAiTravelConcierge =>
      limits.aiTravelConcierge &&
      aiTravelConciergeChatsToday < limits.maxAiTravelConciergeChatsPerDay;
  int get aiTravelConciergeChatsRemaining =>
      TierLimits.isUnlimited(limits.maxAiTravelConciergeChatsPerDay)
          ? 999
          : (limits.maxAiTravelConciergeChatsPerDay -
                  aiTravelConciergeChatsToday)
              .clamp(0, limits.maxAiTravelConciergeChatsPerDay);

  /// AI Meetup Matchmaker: parent compatibility scoring & suggested meetups
  bool get hasAiMeetupMatchmaker => limits.aiMeetupMatchmaker;
  bool get canUseAiMatchmaker =>
      limits.aiMeetupMatchmaker &&
      aiMatchmakerRequestsThisMonth < limits.maxAiMatchmakerRequestsPerMonth;

  // ===========================================================================
  // TRIPS -- FEATURE GATING
  // ===========================================================================

  bool get hasTravelAccess => limits.travelAccess;
  bool get hasPackingListAccess => limits.tripsPackingListAccess;
  int get maxSavedTravels => limits.maxSavedTravels;

  // ===========================================================================
  // CORE SOCIAL -- USAGE REMAINING HELPERS
  // ===========================================================================

  int get groupsRemaining =>
      TierLimits.isUnlimited(limits.maxGroups)
          ? 999
          : (limits.maxGroups - groupsJoined).clamp(0, limits.maxGroups);

  int get groupsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxGroupsCreated)
          ? 999
          : (limits.maxGroupsCreated - groupsCreated)
              .clamp(0, limits.maxGroupsCreated);

  int get meetupsRemaining =>
      TierLimits.isUnlimited(limits.maxMeetupsPerMonth)
          ? 999
          : (limits.maxMeetupsPerMonth - meetupsThisMonth)
              .clamp(0, limits.maxMeetupsPerMonth);

  int get dmRemaining =>
      TierLimits.isUnlimited(limits.maxDMConversations)
          ? 999
          : (limits.maxDMConversations - dmConversations)
              .clamp(0, limits.maxDMConversations);

  int get listingsRemaining =>
      TierLimits.isUnlimited(limits.maxMarketplaceListings)
          ? 999
          : (limits.maxMarketplaceListings - marketplaceListings)
              .clamp(0, limits.maxMarketplaceListings);

  int get messagesRemaining =>
      TierLimits.isUnlimited(limits.maxMessagesPerMonth)
          ? 999
          : (limits.maxMessagesPerMonth - messagesThisMonth)
              .clamp(0, limits.maxMessagesPerMonth);

  // ===========================================================================
  // USAGE RECORDING -- Core Social (called when user takes action)
  // ===========================================================================

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

  // ===========================================================================
  // USAGE RECORDING -- AI Features
  // ===========================================================================

  Future<void> recordAiCopilotChat() => _incrementUsage('ai_copilot_today');
  Future<void> recordAiEventDiscovery() =>
      _incrementUsage('ai_event_disc_week');
  Future<void> recordAiChatSummary() =>
      _incrementUsage('ai_chat_sum_today');
  Future<void> recordAiListingGeneration() =>
      _incrementUsage('ai_listing_gen_month');
  Future<void> recordAiTravelConciergeChat() =>
      _incrementUsage('ai_travel_today');
  Future<void> recordAiMatchmakerRequest() =>
      _incrementUsage('ai_matchmaker_month');
  Future<void> recordAiSmartFeedRefresh() =>
      _incrementUsage('ai_feed_today');

  // ===========================================================================
  // SUBSCRIPTION PURCHASE / UPGRADE / DOWNGRADE
  // ===========================================================================

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

  /// Cancel subscription -- reverts to Explorer at end of billing period
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

  // ===========================================================================
  // GATE HELPERS (for UI)
  // ===========================================================================

  /// Returns the minimum tier required for a feature
  SubscriptionTier minimumTierFor(String feature) {
    switch (feature) {
      // Core social -- Neighbourhood
      case 'private_groups':
      case 'meetups':
      case 'events':
      case 'ad_free':
      case 'profile_badge':
      case 'milestones':
        return SubscriptionTier.neighbourhood;

      // AI -- Neighbourhood
      case 'ai_listing_generator':
      case 'ai_travel_concierge':
      case 'ai_full_copilot':
      case 'ai_full_chat_summaries':
      case 'ai_full_event_discovery':
      case 'trips_packing_list':
        return SubscriptionTier.neighbourhood;

      // AI -- Inner Circle (exclusive)
      case 'ai_matchmaker':
      case 'unlimited_ai':
        return SubscriptionTier.innerCircle;

      // Free tier features
      case 'ai_copilot_basic':
      case 'ai_event_discovery_basic':
      case 'ai_smart_feed_basic':
      case 'ai_recommendations_basic':
      case 'trips_browse':
        return SubscriptionTier.explorer;

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
      // Core social limits
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

      // AI limits
      case 'ai_copilot':
        return 'You\'ve used your ${limits.maxAiCopilotChatsPerDay} AI Copilot chats today. Upgrade to Neighbourhood for 25 chats/day!';
      case 'ai_chat_summaries':
        return 'You\'ve used your ${limits.maxAiChatSummariesPerDay} AI chat summary today. Upgrade for up to 10 summaries/day!';
      case 'ai_listing_generator':
        return 'AI Listing Generator is a Neighbourhood feature. Upgrade to auto-generate listings from photos!';
      case 'ai_travel_concierge':
        return 'AI Travel Concierge is a Neighbourhood feature. Upgrade to plan family trips with AI!';
      case 'ai_matchmaker':
        return 'AI Meetup Matchmaker is an Inner Circle exclusive. Upgrade to get smart parent-matching!';
      case 'ai_event_discovery':
        return 'You\'ve used your weekly AI event discovery. Upgrade to Neighbourhood for daily discovery!';
      case 'ai_smart_feed':
        return 'You\'ve used your daily smart feed refreshes. Upgrade for unlimited personalisation!';
      case 'trips_packing_list':
        return 'Packing lists are a Neighbourhood feature. Upgrade to get AI-powered packing suggestions!';

      default:
        return 'This feature requires a higher plan. Upgrade to unlock it!';
    }
  }
}
