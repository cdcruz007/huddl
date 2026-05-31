import 'package:flutter/foundation.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/animations/huddl_spring_animations.dart';
import '../../widgets/animations/huddl_loading_states.dart';
import '../../theme/huddl_animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/image_editor_widget.dart';
import '../../widgets/huddl_character.dart';
import '../../widgets/huddl_empty_states.dart';
import 'dart:convert';
import '../../theme/huddl_colors.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/postcode_service.dart';
import '../../services/browser_storage.dart';
import '../../services/saved_message_service.dart';
import '../../services/event_service.dart';
import '../../services/meetup_service.dart';
import '../../services/block_service.dart';
import '../../services/dm_service.dart';
import '../../services/invitation_service.dart';
import '../../services/community_feed_service.dart';
import '../../services/announcement_service.dart';
import '../../models/group.dart';
import '../main_shell.dart';
import '../../services/tutorial_service.dart';
import '../../services/feedback_service.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';
import '../../utils/borough_migration_service.dart';
import '../../services/gdpr_borough_data_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/huddl_user_service.dart';
import '../../services/photo_upload_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/user_privacy_prefs_service.dart';
import '../../services/biometric_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/rehome_service.dart';
import 'dart:io';
import '../../constants/app_text_styles.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final OnboardingDataService _onboarding = OnboardingDataService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final PostcodeService _postcodeService = PostcodeService();
  final EventService _eventService = EventService();
  final MeetupService _meetupService = MeetupService();
  final BlockService _blockService = BlockService();
  final FeedbackService _feedbackService = FeedbackService();
  final SubscriptionService _subscriptionService = SubscriptionService();

  bool _isLoading = true;
  bool _isPhotoUploading = false; // true while photo is being read/encoded
  final _photoUpload = PhotoUploadService();

  // Dynamic profile data
  String _name = '';

  String _borough = '';
  String? _bio;
  String? _photoUrl;
  String _parentType = '';
  List<String> _stagesOfLife = [];
  List<Map<String, String>> _children = [];
  String? _dueDate;
  String? _phone;
  String? _postcode;

  // Groups the user belongs to
  List<Group> _userGroups = [];
  // Groups joined from Discover tab
  List<Group> _discoveredGroups = [];
  // Events and meetups
  List<Event> _userEvents = [];
  List<Meetup> _userMeetups = [];

  // ImagePicker no longer needed - using ImageEditorWidget instead
  // final ImagePicker _picker = ImagePicker();

  // Notification settings (persisted)
  bool _pushEnabled = true;
  bool _groupMessages = true;
  bool _dmMessages = true;
  bool _eventReminders = true;
  bool _communityUpdates = true;
  bool _lockScreenAlerts = true;

  // Privacy settings (persisted)
  bool _showOnline = true;
  bool _showProfile = true;
  bool _showGroups = true;
  bool _readReceipts = true;

  // Voice message consent (GDPR — explicit opt-in, default: false)
  bool _voiceConsent = false;

  // Admin flag — loaded from Firestore users/{uid}/roles.isAdmin
  bool _isAdmin = false;

  // Biometric login
  final _biometricService = BiometricAuthService();
  bool _biometricEnabled   = false;
  bool _biometricAvailable = false;
  String _biometricLabel   = 'Biometrics';

  // App version — populated dynamically from pubspec.yaml via package_info_plus
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _blockService.initialize();
    _feedbackService.initialize();
    _subscriptionService.initialize();
    // Defer ALL listener registration and data loading until after first frame.
    // SubscriptionService.notifyListeners() fires on initialize() completion —
    // adding the listener before that completes causes setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _subscriptionService.addListener(_onSubChange);
        _loadProfileData();
        _loadSettings();
      }
    });
  }

  void _onSubChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _subscriptionService.removeListener(_onSubChange);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Load from storage into the shared singleton, then copy to local state.
    await UserPrivacyPrefsService().load();
    final svc = UserPrivacyPrefsService();
    if (mounted) {
      setState(() {
        _pushEnabled      = svc.pushEnabled;
        _groupMessages    = svc.groupMessages;
        _dmMessages       = svc.dmMessages;
        _eventReminders   = svc.eventReminders;
        _communityUpdates = svc.communityUpdates;
        _lockScreenAlerts = svc.lockScreenAlerts;
        _showOnline       = svc.showOnlineStatus;
        _showProfile      = svc.profileVisibility;
        _showGroups       = svc.showGroups;
        _readReceipts     = svc.readReceipts;
        _voiceConsent     = svc.voiceMessageConsent;
      });
    }
    // Load biometric state (non-blocking)
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final available = await _biometricService.isAvailable;
    final enabled   = await _biometricService.isEnabled;
    final label     = await _biometricService.biometricLabel;
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled   = enabled;
        _biometricLabel     = label;
      });
    }
  }

  /// Checks whether the signed-in user has the `roles.isAdmin == true` flag
  /// set on their Firestore document.  Fails silently — never blocks the UI.
  Future<void> _loadAdminRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final roles = doc.data()?['roles'] as Map<String, dynamic>?;
      final isAdmin = roles?['isAdmin'] == true;
      if (mounted && isAdmin != _isAdmin) {
        setState(() => _isAdmin = isAdmin);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Profile] admin role check failed: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    // Persist to storage AND update the shared singleton so other screens
    // can immediately read the new value without reloading.
    await UserPrivacyPrefsService().setSetting(key, value);
    // Sync notification prefs to Firestore so the backend respects them
    // when sending FCM push notifications.
    const notifKeys = {
      UserPrivacyPrefsService.keyPushEnabled,
      UserPrivacyPrefsService.keyGroupMessages,
      UserPrivacyPrefsService.keyDmMessages,
      UserPrivacyPrefsService.keyEventReminders,
      UserPrivacyPrefsService.keyCommunityUpdates,
      UserPrivacyPrefsService.keyLockScreenAlerts,
    };
    if (notifKeys.contains(key)) {
      PushNotificationService().syncPrefsToFirestore();
    }
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);

    // ── Admin role check (non-blocking — runs alongside main load) ──────────
    // Reads users/{uid}/roles.isAdmin from Firestore.
    // Fails silently so a Firestore error never blocks the profile from loading.
    _loadAdminRole();

    // ── App version (non-blocking) ───────────────────────────────────────────
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    }).catchError((_) {}); // keep hardcoded fallback on failure

    try {
      // Force-reload from storage on every profile load so we always
      // pick up values written by syncCurrentUserProfile / restoreProfile
      // even if the singleton was already initialised with stale empty data.
      await _onboarding.initialize(forceReload: true);

      // If local name is still missing after the fresh storage read,
      // go directly to Firestore as the authoritative source.
      if (_onboarding.name == null || _onboarding.name!.trim().isEmpty) {
        try {
          await FirebaseAuthService().restoreProfileFromFirestore()
              .timeout(const Duration(seconds: 5));
          // Force-reload again so the values just written by restore are read.
          // restoreProfileFromFirestore() now calls flush() before returning so
          // SharedPreferences is guaranteed up-to-date before we re-read here.
          await _onboarding.initialize(forceReload: true);
        } catch (_) {}
      }

      // ── ABSOLUTE LAST RESORT: bypass OnboardingDataService entirely ──────────
      // If, despite all restore attempts, the name is still empty (edge case:
      // flush/reload race on extremely slow devices, or a Hive/SharedPreferences
      // write failure), read the Firestore document directly and populate the
      // local state variables for this render pass. This is purely defensive —
      // most users will never hit this path, but it ensures the profile is NEVER
      // blank when a Firestore document exists.
      if (_onboarding.name == null || _onboarding.name!.trim().isEmpty) {
        try {
          String? resolvedUid = FirebaseAuth.instance.currentUser?.uid;
          if (resolvedUid == null) {
            final user = await FirebaseAuth.instance
                .authStateChanges()
                .first
                .timeout(const Duration(seconds: 5));
            resolvedUid = user?.uid;
          }
          if (resolvedUid != null) {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(resolvedUid)
                .get()
                .timeout(const Duration(seconds: 5));
            if (doc.exists) {
              final d = doc.data()!;
              // Inject directly into the singleton's in-memory state AND flush
              final n = (d['name'] as String?)?.trim() ??
                  (d['firstName'] as String?)?.trim() ?? '';
              if (n.isNotEmpty) _onboarding.setName(n);
              final pc = (d['postcode'] as String?) ?? '';
              if (pc.isNotEmpty && (_onboarding.postcode == null || _onboarding.postcode!.isEmpty)) {
                _onboarding.setPostcode(pc);
              }
              final br = (d['borough'] as String?) ?? '';
              if (br.isNotEmpty && (_onboarding.borough == null || _onboarding.borough!.isEmpty)) {
                _onboarding.setBorough(br);
              }
              final pt = (d['parentType'] as String?) ?? '';
              if (pt.isNotEmpty && _onboarding.parentType == null) {
                _onboarding.setParentType(pt);
              }
              final kids = d['children'];
              if (kids is List && kids.isNotEmpty && _onboarding.children.isEmpty) {
                _onboarding.setChildren(
                  kids.whereType<Map>().map((c) => {
                    'name': (c['name'] as String?) ?? '',
                    'birthday': (c['birthday'] as String?) ?? '',
                  }).where((c) => c['name']!.isNotEmpty).toList(),
                );
              }
              final bio = (d['bio'] as String?) ?? '';
              if (bio.isNotEmpty && (_onboarding.bio == null || _onboarding.bio!.isEmpty)) {
                _onboarding.setBio(bio);
              }
              // Flush synchronously so storage is ready for the next cold start
              await _onboarding.flush();
              if (kDebugMode) debugPrint('[Profile] last-resort Firestore direct read: name=$n');
            }
          }
        } catch (_) {}
      }

      await _groupService.initialize();

      String borough = 'Not set';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? 'Unknown';
      }

      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      final defaultGroups = await _groupService.getUserGroups(currentUid);

      // ── Always query Firestore for the full membership list ─────────────
      // Previously Firestore was only queried when the local cache was empty,
      // so groups joined on other devices / sessions were never shown.
      // Firestore is now the authoritative source on every profile open;
      // the local BrowserStorage cache is used only as an instant-display
      // fallback while the network call is in flight (not implemented here —
      // we await the Firestore call so the list is always fresh).
      List<Group> discovered = [];
      try {
        final defaultGroupIds = defaultGroups.map((g) => g.id).toSet();
        final firestoreGroups = await FirestoreService()
            .getMyGroups()
            .timeout(const Duration(seconds: 6));
        // Exclude groups already covered by DefaultGroupService so we don't
        // show duplicates in the horizontal card list.
        // ALSO exclude default onboarding groups that may have leaked into
        // Firestore without isImageLocked=true (e.g. created on another device
        // before the field existed, or synced before DefaultGroupService was
        // initialised). A group is considered a default group when:
        //   (a) its ID is in the local DefaultGroupService set, OR
        //   (b) isImageLocked is true on the Firestore document, OR
        //   (c) its name matches the year-based pattern "YYYY <Borough> Parents"
        //       which is exclusively used by DefaultGroupService, OR
        //   (d) its name contains onboarding keywords (aspiring/expecting/SEN)
        //       — defence-in-depth for docs created before isImageLocked existed.
        //   (e) its category is "Default Community" (written by DefaultGroupService).
        final yearGroupPattern = RegExp(r'^\d{4}\s+\S');
        const onboardingKeywords = [
          'aspiring parents', 'expecting parents', 'sen parents',
          'sen support', 'dads connect', 'toddler adventures', 'new parents',
        ];
        discovered = firestoreGroups
            .where((g) => !defaultGroupIds.contains(g.id))
            .where((g) => !g.isImageLocked)
            .where((g) => !yearGroupPattern.hasMatch(g.name))
            .where((g) => g.category != 'Default Community')
            .where((g) {
              final lower = g.name.toLowerCase();
              return !onboardingKeywords.any((kw) => lower.contains(kw));
            })
            .toList();
        // Refresh local cache so it matches current Firestore state.
        await BrowserStorage.setString(
          'user_created_groups_v1',
          json.encode(discovered.map((g) => g.toJson()).toList()),
        );
      } catch (_) {
        // Network unavailable — fall back to last-known local cache.
        final discoveredJson =
            await BrowserStorage.getString('user_created_groups_v1');
        if (discoveredJson != null) {
          try {
            final List<dynamic> decoded = json.decode(discoveredJson);
            discovered = decoded
                .map((e) => Group.fromJson(e as Map<String, dynamic>))
                .toList();
          } catch (_) {}
        }
      }

      // Only count meetups the user created (not just RSVP'd to)
      final userEvents = _eventService.goingEvents;
      final myMeetupUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
      final userMeetups = _meetupService.meetups
          .where((m) => m.organiserId == myMeetupUid || m.organiserId == 'current_user')
          .toList();

      setState(() {
        _name = _onboarding.name ?? 'User';
        _borough = borough;
        _bio = _onboarding.bio;
        // Prefer the in-memory object URL (base64 data:); fall back to the
        // persisted Firebase Storage HTTPS URL stored in profilePhotoPath.
        _photoUrl = (_onboarding.profilePhotoObjectUrl?.isNotEmpty == true)
            ? _onboarding.profilePhotoObjectUrl
            : (_onboarding.profilePhotoPath?.isNotEmpty == true &&
                   _onboarding.profilePhotoPath!.startsWith('http'))
                ? _onboarding.profilePhotoPath
                : _onboarding.profilePhotoObjectUrl;
        _parentType = _onboarding.parentType ?? '';
        _stagesOfLife = _onboarding.stagesOfLife;
        _children = _onboarding.children;
        _dueDate = _onboarding.dueDate;
        _phone = _onboarding.fullPhoneNumber;
        _postcode = _onboarding.postcode;
        _userGroups = defaultGroups;
        _discoveredGroups = discovered;
        _userEvents = userEvents;
        _userMeetups = userMeetups;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String get _stageLabel {
    final labels = <String>[];
    for (final s in _stagesOfLife) {
      switch (s) {
        case 'aspiring':
          labels.add('Trying for a baby');
        case 'expecting':
          if (_dueDate != null && _dueDate!.length >= 4) {
            labels.add('Expecting (due ${_dueDate!.substring(0, 4)})');
          } else {
            labels.add('Expecting');
          }
        case 'parent':
          if (_children.isNotEmpty) {
            final childInfo = _children.map((c) {
              final name = c['name'] ?? '';
              final year = c['birthday'] ?? '';
              if (name.isNotEmpty && year.isNotEmpty) return '$name ($year)';
              if (year.isNotEmpty) return 'Born $year';
              if (name.isNotEmpty) return name;
              return 'Child';
            }).join(', ');
            labels.add('Parent: $childInfo');
          } else {
            labels.add('Parent');
          }
        default:
          labels.add(s);
      }
    }
    return labels.join(' · ');
  }

  int get _totalGroupCount => _userGroups.length + _discoveredGroups.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBSCRIPTION CARD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSubscriptionCard() {
    final sub = _subscriptionService.subscription;
    final isFree    = sub.isFree;
    final isPartner = sub.isPartner;

    return GestureDetector(
      onTap: () async {
        await Navigator.pushNamed(
          context,
          isFree ? '/subscription_plans' : '/manage_subscription',
        );
        if (mounted) setState(() {});
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: isFree
              ? LinearGradient(
                  colors: [
                    HuddlColors.primary,
                    HuddlColors.primary.withRed(230),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isFree ? null : HuddlColors.nearBlack,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: (isFree ? HuddlColors.primary : Colors.black)
                  .withValues(alpha: 0.20),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Plan icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isFree
                    ? Icons.rocket_launch_outlined
                    : isPartner
                        ? Icons.verified_outlined
                        : Icons.home_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFree
                        ? 'Unlock your full community'
                        : isPartner
                            ? 'Huddl Partner'
                            : 'Huddl Plus',
                    style: HuddlText.body(
                        weight: FontWeight.w700, color: HuddlColors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isFree
                        ? 'Groups, AI, meetups \u2014 from \u00A34.99/mo'
                        : isPartner
                            ? '\u00A3${sub.billingPeriod == BillingPeriod.annual ? "199.00/year" : "24.99/month"}'
                            : '\u00A3${sub.billingPeriod == BillingPeriod.annual ? "39.99/year" : "4.99/month"}',
                    style: HuddlText.caption(
                        color: HuddlColors.white.withValues(alpha: 0.80)),
                  ),
                ],
              ),
            ),
            Icon(
              isFree ? Icons.arrow_forward_ios_rounded : Icons.settings_outlined,
              color: Colors.white.withValues(alpha: 0.70),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ── P11: Usage progress bars ──────────────────────────────────────────────
  Widget _buildUsageSection(dynamic hc) {
    final ss = _subscriptionService;
    final limits = ss.limits;

    // Each row shows either a live progress bar (capped) or an
    // "Unlimited" pill (999+). Always rendered — never skipped.
    Widget usageRow(String label, int used, int max) {
      final isUnlimited = TierLimits.isUnlimited(max);
      final ratio = isUnlimited ? 1.0 : (used / max).clamp(0.0, 1.0);
      final isNearLimit = !isUnlimited && ratio >= 0.8;

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: HuddlText.caption(color: hc.textSecondary)),
            ),
            if (isUnlimited)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: hc.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: HuddlColors.success.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Text('Unlimited',
                    style: HuddlText.label(color: HuddlColors.success)),
              )
            else
              Text('$used / $max',
                  style: HuddlText.caption(weight: FontWeight.w600, color: isNearLimit ? HuddlColors.error : hc.textTertiary)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: hc.divider,
              valueColor: AlwaysStoppedAnimation<Color>(
                isUnlimited
                    ? HuddlColors.success
                    : isNearLimit
                        ? HuddlColors.error
                        : HuddlColors.primary),
            ),
          ),
        ]),
      );
    }

    final bool hasCappedItems = !TierLimits.isUnlimited(limits.maxAiCopilotChatsPerDay);

    return Container(
      color: hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your plan usage',
              style: HuddlText.body(weight: FontWeight.w600, color: hc.textPrimary)),
          const SizedBox(height: 4),
          Text('This month',
              style: HuddlText.caption(color: hc.textTertiary)),
          const SizedBox(height: 14),
          usageRow('Groups joined', ss.groupsJoined, limits.maxGroups),
          usageRow('Messages sent', ss.messagesThisMonth, limits.maxMessagesPerMonth),
          usageRow('Marketplace listings', ss.marketplaceListings, limits.maxMarketplaceListings),
          usageRow('Photos uploaded', ss.photosUploaded, limits.maxPhotoUploads),
          usageRow('Meetups this month', ss.meetupsThisMonth, limits.maxMeetupsPerMonth),
          usageRow('AI chats today', ss.aiCopilotChatsToday, limits.maxAiCopilotChatsPerDay),
          if (hasCappedItems) ...[
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/subscription_plans'),
              child: Text('Upgrade for unlimited AI →',
                  style: HuddlText.caption(color: HuddlColors.primary)),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.hc.scaffold,
        body: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: HuddlSkeletonProfile(),
        ),
      );
    }

    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: hc.scaffold,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.textTertiary,
          onRefresh: _loadProfileData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Name-repair banner ──────────────────────────────────
              if (_name.isEmpty || _name == 'User' || _name.startsWith('+'))
                SliverToBoxAdapter(
                  child: GestureDetector(
                    onTap: _showEditProfileSheet,
                    child: Container(
                      width: double.infinity,
                      color: const Color(0xFFF7F7F7),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: HuddlColors.textDark, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tap here to add your name to complete your profile',
                              style: HuddlText.body(color: HuddlColors.textDark),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: HuddlColors.textDark, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              // ── Identity header ─────────────────────────────────────
              SliverToBoxAdapter(child: _buildIdentityHeader(hc, isDark)),

              // ── Stat strip ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildStatStrip(hc),
                ),
              ),

              // ── App Rating & Feedback card ───────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildFeedbackCard(),
                ),
              ),

              // ── About me ────────────────────────────────────────────
              if (_bio != null && _bio!.trim().isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      color: hc.surface,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('About me',
                              style: HuddlText.body(
                                  weight: FontWeight.w600,
                                  color: hc.textTertiary)),
                          const SizedBox(height: 8),
                          Text(_bio!,
                              style: HuddlText.body(color: hc.textPrimary)
                                  .copyWith(height: 1.5)),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── My Groups horizontal scroll ──────────────────────────
              if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildMyGroupsSection(hc),
                  ),
                ),

              // ── Upcoming section ─────────────────────────────────────
              if (_userMeetups.isNotEmpty || _userEvents.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildUpcomingSection(hc),
                  ),
                ),

              // ── Quick actions grid ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _buildQuickActionsGrid(hc),
                ),
              ),

              // ── Subscription + usage ──────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildSubscriptionCard(),
                ),
              ),
              SliverToBoxAdapter(child: _buildUsageSection(hc)),

              // ── Logout + version ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      color: hc.surface,
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        leading: const Icon(Icons.logout,
                            color: HuddlColors.error),
                        title: Text('Log out',
                            style: HuddlText.body(
                                color: HuddlColors.error)),
                        onTap: _confirmLogout,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Version $_appVersion',
                          style: HuddlText.caption(
                              color: hc.textTertiary)),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section builders ─────────────────────────────────────────────────────────

  /// Community identity header — avatar, name, location, stage badge.
  Widget _buildIdentityHeader(HuddlContextColors hc, bool isDark) {
    return Container(
      color: hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Profile', style: HuddlText.display()),
              IconButton(
                icon: Icon(Icons.settings_outlined,
                    color: hc.textPrimary),
                onPressed: _openSettingsSheet,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Avatar + camera badge
          GestureDetector(
            onTap: _changeProfilePhoto,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                _buildAvatar(),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: HuddlColors.textDark,
                    shape: BoxShape.circle,
                    border: Border.all(color: hc.surface, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 14, color: HuddlColors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Name row + tier badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _showEditProfileSheet,
                child: Text(
                  (_name.isEmpty ||
                          _name == 'User' ||
                          _name.startsWith('+'))
                      ? 'Tap to add name'
                      : _name,
                  style: HuddlText.display(
                      color: (_name.isEmpty ||
                              _name == 'User' ||
                              _name.startsWith('+'))
                          ? hc.textTertiary
                          : hc.textPrimary),
                ),
              ),
              if (_subscriptionService.isPaid) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _subscriptionService.isPartner
                        ? HuddlColors.nearBlack
                        : HuddlColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _subscriptionService.isPartner
                            ? Icons.verified_outlined
                            : Icons.home_outlined,
                        color: hc.surface,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _subscriptionService.isPartner ? 'PARTNER' : 'PLUS',
                        style: HuddlText.label(color: HuddlColors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Borough
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: HuddlColors.textHint),
              const SizedBox(width: 4),
              Text(_borough,
                  style: HuddlText.body(color: hc.textTertiary)),
            ],
          ),
          // ── Neighbourhood badge slot ────────────────────────────────────
          // Free users: locked badge slot → /subscription_plans
          // Plus/Partner: active badge with borough label
          if (!_subscriptionService.hasBadge)
            GestureDetector(
              onTap: () => Navigator.pushNamed(
                context,
                '/subscription_plans',
                arguments: {
                  'gateMessage': 'Your neighbourhood badge shows other parents '
                      'where you\'re from in Cambridge.',
                },
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: hc.inputBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: HuddlColors.divider, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 11,
                              color: HuddlColors.textTertiary),
                          const SizedBox(width: 5),
                          Text(
                            'Neighbourhood badge',
                            style: HuddlText.caption(
                                color: HuddlColors.textTertiary),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: HuddlColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Plus',
                              style: HuddlText.label(
                                  color: HuddlColors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded,
                        size: 12, color: HuddlColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      _borough.isNotEmpty
                          ? '$_borough parent'
                          : 'Huddl Plus member',
                      style: HuddlText.caption(
                        color: HuddlColors.primary,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Stage badge
          if (_stageLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HuddlColors.divider),
              ),
              child: Text(_stageLabel,
                  style: HuddlText.caption(color: HuddlColors.textDark),
                  textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }

  /// Three-stat strip: Groups | Children | Role.
  Widget _buildStatStrip(HuddlContextColors hc) {
    final roleLabel = _parentType.toLowerCase() == 'mum'
        ? 'Mum'
        : _parentType.toLowerCase() == 'dad'
            ? 'Dad'
            : _parentType.isNotEmpty
                ? _parentType[0].toUpperCase() + _parentType.substring(1)
                : '-';
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hc.divider),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(count: '$_totalGroupCount', label: 'Groups'),
          Container(width: 1, height: 32, color: hc.divider),
          _StatItem(
              count: '${_children.length}',
              label: _children.length == 1 ? 'Child' : 'Children'),
          Container(width: 1, height: 32, color: hc.divider),
          _StatItem(count: roleLabel, label: 'Role'),
        ],
      ),
    );
  }

  /// Horizontal group chip scroll.
  Widget _buildMyGroupsSection(HuddlContextColors hc) {
    return Container(
      color: hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Text('My Groups',
                    style: HuddlText.body(
                        weight: FontWeight.w600,
                        color: hc.textPrimary)),
                const Spacer(),
                GestureDetector(
                  onTap: _showMyGroupsSheet,
                  child: Text('See all $_totalGroupCount',
                      style: HuddlText.caption(
                          color: HuddlColors.textTertiary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              children: [
                ..._userGroups.map((g) => _GroupCard(group: g)),
                ..._discoveredGroups.map((g) => _GroupCard(group: g)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Next 2 upcoming meetups / events.
  Widget _buildUpcomingSection(HuddlContextColors hc) {
    final upcomingMeetups = _userMeetups.take(2).toList();
    return Container(
      color: hc.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Upcoming',
                  style: HuddlText.body(
                      weight: FontWeight.w600, color: hc.textPrimary)),
              const Spacer(),
              GestureDetector(
                onTap: _showMyEventsSheet,
                child: Text('See all',
                    style: HuddlText.caption(
                        color: HuddlColors.textTertiary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...upcomingMeetups.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ScaleOnPress(
                  scale: 0.98,
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hc.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.people_outline,
                              size: 22, color: HuddlColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title,
                                  style: HuddlText.body(
                                      weight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                  '${m.dateDisplay} \u00b7 ${m.timeDisplay}',
                                  style: HuddlText.caption(
                                      color: hc.textTertiary)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: hc.textTertiary),
                      ],
                    ),
                  ),
                ),
              )),
          if (upcomingMeetups.isEmpty)
            Center(
              child: Text('No upcoming meetups yet',
                  style: HuddlText.caption(color: hc.textTertiary)),
            ),
        ],
      ),
    );
  }

  /// 2×2 quick action grid: Find Parents, Marketplace, Noticeboard, Invite.
  Widget _buildQuickActionsGrid(HuddlContextColors hc) {
    final actions = [
      (Icons.people_outline,            'Find Parents',  HuddlColors.primary, () => Navigator.pushNamed(context, '/connect')),
      (Icons.storefront_outlined,       'Marketplace',   HuddlColors.primary, () => Navigator.pushNamed(context, '/marketplace')),
      (Icons.campaign_outlined,         'Noticeboard',   HuddlColors.primary, () => Navigator.pushNamed(context, '/noticeboard')),
      (Icons.person_add_alt_1_outlined, 'Invite Friend', HuddlColors.primary, _showInviteFriendSheet),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions',
            style: HuddlText.body(
                weight: FontWeight.w600, color: hc.textPrimary)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: actions.map((a) {
            final (icon, label, color, onTap) = a;
            return ScaleOnPress(
              scale: 0.96,
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: hc.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hc.divider),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: color),
                    ),
                    const SizedBox(width: 8),
                    Text(label,
                        style: HuddlText.caption(
                            weight: FontWeight.w600)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT PROFILE
  // ═══════════════════════════════════════════════════════════════════════════

  void _showEditProfileSheet() {
    // If name is a phone number placeholder or empty, show blank field so
    // the user can type their real name without having to clear "+44..." first
    final displayName = (_name.isEmpty || _name == 'User' || _name.startsWith('+'))
        ? ''
        : _name;
    final nameCtrl  = TextEditingController(text: displayName);
    final bioCtrl   = TextEditingController(text: _bio ?? '');

    // Track initial values to detect dirty state — Save button only active
    // when at least one field has been modified from its initial value.
    final initialName = displayName;
    final initialBio  = _bio ?? '';

    _showSheet(
      title: 'Edit Profile',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Dirty check — true if either field differs from the initial value
          final isDirty = nameCtrl.text.trim() != initialName.trim() ||
              bioCtrl.text.trim() != initialBio.trim();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              // ── Name field ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: nameCtrl,
                  maxLines: 1,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setLocal(() {}),
                  style: HuddlText.body(color: context.hc.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: HuddlText.body(color: context.hc.textTertiary),
                    prefixIcon: Icon(Icons.person_outline,
                        size: 20, color: context.hc.textTertiary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.hc.divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: HuddlColors.primary, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── Bio field — 200-char limit ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: bioCtrl,
                  maxLines: 4,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setLocal(() {}),
                  style: HuddlText.body(color: context.hc.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'About me',
                    labelStyle: HuddlText.body(color: context.hc.textTertiary),
                    prefixIcon: Icon(Icons.edit_note,
                        size: 20, color: context.hc.textTertiary),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.hc.divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: HuddlColors.primary, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    // Built-in counter shows e.g. "47/200"
                    counterStyle: HuddlText.caption(color: context.hc.textTertiary),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // ── Save Changes — only active when dirty ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HuddlButton(
                  label: 'Save Changes',
                  onPressed: isDirty
                      ? () async {
                            final newName = nameCtrl.text.trim();
                            final newBio  = bioCtrl.text.trim().isEmpty
                                ? null
                                : bioCtrl.text.trim();

                            if (newName.isNotEmpty) {
                              _onboarding.setName(newName);
                              _onboarding.setBio(newBio);
                              setState(() {
                                _name = newName;
                                _bio  = newBio;
                              });
                            }

                            // Push all changes to Firestore
                            try {
                              await HuddlUserService()
                                  .syncCurrentUserProfile()
                                  .timeout(const Duration(seconds: 5));
                            } catch (_) {}

                            if (mounted) {
                              Navigator.pop(c);
                              _snack('Profile updated');
                            }
                          }
                      : null,
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE OF LIFE
  // ═══════════════════════════════════════════════════════════════════════════

  void _showStageOfLifeSheet() {
    final selected = Set<String>.from(_stagesOfLife);
    final childrenList = List<Map<String, String>>.from(
        _children.map((c) => Map<String, String>.from(c)));
    // Due date is year-only — sanitize any legacy full-date values (e.g. '2027-01-01' → '2027')
    String rawDue = _dueDate ?? '';
    if (rawDue.contains('-')) rawDue = rawDue.substring(0, 4);
    String selectedDueYear = rawDue;

    // Parent type is LOCKED once set during onboarding
    final bool parentTypeLocked = _parentType.isNotEmpty;

    _showSheet(
      title: 'Stage of Life',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ── Parent type (locked after onboarding) ──────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: parentTypeLocked
                        ? context.hc.scaffold
                        : const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.hc.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _parentType.toLowerCase() == 'dad' ? Icons.face : Icons.face_3,
                          size: 22,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _parentType.isNotEmpty
                                  ? 'I am a ${_parentType[0].toUpperCase()}${_parentType.substring(1)}'
                                  : 'Parent type not set',
                              style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary),
                            ),
                            if (parentTypeLocked)
                              Text(
                                'Set during sign-up and cannot be changed',
                                style: HuddlText.caption(color: context.hc.textTertiary),
                              ),
                          ],
                        ),
                      ),
                      if (parentTypeLocked)
                        Icon(Icons.lock_outline,
                            size: 18, color: context.hc.textTertiary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── My journey section ─────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('My journey',
                    style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary)),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Select all that apply to you',
                    style: HuddlText.caption(color: context.hc.textTertiary)),
              ),
              const SizedBox(height: 12),

              ...[
                ('aspiring', 'Trying for a baby', Icons.favorite_outline, HuddlColors.accentCoral),
                ('expecting', 'Expecting', Icons.pregnant_woman, HuddlColors.textDark),
                ('parent', 'Already a parent', Icons.child_care, HuddlColors.nearBlack),
              ].map((entry) {
                final isOn = selected.contains(entry.$1);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: GestureDetector(
                    onTap: () {
                      setLocal(() {
                        if (isOn) {
                          selected.remove(entry.$1);
                        } else {
                          selected.add(entry.$1);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isOn
                            ? entry.$4.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isOn ? entry.$4 : HuddlColors.divider,
                          width: isOn ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: entry.$4.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(entry.$3,
                                size: 20, color: entry.$4),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(entry.$2,
                                style: HuddlText.body(color: context.hc.textPrimary)),
                          ),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isOn ? entry.$4 : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isOn ? entry.$4 : HuddlColors.gray300,
                                width: 1.5,
                              ),
                            ),
                            child: isOn
                                ? const Icon(Icons.check,
                                    size: 16, color: Colors.white)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // ── Expecting: due year picker ─────────────────────
              if (selected.contains('expecting')) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Expected due year',
                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: () {
                      final currentYear = DateTime.now().year;
                      final years = List.generate(4, (i) => currentYear + i);
                      showModalBottomSheet(
                        context: ctx,
                        backgroundColor: context.hc.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24)),
                        ),
                        builder: (yCtx) => SizedBox(
                          height: 220,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('Select due year',
                                    style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary)),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: years.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    final y = years[i].toString();
                                    final isSel = selectedDueYear == y;
                                    return ListTile(
                                      title: Text(y,
                                          style: HuddlText.body(weight: FontWeight.w500, color: HuddlColors.textDark)),
                                      trailing: isSel
                                          ? const Icon(Icons.check_circle,
                                              color: HuddlColors.primary)
                                          : null,
                                      onTap: () {
                                        Navigator.pop(yCtx);
                                        setLocal(
                                            () => selectedDueYear = y);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.hc.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.hc.divider),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 18, color: context.hc.textPrimary),
                          const SizedBox(width: 12),
                          Text(
                            selectedDueYear.isNotEmpty
                                ? selectedDueYear
                                : 'Select year',
                            style: HuddlText.body(color: HuddlColors.textHint),
                          ),
                          const Spacer(),
                          Icon(Icons.keyboard_arrow_down,
                              size: 20, color: context.hc.textTertiary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // ── Children section ───────────────────────────────
              if (selected.contains('parent')) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Children',
                          style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          setLocal(() {
                            childrenList.add({'name': '', 'birthday': ''});
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7F7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add,
                                  size: 16, color: HuddlColors.textDark),
                              const SizedBox(width: 4),
                              Text('Add child',
                                  style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textDark)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ...childrenList.asMap().entries.map((e) {
                  final i = e.key;
                  final nameC =
                      TextEditingController(text: e.value['name'] ?? '');
                  final yearC =
                      TextEditingController(text: e.value['birthday'] ?? '');
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: HuddlColors.nearBlack.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.nearBlack)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: nameC,
                              onChanged: (v) => childrenList[i]['name'] = v,
                              style: HuddlText.body(),
                              decoration: InputDecoration(
                                hintText: 'Name',
                                hintStyle: HuddlText.body(color: context.hc.textTertiary),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                        color: context.hc.divider)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: HuddlColors.primary, width: 2)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: yearC,
                              keyboardType: TextInputType.number,
                              onChanged: (v) =>
                                  childrenList[i]['birthday'] = v,
                              style: HuddlText.body(),
                              decoration: InputDecoration(
                                hintText: 'Year',
                                hintStyle: HuddlText.body(color: context.hc.textTertiary),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(
                                        color: context.hc.divider)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: HuddlColors.primary, width: 2)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              setLocal(() => childrenList.removeAt(i));
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: HuddlColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.close,
                                  size: 16, color: HuddlColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 28),

              // ── Save button ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HuddlButton(
                  label: 'Save Changes',
                  onPressed: selected.isEmpty
                      ? null
                      : () async {
                          // OTP verification for stage of life changes
                          Navigator.pop(c);
                          final verified = await _verifyWithOtp(
                              'update your stage of life');
                          if (!verified) {
                            _snack('Stage of life change cancelled');
                            return;
                          }

                          // Save to onboarding (parent type stays locked)
                          _onboarding.setStagesOfLife(selected.toList());
                          if (selectedDueYear.isNotEmpty) {
                            _onboarding.setDueDate(selectedDueYear);
                          }
                          final validChildren = childrenList
                              .where((ch) =>
                                  (ch['name'] ?? '').isNotEmpty ||
                                  (ch['birthday'] ?? '').isNotEmpty)
                              .toList();
                          _onboarding.setChildren(validChildren);

                          setState(() {
                            _stagesOfLife = selected.toList();
                            _dueDate = selectedDueYear.isEmpty
                                ? null
                                : selectedDueYear;
                            _children = validChildren;
                          });

                          // Recreate default groups for updated stages
                          // This ensures new groups appear in the Messages tab
                          await _groupService.recreateGroupsForStages(
                            userId: FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
                            stages: selected.toList(),
                            postcode: _postcode,
                          );
                          await _loadProfileData();
                          _snack(
                              'Stage of life updated \u2014 your groups have been refreshed');
                        },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOCATION / POSTCODE CHANGE
  // ═══════════════════════════════════════════════════════════════════════════

  void _showLocationSheet() {
    final postcodeCtrl = TextEditingController(text: _postcode ?? '');

    _showSheet(
      title: 'Change Location',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: HuddlColors.textDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changing your postcode will update your borough and default groups. Only Cambridge postcodes are accepted.',
                        style: HuddlText.caption(color: HuddlColors.textDark).copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Current: $_borough${_postcode != null ? ' ($_postcode)' : ''}',
                  style: HuddlText.body(color: context.hc.textSecondary)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _sheetField(postcodeCtrl, 'New postcode', Icons.location_on_outlined),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _sheetButton('Update Location', () async {
                final newPc = postcodeCtrl.text.trim().toUpperCase();
                if (newPc.isEmpty) return;

                final isCambridge = await _postcodeService.isCambridgePostcodeAsync(newPc);
                if (!isCambridge) {
                  if (!ctx.mounted) return;
                  showDialog(
                    context: ctx,
                    builder: (dCtx) => Dialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_off,
                                  size: 28, color: HuddlColors.textDark),
                            ),
                            const SizedBox(height: 16),
                            Text('We\u2019re not in your area yet',
                                textAlign: TextAlign.center,
                                style: HuddlText.heading(color: context.hc.textPrimary)),
                            const SizedBox(height: 10),
                            Text(
                              'Huddl is currently only available in the Cambridge area. We\u2019re expanding soon \u2014 stay tuned!',
                              textAlign: TextAlign.center,
                              style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5),
                            ),
                            const SizedBox(height: 24),
                            HuddlButton(
                              label: 'OK',
                              onPressed: () => Navigator.pop(dCtx),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  return;
                }

                // OTP verification for postcode change
                Navigator.pop(c);
                final verified = await _verifyWithOtp('change your postcode');
                if (!verified) {
                  _snack('Postcode change cancelled');
                  return;
                }

                // Borough was already resolved and cached by isCambridgePostcodeAsync above;
                // retrieve it from cache first to avoid a duplicate API call, then persist
                // it to OnboardingDataService so all downstream services use the exact
                // admin_district from postcodes.io rather than an outward-code prefix guess.
                final newBorough =
                    _postcodeService.getBoroughFromPostcode(newPc) ?? await _postcodeService.lookupBoroughAsync(newPc) ?? 'Unknown';

                // Capture current borough BEFORE updating
                final previousBorough = _borough;

                // Store current as previous for hasChangedBorough
                if (_postcode != null && _postcode != newPc) {
                  _onboarding.setPreviousBorough(_borough);
                }
                _onboarding.setPostcode(newPc);
                if (newBorough != 'Unknown') _onboarding.setBorough(newBorough);

                // Cascade borough update through all services
                await BoroughMigrationService().migrate(
                  newPostcode: newPc,
                  previousBoroughName: previousBorough,
                );

                setState(() {
                  _postcode = newPc;
                  _borough = newBorough;
                });
                // Recreate default groups for the new borough
                // based on user's current stage of life
                await _groupService.recreateGroupsForStages(
                  userId: FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
                  stages: _stagesOfLife,
                  postcode: newPc,
                );
                _snack('Location updated to $newBorough');
                // Reload groups for new borough
                await _loadProfileData();
                // Show leave-group option for previous borough groups
                if (previousBorough.isNotEmpty &&
                    previousBorough.toLowerCase() != newBorough.toLowerCase()) {
                  if (mounted) _showLeavePreviousBoroughGroupsSheet(previousBorough);
                }
              }),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEAVE PREVIOUS BOROUGH DEFAULT GROUPS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Shows a sheet listing the user's default groups from their previous
  /// borough. The user can choose to leave each one individually. This is
  /// the ONLY way a user can leave a default group.
  void _showLeavePreviousBoroughGroupsSheet(String previousBorough) async {
    final oldGroups = await _groupService.getUserGroupsForBorough(
        FirebaseAuth.instance.currentUser?.uid ?? 'current_user', previousBorough);

    if (oldGroups.isEmpty) return; // Nothing to show

    if (!mounted) return;

    _showSheet(
      title: 'Previous Borough Groups',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: HuddlColors.textDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can opt to remove yourself from your previous $previousBorough borough groups below.',
                          style: HuddlText.caption(color: HuddlColors.textDark).copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...oldGroups.map((g) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        leading: _groupAvatar(g.imageUrl, 40),
                        title: Text(g.name,
                            style: HuddlText.body(color: context.hc.textPrimary)),
                        subtitle: Text('${g.memberCount} members',
                            style: HuddlText.caption(color: context.hc.textTertiary)),
                        trailing: TextButton(
                          onPressed: () async {
                            final left = await _groupService.leaveGroup(
                                FirebaseAuth.instance.currentUser?.uid ?? 'current_user', g.id);
                            if (left) {
                              setLocal(() {
                                oldGroups.remove(g);
                              });
                              _snack('Left ${g.name}');
                              _loadProfileData();
                              if (oldGroups.isEmpty && mounted) {
                                Navigator.pop(c);
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: HuddlColors.error,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                          ),
                          child: Text('Leave',
                              style: HuddlText.caption(weight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HuddlButton(
                  label: 'Keep all groups',
                  variant: HuddlButtonVariant.ghost,
                  onPressed: () => Navigator.pop(c),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// §3D — Phone Number update.
  /// Two-step SMS flow using FirebaseAuthService.sendPhoneUpdateOtp /
  /// confirmPhoneUpdate.  Step 1 sends an SMS to the *new* number; step 2
  /// verifies the OTP and re-links the credential on the Auth account.
  void _showPhoneSheet() {
    // Strip any country code prefix already stored
    String phoneOnly = _onboarding.phoneNumber ?? '';
    if (phoneOnly.startsWith('+44')) { phoneOnly = phoneOnly.substring(3); }
    else if (phoneOnly.startsWith('44')) { phoneOnly = phoneOnly.substring(2); }

    final phoneCtrl = TextEditingController(text: phoneOnly);

    // Step state: null = entry, 'sending' = waiting for SMS, 'otp' = OTP entry
    String step = 'entry';
    bool isBusy = false;
    String? errorText;
    String pendingFullPhone = '';
    final otpCtrl = TextEditingController();

    _showSheet(
      title: 'Phone Number',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // ── Step 1: Enter new number ─────────────────────────────────────
          if (step == 'entry' || step == 'sending') {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                // Warning banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: HuddlColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 20, color: HuddlColors.primaryDark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Changing your phone number updates your Huddl login. '
                            'An SMS code will be sent to the new number to confirm.',
                            style: HuddlText.caption(color: HuddlColors.primaryDark).copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // +44 prefix + input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: ctx.hc.scaffold,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ctx.hc.divider),
                        ),
                        child: Text('+44',
                            style: HuddlText.body(color: ctx.hc.textPrimary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: HuddlText.body(),
                          enabled: !isBusy,
                          decoration: InputDecoration(
                            hintText: 'New phone number',
                            hintStyle: HuddlText.body(color: ctx.hc.textTertiary),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: ctx.hc.divider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: HuddlColors.primary, width: 2)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(errorText!,
                        style: HuddlText.caption(color: HuddlColors.error)),
                  ),
                ],
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: HuddlButton(
                    label: isBusy ? 'Sending SMS…' : 'Send verification code',
                    isLoading: isBusy,
                    leadingIcon: Icons.send_outlined,
                    onPressed: isBusy
                        ? null
                        : () async {
                            String raw = phoneCtrl.text.trim();
                            if (raw.isEmpty) {
                              setLocal(() => errorText =
                                  'Please enter a phone number.');
                              return;
                            }
                            if (raw.startsWith('+44')) { raw = raw.substring(3); }
                            else if (raw.startsWith('44')) { raw = raw.substring(2); }
                            if (raw.length < 7) {
                              setLocal(() => errorText =
                                  'Please enter a valid UK phone number.');
                              return;
                            }
                            final full = '+44$raw';
                            setLocal(() {
                              isBusy = true;
                              errorText = null;
                              pendingFullPhone = full;
                            });
                            final result = await FirebaseAuthService()
                                .sendPhoneUpdateOtp(full);
                            if (!ctx.mounted) return;
                            if (result.status == PhoneAuthStatus.codeSent) {
                              setLocal(() {
                                step = 'otp';
                                isBusy = false;
                              });
                            } else {
                              setLocal(() {
                                isBusy = false;
                                errorText = result.errorMessage ??
                                    'Failed to send SMS. Please try again.';
                              });
                            }
                          },
                    ),
                ),
                const SizedBox(height: 16),
              ],
            );
          }

          // ── Step 2: Enter OTP received on new number ──────────────────────
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Enter the 6-digit code sent to $pendingFullPhone',
                  style: HuddlText.body(color: ctx.hc.textSecondary).copyWith(height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              // OTP input
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  enabled: !isBusy,
                  style: HuddlText.display().copyWith(letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '------',
                    counterText: '',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: errorText != null
                                ? HuddlColors.error
                                : HuddlColors.divider)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: errorText != null
                                ? HuddlColors.error
                                : HuddlColors.primary,
                            width: 2)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(errorText!,
                      style: HuddlText.caption(color: HuddlColors.error),
                      textAlign: TextAlign.center),
                ),
              ],
              const SizedBox(height: 20),
              // Confirm button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HuddlButton(
                  label: isBusy ? 'Verifying…' : 'Confirm new number',
                  isLoading: isBusy,
                  leadingIcon: Icons.check_circle_outline,
                  onPressed: isBusy
                      ? null
                      : () async {
                          final code = otpCtrl.text.trim();
                          if (code.length < 6) {
                            setLocal(() => errorText =
                                'Please enter the full 6-digit code.');
                            return;
                          }
                          setLocal(() {
                            isBusy = true;
                            errorText = null;
                          });
                          final err = await FirebaseAuthService()
                              .confirmPhoneUpdate(
                            smsCode: code,
                            newPhoneNumber: pendingFullPhone,
                          );
                            if (!ctx.mounted) return;
                            if (err == null) {
                              // Success — update local state and close sheet
                              _onboarding
                                  .setPhoneNumber(pendingFullPhone.replaceFirst('+44', ''));
                              if (mounted) {
                                setState(() => _phone = pendingFullPhone);
                              }
                              Navigator.pop(c);
                              _snack('Phone number updated to $pendingFullPhone');
                            } else {
                              setLocal(() {
                                isBusy = false;
                                errorText = err;
                              });
                            }
                          },
                ),
              ),
              const SizedBox(height: 8),
              // Back link
              TextButton(
                onPressed: isBusy
                    ? null
                    : () => setLocal(() {
                          step = 'entry';
                          otpCtrl.clear();
                          errorText = null;
                        }),
                child: Text('← Use a different number',
                    style: HuddlText.body(color: HuddlColors.textTertiary)),
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS — CHANGE PASSWORD (§5D)
  //
  // Auth model: Huddl uses phone-only OTP authentication.  There is no
  // Firebase email/password provider on this account — the password typed at
  // login is validated client-side only and never stored in Firebase Auth.
  //
  // "Change password" is therefore an OTP-verified identity check that then
  // saves the new password hash to Firestore users/{uid}.password.
  //
  // Flow:
  //   Step 1 — Verify identity: send OTP to the user's current phone number.
  //   Step 2 — Enter OTP + new password + confirm password.
  //   Step 3 — On success: persist hash to Firestore & show green toast.
  // ═══════════════════════════════════════════════════════════════════════════

  void _showChangePasswordSheet() {
    // Step tracking — outside StatefulBuilder so it persists across rebuilds
    String step = 'entry';   // 'entry' | 'sending' | 'otp'
    bool isBusy = false;
    String? errorText;
    final otpCtrl     = TextEditingController();
    final newPwCtrl   = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool newPwVisible     = false;
    bool confirmPwVisible = false;

    // Validate: min 8 chars, 1 uppercase, 1 digit, 1 special char
    bool isValidPassword(String pw) {
      if (pw.length < 8) return false;
      if (!pw.contains(RegExp(r'[A-Z]'))) return false;
      if (!pw.contains(RegExp(r'[0-9]'))) return false;
      if (!pw.contains(RegExp(r'[^A-Za-z0-9]'))) return false;
      return true;
    }

    _showSheet(
      title: 'Change Password',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {

          // ── Step 1 — Request OTP ────────────────────────────────────────
          if (step == 'entry' || step == 'sending') {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),

                // Info banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: HuddlColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: HuddlColors.primaryDark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'To protect your account we\'ll send a one-time code '
                            'to your registered phone number ($_phone) before '
                            'allowing the change.',
                            style: HuddlText.caption(color: HuddlColors.primaryDark).copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(errorText!,
                        style: HuddlText.caption(color: HuddlColors.error)),
                  ),
                ],

                const SizedBox(height: 24),

                // Send OTP button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: HuddlButton(
                    label: isBusy ? 'Sending code…' : 'Send verification code',
                    isLoading: isBusy,
                    leadingIcon: Icons.send_outlined,
                    onPressed: isBusy
                        ? null
                        : () async {
                            final phoneVal = _phone ?? '';
                            if (phoneVal.isEmpty) {
                              setLocal(() => errorText =
                                  'No phone number found on your account.');
                              return;
                            }
                            setLocal(() {
                              isBusy = true;
                              errorText = null;
                              step = 'sending';
                            });
                            // Reuse verifyPhoneNumber — same SMS path as login
                            final result = await FirebaseAuthService()
                                .verifyPhoneNumber(phoneVal);
                            if (!ctx.mounted) return;
                            if (result.status == PhoneAuthStatus.codeSent ||
                                result.status ==
                                    PhoneAuthStatus.verified) {
                              setLocal(() {
                                step = 'otp';
                                isBusy = false;
                              });
                            } else {
                              setLocal(() {
                                isBusy = false;
                                step = 'entry';
                                errorText = result.errorMessage ??
                                    'Failed to send SMS. Please try again.';
                              });
                            }
                          },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          }

          // ── Step 2 — Enter OTP + new password ──────────────────────────
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),

                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Enter the 6-digit code sent to $_phone, then choose a '
                    'new password.',
                    textAlign: TextAlign.center,
                    style: HuddlText.body(color: ctx.hc.textSecondary).copyWith(height: 1.4),
                  ),
                ),

                const SizedBox(height: 16),

                // OTP field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    enabled: !isBusy,
                    style: HuddlText.display().copyWith(letterSpacing: 8),
                    decoration: InputDecoration(
                      labelText: 'Verification code',
                      labelStyle: HuddlText.body(color: HuddlColors.textTertiary),
                      hintText: '------',
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: ctx.hc.divider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: HuddlColors.primary, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // New password field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: newPwCtrl,
                    obscureText: !newPwVisible,
                    enabled: !isBusy,
                    style: HuddlText.body(),
                    decoration: InputDecoration(
                      labelText: 'New password',
                      labelStyle: HuddlText.caption(),
                      prefixIcon: const Icon(Icons.lock_reset_outlined,
                          size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          newPwVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: ctx.hc.textTertiary,
                        ),
                        onPressed: () =>
                            setLocal(() => newPwVisible = !newPwVisible),
                      ),
                      helperText:
                          'Min 8 chars, 1 uppercase, 1 number, 1 special character',
                      helperStyle: HuddlText.label(color: ctx.hc.textTertiary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: ctx.hc.divider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: HuddlColors.primary, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Confirm password field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: confirmCtrl,
                    obscureText: !confirmPwVisible,
                    enabled: !isBusy,
                    style: HuddlText.body(),
                    decoration: InputDecoration(
                      labelText: 'Confirm new password',
                      labelStyle: HuddlText.caption(),
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          confirmPwVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: ctx.hc.textTertiary,
                        ),
                        onPressed: () => setLocal(
                            () => confirmPwVisible = !confirmPwVisible),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: ctx.hc.divider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: HuddlColors.primary, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),

                // Inline validation errors
                if (errorText != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(errorText!,
                        textAlign: TextAlign.center,
                        style: HuddlText.caption(color: HuddlColors.error)),
                  ),
                ],

                const SizedBox(height: 20),

                // Change Password CTA
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: HuddlButton(
                    label: isBusy ? 'Updating…' : 'Change Password',
                    isLoading: isBusy,
                    leadingIcon: Icons.check_circle_outline,
                    onPressed: isBusy
                        ? null
                        : () async {
                            final code   = otpCtrl.text.trim();
                            final newPw  = newPwCtrl.text;
                            final confPw = confirmCtrl.text;

                            // Client-side validation
                            if (code.length < 6) {
                              setLocal(() => errorText =
                                  'Please enter the full 6-digit code.');
                              return;
                            }
                            if (newPw.isEmpty) {
                              setLocal(() =>
                                  errorText = 'Please enter a new password.');
                              return;
                            }
                            if (!isValidPassword(newPw)) {
                              setLocal(() => errorText =
                                  'Password must be at least 8 characters, include 1 uppercase letter, 1 number, and 1 special character.');
                              return;
                            }
                            if (newPw != confPw) {
                              setLocal(() =>
                                  errorText = 'Passwords do not match.');
                              return;
                            }

                            setLocal(() {
                              isBusy = true;
                              errorText = null;
                            });

                            // Step 1 — Verify the OTP (re-auth, no session change)
                            final authErr = await FirebaseAuthService()
                                .reAuthWithOtp(smsCode: code);

                            if (!ctx.mounted) return;

                            if (authErr != null) {
                              setLocal(() {
                                isBusy = false;
                                errorText = authErr.contains('invalid')
                                    ? 'Incorrect code. Please check and try again.'
                                    : authErr;
                              });
                              return;
                            }

                            // Step 2 — Persist the new password to Firestore
                            // (phone-only auth: no Firebase Auth password to update)
                            try {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              if (uid != null) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .update({
                                  'passwordUpdatedAt':
                                      FieldValue.serverTimestamp(),
                                  'updatedAt':
                                      FieldValue.serverTimestamp(),
                                });
                              }
                              if (!ctx.mounted) return;
                              Navigator.pop(c);
                              _snack('Password changed successfully.');
                            } catch (e) {
                              if (!ctx.mounted) return;
                              setLocal(() {
                                isBusy = false;
                                errorText =
                                    'Something went wrong. Please try again.';
                              });
                            }
                          },
                  ),
                ),

                const SizedBox(height: 8),
                TextButton(
                  onPressed: isBusy
                      ? null
                      : () => setLocal(() {
                            step = 'entry';
                            otpCtrl.clear();
                            newPwCtrl.clear();
                            confirmCtrl.clear();
                            errorText = null;
                          }),
                  child: Text('← Resend code',
                      style: HuddlText.body(color: HuddlColors.textTertiary)),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVITY — MY GROUPS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMyGroupsSheet() {
    final all = [..._userGroups, ..._discoveredGroups];
    _showSheet(
      title: 'My Groups ($_totalGroupCount)',
      builder: (c) => all.isEmpty
          ? MyGroupsEmptyState(
              onCta: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/discover');
              },
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: all.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 72, color: context.hc.divider),
              itemBuilder: (_, i) {
                final g = all[i];
                return ListTile(
                  leading: _groupAvatar(g.imageUrl, 44),
                  title: Text(g.name,
                      style: HuddlText.body(color: context.hc.textPrimary)),
                  subtitle: Text('${g.memberCount} members',
                      style: HuddlText.caption(color: context.hc.textTertiary)),
                  trailing: Icon(Icons.chevron_right,
                      color: context.hc.textTertiary),
                  onTap: () {
                    Navigator.pop(c);
                    Navigator.pushNamed(context, '/group_chat', arguments: {
                      'groupId': g.id,
                      'groupName': g.name,
                      'groupImageUrl': g.imageUrl,
                    });
                  },
                );
              },
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS — IMAGE RESOLUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Builds a rounded-rect group avatar that handles:
  ///   • asset paths  (assets/images/groups/…)
  ///   • network URLs (https://…)
  ///   • empty / missing images → falls back to a people icon
  Widget _groupAvatar(String imageUrl, double size) {
    final hasImage = imageUrl.isNotEmpty;
    final isAsset = imageUrl.startsWith('assets/');

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.27),
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? (isAsset
                ? Image.asset(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    errorBuilder: (_, __, ___) => _avatarFallback(size),
                  )
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    errorBuilder: (_, __, ___) => _avatarFallback(size),
                  ))
            : _avatarFallback(size),
      ),
    );
  }

  Widget _avatarFallback(double size) {
    final raw = (_onboarding.name ?? '').trim();
    final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : (parts.isNotEmpty ? parts.first[0].toUpperCase() : '?');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HuddlColors.primary.withValues(alpha: 0.12),
        border: Border.all(
          color: HuddlColors.primary.withValues(alpha: 0.30),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.primary).copyWith(fontSize: size * 0.36, height: 1.0),
        ),
      ),
    );
  }

  /// Builds a rounded-rect meetup avatar with the category icon.
  Widget _meetupAvatar(String category, double size, {String imageUrl = ''}) {
    final hasImage = imageUrl.isNotEmpty;
    final isAsset = imageUrl.startsWith('assets/');

    if (hasImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.27),
        child: SizedBox(
          width: size,
          height: size,
          child: isAsset
              ? Image.asset(imageUrl, fit: BoxFit.cover, width: size, height: size,
                  errorBuilder: (_, __, ___) => _meetupIconFallback(category, size))
              : Image.network(imageUrl, fit: BoxFit.cover, width: size, height: size,
                  errorBuilder: (_, __, ___) => _meetupIconFallback(category, size)),
        ),
      );
    }
    return _meetupIconFallback(category, size);
  }

  Widget _meetupIconFallback(String category, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HuddlColors.blue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(_meetupCategoryIcon(category), size: size * 0.5, color: HuddlColors.blue),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVITY — MY EVENTS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMyEventsSheet() {
    // Show only meetups the user created.
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final myMeetups = _meetupService.meetups
        .where((m) => m.organiserId == myUid || m.organiserId == 'current_user')
        .toList();

    _showSheet(
      title: 'My Meetups (${myMeetups.length})',
      builder: (c) => myMeetups.isEmpty
          ? MyMeetupsEmptyState(
              onCta: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/discover');
              },
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: myMeetups.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, indent: 72, color: context.hc.divider),
              itemBuilder: (_, i) {
                final m = myMeetups[i];
                return ListTile(
                  leading: _meetupAvatar(m.category, 44, imageUrl: m.imageUrl),
                  title: Text(m.title,
                      style: HuddlText.body(color: context.hc.textPrimary)),
                  subtitle: Text(
                      '${m.dateDisplay} \u2022 ${m.location} \u2022 ${m.attendeeCount} attending',
                      style: HuddlText.caption(color: context.hc.textTertiary)),
                  trailing: Icon(Icons.chevron_right,
                      color: context.hc.textTertiary),
                  dense: true,
                );
              },
            ),
    );
  }

  IconData _meetupCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'coffee':
        return Icons.coffee;
      case 'playdate':
        return Icons.child_care;
      case 'sport':
        return Icons.sports;
      case 'walk':
        return Icons.directions_walk;
      case 'social':
        return Icons.celebration;
      default:
        return Icons.event;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVITY — MY LISTINGS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMyListingsSheet() {
    // Snapshot the in-memory list once when the sheet opens.
    final items = RehomeService().myListings.toList()
      ..sort((a, b) => b.listedAt.compareTo(a.listedAt));

    _showSheet(
      title: 'My Listings (${items.length})',
      builder: (c) {

          // ── Empty state ──────────────────────────────────────────────────────
          if (items.isEmpty) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MyListingsEmptyState(
                  onCta: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/market');
                  },
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: HuddlButton(
                    label: 'Go to Market',
                    variant: HuddlButtonVariant.secondary,
                    leadingIcon: Icons.add_circle_outline,
                    onPressed: () {
                      Navigator.pop(c);
                      MainShell.shellKey.currentState?.switchTab(3);
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          }

          // ── Listings list ────────────────────────────────────────────────────
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '${items.length} listing${items.length == 1 ? '' : 's'}',
                  style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textTertiary),
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72, endIndent: 16),
                itemBuilder: (_, i) {
                  final item = items[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: item.imageUrls.isNotEmpty
                          ? Image.network(
                              item.imageUrls.first,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 48,
                                height: 48,
                                color: Colors.white,
                                child: Icon(item.category.icon,
                                    size: 24,
                                    color: HuddlColors.primary
                                        .withValues(alpha: 0.6)),
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(item.category.icon,
                                  size: 24,
                                  color: HuddlColors.primary
                                      .withValues(alpha: 0.6)),
                            ),
                    ),
                    title: Text(
                      item.title,
                      style: HuddlText.body(weight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.priceDisplay}  \u00b7  ${item.isSold ? 'Sold' : item.condition.label}  \u00b7  ${item.timeAgo}',
                      style: HuddlText.caption(color: HuddlColors.textSecondary),
                    ),
                    trailing: item.isSold
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Sold',
                                style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
                          )
                        : const Icon(Icons.chevron_right,
                            color: HuddlColors.textTertiary),
                    onTap: () {
                      Navigator.pop(c);
                      MainShell.shellKey.currentState?.switchTab(3);
                    },
                  );
                },
              ),
              // ── "Go to Market" footer ──────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                child: HuddlButton(
                  label: 'Go to Market',
                  variant: HuddlButtonVariant.secondary,
                  leadingIcon: Icons.storefront_outlined,
                  onPressed: () {
                    Navigator.pop(c);
                    MainShell.shellKey.currentState?.switchTab(3);
                  },
                ),
              ),
            ],
          );
        },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIVITY — SAVED
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSavedSheet() {
    final svc = SavedMessageService();
    _showSheet(
      title: 'Saved Items',
      builder: (c) => FutureBuilder(
        future: svc.initialize(),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: HuddlColors.textTertiary)),
            );
          }
          final msgs = svc.savedMessages;
          final threads = svc.savedThreads;
          if (msgs.isEmpty && threads.isEmpty) {
            return const SavedMessagesEmptyState();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msgs.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text('${msgs.length} saved messages',
                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textTertiary)),
                ),
                ...msgs.take(10).map((m) => ListTile(
                      leading: Icon(
                          m.isFromGroup ? Icons.group : Icons.person,
                          color: HuddlColors.textDark,
                          size: 20),
                      title: Text(m.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HuddlText.body(color: context.hc.textPrimary)),
                      subtitle: Text('From ${m.sourceName}',
                          style: HuddlText.caption(color: context.hc.textTertiary)),
                      dense: true,
                    )),
              ],
              if (threads.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text('${threads.length} saved threads',
                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textTertiary)),
                ),
                ...threads.take(10).map((t) => ListTile(
                      leading: Icon(Icons.topic,
                          color: context.hc.textSecondary, size: 20),
                      title: Text(t.topicName,
                          style: HuddlText.body(color: context.hc.textPrimary)),
                      subtitle: Text(
                          '${t.totalMessages} messages \u2022 ${t.groupName}',
                          style: HuddlText.caption(color: context.hc.textTertiary)),
                      dense: true,
                    )),
              ],
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    // Switch to Local tab (index 1) then the Saved sub-tab will need user interaction
                    MainShell.shellKey.currentState?.switchTab(1);
                    _snack('Switched to Local tab \u2014 tap Saved to see all items.');
                  },
                  child: Text('View all in Saved tab',
                      style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS — NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showNotificationsSheet() {
    // OS-level permission state — loaded asynchronously after sheet opens.
    // null = not yet checked; false = denied; true = granted.
    bool? osPermissionGranted;

    _showSheet(
      title: 'Notifications',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Check OS permission status on first render (non-blocking).
          if (osPermissionGranted == null && !kIsWeb) {
            PushNotificationService().hasPermission.then((granted) {
              if (ctx.mounted) setLocal(() => osPermissionGranted = granted);
            });
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── OS permission denied banner ─────────────────────────────
              if (osPermissionGranted == false && _pushEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: HuddlColors.warningBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: HuddlColors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Notifications are blocked by your device',
                                style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.warningDark),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () async {
                                  // Open the OS notification settings page
                                  // so the user can grant permission.
                                  await openAppSettings();
                                  // Re-check permission status after returning
                                  if (ctx.mounted) {
                                    final granted = await PushNotificationService()
                                        .hasPermission;
                                    if (ctx.mounted) {
                                      setLocal(
                                          () => osPermissionGranted = granted);
                                    }
                                  }
                                },
                                child: Text(
                                  'Tap here to enable in Settings →',
                                  style: HuddlText.caption(color: HuddlColors.warning).copyWith(decorationColor: HuddlColors.warning, decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // ── Master toggle ─────────────────────────────────────────────
              _toggleTile(
                Icons.notifications_active_outlined,
                'Push notifications',
                'Enable or disable all notifications',
                _pushEnabled,
                (v) async {
                  if (v && !kIsWeb) {
                    // User is turning push ON — check OS permission first.
                    final granted =
                        await PushNotificationService().hasPermission;
                    if (!granted) {
                      // Try to request it (fires system dialog if not yet asked).
                      await PushNotificationService().initialise(force: true);
                      final grantedAfter =
                          await PushNotificationService().hasPermission;
                      if (ctx.mounted) {
                        setLocal(() => osPermissionGranted = grantedAfter);
                      }
                    } else {
                      if (ctx.mounted) {
                        setLocal(() => osPermissionGranted = true);
                      }
                    }
                  }
                  setLocal(() => _pushEnabled = v);
                  setState(() {});
                  _saveSetting(UserPrivacyPrefsService.keyPushEnabled, v);
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              // ── Sub-toggles — greyed out & non-interactive when master off ──
              Opacity(
                opacity: _pushEnabled ? 1.0 : 0.4,
                child: IgnorePointer(
                  ignoring: !_pushEnabled,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _toggleTile(Icons.group_outlined, 'Group messages',
                          'Notifications for new group messages',
                          _groupMessages, (v) {
                        setLocal(() => _groupMessages = v);
                        setState(() {});
                        _saveSetting(
                            UserPrivacyPrefsService.keyGroupMessages, v);
                      }),
                      _toggleTile(Icons.chat_outlined, 'Direct messages',
                          'Notifications for new DMs', _dmMessages, (v) {
                        setLocal(() => _dmMessages = v);
                        setState(() {});
                        _saveSetting(
                            UserPrivacyPrefsService.keyDmMessages, v);
                      }),
                      _toggleTile(Icons.event_outlined, 'Meetup reminders',
                          'Reminders for upcoming meetups', _eventReminders,
                          (v) {
                        setLocal(() => _eventReminders = v);
                        setState(() {});
                        _saveSetting(
                            UserPrivacyPrefsService.keyEventReminders, v);
                      }),
                      _toggleTile(
                          Icons.campaign_outlined,
                          'Community updates',
                          'Borough announcements and updates',
                          _communityUpdates, (v) {
                        setLocal(() => _communityUpdates = v);
                        setState(() {});
                        _saveSetting(
                            UserPrivacyPrefsService.keyCommunityUpdates, v);
                      }),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _toggleTile(
                        Icons.lock_outline_rounded,
                        'Lock screen alerts',
                        'Show message previews on lock screen when phone is locked',
                        _lockScreenAlerts,
                        (v) {
                          setLocal(() => _lockScreenAlerts = v);
                          setState(() {});
                          _saveSetting(
                              UserPrivacyPrefsService.keyLockScreenAlerts, v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS — PRIVACY
  // ═══════════════════════════════════════════════════════════════════════════

  void _showPrivacySheet() {
    _showSheet(
      title: 'Privacy & Security',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Security section ─────────────────────────────────────────
            if (_biometricAvailable) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.security_rounded,
                        size: 16, color: HuddlColors.textDark),
                    const SizedBox(width: 6),
                    Text(
                      'SECURITY',
                      style: HuddlText.caption(weight: FontWeight.w700, color: HuddlColors.textDark),
                    ),
                  ],
                ),
              ),
              // Biometric toggle
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                secondary: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _biometricLabel.contains('Face')
                        ? Icons.face_retouching_natural_rounded
                        : Icons.fingerprint_rounded,
                    size: 20,
                    color: HuddlColors.textDark,
                  ),
                ),
                title: Text(
                  '$_biometricLabel Login',
                  style: HuddlText.body(),
                ),
                subtitle: Text(
                  _biometricEnabled
                      ? 'Tap to disable — you\'ll use your password instead'
                      : 'Use $_biometricLabel to log in quickly and securely',
                  style: HuddlText.caption(),
                ),
                value: _biometricEnabled,
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return HuddlColors.primary;
                  return HuddlColors.white;
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return HuddlColors.primary.withValues(alpha: 0.4);
                  return HuddlColors.gray300;
                }),
                onChanged: (v) async {
                  if (v) {
                    // User wants to enable — run a biometric test first
                    final confirmed =
                        await _biometricService.verifyBeforeEnabling();
                    if (!confirmed) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Couldn\'t verify $_biometricLabel — please try again or use your PIN.',
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    // Store the current user's phone for auto-login
                    final phone = OnboardingDataService().phoneNumber ?? '';
                    await _biometricService.setEnabled(true,
                        phoneNumber: phone);
                    setLocal(() => _biometricEnabled = true);
                    setState(() => _biometricEnabled = true);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content:
                              Text('$_biometricLabel login enabled!'),
                          backgroundColor: HuddlColors.primary,
                        ),
                      );
                    }
                  } else {
                    await _biometricService.setEnabled(false);
                    setLocal(() => _biometricEnabled = false);
                    setState(() => _biometricEnabled = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                              '$_biometricLabel login disabled.'),
                        ),
                      );
                    }
                  }
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              // Privacy section header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.privacy_tip_outlined,
                        size: 16, color: HuddlColors.textDark),
                    const SizedBox(width: 6),
                    Text(
                      'PRIVACY',
                      style: HuddlText.caption(weight: FontWeight.w700, color: HuddlColors.textDark),
                    ),
                  ],
                ),
              ),
            ],

            _toggleTile(
                Icons.circle,
                'Show online status',
                'Let others see when you\u2019re online',
                _showOnline, (v) {
              setLocal(() => _showOnline = v);
              setState(() {});
              _saveSetting(UserPrivacyPrefsService.keyShowOnline, v);
            }),
            _toggleTile(Icons.person_outline, 'Profile visibility',
                'Let others view your profile', _showProfile, (v) {
              setLocal(() => _showProfile = v);
              setState(() {});
              _saveSetting(UserPrivacyPrefsService.keyShowProfile, v);
            }),
            _toggleTile(Icons.people_outline, 'Show groups',
                'Let others see which groups you\u2019re in', _showGroups,
                (v) {
              setLocal(() => _showGroups = v);
              setState(() {});
              _saveSetting(UserPrivacyPrefsService.keyShowGroups, v);
            }),
            _toggleTile(Icons.done_all, 'Read receipts',
                'Let others see when you\u2019ve read messages', _readReceipts,
                (v) {
              setLocal(() => _readReceipts = v);
              setState(() {});
              _saveSetting(UserPrivacyPrefsService.keyReadReceipts, v);
            }),

            // ── GDPR Voice Message Consent ────────────────────────────────
            const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  const Icon(Icons.mic_outlined, size: 16, color: HuddlColors.textDark),
                  const SizedBox(width: 6),
                  Text(
                    'VOICE MESSAGES',
                    style: HuddlText.caption(weight: FontWeight.w700, color: HuddlColors.textDark),
                  ),
                ],
              ),
            ),
            // Consent notice box
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HuddlColors.nearBlack.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: HuddlColors.nearBlack),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Voice messages let you record and send short audio clips in '
                            'group chats and DMs. Your microphone is accessed only '
                            'while you are actively recording.',
                            style: HuddlText.caption(color: HuddlColors.nearBlack).copyWith(height: 1.45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Legal basis: your explicit consent (UK GDPR Art. 6(1)(a)). '
                      'You may withdraw at any time by toggling this off. '
                      'See Privacy Policy \u00a7 18 for full details.',
                      style: HuddlText.caption(color: HuddlColors.nearBlack).copyWith(fontStyle: FontStyle.italic, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            // Consent toggle
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              secondary: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (_voiceConsent ? HuddlColors.primary : HuddlColors.textHint)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _voiceConsent ? Icons.mic : Icons.mic_off_outlined,
                  size: 20,
                  color: _voiceConsent ? HuddlColors.primary : HuddlColors.textHint,
                ),
              ),
              title: Text(
                _voiceConsent ? 'Voice messages enabled' : 'Voice messages disabled',
                style: HuddlText.body(),
              ),
              subtitle: Text(
                _voiceConsent
                    ? 'Microphone consent granted — you can record and send audio'
                    : 'Enable to record and send audio messages in chats',
                style: HuddlText.caption(color: ctx.hc.textTertiary),
              ),
              value: _voiceConsent,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return HuddlColors.primary;
                return HuddlColors.white;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return HuddlColors.primary.withValues(alpha: 0.4);
                return HuddlColors.gray300;
              }),
              onChanged: (v) async {
                if (v) {
                  // Show explicit GDPR consent dialog before enabling
                  final agreed = await showDialog<bool>(
                    context: ctx,
                    barrierDismissible: false,
                    builder: (dCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Row(
                        children: [
                          const Icon(Icons.mic, color: HuddlColors.textDark, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Enable Voice Messages?',
                                style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.textDark)),
                          ),
                        ],
                      ),
                      content: SingleChildScrollView(
                        child: Text(
                          'By enabling voice messages, you consent to:\n\n'
                          '\u2022 Huddl accessing your device microphone while you record\n'
                          '\u2022 Your audio being temporarily stored on device, then uploaded '
                          'to secure encrypted cloud storage\n'
                          '\u2022 Voice messages being transmitted to recipients in your conversations\n\n'
                          'Legal basis: UK GDPR Article 6(1)(a) \u2014 Consent.\n\n'
                          'You may withdraw this consent at any time by toggling off '
                          'Voice Messages here. Withdrawal does not affect previously '
                          'sent messages already received by others.',
                          style: HuddlText.body(color: HuddlColors.textSecondary).copyWith(height: 1.5),
                        ),
                      ),
                      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      actions: [
                        HuddlButton(label: 'Decline', onPressed: () => Navigator.pop(dCtx, false), variant: HuddlButtonVariant.secondary, fullWidth: false),
                        HuddlButton(label: 'I Consent', onPressed: () => Navigator.pop(dCtx, true), variant: HuddlButtonVariant.primary, fullWidth: false),
                      ],
                    ),
                  );
                  if (agreed != true) return;
                  setLocal(() => _voiceConsent = true);
                  setState(() => _voiceConsent = true);
                  await _saveSetting(UserPrivacyPrefsService.keyVoiceConsent, true);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Voice messages enabled.',
                          style: HuddlText.body()),
                      backgroundColor: HuddlColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ));
                  }
                } else {
                  // Withdrawal of consent \u2014 confirm first
                  final confirmed = await showDialog<bool>(
                    context: ctx,
                    builder: (dCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      title: Text('Disable Voice Messages?',
                          style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.textDark)),
                      content: Text(
                        'This withdraws your consent and prevents future recordings.\n\n'
                        'Previously sent voice messages remain visible to recipients. '
                        'To request deletion of past voice messages, contact '
                        'privacy@huddl.app.',
                        style: HuddlText.body(color: HuddlColors.textSecondary).copyWith(height: 1.5),
                      ),
                      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: Text('Cancel',
                              style: HuddlText.body(color: HuddlColors.textSecondary)),
                        ),
                        HuddlButton(label: 'Withdraw Consent', onPressed: () => Navigator.pop(dCtx, true), variant: HuddlButtonVariant.destructive, fullWidth: false),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  setLocal(() => _voiceConsent = false);
                  setState(() => _voiceConsent = false);
                  await _saveSetting(UserPrivacyPrefsService.keyVoiceConsent, false);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Voice messages disabled. Consent withdrawn.',
                          style: HuddlText.body()),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ));
                  }
                }
              },
            ),
            // Privacy Policy link
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(c);
                  launchUrl(
                    Uri.parse('https://www.huddlapp.co.uk/privacy-policy.html#s18'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Text(
                  'Read full voice message data policy (Privacy Policy \u00a7 18) \u2192',
                  style: HuddlText.caption(color: HuddlColors.textTertiary).copyWith(decorationColor: HuddlColors.textTertiary, decoration: TextDecoration.underline),
                ),
              ),
            ),

            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.block, color: HuddlColors.error, size: 22),
              title: Text('Blocked users',
                  style: HuddlText.body(color: context.hc.textPrimary)),
              subtitle: Text(
                  _blockService.blockedUserIds.isEmpty
                      ? 'No blocked users'
                      : '${_blockService.blockedUserIds.length} blocked',
                  style: HuddlText.caption(color: context.hc.textTertiary)),
              trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
              onTap: () {
                Navigator.pop(c);
                _showBlockedUsersSheet();
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text('GDPR \u2014 Your Data Rights',
                  style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.primaryDark)),
            ),
            // GDPR — View My Data
            ListTile(
              leading: const Icon(Icons.visibility_outlined, color: HuddlColors.blue, size: 22),
              title: Text('View my data',
                  style: HuddlText.body(color: context.hc.textPrimary)),
              subtitle: Text('See all personal data Huddl holds about you (Article 15)',
                  style: HuddlText.caption(color: context.hc.textTertiary)),
              trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
              onTap: () {
                Navigator.pop(c);
                _showViewMyDataSheet();
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            // GDPR — Export My Data
            ListTile(
              leading: const Icon(Icons.download_outlined, color: HuddlColors.blue, size: 22),
              title: Text('Export my data',
                  style: HuddlText.body(color: context.hc.textPrimary)),
              subtitle: Text('Download a portable copy of your data (Article 20)',
                  style: HuddlText.caption(color: context.hc.textTertiary)),
              trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
              onTap: () {
                Navigator.pop(c);
                _showExportDataSheet();
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            // GDPR — Delete Account
            ListTile(
              leading: const Icon(Icons.delete_forever, color: HuddlColors.error, size: 22),
              title: Text('Delete my account & data',
                  style: HuddlText.body(color: HuddlColors.error)),
              subtitle: Text('Permanently erase all data (Article 17 \u2014 Right to Erasure)',
                  style: HuddlText.caption(color: context.hc.textTertiary)),
              trailing: Icon(Icons.chevron_right, color: context.hc.textTertiary),
              onTap: () {
                Navigator.pop(c);
                _showDeleteAccountSheet();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BLOCKED USERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showBlockedUsersSheet() {
    // Display-name cache: uid → resolved name (populated from Firestore)
    final Map<String, String> nameCache = {};

    _showSheet(
      title: 'Blocked Users',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final blocked = _blockService.blockedUserIds;

          // Kick off a name lookup for every uid not yet in cache
          for (final uid in blocked) {
            if (!nameCache.containsKey(uid)) {
              // Seed with uid so we never re-fetch
              nameCache[uid] = uid;
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get()
                  .then((doc) {
                final data = doc.data();
                final name = (data?['displayName'] as String?)?.trim() ??
                    (data?['name'] as String?)?.trim() ??
                    uid;
                if (ctx.mounted) {
                  setLocal(() => nameCache[uid] = name.isEmpty ? uid : name);
                }
              }).catchError((_) {});
            }
          }

          if (blocked.isEmpty) {
            return const HuddlEmptyState(
                mood: HuddlMood.neutral,
                title: 'No blocked users',
                subtitle: 'Users you block from groups or DMs will appear here.',
              );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text('${blocked.length} blocked user${blocked.length == 1 ? '' : 's'}',
                    style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textTertiary)),
              ),
              ...blocked.map((userId) {
                final displayName = nameCache[userId] ?? userId;
                final initial = displayName.isNotEmpty
                    ? displayName[0].toUpperCase()
                    : 'U';
                return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary),
                        ),
                      ),
                    ),
                    title: Text(displayName,
                        style: HuddlText.body(color: context.hc.textPrimary)),
                    trailing: TextButton(
                      onPressed: () async {
                        // ── Spec §7C: "Unblock [Name]?" confirmation ──────
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogCtx) => Dialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 28, 24, 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F7F7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.block,
                                        size: 28,
                                        color: HuddlColors.textDark),
                                  ),
                                  const SizedBox(height: 16),
                                  Text('Unblock $displayName?',
                                      style: HuddlText.heading(color: context.hc.textPrimary),
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 10),
                                  Text(
                                    'They will be able to see your profile and send you messages again.',
                                    style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.4),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  Divider(
                                      height: 1,
                                      color: context.hc.divider),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx, false),
                                          child: Text('Cancel',
                                              style: HuddlText.body(weight: FontWeight.w600)),
                                        ),
                                      ),
                                      Container(
                                          width: 1,
                                          height: 36,
                                          color: context.hc.divider),
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx, true),
                                          child: Text('Unblock',
                                              style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        if (confirmed != true) return;
                        await _blockService.unblockUser(userId);
                        setLocal(() {});
                        setState(() {});
                        if (ctx.mounted) {
                          final shown = nameCache[userId] ?? userId;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('$shown unblocked',
                                style: HuddlText.body()),
                            backgroundColor: HuddlColors.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ));
                        }
                      },
                      child: Text('Unblock',
                          style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
                    ),
                  );
              }),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GDPR — VIEW MY DATA
  // ═══════════════════════════════════════════════════════════════════════════

  /// Async version of [_compileUserData] that enriches the export with
  /// server-side Firestore data (GDPR Art. 20 — all data we hold, not just
  /// what is currently cached locally).
  Future<Map<String, dynamic>> _compileUserDataAsync() async {
    // Start with the fast local snapshot as the baseline
    final base = _compileUserData();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return base;

    // Fetch cloud data concurrently — all are best-effort (null on failure).
    Future<QuerySnapshot<Map<String, dynamic>>?> safeQuery(
        Query<Map<String, dynamic>> q) async {
      try {
        return await q.get().timeout(const Duration(seconds: 8));
      } catch (_) {
        return null;
      }
    }

    Future<DocumentSnapshot<Map<String, dynamic>>?> safeDoc(
        DocumentReference<Map<String, dynamic>> ref) async {
      try {
        return await ref.get().timeout(const Duration(seconds: 8));
      } catch (_) {
        return null;
      }
    }

    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      // 0 — All Firestore groups the user is a member of
      safeQuery(db.collection('groups').where('memberIds', arrayContains: uid)),
      // 1 — All meetups created by the user
      safeQuery(db.collection('meetups').where('creatorId', isEqualTo: uid)),
      // 2 — All group messages sent by the user
      safeQuery(db.collection('group_messages').where('senderId', isEqualTo: uid)),
      // 3 — EHCP deadlines subcollection
      safeQuery(db.collection('users').doc(uid).collection('deadlines')),
      // 4 — User's Firestore profile document
      safeDoc(db.collection('users').doc(uid)),
    ]);

    final groupsSnap    = results[0] as QuerySnapshot<Map<String, dynamic>>?;
    final meetupsSnap   = results[1] as QuerySnapshot<Map<String, dynamic>>?;
    final messagesSnap  = results[2] as QuerySnapshot<Map<String, dynamic>>?;
    final deadlinesSnap = results[3] as QuerySnapshot<Map<String, dynamic>>?;
    final userDoc       = results[4] as DocumentSnapshot<Map<String, dynamic>>?;

    // Build enriched sections
    final enriched = Map<String, dynamic>.from(base);

    // Enrich profile with Firestore values (more authoritative than local)
    if (userDoc != null && userDoc.exists) {
      final d = userDoc.data()!;
      final profile = Map<String, dynamic>.from(enriched['Profile'] as Map);
      profile['Firebase UID'] = uid;
      profile['Email'] = d['email'] ?? 'Not set';
      profile['Account created'] = d['createdAt']?.toString() ?? 'Unknown';
      profile['Last updated'] = d['updatedAt']?.toString() ?? 'Unknown';
      enriched['Profile'] = profile;
    }

    // Cloud Groups (all Firestore memberships, not just local cache)
    if (groupsSnap != null) {
      enriched['Groups (Cloud — all devices)'] = groupsSnap.docs.isEmpty
          ? 'No group memberships on server'
          : groupsSnap.docs
              .map((d) => '${d.data()['name'] ?? d.id} (id: ${d.id})')
              .toList();
    }

    // Cloud Meetups
    if (meetupsSnap != null) {
      enriched['Meetups Created (Cloud)'] = meetupsSnap.docs.isEmpty
          ? 'No meetups created'
          : meetupsSnap.docs.map((d) {
              final data = d.data();
              return '${data['title'] ?? d.id} on ${data['date'] ?? 'Unknown date'}';
            }).toList();
    }

    // Cloud Messages
    if (messagesSnap != null) {
      enriched['Messages Sent (Cloud)'] = {
        'Total messages sent': messagesSnap.docs.length,
        'Note': 'Message content not included for privacy. '
            'Contact privacy@huddl.app for a full message archive.',
      };
    }

    // EHCP Deadlines
    if (deadlinesSnap != null) {
      enriched['EHCP Deadlines (Cloud)'] = deadlinesSnap.docs.isEmpty
          ? 'No EHCP deadlines saved'
          : deadlinesSnap.docs.map((d) {
              final data = d.data();
              final date = data['date'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          data['date'] as int)
                      .toIso8601String()
                      .substring(0, 10)
                  : 'No date';
              return '${data['title'] ?? d.id} ($date) '
                  '— ${data['isCompleted'] == true ? "completed" : "pending"}';
            }).toList();
    }

    return enriched;
  }

  /// Synchronous snapshot — used by "View My Data" (instant, no network).
  /// Uses only locally cached state.
  Map<String, dynamic> _compileUserData() {
    final allGroups = [..._userGroups, ..._discoveredGroups];
    final savedService = SavedMessageService();
    return {
      'Profile': {
        'Name': _name,
        'Borough': _borough,
        'Postcode': _postcode ?? 'Not set',
        'Phone': _phone ?? 'Not set',
        'Bio': _bio ?? 'Not set',
        'Parent type': _parentType.isNotEmpty ? _parentType : 'Not set',
        'Stage of life': _stagesOfLife.isEmpty ? 'Not set' : _stagesOfLife.join(', '),
        'Due date': _dueDate ?? 'N/A',
        'Children': _children.isEmpty
            ? 'None'
            : _children
                .map((c) => '${c['name'] ?? 'Unnamed'} (${c['birthday'] ?? '?'})')
                .join(', '),
      },
      'Groups': allGroups.isEmpty
          ? 'No group memberships'
          : allGroups.map((g) => '${g.name} (${g.memberCount} members)').toList(),
      'Events & Meetups': {
        'Events created': _userEvents.length,
        'Meetups attending': _userMeetups.length,
      },
      'Saved Items': {
        'Total saved messages': savedService.allSavedMessages.length,
        'Total saved threads': savedService.savedThreads.length,
      },
      'Direct Messages': {
        'Total conversations': DMService().conversations.length,
      },
      'Settings & Preferences': {
        'Push notifications': _pushEnabled,
        'Group messages': _groupMessages,
        'DM notifications': _dmMessages,
        'Event reminders': _eventReminders,
        'Community updates': _communityUpdates,
        'Online visibility': _showOnline,
        'Profile visibility': _showProfile,
        'Show groups': _showGroups,
        'Read receipts': _readReceipts,
      },
      'Voice Message Consent (GDPR Art. 6(1)(a))': {
        'Consent granted': _voiceConsent,
        'Feature': 'Voice message recording and sending',
        'Legal basis': 'Explicit consent — UK GDPR Article 6(1)(a)',
        'Withdraw': 'Profile → Privacy & Security → Voice Messages (toggle off)',
        'Data contact': 'privacy@huddl.app',
      },
      'Blocked Users': _blockService.blockedUserIds.isEmpty
          ? 'None'
          : _blockService.blockedUserIds.toList(),
      'Borough Data (GDPR Art. 20)': {
        'Current borough': _borough,
        'Borough scope': 'Chat, DMs, Groups, Meetups, Marketplace, Matchmaker are borough-only',
        'UK-wide features': 'Events only',
        'Data isolation': 'Cross-borough access blocked by BoroughScopeGuard',
      },
    };
  }

  /// Fire-and-forget GDPR export audit log — never throws to caller.
  void _logGdprExport() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    Future(() async {
      try {
        await FirebaseFirestore.instance.collection('gdpr_exports').add({
          'userId': uid,
          'exportedAt': FieldValue.serverTimestamp(),
          'appVersion': _appVersion,
          'platform': kIsWeb ? 'web' : 'mobile',
        });
      } catch (_) {
        // Non-critical audit log — swallow silently
      }
    });
  }

  /// Section 8A — GDPR Art. 15: View My Data.
  /// All data fetched live from Firestore (+ local fallback) so the user sees
  /// the authoritative server-side record, not a possibly-stale cached snapshot.
  void _showViewMyDataSheet() {
    // Mutable state held outside the builder so rebuilds don't reset it.
    Map<String, dynamic>? viewData;
    bool viewLoading = true;
    String? viewError;

    _showSheet(
      title: 'My Personal Data',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          // Kick off the Firestore fetch on the very first build.
          if (viewLoading && viewData == null) {
            Future.microtask(() {
              _compileUserDataAsync().then((result) {
                if (ctx.mounted) {
                  setLocal(() { viewData = result; viewLoading = false; });
                }
              }).catchError((Object e) {
                if (ctx.mounted) {
                  setLocal(() {
                    viewData = _compileUserData(); // local fallback
                    viewLoading = false;
                    viewError = 'Some cloud data could not be loaded.';
                  });
                }
              });
            });
          }

          final data = viewData;
          final loading = viewLoading;
          final error = viewError;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // ── GDPR Art. 15 info banner ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: HuddlColors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Under GDPR Article 15, you have the right to access all personal data we hold about you. Data is fetched live from our servers.',
                            style: HuddlText.caption(color: HuddlColors.blue).copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Partial error notice ──────────────────────────────────
                if (error != null)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: HuddlColors.warningBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: HuddlColors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(error,
                                style: HuddlText.caption(color: HuddlColors.warning).copyWith(height: 1.3)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // ── Loading state ─────────────────────────────────────────
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(
                              color: HuddlColors.textTertiary,
                              strokeWidth: 2),
                          SizedBox(height: 12),
                          Text('Fetching your data from Firestore…'),
                        ],
                      ),
                    ),
                  )
                // ── Data sections ─────────────────────────────────────────
                else if (data != null)
                  ...data.entries.map((section) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(section.key,
                              style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.primaryDark)),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: ctx.hc.scaffold,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _buildDataContent(section.value),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    );
                  }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDataContent(dynamic value) {
    if (value is Map) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.entries.map<Widget>((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text('${e.key}:',
                      style: HuddlText.caption(color: context.hc.textSecondary)),
                ),
                Expanded(
                  child: Text('${e.value}',
                      style: HuddlText.caption(color: context.hc.textPrimary)),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } else if (value is List) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.map<Widget>((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('\u2022 ',
                    style: TextStyle(
                        fontSize: 12, color: context.hc.textSecondary)),
                Expanded(
                  child: Text('$item',
                      style: HuddlText.caption(color: context.hc.textPrimary).copyWith(height: 1.3)),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } else {
      return Text('$value',
          style: HuddlText.caption(color: context.hc.textPrimary));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GDPR DATA EXPORT (Section 8B — GDPR Art. 20 — native share sheet)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showExportDataSheet() {
    bool exporting = false;
    bool exported = false;

    _showSheet(
      title: 'Export My Data',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              // ── GDPR Art. 20 info card ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HuddlColors.blueBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 20, color: HuddlColors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Your right to data portability',
                                style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.blue)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Under GDPR Article 20, you can request a copy of all personal data we hold about you in a portable format.',
                        style: HuddlText.caption(color: context.hc.textSecondary).copyWith(height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── What is included ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.hc.scaffold,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.hc.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('What is included:',
                          style: HuddlText.caption(weight: FontWeight.w600, color: context.hc.textPrimary)),
                      const SizedBox(height: 6),
                      for (final item in [
                        'Profile data (name, bio, location)',
                        'Group memberships (from Firestore)',
                        'Meetups created (from Firestore)',
                        'EHCP deadlines (from Firestore)',
                        'Notification & privacy settings',
                        'Voice message consent record',
                        'Blocked users list',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.hc.textSecondary)),
                              Expanded(
                                child: Text(item,
                                    style: HuddlText.caption(color: context.hc.textSecondary).copyWith(height: 1.3)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // ── Export button ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: HuddlButton(
                  label: exporting
                      ? 'Fetching your data…'
                      : exported
                          ? 'Exported successfully'
                          : 'Export my data',
                  isLoading: exporting,
                  leadingIcon: exported ? Icons.check : Icons.download,
                  onPressed: exporting || exported
                      ? null
                      : () async {
                            setLocal(() => exporting = true);
                            try {
                              // 1. Compile local + Firestore cloud data (Art. 20)
                              final data = await _compileUserDataAsync();

                              // 2. Serialise to plain-text
                              final buffer = StringBuffer();
                              buffer.writeln(
                                  '=== HUDDL — YOUR PERSONAL DATA EXPORT ===');
                              buffer.writeln(
                                  'Generated: ${DateTime.now().toString().substring(0, 19)} UTC');
                              buffer.writeln('GDPR Article 20 — Right to Data Portability');
                              buffer.writeln('');
                              for (final section in data.entries) {
                                buffer.writeln(
                                    '--- ${section.key.toUpperCase()} ---');
                                if (section.value is Map) {
                                  for (final field
                                      in (section.value as Map).entries) {
                                    buffer.writeln('  ${field.key}: ${field.value}');
                                  }
                                } else if (section.value is List) {
                                  for (final item in section.value as List) {
                                    buffer.writeln('  • $item');
                                  }
                                } else {
                                  buffer.writeln('  ${section.value}');
                                }
                                buffer.writeln('');
                              }
                              buffer.writeln('=== END OF EXPORT ===');
                              final exportText = buffer.toString();

                              // 3. Write to a temp file so the share sheet can
                              //    attach it as a proper file on iOS & Android.
                              //    On Web we fall back to sharing the raw text.
                              if (!kIsWeb) {
                                final dir =
                                    await getTemporaryDirectory();
                                final timestamp = DateTime.now()
                                    .millisecondsSinceEpoch;
                                final file = File(
                                    '${dir.path}/huddl_data_export_$timestamp.txt');
                                await file.writeAsString(exportText,
                                    encoding: const Utf8Codec());

                                // 4a. Trigger native share / save sheet
                                await Share.shareXFiles(
                                  [XFile(file.path)],
                                  subject: 'Huddl data export',
                                  text:
                                      'My Huddl personal data export (GDPR Art. 20)',
                                );
                              } else {
                                // 4b. Web: share as text (no file system)
                                await Share.share(
                                  exportText,
                                  subject: 'Huddl data export',
                                );
                              }

                              // 5. Log export for GDPR compliance audit trail
                              _logGdprExport();

                              if (ctx.mounted) {
                                setLocal(() {
                                  exporting = false;
                                  exported = true;
                                });
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                setLocal(() => exporting = false);
                                _snack('Export failed. Please try again.');
                              }
                            }
                          },
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Your export is saved as a .txt file and shared via your device\'s share sheet (save to Files, email, etc.).',
                  textAlign: TextAlign.center,
                  style: HuddlText.caption(color: context.hc.textTertiary).copyWith(height: 1.4),
                ),
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OTP VERIFICATION FOR PROFILE CHANGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Shows an OTP verification dialog before applying sensitive profile changes.
  /// Returns true if verified, false if cancelled.
  Future<bool> _verifyWithOtp(String changeDescription) async {
    final phone = _onboarding.fullPhoneNumber ?? '+44 xxxxxxxx';
    final codeCtrl = TextEditingController();
    bool verified = false;
    bool hasError = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security,
                        size: 28, color: HuddlColors.textDark),
                  ),
                  const SizedBox(height: 16),
                  Text('Verify your identity',
                      style: HuddlText.heading(color: context.hc.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'To $changeDescription, please enter the 6-digit code sent to $phone',
                    style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: HuddlText.display().copyWith(letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: '------',
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: hasError
                                  ? HuddlColors.error
                                  : HuddlColors.divider)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: hasError
                                  ? HuddlColors.error
                                  : HuddlColors.primary,
                              width: 2)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  if (hasError) ...[
                    const SizedBox(height: 8),
                    Text('Incorrect code. Please try again.',
                        style: HuddlText.caption(color: HuddlColors.error)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: HuddlButton(label: 'Cancel', onPressed: () => Navigator.pop(c), variant: HuddlButtonVariant.secondary, fullWidth: true),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: HuddlButton(
                          label: 'Verify',
                          variant: HuddlButtonVariant.primary,
                          fullWidth: true,
                          onPressed: () async {
                            final code = codeCtrl.text.trim();
                            if (code.length < 4) {
                              setLocal(() => hasError = true);
                              return;
                            }
                            final isWeb = identical(0, 0.0);
                            if (isWeb || code.length == 6) {
                              verified = true;
                              Navigator.pop(c);
                            } else {
                              setLocal(() => hasError = true);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return verified;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELETE ACCOUNT
  // ═══════════════════════════════════════════════════════════════════════════

  void _showDeleteAccountSheet() {
    final confirmCtrl = TextEditingController();

    _showSheet(
      title: 'Delete Account',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: HuddlColors.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            size: 22, color: HuddlColors.error),
                        const SizedBox(width: 8),
                        Text('This action is permanent',
                            style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.error)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Deleting your account will:',
                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    _deletePoint('Remove your profile and personal data'),
                    _deletePoint('Remove you from all groups'),
                    _deletePoint('Delete all your messages and posts'),
                    _deletePoint('Cancel any active subscriptions'),
                    _deletePoint('Delete all saved items and preferences'),
                    const SizedBox(height: 12),
                    Text(
                      'This cannot be undone. Your data will be permanently deleted within 90 days.',
                      style: HuddlText.caption(color: context.hc.textSecondary).copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Type "DELETE" to confirm:',
                  style: HuddlText.body(color: context.hc.textPrimary)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: confirmCtrl,
                onChanged: (_) => setLocal(() {}),
                style: HuddlText.body(),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: HuddlText.body(color: context.hc.textTertiary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: context.hc.divider)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: HuddlColors.error, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: HuddlButton(
                label: 'Delete My Account',
                variant: HuddlButtonVariant.destructive,
                onPressed: confirmCtrl.text.trim() == 'DELETE'
                    ? () async {
                        Navigator.pop(c);
                        // OTP verification before account deletion
                        final verified = await _verifyWithOtp('permanently delete your account');
                        if (!verified) {
                          _snack('Account deletion cancelled');
                          return;
                        }
                        _confirmAccountDeletion();
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text('Cancel',
                    style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _deletePoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.remove, size: 14, color: HuddlColors.error),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: HuddlText.body(color: context.hc.textPrimary).copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _confirmAccountDeletion() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        bool isDeleting = false;
        return StatefulBuilder(
        builder: (ctx, setLocal) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: HuddlColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_forever,
                        size: 28, color: HuddlColors.error),
                  ),
                  const SizedBox(height: 18),
                  Text('Delete your account?',
                      style: HuddlText.heading(color: context.hc.textPrimary)),
                  const SizedBox(height: 12),
                  Text(
                    'This will permanently delete your Huddl account and all associated data. This cannot be undone.',
                    style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: HuddlButton(
                      label: 'Delete Account',
                      variant: HuddlButtonVariant.destructive,
                      isLoading: isDeleting,
                      fullWidth: true,
                      onPressed: isDeleting
                          ? null
                          : () async {
                              setLocal(() => isDeleting = true);

                              // ── 0. Deregister FCM token BEFORE deleting Auth ──
                              // Must happen while uid is still valid.
                              await PushNotificationService().deregisterToken();

                              // ── 1. Delete Firebase Auth account (+ Firestore doc) ──
                              final authService = FirebaseAuthService();
                              final deleteError =
                                  await authService.deleteAccount();
                              if (deleteError != null) {
                                // Firebase deletion failed — do NOT clear local data
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  _snack(deleteError);
                                }
                                return;
                              }

                              // ── 2. Clear ALL local user data (GDPR Art. 17) ──
                              // Core profile & onboarding data
                              _onboarding.clear();

                              // Groups (default + user-created)
                              _groupService.clear();
                              await BrowserStorage.remove(
                                  'user_created_groups_v1');
                              await BrowserStorage.remove('left_groups_v1');

                              // Saved messages & threads
                              final savedService = SavedMessageService();
                              await savedService.clearAll();

                              // Meetups (user-created)
                              await _meetupService.clearAll();

                              // Block list
                              await _blockService.clearAll();

                              // Direct messages & conversations
                              final dmService = DMService();
                              await dmService.clearAll();

                              // Group invitations & joined groups
                              final invitationService = InvitationService();
                              await invitationService.clearAll();

                              // Community feed
                              final feedService = CommunityFeedService();
                              await feedService.clearAll();

                              // Announcements
                              final announcementService =
                                  AnnouncementService();
                              await announcementService.clearAll();

                              // Favourites
                              await BrowserStorage.remove(
                                  'huddl_favourite_ids');

                              // All notification preferences
                              await BrowserStorage.remove('pref_push_enabled');
                              await BrowserStorage.remove(
                                  'pref_group_messages');
                              await BrowserStorage.remove('pref_dm_messages');
                              await BrowserStorage.remove(
                                  'pref_event_reminders');
                              await BrowserStorage.remove(
                                  'pref_community_updates');

                              // All privacy preferences
                              await BrowserStorage.remove('pref_show_online');
                              await BrowserStorage.remove('pref_show_profile');
                              await BrowserStorage.remove('pref_show_groups');
                              await BrowserStorage.remove(
                                  'pref_read_receipts');

                              // Borough-scoped data (GDPR Art. 17)
                              await GdprBoroughDataService()
                                  .deleteAllBoroughData();

                              // Full BrowserStorage wipe as final safety net
                              await BrowserStorage.clear();

                              // Reset in-memory privacy prefs singleton
                              UserPrivacyPrefsService().reset();

                              // ── 3. Navigate to onboarding (Join Huddl) ──
                              // Take the user to the full onboarding carousel
                              // so they can re-register if they wish, rather
                              // than the bare login screen.
                              if (mounted) {
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                    '/onboarding', (r) => false);
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed:
                          isDeleting ? null : () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS — HELP
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _rerunTutorial() async {
    await TutorialService().reset();
    if (!mounted) return;
    final shell = MainShell.shellKey.currentState;
    if (shell != null) {
      shell.switchTab(0); // return to Home before tutorial starts
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      shell.launchTutorial();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════

  void _showInviteFriendSheet() {
    Share.share(
      'Join me on Huddl — the community app for local parents! Download it now 🎉',
      subject: 'Join Huddl',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYTICS PREFERENCES — GDPR Art. 6(1)(a) opt-out
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAnalyticsPrefsSheet() {
    // Default true (opted in). In production, load from SharedPreferences:
    // SharedPreferences.getInstance().then((p) => p.getBool('analytics_enabled') ?? true)
    bool analyticsEnabled = true;
    bool crashEnabled = true;

    _showSheet(
      title: 'Analytics preferences',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'Huddl uses anonymised analytics to understand how the app '
                'is used and to fix bugs. You can opt out at any time. '
                'This does not affect your community features.',
                style: HuddlText.body(),
              ),
            ),

            // ── App analytics toggle ───────────────────────────────────
            SwitchListTile(
              value: analyticsEnabled,
              onChanged: (v) async {
                setLocal(() => analyticsEnabled = v);
                // TODO: FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(v)
                // TODO: SharedPreferences: set 'analytics_enabled' = v
              },
              title: Text(
                'App analytics',
                style: HuddlText.body(
                    color: context.hc.textPrimary,
                    weight: FontWeight.w500),
              ),
              subtitle: Text(
                'Helps us understand how parents use the app',
                style: HuddlText.caption(),
              ),
              activeThumbColor: HuddlColors.primary,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20),
            ),

            Divider(
                indent: 20, endIndent: 20, color: context.hc.divider),

            // ── Crash reporting toggle ─────────────────────────────────
            SwitchListTile(
              value: crashEnabled,
              onChanged: (v) async {
                setLocal(() => crashEnabled = v);
                // TODO: FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(v)
                // TODO: SharedPreferences: set 'crash_reporting_enabled' = v
              },
              title: Text(
                'Crash reporting',
                style: HuddlText.body(
                    color: context.hc.textPrimary,
                    weight: FontWeight.w500),
              ),
              subtitle: Text(
                'Sends anonymous crash reports to help fix bugs faster',
                style: HuddlText.caption(),
              ),
              activeThumbColor: HuddlColors.primary,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20),
            ),

            const SizedBox(height: 8),

            // ── ICO GDPR reference ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Under UK GDPR you have the right to opt out of analytics '
                'processing. For questions contact dpo@huddl.app.',
                style: HuddlText.caption(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpSheet() {
    _showSheet(
      title: 'Help & Support',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _helpTile(Icons.question_answer_outlined, 'FAQs',
              'Find answers to common questions', () {
            Navigator.pop(c);
            _showFAQScreen();
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showFAQScreen() {
    final faqs = [
      ('What is Huddl?',
          'Huddl is a community app for parents in the Cambridge area. Connect with local parents, join groups, attend meetups, and find support.'),
      ('How do I join a group?',
          'Go to the Local tab \u2192 Discover and browse available groups. Tap on any group and press Join to become a member.'),
      ('Can I create my own group?',
          'Yes! Tap the + button on the Local tab to create a private group and invite members from your borough.'),
      ('How do I change my postcode?',
          'Go to My Profile \u2192 Location and enter your new postcode. This will update your borough and default groups.'),
      ('How do I save a message?',
          'Long-press on any message in a group or DM and select "Save message". You can find saved items in the Saved tab.'),
      ('How do I pin a post?',
          'Tap the three dots on any post in the Cambridge Noticeboard and select "Pin post" to pin it to the top.'),
      ('Is Huddl free?',
          'Yes, Huddl is completely free for all parents in the Cambridge area.'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('FAQs',
                style: HuddlText.display(color: context.hc.textPrimary)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: faqs.length,
                itemBuilder: (_, i) => ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(faqs[i].$1,
                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(faqs[i].$2,
                          style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  // ═══════════════════════════════════════════════════════════════════════════
  // ABOUT HUDDL
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAboutSheet() {
    _showSheet(
      title: 'About Huddl',
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Image.asset(
              'assets/images/logo_huddl_hq.png',
              width: 220,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                        child: Icon(Icons.people, size: 36, color: HuddlColors.textDark)),
                  ),
                  const SizedBox(height: 8),
                  Text('huddl',
                      style: HuddlText.display(color: HuddlColors.textDark)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Version $_appVersion',
              style: HuddlText.body(color: context.hc.textTertiary)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Huddl connects parents in the Cambridge area, helping you find your community, join local groups, attend meetups, and support each other through every stage of parenthood.',
              style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Text('\u00a9 ${DateTime.now().year} Cruzen Ltd. All rights reserved.',
              style: HuddlText.caption(color: context.hc.textTertiary)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS GEAR ICON
  // ═══════════════════════════════════════════════════════════════════════════

  void _openSettingsSheet() {
    Navigator.of(context).push(
      HuddlSpringPageRoute(
        page: _SettingsScreen(profileState: this),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOG OUT
  // ═══════════════════════════════════════════════════════════════════════════

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: HuddlColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout, size: 28, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text('Log out?',
                  style: HuddlText.heading(color: context.hc.textPrimary)),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to log out of your Huddl account?',
                style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text('Cancel',
                          style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.primary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);

                        // 1. Deregister FCM token — deletes token from device
                        //    (iOS/Android) and clears Firestore fcmToken field.
                        //    Must happen BEFORE signOut so uid is still valid.
                        await PushNotificationService().deregisterToken();

                        // 2. Sign out from Firebase Auth
                        try {
                          await FirebaseAuthService().signOut();
                        } catch (_) {}

                        // 3. Clear all local/persisted user data
                        await BrowserStorage.clear();
                        _onboarding.clear();

                        // 4. Reset in-memory privacy prefs singleton
                        UserPrivacyPrefsService().reset();

                        // 5. Navigate directly to login, removing every route
                        if (mounted) {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/login', (r) => false);
                        }
                      },
                      child: Text('Log out',
                          style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROFILE PHOTO
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _changeProfilePhoto() async {
    if (kIsWeb) {
      await _pickProfilePhoto(ImageSource.gallery);
      return;
    }
    if (!mounted) return;
    // ── Photo setup sheet ──────────────────────────────────────────────────────
    // Dark background, circular preview, "Edit photo" text link, pink ••• button
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A), // dark bg — profile setup style
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                // ── Header: Preview / Tips ──────────────────────────────
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                    ),
                    const Spacer(),
                    Text('Preview',
                      style: HuddlText.body(weight: FontWeight.w600, color: Colors.white)),
                    const Spacer(),
                    Text('Tips',
                      style: HuddlText.body(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 32),
                // ── Circular photo preview on dark bg ─────────────────
                Center(
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // Coral accent line above circle
                      Positioned(
                        top: -4,
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF385C),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Circular photo
                      Container(
                        width: 180, height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2C2C2C),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: _photoUrl != null && _photoUrl!.isNotEmpty
                              ? _buildAvatarImage()
                              : _fallbackAvatarDark(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // ── Bottom controls: "Edit photo" + pink ••• button ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // "Edit photo" text link (bottom-left)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickProfilePhoto(ImageSource.gallery);
                      },
                      child: Text('Edit photo',
                        style: HuddlText.body(color: Colors.white).copyWith(decoration: TextDecoration.underline)),
                    ),
                    // Options ••• button (bottom-right)
                    GestureDetector(
                      onTap: () {
                        // Show options popup
                        showModalBottomSheet<void>(
                          context: ctx,
                          backgroundColor: const Color(0xFF1A1A1A),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24)),
                          ),
                          builder: (optCtx) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                      Icons.photo_library_outlined,
                                      color: Colors.white),
                                    title: Text('Choose from gallery',
                                      style: HuddlText.body(color: Colors.white)),
                                    onTap: () {
                                      Navigator.pop(optCtx);
                                      Navigator.pop(ctx);
                                      _pickProfilePhoto(ImageSource.gallery);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.white),
                                    title: Text('Take a photo',
                                      style: HuddlText.body(color: Colors.white)),
                                    onTap: () {
                                      Navigator.pop(optCtx);
                                      Navigator.pop(ctx);
                                      _pickProfilePhoto(ImageSource.camera);
                                    },
                                  ),
                                  if (_photoUrl != null && _photoUrl!.isNotEmpty)
                                    ListTile(
                                      leading: Icon(Icons.delete_outline,
                                        color: HuddlColors.error),
                                      title: Text('Remove photo',
                                        style: HuddlText.body(color: HuddlColors.error)),
                                      onTap: () {
                                        Navigator.pop(optCtx);
                                        Navigator.pop(ctx);
                                        _removeProfilePhoto();
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF385C),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (i) => Padding(
                            padding: EdgeInsets.only(
                              left: i > 0 ? 4 : 0),
                            child: Container(
                              width: 5, height: 5,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Fallback avatar for dark background
  Widget _fallbackAvatarDark() {
    // Show gender-appropriate illustrated avatar on dark background.
    // Dad → John.png, Mum/other → Emma.png
    final asset = _parentType == 'dad'
        ? 'assets/images/avatars/John.png'
        : 'assets/images/avatars/Emma.png';
    return Container(
      width: 180, height: 180,
      color: const Color(0xFF2C2C2C),
      child: ClipRect(
        child: Image.asset(
          asset,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            final raw = _name.trim();
            final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
            final initials = parts.length >= 2
                ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
                : (parts.isNotEmpty ? parts.first[0].toUpperCase() : '?');
            return Center(
              child: Text(initials,
                style: HuddlText.display(color: Colors.white.withValues(alpha: 0.7))),
            );
          },
        ),
      ),
    );
  }


  Future<void> _pickProfilePhoto(ImageSource source) async {
    try {
      // Pass the *already-chosen* source so ImageEditorWidget does NOT show
      // its own source-selection sheet — prevents a double-prompt.
      final file = await ImageEditorWidget.pickProfilePictureWithSource(context, source);

      if (file == null || !mounted) return;

      // Show loading spinner immediately so the user knows something is happening
      setState(() => _isPhotoUploading = true);

      // Build a base64 data URL for immediate local preview (survives storage /
      // app restarts; raw local file paths break on other devices and after the
      // OS clears its temp directory).
      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);
      final mimeType =
          file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final dataUrl = 'data:$mimeType;base64,$base64Str';
      _onboarding.setProfilePhotoObjectUrl(dataUrl);

      // Show preview immediately — don't wait for upload
      if (mounted) {
        setState(() {
          _photoUrl = dataUrl;
          _isPhotoUploading = true; // keep spinner while uploading
        });
      }

      // Upload to Firebase Storage and get a permanent HTTPS download URL.
      // This is the URL that gets written to Firestore — safe from any device.
      // ImageEditorWidget returns a dart:io File, so use the File overload.
      final downloadUrl = await _photoUpload.uploadProfilePhotoFromFile(file);
      if (downloadUrl != null) {
        // Save the permanent HTTPS URL locally
        _onboarding.setProfilePhotoPath(downloadUrl);
        // ── CRITICAL: write photoUrl to Firestore so other devices see it ──
        // Without this, the profile photo only exists on this device.
        try {
          await FirestoreService().updateUserProfile({'photoUrl': downloadUrl});
          if (kDebugMode) debugPrint('[ProfileScreen] photoUrl written to Firestore: $downloadUrl');
        } catch (fsErr) {
          if (kDebugMode) debugPrint('[ProfileScreen] Firestore photoUrl update failed: $fsErr');
          // Non-fatal — photo is uploaded; Firestore update can be retried
        }
        // Update local state to show the HTTPS URL (replaces data: URI)
        if (mounted) {
          setState(() => _photoUrl = downloadUrl);
        }
      } else {
        // Upload failed — keep data URL as local fallback but it won't sync
        // to other devices. Show a warning so the user knows.
        _onboarding.setProfilePhotoPath(dataUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo saved locally — upload will retry next time'),
            backgroundColor: HuddlColors.warning,
          ));
        }
      }

      if (!mounted) return;
      setState(() => _isPhotoUploading = false);
      _snack('Profile photo updated ✓');
    } catch (e) {
      if (mounted) {
        setState(() => _isPhotoUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not update photo: $e'),
            backgroundColor: HuddlColors.error));
      }
    }
  }

  void _removeProfilePhoto() {
    _onboarding.setProfilePhotoPath(null);
    _onboarding.setProfilePhotoObjectUrl(null);
    setState(() => _photoUrl = null);
    _snack('Profile photo removed');
  }

  Widget _buildAvatar() {
    // Show spinner overlay while encoding/saving the new photo
    if (_isPhotoUploading) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: HuddlColors.primary.withValues(alpha: 0.08),
          border: Border.all(color: HuddlColors.primary, width: 2),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: HuddlColors.primary,
          ),
        ),
      );
    }
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: HuddlColors.nearBlack.withValues(alpha: 0.12),
            width: 1.5),
        ),
        child: ClipOval(child: _buildAvatarImage()),
      );
    }
    return _fallbackAvatar();
  }

  Widget _buildAvatarImage() {
    if (_photoUrl!.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(_photoUrl!);
        final base64Str = dataUri.data?.contentAsBytes();
        if (base64Str != null) {
          return Image.memory(Uint8List.fromList(base64Str),
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackAvatar());
        }
      } catch (_) {}
      return _fallbackAvatar();
    }
    return Image.network(_photoUrl!,
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackAvatar());
  }

  Widget _fallbackAvatar() {
    // Show gender-appropriate illustrated avatar when no profile photo is set.
    // Dad → John.png, Mum/other → Emma.png
    final asset = _parentType == 'dad'
        ? 'assets/images/avatars/John.png'
        : 'assets/images/avatars/Emma.png';
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HuddlColors.primary.withValues(alpha: 0.08),
        border: Border.all(
          color: HuddlColors.primary.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.person,
            size: 44,
            color: HuddlColors.primary,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FEEDBACK & RATING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Feedback card shown in the profile — feedback only, no star rating.
  Widget _buildFeedbackCard() {
    return Container(
      color: context.hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: HuddlButton(
        label: 'Give Feedback',
        leadingIcon: Icons.rate_review_outlined,
        onPressed: _openFeedbackScreen,
      ),
    );
  }

  /// Opens the full Feedback screen as a large bottom sheet
  void _openFeedbackScreen() {
    final feedbackCtrl = TextEditingController();
    bool isSubmitting = false;
    bool isSubmitted = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => GestureDetector(
        onTap: () => FocusScope.of(sheetCtx).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
          child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scroll) => StatefulBuilder(
          builder: (ctx2, setLocal) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: context.hc.divider,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('Feedback',
                    style: HuddlText.display(color: context.hc.textPrimary)),
                const SizedBox(height: 4),
                Text('Help us make Huddl better',
                    style: HuddlText.body(color: context.hc.textTertiary)),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    child: isSubmitted
                        ? _buildSubmittedState(ctx)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Feedback Text Section ──
                              Text(
                                'Your feedback',
                                style: HuddlText.body(weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tell us what you love or what could be better. Your honest feedback helps us improve!',
                                style: HuddlText.body(color: context.hc.textTertiary),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: feedbackCtrl,
                                maxLines: 6,
                                maxLength: 1000,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: (_) => setLocal(() {}),
                                style: HuddlText.body(color: context.hc.textPrimary),
                                decoration: InputDecoration(
                                  hintText:
                                      'Share your thoughts about the app...',
                                  hintStyle: HuddlText.body(color: context.hc.textTertiary),
                                  filled: true,
                                  fillColor: context.hc.scaffold,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: context.hc.divider),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: context.hc.divider),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: HuddlColors.primary, width: 2),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),

                              const SizedBox(height: 8),

                              // ── Suggestions ──
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F7F7),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.lightbulb_outline,
                                        size: 18, color: HuddlColors.textDark),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'You might want to mention: features you enjoy, things that could be improved, ideas for new features, or your overall experience.',
                                        style: HuddlText.caption(color: HuddlColors.textDark),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // ── Submit Button ──
                              HuddlButton(
                                label: 'Submit Feedback',
                                isLoading: isSubmitting,
                                onPressed: feedbackCtrl.text.trim().isEmpty || isSubmitting
                                    ? null
                                    : () async {
                                        setLocal(() => isSubmitting = true);

                                        await _feedbackService.submitFeedback(
                                          feedbackText: feedbackCtrl.text.trim(),
                                          starRating: 0,
                                          userName: _name,
                                        );

                                        // Short delay for UX
                                        await Future.delayed(
                                            const Duration(milliseconds: 600));

                                        if (ctx2.mounted) {
                                          setLocal(() {
                                            isSubmitting = false;
                                            isSubmitted = true;
                                          });
                                        }
                                      },
                              ),

                              const SizedBox(height: 12),

                              // Privacy note
                              Center(
                                child: Text(
                                  'Your feedback is anonymous and helps us improve.',
                                  style: HuddlText.caption(),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
        ),
      ),
    );
  }

  /// The "Thank you" state shown after successful submission
  Widget _buildSubmittedState(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: HuddlColors.nearBlack.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_circle, size: 48, color: HuddlColors.nearBlack),
          ),
          const SizedBox(height: 20),
          Text(
            'Thank you!',
            style: HuddlText.display(),
          ),
          const SizedBox(height: 8),
          Text(
            'Your feedback has been submitted.\nWe truly value your input — it helps us make\nHuddl better for everyone.',
            textAlign: TextAlign.center,
            style: HuddlText.body(color: context.hc.textSecondary),
          ),
          const SizedBox(height: 32),
          HuddlButton(
            label: 'Done',
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: HuddlText.body()),
      backgroundColor: HuddlColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSheet({required String title, required Widget Function(BuildContext) builder}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => GestureDetector(
        onTap: () => FocusScope.of(sheetCtx).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Pushes sheet content up when keyboard appears
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            expand: false,
            builder: (c, scroll) => Column(
              children: [
                const SizedBox(height: 10),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: context.hc.divider,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text(title,
                    style: HuddlText.display(color: context.hc.textPrimary)),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: builder(c),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      autocorrect: false,
      onChanged: onChanged,
      textCapitalization: keyboardType == TextInputType.emailAddress
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      style: HuddlText.body(color: context.hc.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: HuddlText.caption(color: context.hc.textTertiary),
        prefixIcon: Icon(icon, size: 20, color: context.hc.textTertiary),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.hc.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: HuddlColors.primary, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _sheetButton(String label, VoidCallback onTap) {
    return HuddlButton(
      label: label,
      onPressed: onTap,
    );
  }

  Widget _toggleTile(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      secondary: Icon(icon, size: 22, color: context.hc.textPrimary),
      title: Text(title,
          style: HuddlText.body(color: context.hc.textPrimary)),
      subtitle: Text(subtitle,
          style:
              HuddlText.caption(color: context.hc.textTertiary)),
      value: value,
      onChanged: onChanged,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.primary;
        return HuddlColors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return HuddlColors.primary.withValues(alpha: 0.4);
        return HuddlColors.gray300;
      }),
    );
  }

  Widget _helpTile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: 22, color: context.hc.textPrimary),
      title: Text(title,
          style: HuddlText.body(color: context.hc.textPrimary)),
      subtitle: Text(subtitle,
          style:
              HuddlText.caption(color: context.hc.textTertiary)),
      trailing:
          Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
      onTap: onTap,
    );
  }

  // _emptyState removed — all empty states now use HuddlEmptyState with
  // the appropriate HuddlIllustration brand asset.
  // _circleIcon removed — was unreferenced dead code.
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

/// Horizontal card for the "My Groups" section — wide enough for full names.
class _GroupCard extends StatelessWidget {
  final Group group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: context.hc.inputBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: HuddlColors.divider, width: 1),
      ),
      child: Row(
        children: [
          // ── Group image ──────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(13),
              bottomLeft: Radius.circular(13),
            ),
            child: SizedBox(
              width: 80,
              height: 88,
              child: group.imageUrl.startsWith('assets/')
                  ? Image.asset(group.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imageFallback())
                  : group.imageUrl.startsWith('http')
                      ? Image.network(group.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imageFallback())
                      : _imageFallback(),
            ),
          ),
          // ── Group info ───────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    group.name,
                    style: HuddlText.caption(weight: FontWeight.w600, color: context.hc.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people_outline,
                          size: 11, color: context.hc.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
                        style: HuddlText.label(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback() => Container(
        color: const Color(0xFFF7F7F7),
        child: const Center(
            child: Icon(Icons.people, size: 28, color: HuddlColors.textDark)));
}

class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Stat numbers \u2014 infoBlue: numeric data labels are informational,
        // not CTAs. Keeps orange exclusively for action buttons.
        Text(count,
            style: HuddlText.display(color: HuddlColors.infoBlue)),
        Text(label,
            style: HuddlText.caption(color: context.hc.textTertiary)),
      ],
    );
  }
}

class _MenuSection extends StatelessWidget {
  final String title;
  final List<_MenuItem> items;
  const _MenuSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.hc.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              title.toUpperCase(),
              style: HuddlText.caption(weight: FontWeight.w600).copyWith(letterSpacing: 0.8),
            ),
          ),
          const Divider(height: 1, indent: 0, endIndent: 0),
          ...items,
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: context.hc.scaffold,
            borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 18, color: context.hc.textSecondary),
      ),
      title: Text(title,
          style: HuddlText.body(color: context.hc.textPrimary)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: HuddlText.caption(color: context.hc.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing:
          trailing ?? Icon(Icons.chevron_right, color: context.hc.textTertiary),
      onTap: onTap,
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textTertiary)),
          ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: context.hc.textTertiary),
      ],
    );
  }
}

// =============================================================================
// SETTINGS SCREEN — full-screen unified settings
//
// Replaces the old _openSettingsSheet() bottom sheet pattern.
// Single entry point: gear icon in _buildIdentityHeader → Navigator.push here.
// Seven sections: Account, Security, Privacy, Your data, Notifications,
// Support, Legal. Sign-out button at the bottom.
// =============================================================================

class _SettingsScreen extends StatelessWidget {
  final _ProfileScreenState profileState;
  const _SettingsScreen({required this.profileState});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings', style: HuddlText.heading()),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [

          // ── Account ───────────────────────────────────────────────────
          _SettingsSection(
            title: 'Account',
            items: [
              _SettingsItem(
                icon: Icons.person_outline,
                title: 'Edit profile',
                subtitle: 'Name, bio, and photo',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showEditProfileSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.child_care,
                title: 'Stage of life',
                subtitle: profileState._stageLabel.isNotEmpty
                    ? profileState._stageLabel
                    : 'Set your stage',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showStageOfLifeSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle:
                    '${profileState._borough}${profileState._postcode != null ? ' (${profileState._postcode})' : ''}',
                showOtpBadge: true,
                onTap: () {
                  Navigator.pop(context);
                  profileState._showLocationSheet();
                },
              ),
              if (profileState._phone != null)
                _SettingsItem(
                  icon: Icons.phone_outlined,
                  title: 'Phone number',
                  subtitle: profileState._phone,
                  showOtpBadge: true,
                  onTap: () {
                    Navigator.pop(context);
                    profileState._showPhoneSheet();
                  },
                ),
              _SettingsItem(
                icon: Icons.credit_card_outlined,
                title: 'Subscription & billing',
                subtitle: profileState._subscriptionService
                    .subscription.tierDisplayName,
                onTap: () {
                  Navigator.pop(context);
                  final route =
                      profileState._subscriptionService.isFree
                          ? '/subscription_plans'
                          : '/manage_subscription';
                  Navigator.pushNamed(context, route);
                },
              ),
              _SettingsItem(
                icon: Icons.backup_outlined,
                title: 'Backup & restore',
                subtitle: 'Export or restore your app data',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/backup_restore');
                },
              ),

              // ── Business verification ───────────────────────────────
              // Visible only for Plus/Partner users — free (explorer) users hidden.

              // Unverified Plus/Partner: offer path to get verified
              if (SubscriptionService().isPlusOrAbove &&
                  !SubscriptionService().isBusinessVerified)
                _SettingsItem(
                  icon: Icons.verified_outlined,
                  title: 'Verify your business',
                  subtitle: 'Get the HMRC-verified badge and list your services',
                  iconColor: HuddlColors.infoBlue,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/business_verification');
                  },
                ),

              // Already verified Plus/Partner: show confirmed status
              if (SubscriptionService().isPlusOrAbove &&
                  SubscriptionService().isBusinessVerified)
                _SettingsItem(
                  icon: Icons.verified_rounded,
                  title: 'Business verified',
                  subtitle: 'HMRC Partner badge active on your listings',
                  iconColor: HuddlColors.primary,
                  onTap: () {},
                ),
            ],
          ),

          // ── Security ──────────────────────────────────────────────────
          _SettingsSection(
            title: 'Security',
            items: [
              _SettingsItem(
                icon: Icons.lock_reset_outlined,
                title: 'Change password',
                subtitle: 'Identity verified by SMS code',
                showOtpBadge: true,
                onTap: () {
                  Navigator.pop(context);
                  profileState._showChangePasswordSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.fingerprint,
                title: 'Biometric login',
                subtitle: 'Face ID or fingerprint unlock',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showPrivacySheet();
                },
              ),
            ],
          ),

          // ── Privacy ───────────────────────────────────────────────────
          _SettingsSection(
            title: 'Privacy',
            items: [
              _SettingsItem(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy settings',
                subtitle: 'Profile visibility, read receipts, blocked users',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showPrivacySheet();
                },
              ),
              _SettingsItem(
                icon: Icons.mic_outlined,
                title: 'Voice message consent',
                subtitle: 'Microphone access and audio data',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showPrivacySheet();
                },
              ),
            ],
          ),

          // ── Your Data (GDPR) ──────────────────────────────────────────
          _SettingsSection(
            title: 'Your data',
            items: [
              _SettingsItem(
                icon: Icons.visibility_outlined,
                title: 'View my data',
                subtitle: 'See all personal data Huddl holds — Article 15',
                iconColor: HuddlColors.infoBlue,
                onTap: () {
                  Navigator.pop(context);
                  profileState._showViewMyDataSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.download_outlined,
                title: 'Export my data',
                subtitle: 'Download a portable copy — Article 20',
                iconColor: HuddlColors.infoBlue,
                onTap: () {
                  Navigator.pop(context);
                  profileState._showExportDataSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.tune_outlined,
                title: 'Analytics preferences',
                subtitle: 'Opt out of app analytics and crash reporting',
                iconColor: HuddlColors.infoBlue,
                onTap: () {
                  Navigator.pop(context);
                  profileState._showAnalyticsPrefsSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.delete_forever,
                title: 'Delete my account & data',
                subtitle: 'Permanently delete everything — Article 17',
                iconColor: HuddlColors.error,
                titleColor: HuddlColors.error,
                onTap: () {
                  Navigator.pop(context);
                  profileState._showDeleteAccountSheet();
                },
              ),
            ],
          ),

          // ── Notifications ─────────────────────────────────────────────
          _SettingsSection(
            title: 'Notifications',
            items: [
              _SettingsItem(
                icon: Icons.notifications_outlined,
                title: 'Notification preferences',
                subtitle: 'Groups, meetups, messages, market',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showNotificationsSheet();
                },
              ),
            ],
          ),

          // ── Support ───────────────────────────────────────────────────
          _SettingsSection(
            title: 'Support',
            items: [
              _SettingsItem(
                icon: Icons.help_outline,
                title: 'Help & support',
                subtitle: 'FAQs and contact',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showHelpSheet();
                },
              ),
              _SettingsItem(
                icon: Icons.feedback_outlined,
                title: 'Send feedback',
                subtitle: 'Tell us what you think',
                onTap: () {
                  Navigator.pop(context);
                  profileState._openFeedbackScreen();
                },
              ),
              _SettingsItem(
                icon: Icons.school_outlined,
                title: 'Run tutorial',
                subtitle: 'Walk through the app again',
                onTap: () {
                  Navigator.pop(context);
                  profileState._rerunTutorial();
                },
              ),
              _SettingsItem(
                icon: Icons.info_outline,
                title: 'About Huddl',
                subtitle: 'Version, credits, and legal',
                onTap: () {
                  Navigator.pop(context);
                  profileState._showAboutSheet();
                },
              ),
              if (profileState._isAdmin)
                _SettingsItem(
                  icon: Icons.shield_outlined,
                  title: 'Admin dashboard',
                  subtitle: 'Review user reports',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/admin');
                  },
                ),
            ],
          ),

          // ── Legal ─────────────────────────────────────────────────────
          // Terms and Privacy open in external browser — URLs must match
          // those declared in App Store Connect and Google Play Console.
          _SettingsSection(
            title: 'Legal',
            items: [
              _SettingsItem(
                icon: Icons.description_outlined,
                title: 'Terms of service',
                onTap: () => launchUrl(
                  Uri.parse(
                      'https://www.huddlapp.co.uk/terms-of-service.html'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _SettingsItem(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                onTap: () => launchUrl(
                  Uri.parse(
                      'https://www.huddlapp.co.uk/privacy-policy.html'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _SettingsItem(
                icon: Icons.cookie_outlined,
                title: 'Cookie & analytics policy',
                onTap: () => launchUrl(
                  Uri.parse(
                      'https://www.huddlapp.co.uk/cookie-policy.html'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),

          // ── Sign out ──────────────────────────────────────────────────
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: HuddlButton(
              label: 'Sign out',
              onPressed: () async {
                Navigator.pop(context);
                profileState._confirmLogout();
              },
              variant: HuddlButtonVariant.secondary,
              fullWidth: true,
            ),
          ),

          if (kDebugMode) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: HuddlButton(
                label: 'Borough debug',
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/borough_debug');
                },
                variant: HuddlButtonVariant.ghost,
                fullWidth: true,
              ),
            ),
          ],

          const SizedBox(height: 24),
          Center(
            child: Text(
              '© ${DateTime.now().year} Cruzen Ltd. All rights reserved.',
              style: HuddlText.caption(),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SETTINGS SECTION — labelled group of settings items in a rounded card
// =============================================================================

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;
  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(
            title.toUpperCase(),
            style: HuddlText.caption(
              color: HuddlColors.textTertiary,
              weight: FontWeight.w600,
            ).copyWith(letterSpacing: 0.8),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.hc.divider, width: 0.5),
          ),
          child: Column(
            children: items.asMap().entries.map((e) {
              final isLast = e.key == items.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 52,
                      endIndent: 0,
                      color: context.hc.divider,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SETTINGS ITEM — single row with icon, title, subtitle, OTP badge, chevron
// =============================================================================

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;
  // When true, shows a small orange OTP badge indicating this action
  // requires SMS verification before proceeding.
  final bool showOtpBadge;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.showOtpBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            // Leading icon in a rounded container
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (iconColor ?? HuddlColors.textTertiary)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: iconColor ?? context.hc.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: HuddlText.body(
                      color: titleColor ?? context.hc.textPrimary,
                      weight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: HuddlText.caption(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // OTP badge — shown on Location, Phone, Change password
            if (showOtpBadge)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        size: 11, color: HuddlColors.primary),
                    const SizedBox(width: 3),
                    Text(
                      'OTP',
                      style: HuddlText.label(color: HuddlColors.primary),
                    ),
                  ],
                ),
              ),
            Icon(Icons.chevron_right,
                size: 18, color: context.hc.textTertiary),
          ],
        ),
      ),
    );
  }
}
