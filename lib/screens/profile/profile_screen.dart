import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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

  final ImagePicker _picker = ImagePicker();

  // Notification settings (persisted)
  bool _pushEnabled = true;
  bool _groupMessages = true;
  bool _dmMessages = true;
  bool _eventReminders = true;
  bool _communityUpdates = true;

  // Privacy settings (persisted)
  bool _showOnline = true;
  bool _showProfile = true;
  bool _showGroups = true;
  bool _readReceipts = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadSettings();
    _blockService.initialize();
    _feedbackService.initialize();
    _subscriptionService.initialize();
    _subscriptionService.addListener(_onSubChange);
  }

  void _onSubChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final nPush = await BrowserStorage.getString('pref_push_enabled');
    final nGroup = await BrowserStorage.getString('pref_group_messages');
    final nDM = await BrowserStorage.getString('pref_dm_messages');
    final nEvent = await BrowserStorage.getString('pref_event_reminders');
    final nComm = await BrowserStorage.getString('pref_community_updates');
    final pOnline = await BrowserStorage.getString('pref_show_online');
    final pProfile = await BrowserStorage.getString('pref_show_profile');
    final pGroups = await BrowserStorage.getString('pref_show_groups');
    final pRead = await BrowserStorage.getString('pref_read_receipts');
    if (mounted) {
      setState(() {
        if (nPush != null) _pushEnabled = nPush == 'true';
        if (nGroup != null) _groupMessages = nGroup == 'true';
        if (nDM != null) _dmMessages = nDM == 'true';
        if (nEvent != null) _eventReminders = nEvent == 'true';
        if (nComm != null) _communityUpdates = nComm == 'true';
        if (pOnline != null) _showOnline = pOnline == 'true';
        if (pProfile != null) _showProfile = pProfile == 'true';
        if (pGroups != null) _showGroups = pGroups == 'true';
        if (pRead != null) _readReceipts = pRead == 'true';
      });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    await BrowserStorage.setString(key, value.toString());
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      await _onboarding.initialize();
      await _groupService.initialize();

      String borough = 'Not set';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? 'Unknown';
      }

      final defaultGroups = await _groupService.getUserGroups('current_user');

      final discoveredJson =
          await BrowserStorage.getString('user_created_groups_v1');
      List<Group> discovered = [];
      if (discoveredJson != null) {
        final List<dynamic> decoded = json.decode(discoveredJson);
        discovered = decoded
            .map((e) => Group.fromJson(e as Map<String, dynamic>))
            .toList();
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
    String planLabel = 'Explorer';
    String subtitle = 'Upgrade for unlimited access';

    if (isNeighbourhood) {
      accentColor = HuddlColors.primary;
      icon = Icons.home_outlined;
      planLabel = 'Huddl Neighbourhood';
      subtitle = sub.isTrial
          ? 'Trial \u2022 ${sub.trialDaysRemaining} days left'
          : sub.billingPeriod == BillingPeriod.annual
              ? '\u00A349.99/year'
              : '\u00A35.99/month';
    } else if (isInnerCircle) {
      accentColor = HuddlColors.teal;
      icon = Icons.workspace_premium;
      planLabel = 'Inner Circle';
      subtitle = sub.billingPeriod == BillingPeriod.annual
          ? '\u00A399.99/year'
          : '\u00A311.99/month';
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
                color: isFree
                    ? HuddlColors.peachVeryLight
                    : accentColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isFree
                      ? HuddlColors.primary.withValues(alpha: 0.2)
                      : accentColor.withValues(alpha: 0.2),
                ),
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
                            if (sub.isTrial) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: HuddlColors.accentAmber
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Trial',
                                    style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: HuddlColors.yellowDark)),
                              ),
                            ],
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
                        gradient: HuddlColors.primaryGradient,
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
                // ── Profile header ──────────────────────────────────────
                Container(
                  color: context.hc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('My Profile',
                              style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.textPrimary)),
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
                          Text(_name,
                              style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.textPrimary)),
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
                            color: HuddlColors.peachLight,
                            borderRadius: BorderRadius.circular(12),
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

                // ── My groups horizontal list ────────────────────────────
                if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                  Container(
                    color: context.hc.surface,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('My Groups',
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: context.hc.textTertiary)),
                            const Spacer(),
                            Text('$_totalGroupCount total',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: context.hc.textTertiary)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 90,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ..._userGroups.map((g) => _GroupChip(group: g)),
                              ..._discoveredGroups
                                  .map((g) => _GroupChip(group: g)),
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
                      title: 'Feedback & Rating',
                      subtitle: 'Tell us what you think',
                      onTap: _openFeedbackScreen,
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
                      onTap: () => Navigator.pushNamed(context, '/terms'),
                    ),
                    _MenuItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () => Navigator.pushNamed(context, '/privacy'),
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
    final nameCtrl = TextEditingController(text: _name);
    final bioCtrl = TextEditingController(text: _bio ?? '');

    _showSheet(
      title: 'Edit Profile',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          _sheetField(nameCtrl, 'Name', Icons.person_outline),
          const SizedBox(height: 16),
          _sheetField(bioCtrl, 'About me', Icons.edit_note, maxLines: 4),
          const SizedBox(height: 24),
          _sheetButton('Save Changes', () {
            final newName = nameCtrl.text.trim();
            if (newName.isNotEmpty) {
              _onboarding.setName(newName);
              _onboarding.setBio(bioCtrl.text.trim().isEmpty ? null : bioCtrl.text.trim());
              setState(() {
                _name = newName;
                _bio = bioCtrl.text.trim().isEmpty ? null : bioCtrl.text.trim();
              });
            }
            Navigator.pop(c);
            _snack('Profile updated');
          }),
          const SizedBox(height: 16),
        ],
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
                        : HuddlColors.peachVeryLight,
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
                  color: HuddlColors.peachLight,
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

                if (!_postcodeService.isCambridgePostcode(newPc)) {
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

                final newBorough =
                    _postcodeService.getBoroughFromPostcode(newPc) ?? 'Unknown';

                // Capture current borough BEFORE updating
                final previousBorough = _borough;

                // Store current as previous for hasChangedBorough
                if (_postcode != null && _postcode != newPc) {
                  _onboarding.setPreviousBorough(_borough);
                }
                _onboarding.setPostcode(newPc);

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
                    color: HuddlColors.peachLight,
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
    final phoneCtrl = TextEditingController(
        text: _onboarding.phoneNumber ?? '');

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
              final newPhone = phoneCtrl.text.trim();
              if (newPhone.isNotEmpty) {
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
          ? _emptyState(Icons.people_outline, 'No groups yet',
              'Join groups from the Discover tab.')
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
      color: HuddlColors.peachLight,
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
          ? _emptyState(Icons.event_outlined, 'No meetups yet',
              'Meetups you create or attend will appear here.')
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
                            color: HuddlColors.peachLight,
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
          _emptyState(Icons.storefront_outlined, 'No listings yet',
              'Items you list on Market will appear here.'),
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
            return _emptyState(Icons.bookmark_border, 'No saved items',
                'Long-press a message to save it, or save reply threads from groups.');
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
            _toggleTile(
              Icons.notifications_active_outlined,
              'Push notifications',
              'Enable or disable all notifications',
              _pushEnabled,
              (v) {
                setLocal(() => _pushEnabled = v);
                setState(() {});
                _saveSetting('pref_push_enabled', v);
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _toggleTile(Icons.group_outlined, 'Group messages',
                'Notifications for new group messages', _groupMessages, (v) {
              setLocal(() => _groupMessages = v);
              setState(() {});
              _saveSetting('pref_group_messages', v);
            }),
            _toggleTile(Icons.chat_outlined, 'Direct messages',
                'Notifications for new DMs', _dmMessages, (v) {
              setLocal(() => _dmMessages = v);
              setState(() {});
              _saveSetting('pref_dm_messages', v);
            }),
            _toggleTile(Icons.event_outlined, 'Meetup reminders',
                'Reminders for upcoming meetups', _eventReminders, (v) {
              setLocal(() => _eventReminders = v);
              setState(() {});
              _saveSetting('pref_event_reminders', v);
            }),
            _toggleTile(Icons.campaign_outlined, 'Community updates',
                'Borough announcements and updates', _communityUpdates, (v) {
              setLocal(() => _communityUpdates = v);
              setState(() {});
              _saveSetting('pref_community_updates', v);
            }),
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
      title: 'Privacy',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toggleTile(
                Icons.circle,
                'Show online status',
                'Let others see when you\u2019re online',
                _showOnline, (v) {
              setLocal(() => _showOnline = v);
              setState(() {});
              _saveSetting('pref_show_online', v);
            }),
            _toggleTile(Icons.person_outline, 'Profile visibility',
                'Let others view your profile', _showProfile, (v) {
              setLocal(() => _showProfile = v);
              setState(() {});
              _saveSetting('pref_show_profile', v);
            }),
            _toggleTile(Icons.people_outline, 'Show groups',
                'Let others see which groups you\u2019re in', _showGroups,
                (v) {
              setLocal(() => _showGroups = v);
              setState(() {});
              _saveSetting('pref_show_groups', v);
            }),
            _toggleTile(Icons.done_all, 'Read receipts',
                'Let others see when you\u2019ve read messages', _readReceipts,
                (v) {
              setLocal(() => _readReceipts = v);
              setState(() {});
              _saveSetting('pref_read_receipts', v);
            }),
            const SizedBox(height: 12),
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
            return _emptyState(Icons.block, 'No blocked users',
                'Users you block from groups or DMs will appear here.');
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
      'Blocked Users': _blockService.blockedUserIds.isEmpty
          ? 'None'
          : _blockService.blockedUserIds.toList(),
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
    final otp = '123456'; // Demo OTP
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
                          onPressed: () {
                            if (codeCtrl.text.trim() == otp ||
                                codeCtrl.text.trim() == '123456') {
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
                child: const Icon(Icons.delete_forever,
                    size: 28, color: HuddlColors.error),
              ),
              const SizedBox(height: 18),
              Text('Account deleted',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.hc.textPrimary)),
              const SizedBox(height: 12),
              Text(
                'Your account has been scheduled for deletion. All data will be permanently removed within 90 days.',
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
                  onPressed: () async {
                    Navigator.pop(c);
                    // Clear ALL user data — GDPR-compliant full deletion
                    // 1. Core profile & onboarding data
                    _onboarding.clear();

                    // 2. Groups (default + user-created)
                    _groupService.clear();
                    await BrowserStorage.remove('user_created_groups_v1');

                    // 3. Saved messages & threads
                    final savedService = SavedMessageService();
                    await savedService.clearAll();

                    // 4. Meetups (user-created)
                    await _meetupService.clearAll();

                    // 5. Block list
                    await _blockService.clearAll();

                    // 6. Direct messages & conversations
                    final dmService = DMService();
                    await dmService.clearAll();

                    // 7. Group invitations & joined groups
                    final invitationService = InvitationService();
                    await invitationService.clearAll();

                    // 8. Community feed
                    final feedService = CommunityFeedService();
                    await feedService.clearAll();

                    // 9. Announcements
                    final announcementService = AnnouncementService();
                    await announcementService.clearAll();

                    // 10. Favourites
                    await BrowserStorage.remove('huddl_favourite_ids');

                    // 11. All notification preferences
                    await BrowserStorage.remove('pref_push_enabled');
                    await BrowserStorage.remove('pref_group_messages');
                    await BrowserStorage.remove('pref_dm_messages');
                    await BrowserStorage.remove('pref_event_reminders');
                    await BrowserStorage.remove('pref_community_updates');

                    // 12. All privacy preferences
                    await BrowserStorage.remove('pref_show_online');
                    await BrowserStorage.remove('pref_show_profile');
                    await BrowserStorage.remove('pref_show_groups');
                    await BrowserStorage.remove('pref_read_receipts');
                    if (mounted) {
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/splash', (r) => false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text('OK',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
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
          _helpTile(Icons.email_outlined, 'Contact us',
              'Email us at support@huddl.app', () {
            Navigator.pop(c);
            _snack('Contact: support@huddl.app');
          }),
          _helpTile(Icons.feedback_outlined, 'Send feedback',
              'Help us improve Huddl', () {
            Navigator.pop(c);
            _showFeedbackSheet();
          }),
          _helpTile(Icons.description_outlined, 'Terms of Service',
              'Read our terms', () {
            Navigator.pop(c);
            Navigator.pushNamed(context, '/terms');
          }),
          _helpTile(Icons.privacy_tip_outlined, 'Privacy Policy',
              'Read our privacy policy', () {
            Navigator.pop(c);
            Navigator.pushNamed(context, '/privacy');
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

  void _showFeedbackSheet() {
    final ctrl = TextEditingController();
    _showSheet(
      title: 'Send Feedback',
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
                'We\u2019d love to hear from you! Tell us how we can improve Huddl.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: context.hc.textSecondary, height: 1.4)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _sheetField(ctrl, 'Your feedback', Icons.feedback_outlined,
                maxLines: 5),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _sheetButton('Submit', () {
              Navigator.pop(c);
              _snack('Thank you for your feedback!');
            }),
          ),
          const SizedBox(height: 16),
        ],
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
                      color: HuddlColors.peachLight,
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
          const Divider(indent: 20, endIndent: 20),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.description_outlined, size: 20),
            title: Text('Terms of Service',
                style: GoogleFonts.poppins(fontSize: 14)),
            trailing: Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/terms');
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.privacy_tip_outlined, size: 20),
            title: Text('Privacy Policy',
                style: GoogleFonts.poppins(fontSize: 14)),
            trailing: Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/privacy');
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.map_outlined, size: 20),
            title: Text('User Journey Maps',
                style: GoogleFonts.poppins(fontSize: 14)),
            trailing: Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/journey_maps');
            },
          ),
          const SizedBox(height: 16),
          Text('\u00a9 2025 Huddl. All rights reserved.',
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
                        // Clear all persisted user data on logout
                        await BrowserStorage.clear();
                        _onboarding.clear();
                        if (mounted) {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/splash', (r) => false);
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
      final file = await _picker.pickImage(
          source: source,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
          preferredCameraDevice: CameraDevice.front);
      if (file != null && mounted) {
        _onboarding.setProfilePhotoPath(kIsWeb ? file.name : file.path);
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType =
            file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';
        _onboarding.setProfilePhotoObjectUrl(dataUrl);
        setState(() => _photoUrl = dataUrl);
        if (mounted) _snack('Profile photo updated');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not access photos: $e'),
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
        color: HuddlColors.peachLight,
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
            child: Text(_name.isNotEmpty ? _name[0].toUpperCase() : 'U',
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

  /// Prominent feedback card shown in the profile — includes static 4.8 rating
  Widget _buildFeedbackCard() {
    return Container(
      color: context.hc.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rating display row
          Row(
            children: [
              // Star cluster
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: HuddlColors.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.star_rounded,
                    size: 28, color: HuddlColors.accentAmber),
              ),
              const SizedBox(width: 12),
              // Rating text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_feedbackService.displayRating}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/ 5.0',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.hc.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 5 star icons showing 4.8
                        ...List.generate(5, (i) {
                          if (i < 4) {
                            return const Icon(Icons.star_rounded,
                                size: 16, color: HuddlColors.accentAmber);
                          } else {
                            return Icon(Icons.star_rounded,
                                size: 16,
                                color: HuddlColors.accentAmber
                                    .withValues(alpha: 0.4));
                          }
                        }),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'App Rating',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Feedback CTA button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openFeedbackScreen,
              icon: const Icon(Icons.rate_review_outlined,
                  size: 20, color: Colors.white),
              label: Text(
                'Give Feedback & Rate',
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
        ],
      ),
    );
  }

  /// Opens the full Feedback & Rating screen as a large bottom sheet
  void _openFeedbackScreen() {
    int selectedRating = 0;
    final feedbackCtrl = TextEditingController();
    bool isSubmitting = false;
    bool isSubmitted = false;

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
                Text('Feedback & Rating',
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
                              // ── Star Rating Section ──
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: context.hc.scaffold,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'How would you rate Huddl?',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: context.hc.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // Interactive stars
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: List.generate(5, (i) {
                                          final starIndex = i + 1;
                                          return GestureDetector(
                                            onTap: () {
                                              setLocal(() =>
                                                  selectedRating = starIndex);
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6),
                                              child: AnimatedScale(
                                                scale:
                                                    selectedRating >= starIndex
                                                        ? 1.1
                                                        : 1.0,
                                                duration: const Duration(
                                                    milliseconds: 150),
                                                child: Icon(
                                                  selectedRating >= starIndex
                                                      ? Icons.star_rounded
                                                      : Icons
                                                          .star_outline_rounded,
                                                  size: 44,
                                                  color: selectedRating >=
                                                          starIndex
                                                      ? HuddlColors.accentAmber
                                                      : HuddlColors.gray300,
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                      const SizedBox(height: 8),
                                      if (selectedRating > 0)
                                        Text(
                                          _ratingLabel(selectedRating),
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: HuddlColors.accentAmber,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

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
                                  color: HuddlColors.peachLight,
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
                                  onPressed: (selectedRating == 0 &&
                                          feedbackCtrl.text.trim().isEmpty)
                                      ? null
                                      : isSubmitting
                                          ? null
                                          : () async {
                                              if (selectedRating == 0) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Please select a star rating',
                                                        style:
                                                            GoogleFonts.poppins(
                                                                fontSize: 13)),
                                                    backgroundColor:
                                                        HuddlColors
                                                            .accentAmber,
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        10)),
                                                  ),
                                                );
                                                return;
                                              }

                                              setLocal(
                                                  () => isSubmitting = true);

                                              await _feedbackService
                                                  .submitFeedback(
                                                feedbackText: feedbackCtrl.text
                                                    .trim(),
                                                starRating: selectedRating,
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
            'Your feedback and rating have been submitted.\nWe truly value your input — it helps us make\nHuddl better for everyone.',
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

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Great';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
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
      builder: (_) => DraggableScrollableSheet(
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
    );
  }

  Widget _sheetField(TextEditingController ctrl, String label, IconData icon,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
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
      activeThumbColor: HuddlColors.primary,
      activeTrackColor: HuddlColors.primary.withValues(alpha: 0.4),
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

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: HuddlColors.peachLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 32, color: HuddlColors.primary),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.hc.textPrimary)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(subtitle,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: context.hc.textTertiary),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _circleIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
          color: HuddlColors.peachLight, shape: BoxShape.circle),
      child: Icon(icon, color: HuddlColors.primary),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupChip extends StatelessWidget {
  final Group group;
  const _GroupChip({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: HuddlColors.primary.withValues(alpha: 0.3), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: group.imageUrl.startsWith('assets/')
                ? Image.asset(group.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _iconFallback())
                : _iconFallback(),
          ),
          const SizedBox(height: 4),
          Text(group.name,
              style: GoogleFonts.poppins(
                  fontSize: 10, color: context.hc.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _iconFallback() => Container(
      color: HuddlColors.peachLight,
      child: const Center(
          child: Icon(Icons.people, size: 24, color: HuddlColors.primary)));
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textTertiary)),
          ),
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: context.hc.scaffold,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: context.hc.textPrimary),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
              color: HuddlColors.peachLight,
              borderRadius: BorderRadius.circular(10)),
          child: Text('$count',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: HuddlColors.primary)),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: context.hc.textTertiary),
      ],
    );
  }
}
