import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../../models/group.dart';
import '../main_shell.dart';

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

      // Load events and meetups
      final userEvents = _eventService.events
          .where((e) => e.isUserCreated)
          .toList();
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
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: HuddlColors.background,
        body: Center(
            child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: HuddlColors.background,
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
                  color: HuddlColors.white,
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
                                  color: HuddlColors.textDark)),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined,
                                color: HuddlColors.textDark),
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
                                    color: HuddlColors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 14, color: HuddlColors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_name,
                          style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark)),
                      const SizedBox(height: 4),
                      Text(_borough,
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: HuddlColors.textHint)),
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
                              width: 1, height: 32, color: HuddlColors.divider),
                          _StatItem(
                              count: '${_children.length}',
                              label:
                                  _children.length == 1 ? 'Child' : 'Children'),
                          Container(
                              width: 1, height: 32, color: HuddlColors.divider),
                          _StatItem(
                            count: _parentType == 'mum'
                                ? 'Mum'
                                : _parentType == 'dad'
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

                // ── About me section ─────────────────────────────────────
                if (_bio != null && _bio!.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: HuddlColors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('About me',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textHint)),
                        const SizedBox(height: 8),
                        Text(_bio!,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: HuddlColors.textDark,
                                height: 1.5)),
                      ],
                    ),
                  ),
                if (_bio != null && _bio!.trim().isNotEmpty)
                  const SizedBox(height: 8),

                // ── My groups horizontal list ────────────────────────────
                if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                  Container(
                    color: HuddlColors.white,
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
                                    color: HuddlColors.textHint)),
                            const Spacer(),
                            Text('$_totalGroupCount total',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: HuddlColors.textHint)),
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
                      title: 'My Events',
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
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap: _showHelpSheet,
                    ),
                    _MenuItem(
                      icon: Icons.info_outline,
                      title: 'About Huddl',
                      onTap: _showAboutSheet,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Logout
                Container(
                  color: HuddlColors.white,
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
                          fontSize: 12, color: HuddlColors.textHint)),
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
    final dueDateCtrl = TextEditingController(text: _dueDate ?? '');
    final childrenList = List<Map<String, String>>.from(
        _children.map((c) => Map<String, String>.from(c)));
    final parentTypeValue = ValueNotifier<String>(_parentType);

    _showSheet(
      title: 'Stage of Life',
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // Parent type
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('I am a...',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 10,
                children: ['mum', 'dad'].map((t) {
                  final isSelected = parentTypeValue.value == t;
                  return ChoiceChip(
                    label: Text(t[0].toUpperCase() + t.substring(1)),
                    selected: isSelected,
                    labelStyle: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : HuddlColors.textDark),
                    selectedColor: HuddlColors.primary,
                    backgroundColor: HuddlColors.background,
                    onSelected: (_) {
                      setLocal(() => parentTypeValue.value = t);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(indent: 20, endIndent: 20),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('My journey',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark)),
            ),
            const SizedBox(height: 8),
            ...[
              ('aspiring', 'Trying for a baby', Icons.favorite_outline),
              ('expecting', 'Expecting', Icons.pregnant_woman),
              ('parent', 'Already a parent', Icons.child_care),
            ].map((entry) {
              final isOn = selected.contains(entry.$1);
              return CheckboxListTile(
                value: isOn,
                title: Row(
                  children: [
                    Icon(entry.$3, size: 20, color: HuddlColors.primary),
                    const SizedBox(width: 10),
                    Text(entry.$2,
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: HuddlColors.textDark)),
                  ],
                ),
                activeColor: HuddlColors.primary,
                controlAffinity: ListTileControlAffinity.trailing,
                onChanged: (v) {
                  setLocal(() {
                    if (v == true) {
                      selected.add(entry.$1);
                    } else {
                      selected.remove(entry.$1);
                    }
                  });
                },
              );
            }),
            // Expecting due date
            if (selected.contains('expecting')) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _sheetField(dueDateCtrl, 'Due date (YYYY-MM)', Icons.calendar_today),
              ),
            ],
            // Children
            if (selected.contains('parent')) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('Children',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Add child',
                          style: GoogleFonts.poppins(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: HuddlColors.primary),
                      onPressed: () {
                        setLocal(() {
                          childrenList.add({'name': '', 'birthday': ''});
                        });
                      },
                    ),
                  ],
                ),
              ),
              ...childrenList.asMap().entries.map((e) {
                final i = e.key;
                final nameC = TextEditingController(text: e.value['name'] ?? '');
                final yearC = TextEditingController(text: e.value['birthday'] ?? '');
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameC,
                          onChanged: (v) => childrenList[i]['name'] = v,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Name',
                            hintStyle: GoogleFonts.poppins(
                                fontSize: 14, color: HuddlColors.textHint),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: HuddlColors.divider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: HuddlColors.primary, width: 2)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: yearC,
                          onChanged: (v) => childrenList[i]['birthday'] = v,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Birth year',
                            hintStyle: GoogleFonts.poppins(
                                fontSize: 14, color: HuddlColors.textHint),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide:
                                    const BorderSide(color: HuddlColors.divider)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                    color: HuddlColors.primary, width: 2)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 20, color: HuddlColors.error),
                        onPressed: () {
                          setLocal(() => childrenList.removeAt(i));
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _sheetButton('Save', () {
                _onboarding.setParentType(parentTypeValue.value);
                _onboarding.setStagesOfLife(selected.toList());
                if (dueDateCtrl.text.trim().isNotEmpty) {
                  _onboarding.setDueDate(dueDateCtrl.text.trim());
                }
                _onboarding.setChildren(childrenList
                    .where((c) =>
                        (c['name'] ?? '').isNotEmpty ||
                        (c['birthday'] ?? '').isNotEmpty)
                    .toList());
                setState(() {
                  _parentType = parentTypeValue.value;
                  _stagesOfLife = selected.toList();
                  _dueDate = dueDateCtrl.text.trim().isEmpty
                      ? null
                      : dueDateCtrl.text.trim();
                  _children = childrenList
                      .where((c) =>
                          (c['name'] ?? '').isNotEmpty ||
                          (c['birthday'] ?? '').isNotEmpty)
                      .toList();
                });
                Navigator.pop(c);
                // Recreate default groups for the updated stages
                _groupService.recreateGroupsForStages(
                  userId: 'current_user',
                  stages: selected.toList(),
                  postcode: _postcode,
                );
                _loadProfileData();
                _snack('Stage of life updated — groups refreshed');
              }),
            ),
            const SizedBox(height: 16),
          ],
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
                        'Changing your postcode will update your borough and default groups. This may remove you from current borough groups.',
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
                      fontSize: 14, color: HuddlColors.textSecondary)),
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
                  _snack('We are not in your area yet. Huddl is currently only available in the Cambridge area.');
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

                // Store current as previous for hasChangedBorough
                if (_postcode != null && _postcode != newPc) {
                  _onboarding.setPreviousBorough(_borough);
                }
                _onboarding.setPostcode(newPc);

                setState(() {
                  _postcode = newPc;
                  _borough = newBorough;
                });
                _snack('Location updated to $newBorough');
                // Reload groups for new borough
                _loadProfileData();
              }),
            ),
            const SizedBox(height: 16),
          ],
        ),
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
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: HuddlColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: HuddlColors.divider),
                  ),
                  child: Text('+44',
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textDark)),
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
                          fontSize: 14, color: HuddlColors.textHint),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: HuddlColors.divider)),
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
                _onboarding.setPhoneNumber(newPhone);
                setState(() => _phone = '+44$newPhone');
                _snack('Phone number updated');
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
                  const Divider(height: 1, indent: 72, color: HuddlColors.divider),
              itemBuilder: (_, i) {
                final g = all[i];
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: HuddlColors.peachLight,
                      borderRadius: BorderRadius.circular(12),
                      image: g.imageUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(g.imageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: g.imageUrl.isEmpty
                        ? const Center(
                            child: Icon(Icons.people,
                                size: 22, color: HuddlColors.primary))
                        : null,
                  ),
                  title: Text(g.name,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: HuddlColors.textDark)),
                  subtitle: Text('${g.memberCount} members',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: HuddlColors.textHint)),
                  trailing: const Icon(Icons.chevron_right,
                      color: HuddlColors.textHint),
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
  // ACTIVITY — MY EVENTS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showMyEventsSheet() {
    final allEvents = _eventService.events.where((e) => e.isUserCreated).toList();
    final goingMeetups = _meetupService.meetups
        .where((m) => m.organiserId == 'current_user' || m.isGoing)
        .toList();
    final totalCount = allEvents.length + goingMeetups.length;

    _showSheet(
      title: 'My Events ($totalCount)',
      builder: (c) => totalCount == 0
          ? _emptyState(Icons.event_outlined, 'No events yet',
              'Events you create or RSVP to will appear here.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allEvents.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Text('Events you created',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textHint)),
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
                                color: HuddlColors.textDark)),
                        subtitle: Text('${e.dateDisplay} \u2022 ${e.location}',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: HuddlColors.textHint)),
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
                            color: HuddlColors.textHint)),
                  ),
                  ...goingMeetups.map((m) {
                    final isOrganiser = m.organiserId == 'current_user';
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: HuddlColors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _meetupCategoryIcon(m.category),
                          size: 22,
                          color: HuddlColors.blue,
                        ),
                      ),
                      title: Text(m.title,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.textDark)),
                      subtitle: Text(
                          '${m.dateDisplay} \u2022 ${m.location}${isOrganiser ? ' \u2022 Organiser' : ''}',
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: HuddlColors.textHint)),
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
              'Items you list on Preloved will appear here.'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text('Go to Preloved',
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
                // Switch to Preloved tab (index 3)
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
                          color: HuddlColors.textHint)),
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
                              fontSize: 13, color: HuddlColors.textDark)),
                      subtitle: Text('From ${m.sourceName}',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: HuddlColors.textHint)),
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
                          color: HuddlColors.textHint)),
                ),
                ...threads.take(10).map((t) => ListTile(
                      leading: const Icon(Icons.topic,
                          color: HuddlColors.blue, size: 20),
                      title: Text(t.topicName,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.textDark)),
                      subtitle: Text(
                          '${t.totalMessages} messages \u2022 ${t.groupName}',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: HuddlColors.textHint)),
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
            _toggleTile(Icons.event_outlined, 'Event reminders',
                'Reminders for upcoming events', _eventReminders, (v) {
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
                      color: HuddlColors.textDark)),
              subtitle: Text(
                  _blockService.blockedUserIds.isEmpty
                      ? 'No blocked users'
                      : '${_blockService.blockedUserIds.length} blocked',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textHint)),
              trailing: const Icon(Icons.chevron_right, color: HuddlColors.textHint),
              onTap: () {
                Navigator.pop(c);
                _showBlockedUsersSheet();
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 8),
            // GDPR Data Export
            ListTile(
              leading: const Icon(Icons.download_outlined, color: HuddlColors.blue, size: 22),
              title: Text('Export my data',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark)),
              subtitle: Text('Download a copy of your personal data (GDPR)',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textHint)),
              trailing: const Icon(Icons.chevron_right, color: HuddlColors.textHint),
              onTap: () {
                Navigator.pop(c);
                _showExportDataSheet();
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: HuddlColors.error, size: 22),
              title: Text('Delete account',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.error)),
              subtitle: Text('Permanently delete your account and all data',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: HuddlColors.textHint)),
              trailing: const Icon(Icons.chevron_right, color: HuddlColors.textHint),
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
                        color: HuddlColors.textHint)),
              ),
              ...blocked.map((userId) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: HuddlColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          userId.isNotEmpty ? userId[0].toUpperCase() : 'U',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark),
                        ),
                      ),
                    ),
                    title: Text(userId,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.textDark)),
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
  // GDPR DATA EXPORT
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
                        'Under GDPR, you have the right to request a copy of all personal data we hold about you. This includes:',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: HuddlColors.textSecondary,
                            height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      ...[
                        'Profile information (name, phone, postcode)',
                        'Group memberships and activity',
                        'Messages and saved items',
                        'Events and meetups',
                        'Preferences and settings',
                      ].map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('\u2022 ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: HuddlColors.textSecondary)),
                                Expanded(
                                  child: Text(item,
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: HuddlColors.textSecondary,
                                          height: 1.3)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
                            ? 'Preparing export...'
                            : exported
                                ? 'Export ready!'
                                : 'Request data export',
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
                    onPressed: exporting
                        ? null
                        : () async {
                            setLocal(() => exporting = true);
                            await Future.delayed(
                                const Duration(milliseconds: 1500));
                            if (ctx.mounted) {
                              setLocal(() {
                                exporting = false;
                                exported = true;
                              });
                              _snack(
                                  'Data export prepared. In production, this would be sent to your email.');
                            }
                          },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Your data will be compiled and sent to your registered email within 24 hours.',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                      height: 1.4),
                  textAlign: TextAlign.center,
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
  // OTP VERIFICATION FOR PROFILE CHANGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Shows an OTP verification dialog before applying sensitive profile changes.
  /// Returns true if verified, false if cancelled.
  Future<bool> _verifyWithOtp(String changeDescription) async {
    final phone = _onboarding.fullPhoneNumber ?? '+44 xxxxxxxx';
    final otp = '123456'; // Demo OTP
    final codeCtrl = TextEditingController();
    bool verified = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setLocal) {
          bool hasError = false;
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
                          color: HuddlColors.textDark)),
                  const SizedBox(height: 8),
                  Text(
                    'To $changeDescription, please enter the 6-digit code sent to $phone',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: HuddlColors.textSecondary,
                        height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text('Demo code: $otp',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary)),
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
                            side: const BorderSide(color: HuddlColors.divider),
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
                          color: HuddlColors.textDark),
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
                          color: HuddlColors.textSecondary,
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
                      color: HuddlColors.textDark)),
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
                      fontSize: 14, color: HuddlColors.textHint),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: HuddlColors.divider)),
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
                      ? () {
                          Navigator.pop(c);
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
                    fontSize: 13, color: HuddlColors.textDark, height: 1.4)),
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
                      color: HuddlColors.textDark)),
              const SizedBox(height: 12),
              Text(
                'Your account has been scheduled for deletion. All data will be permanently removed within 90 days.',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textSecondary,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(c);
                    _onboarding.clear();
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/splash', (r) => false);
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
          'Huddl is a community app for parents in the Cambridge area. Connect with local parents, join groups, attend events, and find support.'),
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
      backgroundColor: HuddlColors.white,
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
                    color: HuddlColors.divider,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('FAQs',
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark)),
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
                          color: HuddlColors.textDark)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Text(faqs[i].$2,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: HuddlColors.textSecondary,
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
                    fontSize: 13, color: HuddlColors.textSecondary, height: 1.4)),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          Text('Huddl',
              style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: HuddlColors.textDark)),
          const SizedBox(height: 4),
          Text('Version 1.0.0',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: HuddlColors.textHint)),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Huddl connects parents in the Cambridge area, helping you find your community, join local groups, attend events, and support each other through every stage of parenthood.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: HuddlColors.textSecondary,
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
            trailing: const Icon(Icons.chevron_right, size: 20, color: HuddlColors.textHint),
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
            trailing: const Icon(Icons.chevron_right, size: 20, color: HuddlColors.textHint),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/privacy');
            },
          ),
          const SizedBox(height: 16),
          Text('\u00a9 2025 Huddl. All rights reserved.',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: HuddlColors.textHint)),
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
                      color: HuddlColors.textDark)),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to log out of your Huddl account?',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: HuddlColors.textSecondary,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Divider(height: 1, color: HuddlColors.divider),
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
                  Container(width: 1, height: 40, color: HuddlColors.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/splash', (r) => false);
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
      backgroundColor: Colors.white,
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
                      color: HuddlColors.divider,
                      borderRadius: BorderRadius.circular(2))),
              Text('Change profile photo',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.textDark)),
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
            backgroundColor: Colors.red.shade400));
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
      child: Center(
        child: Text(_name.isNotEmpty ? _name[0].toUpperCase() : 'U',
            style: GoogleFonts.poppins(
                fontSize: 36,
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary)),
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
      backgroundColor: HuddlColors.white,
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
                    color: HuddlColors.divider,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark)),
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
      style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
        prefixIcon: Icon(icon, size: 20, color: HuddlColors.textHint),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: HuddlColors.divider)),
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
      secondary: Icon(icon, size: 22, color: HuddlColors.textDark),
      title: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: HuddlColors.textDark)),
      subtitle: Text(subtitle,
          style:
              GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
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
      leading: Icon(icon, size: 22, color: HuddlColors.textDark),
      title: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: HuddlColors.textDark)),
      subtitle: Text(subtitle,
          style:
              GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textHint)),
      trailing:
          const Icon(Icons.chevron_right, size: 20, color: HuddlColors.textHint),
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
                  color: HuddlColors.textDark)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(subtitle,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: HuddlColors.textHint),
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
                  fontSize: 10, color: HuddlColors.textSecondary),
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
                color: HuddlColors.textDark)),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12, color: HuddlColors.textHint)),
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
      color: HuddlColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.textHint)),
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
            color: HuddlColors.background,
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: HuddlColors.textDark),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: HuddlColors.textDark)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: HuddlColors.textHint),
              maxLines: 2,
              overflow: TextOverflow.ellipsis)
          : null,
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: HuddlColors.textHint),
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
        const Icon(Icons.chevron_right, color: HuddlColors.textHint),
      ],
    );
  }
}
