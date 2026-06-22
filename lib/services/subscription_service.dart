import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/subscription.dart';
import 'browser_storage.dart';

/// Singleton service managing the user's subscription state, feature-gating,
/// usage tracking, and purchase flow. Persists state via BrowserStorage.
///
/// FEATURE GATING STRATEGY:
/// - Welcome (free) gets a taster of AI (3 copilot chats/day, basic discovery)
/// - Plus unlocks full AI suite with generous daily caps
/// - Partner gets unlimited AI plus exclusive business features
/// - AI limits reset daily/weekly/monthly depending on the feature
class SubscriptionService extends ChangeNotifier {
  // ---- Singleton ----
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;
  SubscriptionService._();

  static const String _subKey = 'user_subscription_v2';
  static const String _usageKey = 'subscription_usage_v2';

  // ── Lifetime usage keys (never reset) ─────────────────────────────────────
  static const String _listingsCreatedKey    = 'listings_created_lifetime';
  static const String _buyerContactsKey      = 'buyer_contacts_lifetime';
  static const String _userGroupsCreatedKey  = 'user_groups_created_lifetime';
  static const String _freeMeetupsCreatedKey = 'free_meetups_created_lifetime';
  static const String _pollsCreatedKey       = 'polls_created_lifetime';
  static const String _questionsPostedKey    = 'questions_posted_lifetime';
  static const String _savedItemsKey         = 'saved_items_lifetime';
  static const String _aiSavedSummariesKey   = 'ai_saved_summaries_lifetime';

  bool _initialized = false;
  late UserSubscription _subscription;
  final Map<String, int> _usageCounts = {};

  UserSubscription get subscription => _subscription;
  SubscriptionTier get tier => _subscription.tier;
  TierLimits get limits => _subscription.limits;

  // ---- Tier checks (used across the app for gating) ----
  bool get isFree => _subscription.isFree;
  bool get isPaid => _subscription.isPaid;
  bool get isWelcome => _subscription.isWelcome;
  bool get isPlus => _subscription.isPlus;
  bool get isPartner => _subscription.isPartner;


  // ── Plus or above ─────────────────────────────────────────────────────────
  bool get isPlusOrAbove => isPlus || isPartner;

  // ── Paid meetups (Plus or above only; free meetups open to all) ───────────────
  bool get canCreatePaidMeetup => isPlusOrAbove;

  // ── Business-gated features (require tier + verification) ─────────────────────
  bool get canOwnServiceListing    => isPlusOrAbove && isBusinessVerified;
  bool get canCreateCommercialEvent => isPlusOrAbove && isBusinessVerified;

  // ── Partner-exclusive features ────────────────────────────────────────────────
  bool get canPromoteInFeed          => isPartner;
  bool get hasBusinessProfile        => isPartner;
  bool get hasAnalyticsDashboard     => isPartner;
  bool get canRespondToEndorsements  => isPartner;
  bool get hasUnlimitedServiceListings => isPartner;

  // ---- Partner / Business verification ----
  bool _businessVerified = false;
  bool get isBusinessVerified => _businessVerified;

