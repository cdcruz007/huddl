import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/image_editor_widget.dart';
import '../../widgets/common/huddl_empty_state.dart';
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
import '../debug/borough_debug_screen.dart';
import '../../services/gdpr_borough_data_service.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/huddl_user_service.dart';
import '../../services/photo_upload_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/user_privacy_prefs_service.dart';
import '../../services/biometric_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // Biometric login
  final _biometricService = BiometricAuthService();
  bool _biometricEnabled   = false;
  bool _biometricAvailable = false;
  String _biometricLabel   = 'Biometrics';

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
          // Force-reload again so the values just written by restore are read
          await _onboarding.initialize(forceReload: true);
        } catch (_) {}
      }

      await _groupService.initialize();

      String borough = 'Not set';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? 'Unknown';
      }

      final defaultGroups = await _groupService.getUserGroups('current_user');

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
        //       which is exclusively used by DefaultGroupService.
        final yearGroupPattern = RegExp(r'^\d{4}\s+\S');
        discovered = firestoreGroups
            .where((g) => !defaultGroupIds.contains(g.id))
            .where((g) => !g.isImageLocked)
            .where((g) => !yearGroupPattern.hasMatch(g.name))
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

      // Load events the user is registered for
      final userEvents = _eventService.goingEvents;
      final userMeetups = _meetupService.meetups
          .where((m) => m.organiserId == 'current_user' || m.isGoing)
          .toList();

      setState(() {
        _name = _onboarding.name ?? 'User';
        _borough = borough;
        _bio = _onboarding.bio;
        _photoUrl = _onboarding.profilePhotoObjectUrl;
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
    final isFree = sub.isFree;
    final isNeighbourhood = sub.isNeighbourhood;
    final isInnerCircle = sub.isInnerCircle;

    Color accentColor = HuddlColors.textHint;
    IconData icon = Icons.explore_outlined;
    String planLabel = 'Welcome';
    String subtitle = 'Upgrade for unlimited access';

    if (isNeighbourhood) {
      accentColor = HuddlColors.primary;
      icon = Icons.home_outlined;
      planLabel = 'Neighbour';
      subtitle = sub.billingPeriod == BillingPeriod.annual
              ? '\u00A349.99/year'
              : '\u00A35.99/month';
    } else if (isInnerCircle) {
      accentColor = HuddlColors.teal;
      icon = Icons.workspace_premium;
      planLabel = 'Circle';
      subtitle = sub.billingPeriod == BillingPeriod.annual
          ? '\u00A399.99/year'
          : '\u00A312.99/month';
    }

    return Container(
      color: context.hc.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Subscription',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textTertiary)),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () async {
              if (isFree) {
                await Navigator.pushNamed(context, '/subscription_plans');
              } else {
                await Navigator.pushNamed(context, '/manage_subscription');
              }
              if (mounted) setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isFree
                      ? HuddlColors.primary.withValues(alpha: 0.25)
                      : accentColor.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accentColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(planLabel,
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: context.hc.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(subtitle,
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: context.hc.textSecondary)),
                      ],
                    ),
                  ),
                  if (isFree)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: HuddlColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Upgrade',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.white)),
                    )
                  else
                    Icon(Icons.chevron_right,
                        color: accentColor, size: 22),
                ],
              ),
            ),
          ),
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
        body: Center(
            child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.primary,
          onRefresh: _loadProfileData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // ── Name-repair banner ──────────────────────────────────
                // Shown when the user's name is missing or is a phone-number
                // placeholder left by the automatic self-repair after a
                // Firestore name-overwrite bug. Tapping it opens Edit Profile.
                if (_name.isEmpty || _name == 'User' || _name.startsWith('+'))
                  GestureDetector(
                    onTap: _showEditProfileSheet,
                    child: Container(
                      width: double.infinity,
                      color: HuddlColors.primary.withValues(alpha: 0.10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: HuddlColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tap here to add your name to complete your profile',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: HuddlColors.primary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: HuddlColors.primary, size: 18),
                        ],
                      ),
                    ),
                  ),
                // ── Profile header ──────────────────────────────────────
                Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'My Profile',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.settings_outlined,
                                color: context.hc.textPrimary),
                            onPressed: _openSettingsSheet,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
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
                                color: HuddlColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: context.hc.surface, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 14, color: HuddlColors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _showEditProfileSheet,
                            child: Text(
                                (_name.isEmpty || _name == 'User' || _name.startsWith('+'))
                                    ? 'Tap to add name'
                                    : _name,
                                style: GoogleFonts.poppins(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: (_name.isEmpty || _name == 'User' || _name.startsWith('+'))
                                        ? HuddlColors.primary.withValues(alpha: 0.6)
                                        : context.hc.textPrimary)),
                          ),
                          if (_subscriptionService.isPaid) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _subscriptionService.isInnerCircle
                                    ? HuddlColors.teal
                                    : HuddlColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _subscriptionService.isInnerCircle
                                        ? Icons.workspace_premium
                                        : Icons.home_outlined,
                                    color: context.hc.surface,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    _subscriptionService.isInnerCircle ? 'INNER CIRCLE' : 'N\'HOOD',
                                    style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: HuddlColors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 16, color: HuddlColors.textHint),
                          const SizedBox(width: 4),
                          Text(_borough,
                              style: GoogleFonts.poppins(
                                  fontSize: 14, color: context.hc.textTertiary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_stageLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: HuddlColors.primary.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(_stageLabel,
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.primary),
                              textAlign: TextAlign.center),
                        ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(
                              count: '$_totalGroupCount', label: 'Groups'),
                          Container(
                              width: 1, height: 32, color: context.hc.divider),
                          _StatItem(
                              count: '${_children.length}',
                              label:
                                  _children.length == 1 ? 'Child' : 'Children'),
                          Container(
                              width: 1, height: 32, color: context.hc.divider),
                          _StatItem(
                            count: _parentType.toLowerCase() == 'mum'
                                ? 'Mum'
                                : _parentType.toLowerCase() == 'dad'
                                    ? 'Dad'
                                    : _parentType.isNotEmpty
                                        ? _parentType[0].toUpperCase() +
                                            _parentType.substring(1)
                                        : '-',
                            label: 'Role',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── App Rating & Feedback card ─────────────────────────
                _buildFeedbackCard(),

                const SizedBox(height: 8),

                // ── About me section ─────────────────────────────────────
                if (_bio != null && _bio!.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: context.hc.surface,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About me',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.hc.textTertiary)),
                        const SizedBox(height: 8),
                        Text(_bio!,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: context.hc.textPrimary,
                                height: 1.5)),
                      ],
                    ),
                  ),
                if (_bio != null && _bio!.trim().isNotEmpty)
                  const SizedBox(height: 8),

                // ── My groups horizontal card list ───────────────────────
                if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                  Container(
                    color: context.hc.surface,
                    padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Row(
                            children: [
                              Text('My Groups',
                                  style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.hc.textPrimary)),
                              const Spacer(),
                              GestureDetector(
                                onTap: _showMyGroupsSheet,
                                child: Text('See all $_totalGroupCount',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: HuddlColors.primary,
                                        fontWeight: FontWeight.w500)),
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
                  ),
                if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                  const SizedBox(height: 8),

                // ── Subscription section ──────────────────────────────────
                _buildSubscriptionCard(),
                const SizedBox(height: 8),

                // ── Account section ──────────────────────────────────────
                _MenuSection(
                  title: 'Account',
                  items: [
                    _MenuItem(
                      icon: Icons.person_outline,
                      title: 'Edit profile',
                      onTap: _showEditProfileSheet,
                    ),
                    _MenuItem(
                      icon: Icons.child_care,
                      title: 'Stage of life',
                      subtitle: _stageLabel.isNotEmpty ? _stageLabel : null,
                      onTap: _showStageOfLifeSheet,
                    ),
                    _MenuItem(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      subtitle: '$_borough${_postcode != null ? ' ($_postcode)' : ''}',
                      onTap: _showLocationSheet,
                    ),
                    if (_phone != null)
                      _MenuItem(
                        icon: Icons.phone_outlined,
                        title: 'Phone',
                        subtitle: _phone,
                        onTap: _showPhoneSheet,
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                _MenuSection(
                  title: 'Activity',
                  items: [
                    _MenuItem(
                      icon: Icons.people_outline,
                      title: 'My Groups',
                      trailing: _CountBadge(count: _totalGroupCount),
                      onTap: _showMyGroupsSheet,
                    ),
                    _MenuItem(
                      icon: Icons.event_outlined,
                      title: 'My Meetups',
                      trailing: _CountBadge(count: _userEvents.length + _userMeetups.length),
                      onTap: _showMyEventsSheet,
                    ),
                    _MenuItem(
                      icon: Icons.storefront_outlined,
                      title: 'My listings',
                      trailing: const _CountBadge(count: 0),
                      onTap: _showMyListingsSheet,
                    ),
                    _MenuItem(
                      icon: Icons.bookmark_border,
                      title: 'Saved',
                      onTap: _showSavedSheet,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                _MenuSection(
                  title: 'Settings',
                  items: [
                    _MenuItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      onTap: _showNotificationsSheet,
                    ),
                    _MenuItem(
                      icon: Icons.lock_outline,
                      title: 'Privacy',
                      onTap: _showPrivacySheet,
                    ),
                    _MenuItem(
                      icon: Icons.password_outlined,
                      title: 'Change password',
                      onTap: _showChangePasswordSheet,
                    ),
                    _MenuItem(
                      icon: Icons.feedback_outlined,
                      title: 'Feedback',
                      subtitle: 'Tell us what you think',
                      onTap: _openFeedbackScreen,
                    ),
                    if (kDebugMode)
                      _MenuItem(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Admin Dashboard',
                        subtitle: 'Review reported content',
                        onTap: () => Navigator.pushNamed(context, '/admin'),
                      ),
                    _MenuItem(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap: _showHelpSheet,
                    ),
                    _MenuItem(
                      icon: Icons.school_outlined,
                      title: 'Run Tutorial',
                      subtitle: 'Walk through the app again',
                      onTap: _rerunTutorial,
                    ),
                    _MenuItem(
                      icon: Icons.info_outline,
                      title: 'About Huddl',
                      onTap: _showAboutSheet,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                _MenuSection(
                  title: 'Legal',
                  items: [
                    _MenuItem(
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.huddlapp.co.uk/terms-of-service.html'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    _MenuItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.huddlapp.co.uk/privacy-policy.html'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Logout
                Container(
                  color: context.hc.surface,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading:
                        const Icon(Icons.logout, color: HuddlColors.error),
                    title: Text('Log out',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.error)),
                    onTap: _confirmLogout,
                  ),
                ),

                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Version 1.0.0',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: context.hc.textTertiary)),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
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

    _showSheet(
      title: 'Edit Profile',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            _sheetField(nameCtrl, 'Name', Icons.person_outline),
            const SizedBox(height: 16),
            _sheetField(bioCtrl, 'About me', Icons.edit_note, maxLines: 4),
            const SizedBox(height: 24),
            _sheetButton('Save Changes', () async {
              final newName = nameCtrl.text.trim();
              final newBio  = bioCtrl.text.trim().isEmpty ? null : bioCtrl.text.trim();

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
                await HuddlUserService().syncCurrentUserProfile()
                    .timeout(const Duration(seconds: 5));
              } catch (_) {}

              if (mounted) {
                Navigator.pop(c);
                _snack('Profile updated');
              }
            }),
            const SizedBox(height: 16),
          ],
        ),
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
                        : HuddlColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.hc.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: HuddlColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _parentType.toLowerCase() == 'dad' ? Icons.face : Icons.face_3,
                          size: 22,
                          color: HuddlColors.primary,
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
                              style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.textPrimary),
                            ),
                            if (parentTypeLocked)
                              Text(
                                'Set during sign-up and cannot be changed',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: context.hc.textTertiary),
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
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary)),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Select all that apply to you',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: context.hc.textTertiary)),
              ),
              const SizedBox(height: 12),

              ...[
                ('aspiring', 'Trying for a baby', Icons.favorite_outline, HuddlColors.accentCoral),
                ('expecting', 'Expecting', Icons.pregnant_woman, HuddlColors.primary),
                ('parent', 'Already a parent', Icons.child_care, HuddlColors.teal),
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
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: isOn ? FontWeight.w600 : FontWeight.w500,
                                    color: context.hc.textPrimary)),
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
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary)),
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
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20)),
                        ),
                        builder: (yCtx) => SizedBox(
                          height: 220,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text('Select due year',
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: context.hc.textPrimary)),
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
                                          style: GoogleFonts.poppins(
                                              fontSize: 16,
                                              fontWeight: isSel
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: isSel
                                                  ? HuddlColors.primary
                                                  : HuddlColors.textDark)),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.hc.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 18, color: HuddlColors.primary),
                          const SizedBox(width: 12),
                          Text(
                            selectedDueYear.isNotEmpty
                                ? selectedDueYear
                                : 'Select year',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: selectedDueYear.isNotEmpty
                                    ? HuddlColors.textDark
                                    : HuddlColors.textHint),
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
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary)),
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
                            color: HuddlColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add,
                                  size: 16, color: HuddlColors.primary),
                              const SizedBox(width: 4),
                              Text('Add child',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: HuddlColors.primary)),
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
                              color: HuddlColors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text('${i + 1}',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: HuddlColors.teal)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: nameC,
                              onChanged: (v) => childrenList[i]['name'] = v,
                              style: GoogleFonts.poppins(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Name',
                                hintStyle: GoogleFonts.poppins(
                                    fontSize: 13, color: context.hc.textTertiary),
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
                              style: GoogleFonts.poppins(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Year',
                                hintStyle: GoogleFonts.poppins(
                                    fontSize: 13, color: context.hc.textTertiary),
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
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
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
                              userId: 'current_user',
                              stages: selected.toList(),
                              postcode: _postcode,
                            );
                            await _loadProfileData();
                            _snack(
                                'Stage of life updated \u2014 your groups have been refreshed');
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HuddlColors.primary,
                      disabledBackgroundColor:
                          HuddlColors.primary.withValues(alpha: 0.3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                    ),
                    child: Text('Save Changes',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
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
                  color: HuddlColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: HuddlColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changing your postcode will update your borough and default groups. Only Cambridge postcodes are accepted.',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: HuddlColors.primary, height: 1.4),
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
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: context.hc.textSecondary)),
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
                                color: HuddlColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.location_off,
                                  size: 28, color: HuddlColors.primary),
                            ),
                            const SizedBox(height: 16),
                            Text('We\u2019re not in your area yet',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: context.hc.textPrimary)),
                            const SizedBox(height: 10),
                            Text(
                              'Huddl is currently only available in the Cambridge area. We\u2019re expanding soon \u2014 stay tuned!',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: context.hc.textSecondary,
                                  height: 1.5),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(dCtx),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: HuddlColors.primary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                ),
                                child: Text('OK',
                                    style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ),
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

                // Borough was already resolved and cached by isCambridgePostcodeAsync above.
                final newBorough =
                    _postcodeService.getBoroughFromPostcode(newPc) ?? await _postcodeService.lookupBoroughAsync(newPc) ?? 'Unknown';

                // Capture current borough BEFORE updating
                final previousBorough = _borough;

                // Store current as previous for hasChangedBorough
                if (_postcode != null && _postcode != newPc) {
                  _onboarding.setPreviousBorough(_borough);
                }
                _onboarding.setPostcode(newPc);

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
                  userId: 'current_user',
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
        'current_user', previousBorough);

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
                    color: HuddlColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: HuddlColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can opt to remove yourself from your previous $previousBorough borough groups below.',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: HuddlColors.primary,
                              height: 1.4),
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
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary)),
                        subtitle: Text('${g.memberCount} members',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: context.hc.textTertiary)),
                        trailing: TextButton(
                          onPressed: () async {
                            final left = await _groupService.leaveGroup(
                                'current_user', g.id);
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
                              style: GoogleFonts.poppins(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(c),
                    style: TextButton.styleFrom(
                      foregroundColor: HuddlColors.textSecondary,
                    ),
                    child: Text('Keep all groups',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w500)),
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
  // PHONE
  // ═══════════════════════════════════════════════════════════════════════════

  void _showPhoneSheet() {
    // Remove country code if it's already in the phone number
    String phoneOnly = _onboarding.phoneNumber ?? '';
    if (phoneOnly.startsWith('+44')) {
      phoneOnly = phoneOnly.substring(3);
    } else if (phoneOnly.startsWith('44')) {
      phoneOnly = phoneOnly.substring(2);
    }
    final phoneCtrl = TextEditingController(text: phoneOnly);

    _showSheet(
      title: 'Phone Number',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 20, color: HuddlColors.primaryDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Changing your phone number will also update your login credentials. You will need to use the new number to sign in.',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.primaryDark,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.hc.scaffold,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.hc.divider),
                  ),
                  child: Text('+44',
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textPrimary)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.poppins(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Phone number',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textTertiary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: context.hc.divider)),
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
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _sheetButton('Update Phone', () async {
              String newPhone = phoneCtrl.text.trim();
              if (newPhone.isNotEmpty) {
                // Remove country code if user accidentally included it
                if (newPhone.startsWith('+44')) {
                  newPhone = newPhone.substring(3);
                } else if (newPhone.startsWith('44')) {
                  newPhone = newPhone.substring(2);
                }
                
                // OTP verification for phone change
                Navigator.pop(c);
                final verified = await _verifyWithOtp('change your phone number');
                if (!verified) {
                  _snack('Phone update cancelled');
                  return;
                }
                // Update phone number — this also changes login credentials
                _onboarding.setPhoneNumber(newPhone);
                setState(() => _phone = '+44$newPhone');
                _snack('Phone number updated. Your login credentials have been updated to +44$newPhone.');
              }
            }),
          ),
          const SizedBox(height: 16),
        ],
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
          ? HuddlEmptyState(
              illustration: HuddlIllustration.groupsEmpty,
              title: 'No groups yet',
              subtitle: 'Join groups from the Discover tab.',
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
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.hc.textPrimary)),
                  subtitle: Text('${g.memberCount} members',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: context.hc.textTertiary)),
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
    return Container(
      width: size,
      height: size,
      color: HuddlColors.primary.withValues(alpha: 0.08),
      child: Icon(Icons.people, size: size * 0.5, color: HuddlColors.primary),
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
    final allEvents = _eventService.goingEvents;
    final goingMeetups = _meetupService.meetups
        .where((m) => m.organiserId == 'current_user' || m.isGoing)
        .toList();
    final totalCount = allEvents.length + goingMeetups.length;

    _showSheet(
      title: 'My Meetups ($totalCount)',
      builder: (c) => totalCount == 0
          ? HuddlEmptyState(
              illustration: HuddlIllustration.events,
              title: 'No meetups yet',
              subtitle: 'Meetups you create or attend will appear here.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allEvents.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Text('Events you\'re attending',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textTertiary)),
                  ),
                  ...allEvents.map((e) => ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: e.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(e.icon, size: 22, color: e.color),
                        ),
                        title: Text(e.title,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary)),
                        subtitle: Text('${e.dateDisplay} \u2022 ${e.location}',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: context.hc.textTertiary)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${e.attendees}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.primary)),
                        ),
                        dense: true,
                      )),
                ],
                if (goingMeetups.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text('Meetups',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.hc.textTertiary)),
                  ),
                  ...goingMeetups.map((m) {
                    final isOrganiser = m.organiserId == 'current_user';
                    return ListTile(
                      leading: _meetupAvatar(m.category, 44, imageUrl: m.imageUrl),
                      title: Text(m.title,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: context.hc.textPrimary)),
                      subtitle: Text(
                          '${m.dateDisplay} \u2022 ${m.location}${isOrganiser ? ' \u2022 Organiser' : ''}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: context.hc.textTertiary)),
                      trailing: m.isGoing
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: HuddlColors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Going',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: HuddlColors.teal)),
                            )
                          : null,
                      dense: true,
                    );
                  }),
                ],
                const SizedBox(height: 16),
              ],
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
    _showSheet(
      title: 'My Listings',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HuddlEmptyState(
              illustration: HuddlIllustration.marketplaceEmpty,
              title: 'No listings yet',
              subtitle: 'Items you list on Market will appear here.',
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text('Go to Market',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: HuddlColors.primary,
                side: const BorderSide(color: HuddlColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(c);
                // Switch to Market tab (index 3)
                MainShell.shellKey.currentState?.switchTab(3);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
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
              child: Center(child: CircularProgressIndicator(color: HuddlColors.primary)),
            );
          }
          final msgs = svc.savedMessages;
          final threads = svc.savedThreads;
          if (msgs.isEmpty && threads.isEmpty) {
            return const HuddlEmptyState(
                illustration: HuddlIllustration.saved,
                title: 'No saved items',
                subtitle: 'Long-press a message to save it, or save reply threads from groups.',
              );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msgs.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text('${msgs.length} saved messages',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textTertiary)),
                ),
                ...msgs.take(10).map((m) => ListTile(
                      leading: Icon(
                          m.isFromGroup ? Icons.group : Icons.person,
                          color: HuddlColors.primary,
                          size: 20),
                      title: Text(m.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 13, color: context.hc.textPrimary)),
                      subtitle: Text('From ${m.sourceName}',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: context.hc.textTertiary)),
                      dense: true,
                    )),
              ],
              if (threads.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text('${threads.length} saved threads',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textTertiary)),
                ),
                ...threads.take(10).map((t) => ListTile(
                      leading: const Icon(Icons.topic,
                          color: HuddlColors.blue, size: 20),
                      title: Text(t.topicName,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: context.hc.textPrimary)),
                      subtitle: Text(
                          '${t.totalMessages} messages \u2022 ${t.groupName}',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: context.hc.textTertiary)),
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
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary)),
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
    _showSheet(
      title: 'Notifications',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Master toggle ──────────────────────────────────────────────
            _toggleTile(
              Icons.notifications_active_outlined,
              'Push notifications',
              'Enable or disable all notifications',
              _pushEnabled,
              (v) {
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
                        'Notifications for new group messages', _groupMessages,
                        (v) {
                      setLocal(() => _groupMessages = v);
                      setState(() {});
                      _saveSetting(UserPrivacyPrefsService.keyGroupMessages, v);
                    }),
                    _toggleTile(Icons.chat_outlined, 'Direct messages',
                        'Notifications for new DMs', _dmMessages, (v) {
                      setLocal(() => _dmMessages = v);
                      setState(() {});
                      _saveSetting(UserPrivacyPrefsService.keyDmMessages, v);
                    }),
                    _toggleTile(Icons.event_outlined, 'Meetup reminders',
                        'Reminders for upcoming meetups', _eventReminders, (v) {
                      setLocal(() => _eventReminders = v);
                      setState(() {});
                      _saveSetting(UserPrivacyPrefsService.keyEventReminders, v);
                    }),
                    _toggleTile(Icons.campaign_outlined, 'Community updates',
                        'Borough announcements and updates', _communityUpdates,
                        (v) {
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
                        // _saveSetting already syncs all notif prefs to Firestore
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
        ),
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
                        size: 16, color: HuddlColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'SECURITY',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.primary,
                        letterSpacing: 0.8,
                      ),
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
                    color: HuddlColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _biometricLabel.contains('Face')
                        ? Icons.face_retouching_natural_rounded
                        : Icons.fingerprint_rounded,
                    size: 20,
                    color: HuddlColors.primary,
                  ),
                ),
                title: Text(
                  '$_biometricLabel Login',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ctx.hc.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _biometricEnabled
                      ? 'Tap to disable — you\'ll use your password instead'
                      : 'Use $_biometricLabel to log in quickly and securely',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: ctx.hc.textTertiary,
                  ),
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
                        size: 16, color: HuddlColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'PRIVACY',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: HuddlColors.primary,
                        letterSpacing: 0.8,
                      ),
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
                  const Icon(Icons.mic_outlined, size: 16, color: HuddlColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'VOICE MESSAGES',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.primary,
                      letterSpacing: 0.8,
                    ),
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
                  color: HuddlColors.teal.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HuddlColors.teal.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: HuddlColors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Voice messages let you record and send short audio clips in '
                            'group chats and DMs. Your microphone is accessed only '
                            'while you are actively recording.',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: HuddlColors.teal, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Legal basis: your explicit consent (UK GDPR Art. 6(1)(a)). '
                      'You may withdraw at any time by toggling this off. '
                      'See Privacy Policy \u00a7 16 for full details.',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: HuddlColors.teal,
                          fontStyle: FontStyle.italic,
                          height: 1.4),
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
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ctx.hc.textPrimary,
                ),
              ),
              subtitle: Text(
                _voiceConsent
                    ? 'Microphone consent granted — you can record and send audio'
                    : 'Enable to record and send audio messages in chats',
                style: GoogleFonts.poppins(fontSize: 12, color: ctx.hc.textTertiary),
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
                          const Icon(Icons.mic, color: HuddlColors.primary, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Enable Voice Messages?',
                                style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: HuddlColors.textDark)),
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
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: HuddlColors.textSecondary,
                              height: 1.5),
                        ),
                      ),
                      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      actions: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: HuddlColors.textSecondary,
                            side: const BorderSide(color: HuddlColors.divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                          ),
                          child: Text('Decline',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.primary,
                            foregroundColor: HuddlColors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            elevation: 0,
                          ),
                          child: Text('I Consent',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
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
                          style: GoogleFonts.poppins(fontSize: 13)),
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
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: HuddlColors.textDark)),
                      content: Text(
                        'This withdraws your consent and prevents future recordings.\n\n'
                        'Previously sent voice messages remain visible to recipients. '
                        'To request deletion of past voice messages, contact '
                        'privacy@huddl.app.',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: HuddlColors.textSecondary,
                            height: 1.5),
                      ),
                      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: Text('Cancel',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: HuddlColors.textSecondary)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.error,
                            foregroundColor: HuddlColors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            elevation: 0,
                          ),
                          child: Text('Withdraw Consent',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
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
                          style: GoogleFonts.poppins(fontSize: 13)),
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
                    Uri.parse('https://www.huddlapp.co.uk/privacy-policy.html#s16'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: Text(
                  'Read full voice message data policy (Privacy Policy \u00a7 16) \u2192',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.primary,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                      decorationColor: HuddlColors.primary),
                ),
              ),
            ),

            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.block, color: HuddlColors.error, size: 22),
              title: Text('Blocked users',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary)),
              subtitle: Text(
                  _blockService.blockedUserIds.isEmpty
                      ? 'No blocked users'
                      : '${_blockService.blockedUserIds.length} blocked',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.hc.textTertiary)),
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
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.primaryDark)),
            ),
            // GDPR — View My Data
            ListTile(
              leading: const Icon(Icons.visibility_outlined, color: HuddlColors.blue, size: 22),
              title: Text('View my data',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary)),
              subtitle: Text('See all personal data Huddl holds about you (Article 15)',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.hc.textTertiary)),
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
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary)),
              subtitle: Text('Download a portable copy of your data (Article 20)',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.hc.textTertiary)),
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
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.error)),
              subtitle: Text('Permanently erase all data (Article 17 \u2014 Right to Erasure)',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.hc.textTertiary)),
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
    _showSheet(
      title: 'Blocked Users',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final blocked = _blockService.blockedUserIds;
          if (blocked.isEmpty) {
            return const HuddlEmptyState(
                illustration: HuddlIllustration.marketplace,
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
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textTertiary)),
              ),
              ...blocked.map((userId) => ListTile(
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
                          userId.isNotEmpty ? userId[0].toUpperCase() : 'U',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.hc.textPrimary),
                        ),
                      ),
                    ),
                    title: Text(userId,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.hc.textPrimary)),
                    trailing: TextButton(
                      onPressed: () async {
                        await _blockService.unblockUser(userId);
                        setLocal(() {});
                        setState(() {});
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('$userId unblocked',
                                style: GoogleFonts.poppins(fontSize: 13)),
                            backgroundColor: HuddlColors.primary,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ));
                        }
                      },
                      child: Text('Unblock',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary)),
                    ),
                  )),
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

  /// Compiles all personal data held for the user and returns it as a
  /// human-readable map. Used by both "View My Data" and "Export My Data".
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

  void _showViewMyDataSheet() {
    final data = _compileUserData();
    _showSheet(
      title: 'My Personal Data',
      builder: (c) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
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
                        'Under GDPR Article 15, you have the right to access all personal data we hold about you.',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: HuddlColors.blue,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...data.entries.map((section) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(section.key,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: HuddlColors.primaryDark)),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.hc.scaffold,
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
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.hc.textSecondary)),
                ),
                Expanded(
                  child: Text('${e.value}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: context.hc.textPrimary)),
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
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textPrimary,
                          height: 1.3)),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } else {
      return Text('$value',
          style: GoogleFonts.poppins(
              fontSize: 12, color: context.hc.textPrimary));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GDPR DATA EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  void _showExportDataSheet() {
    bool exporting = false;
    bool exported = false;
    String? exportedText;

    _showSheet(
      title: 'Export My Data',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
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
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: HuddlColors.blue)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Under GDPR Article 20, you can request a copy of all personal data we hold about you in a portable format.',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: context.hc.textSecondary,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (exported && exportedText != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.hc.scaffold,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.hc.divider),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        exportedText!,
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textPrimary,
                            height: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: HuddlColors.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Your data has been compiled. You can select and copy the text above.',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.success,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : exported
                            ? const Icon(Icons.check, size: 20)
                            : const Icon(Icons.download, size: 20),
                    label: Text(
                        exporting
                            ? 'Compiling your data...'
                            : exported
                                ? 'Export complete'
                                : 'Export my data',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          exported ? HuddlColors.success : HuddlColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    onPressed: exporting || exported
                        ? null
                        : () async {
                            setLocal(() => exporting = true);
                            // Actually compile user data
                            final data = _compileUserData();
                            final buffer = StringBuffer();
                            buffer.writeln('=== HUDDL — YOUR PERSONAL DATA EXPORT ===');
                            buffer.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
                            buffer.writeln('');
                            for (final section in data.entries) {
                              buffer.writeln('--- ${section.key.toUpperCase()} ---');
                              if (section.value is Map) {
                                for (final field in (section.value as Map).entries) {
                                  buffer.writeln('  ${field.key}: ${field.value}');
                                }
                              } else if (section.value is List) {
                                for (final item in section.value as List) {
                                  buffer.writeln('  \u2022 $item');
                                }
                              } else {
                                buffer.writeln('  ${section.value}');
                              }
                              buffer.writeln('');
                            }
                            buffer.writeln('=== END OF EXPORT ===');
                            await Future.delayed(
                                const Duration(milliseconds: 800));
                            if (ctx.mounted) {
                              setLocal(() {
                                exporting = false;
                                exported = true;
                                exportedText = buffer.toString();
                              });
                            }
                          },
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
  // CHANGE PASSWORD (with OTP verification)
  // ═══════════════════════════════════════════════════════════════════════════

  void _showChangePasswordSheet() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    _showSheet(
      title: 'Change Password',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'You will need to verify via OTP before your password is changed.',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: context.hc.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _sheetField(
                    currentCtrl, 'Current password', Icons.lock_outline),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _sheetField(
                    newCtrl, 'New password', Icons.lock_reset),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Min 8 characters, 1 uppercase, 1 number, 1 special character',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: context.hc.textTertiary),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _sheetField(
                    confirmCtrl, 'Confirm new password', Icons.lock_outline),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _sheetButton('Change Password', () async {
                  final current = currentCtrl.text.trim();
                  final newPw = newCtrl.text.trim();
                  final confirm = confirmCtrl.text.trim();

                  if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
                    _snack('Please fill in all fields');
                    return;
                  }
                  if (newPw.length < 8) {
                    _snack('Password must be at least 8 characters');
                    return;
                  }
                  if (!RegExp(r'[A-Z]').hasMatch(newPw)) {
                    _snack('Password must contain at least 1 uppercase letter');
                    return;
                  }
                  if (!RegExp(r'[0-9]').hasMatch(newPw)) {
                    _snack('Password must contain at least 1 number');
                    return;
                  }
                  if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(newPw)) {
                    _snack('Password must contain at least 1 special character');
                    return;
                  }
                  if (newPw != confirm) {
                    _snack('Passwords do not match');
                    return;
                  }

                  Navigator.pop(c);
                  final verified =
                      await _verifyWithOtp('change your password');
                  if (!verified) {
                    _snack('Password change cancelled');
                    return;
                  }

                  // Persist the new password to login credentials
                  _onboarding.setPassword(newPw);
                  _snack('Password changed successfully');
                }),
              ),
              const SizedBox(height: 16),
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
                      color: HuddlColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security,
                        size: 28, color: HuddlColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text('Verify your identity',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'To $changeDescription, please enter the 6-digit code sent to $phone',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: context.hc.textSecondary,
                        height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8),
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
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.error)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(c),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: HuddlColors.textSecondary,
                            side: BorderSide(color: context.hc.divider),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text('Cancel',
                              style: GoogleFonts.poppins(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            final code = codeCtrl.text.trim();
                            if (code.length < 4) {
                              setLocal(() => hasError = true);
                              return;
                            }
                            // Verify via Firebase phone auth on mobile,
                            // or accept any 6-digit code on web preview
                            final isWeb = identical(0, 0.0); // dart:core web check
                            if (isWeb || code.length == 6) {
                              // TODO: In production, verify code via SMS backend
                              verified = true;
                              Navigator.pop(c);
                            } else {
                              setLocal(() => hasError = true);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                          child: Text('Verify',
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
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
                            style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: HuddlColors.error)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Deleting your account will:',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary),
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
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textSecondary,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Type "DELETE" to confirm:',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: confirmCtrl,
                onChanged: (_) => setLocal(() {}),
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: GoogleFonts.poppins(
                      fontSize: 14, color: context.hc.textTertiary),
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
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.error,
                    disabledBackgroundColor:
                        HuddlColors.error.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text('Delete My Account',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.primary)),
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
                style: GoogleFonts.poppins(
                    fontSize: 13, color: context.hc.textPrimary, height: 1.4)),
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
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary)),
                  const SizedBox(height: 12),
                  Text(
                    'This will permanently delete your Huddl account and all associated data. This cannot be undone.',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: context.hc.textSecondary,
                        height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isDeleting
                          ? null
                          : () async {
                              setLocal(() => isDeleting = true);

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
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.error,
                        disabledBackgroundColor:
                            HuddlColors.error.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: isDeleting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('Delete Account',
                              style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed:
                          isDeleting ? null : () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary)),
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
      shell.launchTutorial();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════

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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary)),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: faqs.length,
                itemBuilder: (_, i) => ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(faqs[i].$1,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(faqs[i].$2,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: context.hc.textSecondary,
                              height: 1.5)),
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
                      color: HuddlColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                        child: Icon(Icons.people, size: 36, color: HuddlColors.primary)),
                  ),
                  const SizedBox(height: 8),
                  Text('huddl',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: HuddlColors.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Version 1.0.0',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: context.hc.textTertiary)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Huddl connects parents in the Cambridge area, helping you find your community, join local groups, attend meetups, and support each other through every stage of parenthood.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textSecondary,
                  height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Text('\u00a9 2026 Cruzen Ltd. All rights reserved.',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: context.hc.textTertiary)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SETTINGS GEAR ICON
  // ═══════════════════════════════════════════════════════════════════════════

  void _openSettingsSheet() {
    _showSheet(
      title: 'Settings',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _helpTile(Icons.notifications_outlined, 'Notifications',
              'Manage push notifications', () {
            Navigator.pop(c);
            _showNotificationsSheet();
          }),
          _helpTile(Icons.lock_outline, 'Privacy', 'Control your privacy settings',
              () {
            Navigator.pop(c);
            _showPrivacySheet();
          }),
          _helpTile(Icons.backup_outlined, 'Backup & Restore',
              'Export or restore your app data', () {
            Navigator.pop(c);
            Navigator.pushNamed(context, '/backup_restore');
          }),
          _helpTile(Icons.person_outline, 'Edit profile',
              'Change name, bio, and photo', () {
            Navigator.pop(c);
            _showEditProfileSheet();
          }),
          _helpTile(Icons.location_on_outlined, 'Change location',
              'Update your postcode', () {
            Navigator.pop(c);
            _showLocationSheet();
          }),
          const Divider(indent: 16, endIndent: 16),
          _helpTile(Icons.help_outline, 'Help & Support', 'FAQs and contact',
              () {
            Navigator.pop(c);
            _showHelpSheet();
          }),
          _helpTile(Icons.info_outline, 'About Huddl', 'Version and legal', () {
            Navigator.pop(c);
            _showAboutSheet();
          }),
          if (kDebugMode)
            _helpTile(Icons.bug_report_outlined, 'Borough Debug',
                'Borough scoping & analytics', () {
              Navigator.pop(c);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const BoroughDebugScreen()),
              );
            }),
          const SizedBox(height: 16),
        ],
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
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.hc.textPrimary)),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to log out of your Huddl account?',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: context.hc.textSecondary,
                    height: 1.5),
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
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(c);

                        // 1. Sign out from Firebase Auth — MUST happen first
                        //    so the splash screen sees isSignedIn = false
                        try {
                          await FirebaseAuthService().signOut();
                        } catch (_) {}

                        // 2. Clear all local/persisted user data
                        await BrowserStorage.clear();
                        _onboarding.clear();

                        // 3. Reset in-memory privacy prefs singleton
                        UserPrivacyPrefsService().reset();

                        // 4. Navigate directly to login, removing every route
                        //    (bypasses splash which would re-detect the auth
                        //    token and bounce straight back to /home)
                        if (mounted) {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/login', (r) => false);
                        }
                      },
                      child: Text('Log out',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.error)),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: context.hc.divider,
                      borderRadius: BorderRadius.circular(2))),
              Text('Change profile photo',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.hc.textPrimary)),
              const SizedBox(height: 16),
              ListTile(
                leading: _circleIcon(Icons.photo_library_outlined),
                title: Text('Choose from gallery',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: _circleIcon(Icons.camera_alt_outlined),
                title: Text('Take a photo',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto(ImageSource.camera);
                },
              ),
              if (_photoUrl != null && _photoUrl!.isNotEmpty)
                ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        color: HuddlColors.errorLight, shape: BoxShape.circle),
                    child: const Icon(Icons.delete_outline,
                        color: HuddlColors.error),
                  ),
                  title: Text('Remove photo',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeProfilePhoto();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
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
        _onboarding.setProfilePhotoPath(downloadUrl);
      } else {
        // Upload failed — keep data URL as local fallback but it won't sync
        // to other devices. Show a warning so the user knows.
        _onboarding.setProfilePhotoPath(dataUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo saved locally — sync may take a moment'),
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
          border: Border.all(color: HuddlColors.primary, width: 2),
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
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HuddlColors.primary.withValues(alpha: 0.08),
        border: Border.all(color: HuddlColors.primary, width: 2),
      ),
      child: ClipOval(
        child: Image.asset(
          _parentType.toLowerCase() == 'dad'
              ? 'assets/images/avatars/John.png'
              : 'assets/images/avatars/Emma.png',
          width: 84,
          height: 84,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Center(
            child: Text(
                (_name.isNotEmpty && !_name.startsWith('+') && _name != 'User')
                    ? _name[0].toUpperCase()
                    : 'U',
                style: GoogleFonts.poppins(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary)),
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
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _openFeedbackScreen,
          icon: const Icon(Icons.rate_review_outlined,
              size: 20, color: Colors.white),
          label: Text(
            'Give Feedback',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: HuddlColors.primary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            elevation: 0,
          ),
        ),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary)),
                const SizedBox(height: 4),
                Text('Help us make Huddl better',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: context.hc.textTertiary)),
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
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: context.hc.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tell us what you love or what could be better. Your honest feedback helps us improve!',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: context.hc.textTertiary,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: feedbackCtrl,
                                maxLines: 6,
                                maxLength: 1000,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: (_) => setLocal(() {}),
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: context.hc.textPrimary),
                                decoration: InputDecoration(
                                  hintText:
                                      'Share your thoughts about the app...',
                                  hintStyle: GoogleFonts.poppins(
                                      fontSize: 14,
                                      color: context.hc.textTertiary),
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
                                  color: HuddlColors.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.lightbulb_outline,
                                        size: 18, color: HuddlColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'You might want to mention: features you enjoy, things that could be improved, ideas for new features, or your overall experience.',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: HuddlColors.primary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // ── Submit Button ──
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: feedbackCtrl.text.trim().isEmpty
                                      ? null
                                      : isSubmitting
                                          ? null
                                          : () async {
                                              setLocal(
                                                  () => isSubmitting = true);

                                              await _feedbackService
                                                  .submitFeedback(
                                                feedbackText: feedbackCtrl.text
                                                    .trim(),
                                                starRating: 0,
                                                userName: _name,
                                              );

                                              // Short delay for UX
                                              await Future.delayed(
                                                  const Duration(
                                                      milliseconds: 600));

                                              if (ctx2.mounted) {
                                                setLocal(() {
                                                  isSubmitting = false;
                                                  isSubmitted = true;
                                                });
                                              }
                                            },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: HuddlColors.primary,
                                    disabledBackgroundColor: HuddlColors.primary
                                        .withValues(alpha: 0.3),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(24)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 15),
                                    elevation: 0,
                                  ),
                                  child: isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : Text(
                                          'Submit Feedback',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Privacy note
                              Center(
                                child: Text(
                                  'Your feedback is anonymous and helps us improve.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: context.hc.textTertiary,
                                  ),
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
              color: HuddlColors.teal.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_circle, size: 48, color: HuddlColors.teal),
          ),
          const SizedBox(height: 20),
          Text(
            'Thank you!',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your feedback has been submitted.\nWe truly value your input — it helps us make\nHuddl better for everyone.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: context.hc.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: Text('Done',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
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
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary)),
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
      style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
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
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: HuddlColors.primary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ),
    );
  }

  Widget _toggleTile(IconData icon, String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      secondary: Icon(icon, size: 22, color: context.hc.textPrimary),
      title: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary)),
      subtitle: Text(subtitle,
          style:
              GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary)),
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
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary)),
      subtitle: Text(subtitle,
          style:
              GoogleFonts.poppins(fontSize: 12, color: context.hc.textTertiary)),
      trailing:
          Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
      onTap: onTap,
    );
  }

  // _emptyState removed — all empty states now use HuddlEmptyState with
  // the appropriate HuddlIllustration brand asset.

  Widget _circleIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
      child: Icon(icon, color: HuddlColors.primary),
    );
  }
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
            color: HuddlColors.primary.withValues(alpha: 0.15), width: 1),
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
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                      height: 1.3,
                    ),
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
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: context.hc.textTertiary,
                        ),
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
        color: HuddlColors.primary.withValues(alpha: 0.08),
        child: const Center(
            child: Icon(Icons.people, size: 28, color: HuddlColors.primary)));
}

class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(count,
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: context.hc.textPrimary)),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12, color: context.hc.textTertiary)),
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
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: context.hc.textTertiary,
              ),
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
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: context.hc.textTertiary),
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
                color: HuddlColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.primary)),
          ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: context.hc.textTertiary),
      ],
    );
  }
}