  /// Load business verification status from Firestore.
  /// Call from screens that gate on isBusinessVerified. Non-blocking.
  Future<void> loadBusinessVerificationStatus() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      if (doc.exists) {
        _businessVerified =
            doc.data()?['businessVerified'] as bool? ?? false;
        notifyListeners();
      }
    } catch (_) {
      // Non-fatal — offline
    }
  }

  // ---- Scheduled change / cancellation getters ----
  bool get hasScheduledChange => _subscription.hasScheduledChange;
  bool get isPendingCancellation => _subscription.isPendingCancellation;
  SubscriptionTier? get scheduledTier => _subscription.scheduledTier;
  BillingPeriod? get scheduledPeriod => _subscription.scheduledPeriod;
  String? get scheduledChangeSummary => _subscription.scheduledChangeSummary;
  int get daysUntilRenewal => _subscription.daysUntilRenewal;
  DateTime? get renewalDate => _subscription.renewalDate;

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
        _subscription = UserSubscription.welcome();
      }
    } else {
      _subscription = UserSubscription.welcome();
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

    // ── Cross-device sync: read from Firestore (authoritative) ───────────
    // The server doc is written by Stripe/receipt webhooks and is the source
    // of truth for tier, active state, and renewalDate.  We adopt the remote
    // in BOTH directions (upgrade AND downgrade/lapse) so a cancelled user
    // cannot retain paid features via a stale local cache.
    //
    // DOWNGRADE GUARD — race with purchase():
    //   purchase() writes local optimistically (startDate = now) then calls
    //   _syncToFirestore().  If remote-sync runs before the webhook echo lands,
    //   the remote doc still shows the old (lower) tier.  Guard: if local
    //   startDate is within the last 5 minutes AND local tier > remote
    //   effective tier, the remote read is stale — skip the downgrade.
    //   5 minutes is generous; the Stripe/Apple webhook typically lands in < 30s.
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists) {
          final data = doc.data()!;
          final tierStr    = data['tier']          as String? ?? 'welcome';
          final periodStr  = data['billingPeriod'] as String? ?? 'monthly';
          final isActive   = data['isActive']      as bool?   ?? false;
          final cancelAtEnd =
              data['cancelledAtPeriodEnd'] as bool? ?? false;
          final schedTierStr   = data['scheduledTier']   as String?;
          final schedPeriodStr = data['scheduledPeriod'] as String?;

          // ── renewalDate: accept both int-millis (old client writes) and
          //    ISO-8601 string (receipt webhook writes via toISOString()).
          DateTime? parsedRenewal;
          final rawRenewal = data['renewalDate'];
          if (rawRenewal is int) {
            parsedRenewal =
                DateTime.fromMillisecondsSinceEpoch(rawRenewal);
          } else if (rawRenewal is String && rawRenewal.isNotEmpty) {
            parsedRenewal = DateTime.tryParse(rawRenewal);
          }

          final remoteTier = SubscriptionTier.values.firstWhere(
            (t) => t.name == tierStr,
            orElse: () => SubscriptionTier.welcome,
          );
          final remotePeriod = BillingPeriod.values.firstWhere(
            (p) => p.name == periodStr,
            orElse: () => BillingPeriod.monthly,
          );

          // ── Effective remote tier ────────────────────────────────────────
          // If isActive == false AND the subscription is NOT in a grace period
          // (cancelledAtPeriodEnd still within renewalDate), treat the remote
          // entitlement as welcome (lapsed).  This mirrors the existing
          // isPendingCancellation semantics.
          final now = DateTime.now();
          final withinRenewalWindow = parsedRenewal != null &&
              parsedRenewal.isAfter(now);
          final effectiveTier =
              (!isActive && !(cancelAtEnd && withinRenewalWindow))
                  ? SubscriptionTier.welcome
                  : remoteTier;
          final effectiveActive =
              isActive || (cancelAtEnd && withinRenewalWindow);

          // ── Downgrade guard ──────────────────────────────────────────────
          // Skip adopting a remote downgrade if the local subscription was
          // upgraded very recently (within 5 minutes), which indicates the
          // remote doc is stale from before the purchase webhook arrived.
          final localTierIndex   = _subscription.tier.index;
          final effectiveTierIdx = effectiveTier.index;
          final isRemoteDowngrade = effectiveTierIdx < localTierIndex;
          final localIsRecent =
              now.difference(_subscription.startDate) <
                  const Duration(minutes: 5);
          if (isRemoteDowngrade && localIsRecent) {
            // Local purchase is very fresh — remote is likely stale.
            // Skip sync this startup; next cold-start will see the real doc.
            if (kDebugMode) {
              debugPrint('[SubscriptionService] remote-sync: skipping stale '
                  'downgrade (local upgraded ${now.difference(_subscription.startDate).inSeconds}s ago)');
            }
          } else {
            // ── Adopt remote if it differs from local ────────────────────
            final localDiffers = _subscription.tier != effectiveTier ||
                _subscription.isActive != effectiveActive;
            if (localDiffers) {
              _subscription = UserSubscription(
                tier: effectiveTier,
                billingPeriod: remotePeriod,
                startDate: _subscription.startDate,
                renewalDate: parsedRenewal,
                isActive: effectiveActive,
                cancelledAtPeriodEnd: cancelAtEnd,
                scheduledTier: schedTierStr == null
                    ? null
                    : SubscriptionTier.values.firstWhere(
                        (t) => t.name == schedTierStr,
                        orElse: () => SubscriptionTier.welcome),
                scheduledPeriod: schedPeriodStr == null
                    ? null
                    : BillingPeriod.values.firstWhere(
                        (p) => p.name == schedPeriodStr,
                        orElse: () => BillingPeriod.monthly),
              );
              if (kDebugMode) {
                debugPrint('[SubscriptionService] remote-sync adopted: '
                    'tier=${effectiveTier.name} active=$effectiveActive');
              }
            }
          }
        }
      }
    } catch (_) {
      // Non-fatal — offline or Firestore unavailable; local state is fine.
    }

    _initialized = true;
    // CRITICAL: Use Future.delayed(Duration.zero) instead of addPostFrameCallback.
    // When initialize() is called from main() before runApp(), any
    // addPostFrameCallback registered at that point fires DURING the very first
    // build frame (because that IS the next frame), causing the same
    // setState-during-build crash we're trying to avoid.
    // Future.delayed(Duration.zero) schedules on the microtask/event queue,
    // guaranteed to run AFTER the current build cycle completes.
    Future.delayed(Duration.zero, () {
      if (hasListeners) notifyListeners();
    });
  }

  Future<void> _persist() async {
    await BrowserStorage.setString(_subKey, jsonEncode(_subscription.toJson()));
    await BrowserStorage.setString(_usageKey, jsonEncode(_usageCounts));
    // Non-blocking Firestore sync so other devices get the updated state
    _syncToFirestore();
  }

  /// Persist only usage counts (not subscription state).
  /// Used by lifetime record methods to avoid unnecessary Firestore subscription syncs.
  Future<void> _persistUsage() async {
    await BrowserStorage.setString(_usageKey, jsonEncode(_usageCounts));
  }

  // ── Firestore sync — write subscription state for cross-device consistency ───
  Future<void> _syncToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(uid)
          .set({
        'tier': _subscription.tier.name,
        'billingPeriod': _subscription.billingPeriod.name,
        'renewalDate': _subscription.renewalDate?.millisecondsSinceEpoch,
        'isActive': _subscription.isActive,
        'cancelledAtPeriodEnd': _subscription.cancelledAtPeriodEnd,
        'scheduledTier': _subscription.scheduledTier?.name,
        'scheduledPeriod': _subscription.scheduledPeriod?.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal — local state is still persisted
    }
  }

  // ===========================================================================
  // FIRESTORE RESTORE
  // Called by FirebaseAuthService.restoreProfileFromFirestore() on fresh
  // installs to reinstate a paid subscription from Firestore data so the user
  // does not lose their tier when BrowserStorage is empty.
  // ===========================================================================

  Future<void> restoreFromFirestore({
    required SubscriptionTier tier,
    required BillingPeriod period,
    DateTime? renewalDate,
    bool isFoundingMember = false,
  }) async {
    if (!_initialized) await initialize();

    // Only restore if the local subscription is currently on Welcome (free).
    // If the user already has a paid local subscription, leave it untouched.
    if (!_subscription.isFree) return;

    final now = DateTime.now();
    _subscription = UserSubscription(
      tier: tier,
      billingPeriod: period,
      startDate: now,
      renewalDate: renewalDate ?? now.add(const Duration(days: 365)),
      isActive: true,
      cancelledAtPeriodEnd: false,
      scheduledTier: null,
      scheduledPeriod: null,
    );

    await _persist();
    notifyListeners();
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
  // P10: Photo upload gating
  int get photosUploaded => _usage('photos_uploaded');
  bool get canUploadPhoto =>
      TierLimits.isUnlimited(limits.maxPhotoUploads) ||
      photosUploaded < limits.maxPhotoUploads;
  Future<void> recordPhotoUpload() => _incrementUsage('photos_uploaded');

  // ===========================================================================
  // AI FEATURE -- USAGE GETTERS
  // ===========================================================================

  int get aiCopilotChatsToday => _usage('ai_copilot_today');
  int get aiEventDiscoveriesThisWeek => _usage('ai_event_disc_week');
  int get aiChatSummariesToday => _usage('ai_chat_sum_today');
  int get aiListingGenerationsThisMonth => _usage('ai_listing_gen_month');
  int get aiMatchmakerRequestsThisMonth => _usage('ai_matchmaker_month');
  int get aiSmartFeedRefreshesToday => _usage('ai_feed_today');

  // ===========================================================================
  // CORE SOCIAL -- FEATURE GATING (can the user do X?)
  // ===========================================================================

  bool get canJoinGroup => groupsJoined < limits.maxGroups;
  bool get canCreateGroup => groupsCreated < limits.maxGroupsCreated;
  bool get canCreateMeetup => meetupsThisMonth < limits.maxMeetupsPerMonth;
  bool get canStartDM => dmConversations < limits.maxDMConversations;
  // ── Listings created (lifetime) ────────────────────────────────────────────
  int get listingsCreatedTotal =>
      _usageCounts[_listingsCreatedKey] ?? 0;
  int get listingsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxListingsCreatedLifetime)
          ? 999
          : (limits.maxListingsCreatedLifetime - listingsCreatedTotal)
              .clamp(0, limits.maxListingsCreatedLifetime);
  bool get canCreateListing =>
      TierLimits.isUnlimited(limits.maxListingsCreatedLifetime) ||
      listingsCreatedTotal < limits.maxListingsCreatedLifetime;
  bool get canSendMessage => messagesThisMonth < limits.maxMessagesPerMonth;

  // ── Buyer contacts (lifetime) ─────────────────────────────────────────────
  int get buyerContactsTotal =>
      _usageCounts[_buyerContactsKey] ?? 0;
  int get buyerContactsRemaining =>
      TierLimits.isUnlimited(limits.maxBuyerContactsLifetime)
          ? 999
          : (limits.maxBuyerContactsLifetime - buyerContactsTotal)
              .clamp(0, limits.maxBuyerContactsLifetime);
  bool get canContactSeller =>
      TierLimits.isUnlimited(limits.maxBuyerContactsLifetime) ||
      buyerContactsTotal < limits.maxBuyerContactsLifetime;

  // ── User-created groups (lifetime) ───────────────────────────────────────
  int get userGroupsCreatedTotal =>
      _usageCounts[_userGroupsCreatedKey] ?? 0;
  int get userGroupsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxUserCreatedGroupsLifetime)
          ? 999
          : (limits.maxUserCreatedGroupsLifetime - userGroupsCreatedTotal)
              .clamp(0, limits.maxUserCreatedGroupsLifetime);
  bool get canCreateUserGroup =>
      TierLimits.isUnlimited(limits.maxUserCreatedGroupsLifetime) ||
      userGroupsCreatedTotal < limits.maxUserCreatedGroupsLifetime;

  // ── Free meetups created (lifetime) ──────────────────────────────────────
  int get freeMeetupsCreatedTotal =>
      _usageCounts[_freeMeetupsCreatedKey] ?? 0;
  int get freeMeetupsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxFreeMeetupsLifetime)
          ? 999
          : (limits.maxFreeMeetupsLifetime - freeMeetupsCreatedTotal)
              .clamp(0, limits.maxFreeMeetupsLifetime);
  bool get canCreateFreeMeetup =>
      TierLimits.isUnlimited(limits.maxFreeMeetupsLifetime) ||
      freeMeetupsCreatedTotal < limits.maxFreeMeetupsLifetime;

  // ── Polls created (lifetime) ──────────────────────────────────────────────
  int get pollsCreatedTotal =>
      _usageCounts[_pollsCreatedKey] ?? 0;
  int get pollsCreatedRemaining =>
      TierLimits.isUnlimited(limits.maxPollsCreatedLifetime)
          ? 999
          : (limits.maxPollsCreatedLifetime - pollsCreatedTotal)
              .clamp(0, limits.maxPollsCreatedLifetime);
  bool get canCreatePoll =>
      TierLimits.isUnlimited(limits.maxPollsCreatedLifetime) ||
      pollsCreatedTotal < limits.maxPollsCreatedLifetime;

  // ── Q&A questions (lifetime) ──────────────────────────────────────────────
  int get questionsPostedTotal =>
      _usageCounts[_questionsPostedKey] ?? 0;
  int get questionsPostedRemaining =>
      TierLimits.isUnlimited(limits.maxQuestionsLifetime)
          ? 999
          : (limits.maxQuestionsLifetime - questionsPostedTotal)
              .clamp(0, limits.maxQuestionsLifetime);
  bool get canPostQuestion =>
      TierLimits.isUnlimited(limits.maxQuestionsLifetime) ||
      questionsPostedTotal < limits.maxQuestionsLifetime;

  // ── Saved items (lifetime) ────────────────────────────────────────────────
  int get savedItemsTotal =>
      _usageCounts[_savedItemsKey] ?? 0;
  int get savedItemsRemaining =>
      TierLimits.isUnlimited(limits.maxSavedItemsLifetime)
          ? 999
          : (limits.maxSavedItemsLifetime - savedItemsTotal)
              .clamp(0, limits.maxSavedItemsLifetime);
  bool get canSaveItem =>
      TierLimits.isUnlimited(limits.maxSavedItemsLifetime) ||
      savedItemsTotal < limits.maxSavedItemsLifetime;

  // ── AI saved summaries (lifetime) ────────────────────────────────────────
  int get aiSavedSummariesTotal =>
      _usageCounts[_aiSavedSummariesKey] ?? 0;
  int get aiSavedSummariesRemaining =>
      TierLimits.isUnlimited(limits.maxAiSavedSummariesLifetime)
          ? 999
          : (limits.maxAiSavedSummariesLifetime - aiSavedSummariesTotal)
              .clamp(0, limits.maxAiSavedSummariesLifetime);
  bool get canUseAiSavedSummary =>
      TierLimits.isUnlimited(limits.maxAiSavedSummariesLifetime) ||
      aiSavedSummariesTotal < limits.maxAiSavedSummariesLifetime;

  // ── Listing duration days ─────────────────────────────────────────────────
  int get listingDurationDays => limits.listingDurationDays;
  bool get hasUnlimitedListingDuration =>
      TierLimits.isUnlimited(limits.listingDurationDays);


  bool get canCreatePrivateGroup => limits.canCreatePrivateGroups;
  bool get canCreateMeetupFeature => limits.canCreateMeetups;
  bool get canCreateEvent => canCreateMeetupFeature; // backward-compat
  bool get isAdFree => true; // App has no ads
  bool get hasBadge => limits.customProfileBadge;
  bool get hasMilestoneTracker => false; // Feature removed

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

  /// AI Meetup Matchmaker: parent compatibility scoring & suggested meetups
  bool get hasAiMeetupMatchmaker => limits.aiMeetupMatchmaker;
  bool get canUseAiMatchmaker =>
      limits.aiMeetupMatchmaker &&
      aiMatchmakerRequestsThisMonth < limits.maxAiMatchmakerRequestsPerMonth;

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
  Future<void> recordAiMatchmakerRequest() =>
      _incrementUsage('ai_matchmaker_month');
  Future<void> recordAiSmartFeedRefresh() =>
      _incrementUsage('ai_feed_today');


  // ===========================================================================
  // USAGE RECORDING -- Lifetime gates (NEVER reset monthly)
  // ===========================================================================

  Future<void> recordListingCreated() async {
    if (TierLimits.isUnlimited(limits.maxListingsCreatedLifetime)) return;
    _usageCounts[_listingsCreatedKey] =
        (_usageCounts[_listingsCreatedKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordBuyerContact() async {
    if (TierLimits.isUnlimited(limits.maxBuyerContactsLifetime)) return;
    _usageCounts[_buyerContactsKey] =
        (_usageCounts[_buyerContactsKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordUserGroupCreated() async {
    if (TierLimits.isUnlimited(limits.maxUserCreatedGroupsLifetime)) return;
    _usageCounts[_userGroupsCreatedKey] =
        (_usageCounts[_userGroupsCreatedKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordFreeMeetupCreated() async {
    if (TierLimits.isUnlimited(limits.maxFreeMeetupsLifetime)) return;
    _usageCounts[_freeMeetupsCreatedKey] =
        (_usageCounts[_freeMeetupsCreatedKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordPollCreated() async {
    if (TierLimits.isUnlimited(limits.maxPollsCreatedLifetime)) return;
    _usageCounts[_pollsCreatedKey] =
        (_usageCounts[_pollsCreatedKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordQuestionPosted() async {
    if (TierLimits.isUnlimited(limits.maxQuestionsLifetime)) return;
    _usageCounts[_questionsPostedKey] =
        (_usageCounts[_questionsPostedKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordSavedItem() async {
    if (TierLimits.isUnlimited(limits.maxSavedItemsLifetime)) return;
    _usageCounts[_savedItemsKey] =
        (_usageCounts[_savedItemsKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  Future<void> recordAiSavedSummary() async {
    if (TierLimits.isUnlimited(limits.maxAiSavedSummariesLifetime)) return;
    _usageCounts[_aiSavedSummariesKey] =
        (_usageCounts[_aiSavedSummariesKey] ?? 0) + 1;
    await _persistUsage();
    notifyListeners();
  }

  // ===========================================================================
  // SUBSCRIPTION PURCHASE / UPGRADE / DOWNGRADE
  //
  // BILLING-CYCLE POLICY:
  //   • Purchasing from Welcome (free) activates immediately.
  //   • Switching between paid tiers (upgrade or downgrade) is *scheduled*
  //     — the new tier/period take effect on the next renewalDate.
  //   • Cancelling sets cancelledAtPeriodEnd = true; the user keeps full
  //     access at the current tier until renewalDate, after which the sub
  //     reverts to Welcome.
  //   • A scheduled change can be *revoked* (revert to current plan).
  // ===========================================================================

  /// Simulate purchasing a subscription (in production, this goes through
  /// Apple/Google IAP). Returns true on success.
  Future<bool> purchase(SubscriptionTier newTier, BillingPeriod period) async {
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
      scheduledTier: null,
      scheduledPeriod: null,
      cancelledAtPeriodEnd: false,
    );

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
          'SubscriptionService: Upgraded to ${newTier.name} (${period.name})');
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Schedule a tier / period change that takes effect at next billing cycle.
  // ---------------------------------------------------------------------------

  /// Schedule a plan change (upgrade or downgrade) that activates at the
  /// start of the next billing period.
  ///
  /// During the interim the user keeps full access to the *current* tier.
  Future<bool> schedulePlanChange(
    SubscriptionTier newTier,
    BillingPeriod newPeriod,
  ) async {
    if (!_initialized) await initialize();

    // If the user is on Welcome (free) there is nothing to "schedule" —
    // an immediate purchase is appropriate.
    if (_subscription.isFree) {
      return purchase(newTier, newPeriod);
    }

    // If they chose the same tier+period they're already on, no-op.
    if (newTier == _subscription.tier &&
        newPeriod == _subscription.billingPeriod) {
      return false;
    }

    _subscription = UserSubscription(
      tier: _subscription.tier,
      billingPeriod: _subscription.billingPeriod,
      startDate: _subscription.startDate,
      renewalDate: _subscription.renewalDate,
      isActive: _subscription.isActive,
      scheduledTier: newTier,
      scheduledPeriod: newPeriod,
      cancelledAtPeriodEnd: false,
    );

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
          'SubscriptionService: Scheduled change to ${newTier.name} '
          '(${newPeriod.name}) at next billing cycle');
    }
    return true;
  }

  /// Revoke a previously-scheduled tier change so that the current plan
  /// continues to renew normally.
  Future<void> revokeScheduledChange() async {
    if (!_initialized) await initialize();
    if (!_subscription.hasScheduledChange &&
        !_subscription.cancelledAtPeriodEnd) {
      return;
    }

    _subscription = UserSubscription(
      tier: _subscription.tier,
      billingPeriod: _subscription.billingPeriod,
      startDate: _subscription.startDate,
      renewalDate: _subscription.renewalDate,
      isActive: _subscription.isActive,
      scheduledTier: null,
      scheduledPeriod: null,
      cancelledAtPeriodEnd: false,
    );

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint('SubscriptionService: Revoked scheduled change / cancellation');
    }
  }


  /// Cancel subscription -- sets cancelledAtPeriodEnd so the user retains
  /// access at the current tier until the end of the billing period.
  ///
  /// After [renewalDate] the subscription will revert to the free tier.
  Future<void> cancelSubscription() async {
    if (!_initialized) await initialize();

    // If the user is already free, just reset.
    if (_subscription.isFree) {
      _subscription = UserSubscription.welcome();
      await _persist();
      notifyListeners();
      return;
    }

    _subscription = UserSubscription(
      tier: _subscription.tier,
      billingPeriod: _subscription.billingPeriod,
      startDate: _subscription.startDate,
      renewalDate: _subscription.renewalDate,
      isActive: true, // still active until renewalDate
      scheduledTier: null, // clear any scheduled change
      scheduledPeriod: null,
      cancelledAtPeriodEnd: true,
    );

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint(
          'SubscriptionService: Cancelled — access until '
          '${_subscription.renewalDate}');
    }
  }

  /// Reactivate a cancelled subscription (undo cancellation).
  Future<void> reactivateSubscription() async {
    if (!_initialized) await initialize();
    if (!_subscription.cancelledAtPeriodEnd) return;

    _subscription = UserSubscription(
      tier: _subscription.tier,
      billingPeriod: _subscription.billingPeriod,
      startDate: _subscription.startDate,
      renewalDate: _subscription.renewalDate,
      isActive: true,
      scheduledTier: null,
      scheduledPeriod: null,
      cancelledAtPeriodEnd: false,
    );

    await _persist();
    notifyListeners();

    if (kDebugMode) {
      debugPrint('SubscriptionService: Reactivated subscription');
    }
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
      // ── Lifetime-gated features (Plus unlocks) ────────────────────────────
      case 'listings_created':
      case 'buyer_contacts':
      case 'user_groups':
      case 'free_meetups':
      case 'polls':
      case 'questions':
      case 'saved_items':
      case 'ai_saved_summaries':
      case 'service_contact':
      // Core social -- Plus
      case 'paid_meetups':
      case 'private_groups':
      case 'meetups':
      case 'events':
      case 'profile_badge':
      // AI -- Plus
      case 'ai_listing_generator':
      case 'ai_chat_summaries':
      case 'ai_event_recommendations':
      case 'ai_full_copilot':
      case 'ai_full_chat_summaries':
      case 'ai_full_event_discovery':
        return SubscriptionTier.plus;

      // ── Partner-exclusive features ────────────────────────────────────────
      case 'business_profile':
      case 'partner_analytics':
      case 'endorsement_replies':
      case 'feed_promotion':
      case 'unlimited_service_listings':
      case 'ai_matchmaker':
      case 'unlimited_ai':
        return SubscriptionTier.partner;

      // Free tier features
      case 'ai_copilot_basic':
      case 'ai_event_discovery_basic':
      case 'ai_smart_feed_basic':
      case 'ai_recommendations_basic':
        return SubscriptionTier.welcome;

      default:
        return SubscriptionTier.welcome;
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
      // ── Lifetime gate messages ─────────────────────────────────────────────
      case 'listings_created':
        return 'Free members can create up to ${limits.maxListingsCreatedLifetime} '
            'listings. Upgrade to Huddl Plus for unlimited listings with 60-day duration.';
      case 'buyer_contacts':
        return 'Free members can contact up to ${limits.maxBuyerContactsLifetime} '
            'sellers. Upgrade to Huddl Plus for unlimited messages and offers.';
      case 'user_groups':
        return 'Free members can create up to ${limits.maxUserCreatedGroupsLifetime} '
            'hobby groups. Upgrade to Huddl Plus for unlimited groups.';
      case 'free_meetups':
        return 'Free members can create up to ${limits.maxFreeMeetupsLifetime} '
            'meetups. Upgrade to Huddl Plus to organise unlimited meetups.';
      case 'polls':
        return 'Free members can create up to ${limits.maxPollsCreatedLifetime} '
            'polls. Upgrade to Huddl Plus for unlimited polls.';
      case 'questions':
        return 'Free members can post up to ${limits.maxQuestionsLifetime} '
            'questions. Upgrade to Huddl Plus for unlimited community Q&A.';
      case 'saved_items':
        return 'Free members can save up to ${limits.maxSavedItemsLifetime} '
            'items. Upgrade to Huddl Plus to save everything you find.';
      case 'ai_saved_summaries':
        return 'Free members get ${limits.maxAiSavedSummariesLifetime} '
            'AI saved summaries. Upgrade to Huddl Plus for unlimited intelligent search of your saves.';
      case 'service_contact':
        return 'Contact trusted local childminders, tutors and classes directly. '
            'Upgrade to Huddl Plus for unlimited service provider contact.';

      // Core social limits
      case 'groups_join':
        return 'You\'ve joined $tierName\'s max of ${limits.maxGroups} groups. Upgrade to Huddl Plus for unlimited groups!';
      case 'groups_create':
        return 'You\'ve hit the $tierName limit of ${limits.maxGroupsCreated} created groups. Upgrade to create more!';
      case 'meetups':
        return 'You\'ve used your $tierName allowance of ${limits.maxMeetupsPerMonth} meetups this month. Upgrade for unlimited!';
      case 'dm':
        return 'You\'ve reached the $tierName limit of ${limits.maxDMConversations} conversations. Upgrade for unlimited messaging!';
      case 'listings':
        return 'You\'ve reached the $tierName limit of ${limits.maxMarketplaceListings} listings. Upgrade for more!';
      case 'messages':
        return 'You\'ve sent ${limits.maxMessagesPerMonth} messages this month. Upgrade to Huddl Plus for unlimited messaging!';
      case 'private_groups':
        return 'Private groups are a Huddl Plus feature. Upgrade to create private groups!';
      case 'events':
        return 'Meetup creation is a Huddl Plus feature. Upgrade to create and host meetups!';

      // AI limits
      case 'ai_copilot':
        return 'You\'ve used your ${limits.maxAiCopilotChatsPerDay} AI Copilot chats today. Upgrade to Huddl Plus for 25 chats/day!';
      case 'ai_chat_summaries':
        return 'You\'ve used your ${limits.maxAiChatSummariesPerDay} AI chat summary today. Upgrade for up to 10 summaries/day!';
      case 'ai_listing_generator':
        return 'AI Listing Writer is a Huddl Plus feature. Upgrade to auto-generate listings from photos!';
      case 'ai_matchmaker':
        return 'AI Meetup Matchmaker is exclusive to Huddl Partner — '
            'it finds compatible parents nearby and suggests the perfect meetup.';
      case 'ai_event_discovery':
        return 'You\'ve used your weekly AI event discovery. Upgrade to Huddl Plus for daily discovery!';
      case 'ai_smart_feed':
        return 'You\'ve used your daily smart feed refreshes. Upgrade for unlimited personalisation!';
      case 'community_qa':
        return 'You\'ve reached your $tierName weekly question limit. Upgrade to Huddl Plus for 15 questions/week!';

      default:
        return 'This feature requires a higher plan. Upgrade to unlock it!';
    }
  }
}
