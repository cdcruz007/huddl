import 'dart:convert';
import '../../theme/huddl_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/image_editor_widget.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';
import '../../services/meetup_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../services/invitation_service.dart';
import '../../services/postcode_service.dart';
import '../../services/dm_service.dart';
import '../../services/member_photo_service.dart';
import '../../widgets/huddl_widgets.dart';
import '../../models/group.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_prompt.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/borough_badge.dart';
import '../../widgets/places_autocomplete_field.dart';
import '../../constants/app_text_styles.dart';
import '../../services/huddl_notification_service.dart';
import '../../services/backend_api_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE MEETUP — premium card-based form, Figma-aligned redesign
// Logic, Firebase, Stripe, state management: 100% unchanged.
// Only presentation layer (build / widget helpers) updated.
// ═══════════════════════════════════════════════════════════════════════════════

class CreateMeetupScreen extends StatefulWidget {
  const CreateMeetupScreen({super.key});

  @override
  State<CreateMeetupScreen> createState() => _CreateMeetupScreenState();
}

class _CreateMeetupScreenState extends State<CreateMeetupScreen> {
  // ── Controllers ──
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _scrollController = ScrollController();

  // ── Form state ──
  final Set<String> _selectedCategories = {};
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isFree = false;
  bool _isOnline = false;
  bool _repeatOn = false;
  String _repeatFrequency = 'Every week';
  final String _repeatEndOption = 'no_end';
  DateTime? _repeatEndDate;
  String? _pickedImageUrl;
  bool _isCreating = false;
  int? _maxAttendees;
  final TextEditingController _attendeesCtrl = TextEditingController();

  // ── Participants ──
  final Map<String, bool> _participants = {
    'Mums': false,
    'Dads': false,
    'Aspiring parents': false,
    'Expecting parents': false,
    'Kids': false,
  };
  final _minAgeCtrl = TextEditingController();
  final _maxAgeCtrl = TextEditingController();

  // ── Privacy ──
  String _privacy = 'public';
  String? _selectedGroupId;
  String? _selectedGroupName;
  List<Group> _userGroups = [];

  // ── Private meetup invitees ──
  final Set<String> _selectedMemberIds = {};
  List<BoroughMember> _boroughMembers = [];
  String _memberSearchQuery = '';
  final TextEditingController _memberSearchController = TextEditingController();
  String? _userBorough;

  // ── Categories matching screenshots ──
  static const _categories = [
    {'label': 'Hanging out', 'icon': HuddlIcons.usersThree},
    {'label': 'Pregnancy', 'icon': HuddlIcons.pregnant},
    {'label': 'Playdate', 'icon': HuddlIcons.childCare},
    {'label': 'Sports & exercise', 'icon': HuddlIcons.fitness},
    {'label': 'Coffee & tea', 'icon': HuddlIcons.coffee},
    {'label': 'Parks & Walks', 'icon': HuddlIcons.park},
    {'label': 'Food & nutrition', 'icon': HuddlIcons.restaurant},
    {'label': 'Performance & shows', 'icon': HuddlIcons.theater},
    {'label': 'Other', 'icon': HuddlIcons.moreHoriz},
  ];

  static const _repeatOptions = [
    'Does not repeat',
    'Every day',
    'Every week',
    'Every 2 weeks',
    'Every month',
  ];

  final _meetupService = MeetupService();
  final _onboardingService = OnboardingDataService();
  final _groupService = DefaultGroupService();

  @override
  void initState() {
    super.initState();
    _initServices();
    _loadUserGroups();
    _restoreDraft();
  }

  /// L4: Restore draft from persistent storage
  Future<void> _restoreDraft() async {
    final draftJson = await BrowserStorage.getString('create_meetup_draft_v1');
    if (draftJson == null) return;
    try {
      final d = json.decode(draftJson) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _titleCtrl.text = d['title'] as String? ?? '';
          _descriptionCtrl.text = d['description'] as String? ?? '';
          _locationCtrl.text = d['location'] as String? ?? '';
          _priceCtrl.text = d['price'] as String? ?? '';
          _isFree = d['isFree'] as bool? ?? false;
          _isOnline = d['isOnline'] as bool? ?? false;
          if (d['categories'] is List) {
            _selectedCategories.addAll(
              (d['categories'] as List).cast<String>(),
            );
          }
        });
      }
    } catch (_) {}
  }

  /// L4: Save draft to persistent storage
  Future<void> _saveDraft() async {
    final draftData = {
      'title': _titleCtrl.text,
      'description': _descriptionCtrl.text,
      'location': _locationCtrl.text,
      'price': _priceCtrl.text,
      'isFree': _isFree,
      'isOnline': _isOnline,
      'categories': _selectedCategories.toList(),
    };
    await BrowserStorage.setString('create_meetup_draft_v1', json.encode(draftData));
  }

  /// L4: Clear draft after successful creation
  Future<void> _clearDraft() async {
    await BrowserStorage.remove('create_meetup_draft_v1');
  }

  Future<void> _initServices() async {
    await _onboardingService.initialize();
    final postcode = _onboardingService.postcode;
    final borough = PostcodeService().getBoroughFromPostcode(postcode);
    final members = InvitationService.getBoroughMembers(borough);
    if (mounted) {
      setState(() {
        _userBorough = borough;
        _boroughMembers = members;
      });
    }
  }

  Future<void> _loadUserGroups() async {
    await _groupService.initialize();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final defaultGroups = await _groupService.getUserGroups(uid);
    List<Group> discovered = [];
    try {
      final discoveredJson =
          await BrowserStorage.getString('user_created_groups_v1');
      if (discoveredJson != null) {
        final List<dynamic> decoded = json.decode(discoveredJson);
        discovered = decoded
            .map((e) => Group.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _userGroups = [...defaultGroups, ...discovered]);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _locationCtrl.dispose();
    _priceCtrl.dispose();
    _scrollController.dispose();
    _memberSearchController.dispose();
    _minAgeCtrl.dispose();
    _maxAgeCtrl.dispose();
    _attendeesCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  bool get _isFormValid =>
      _titleCtrl.text.trim().isNotEmpty &&
      (_locationCtrl.text.trim().isNotEmpty || _isOnline) &&
      _selectedDate != null &&
      _startTime != null &&
      _endTime != null &&
      _selectedCategories.isNotEmpty;  // Photo is optional

  // ── Pickers ──────────────────────────────────────────────────────────
  void _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _selectedDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  void _pickStartTime() async {
    final time = await showSimpleTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (time != null) setState(() => _startTime = time);
  }

  void _pickEndTime() async {
    final time = await showSimpleTimePicker(
      context: context,
      initialTime: _endTime ?? const TimeOfDay(hour: 15, minute: 0),
    );
    if (time != null) {
      // Validate: end time must be after start time
      if (_startTime != null) {
        final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
        final endMinutes = time.hour * 60 + time.minute;
        if (endMinutes <= startMinutes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('End time must be after start time'),
              backgroundColor: HuddlColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
          return;
        }
      }
      setState(() => _endTime = time);
    }
  }

  // ── Image picker ──────────────────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final file = await ImageEditorWidget.pickMeetupImage(context);
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        setState(
            () => _pickedImageUrl = 'data:$mimeType;base64,$base64Str');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update image: $e'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  Widget _buildPickedImage() {
    if (_pickedImageUrl != null && _pickedImageUrl!.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(_pickedImageUrl!);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(Uint8List.fromList(bytes),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _photoPlaceholder());
        }
      } catch (_) {}
    }
    return _photoPlaceholder();
  }

  // ── Create ──────────────────────────────────────────────────────────
  Future<void> _createMeetup() async {
    // Free meetups: open to all tiers
    // Paid meetups (price > £0): Plus or above only
    final subService = SubscriptionService();
    await subService.initialize();

    // Gate 1: Free meetup lifetime limit (free tier only)
    if (_isFree && !subService.isPlusOrAbove && !subService.canCreateFreeMeetup) {
      if (mounted) {
        Navigator.pushNamed(context, '/subscription_gate', arguments: {
          'featureTitle': 'Meetup limit reached',
          'featureDescription': subService.limitReachedMessage('free_meetups'),
          'requiredPlan': 'Huddl Plus',
          'featureIcon': HuddlIcons.usersThree.codePoint,
        });
      }
      return;
    }

    if (!_isFree && !subService.canCreatePaidMeetup) {
      if (mounted) {
        await showUpgradePrompt(
          context,
          feature: 'paid meetups',
          message: 'Creating a paid meetup requires Huddl Plus. '
              'Free meetups are available to all members.',
          requiredTier: SubscriptionTier.plus,
        );
      }
      return;
    }
    if (!mounted) return;

    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please fill in all required fields'),
        backgroundColor: HuddlColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    setState(() => _isCreating = true);

    final organiserName = _onboardingService.name ?? 'You';
    final id = 'mu_${DateTime.now().millisecondsSinceEpoch}';

    MeetupRepeat repeat = MeetupRepeat.none;
    if (_repeatOn) {
      if (_repeatFrequency == 'Every day') {
        repeat = MeetupRepeat.daily;
      } else if (_repeatFrequency == 'Every week' ||
          _repeatFrequency == 'Every 2 weeks') {
        repeat = MeetupRepeat.weekly;
      } else if (_repeatFrequency == 'Every month') {
        repeat = MeetupRepeat.monthly;
      }
    }

    MeetupPrivacy privacy = MeetupPrivacy.public;
    if (_privacy == 'group') {
      privacy = MeetupPrivacy.group;
    } else if (_privacy == 'private') {
      privacy = MeetupPrivacy.private_;
    }

    final st = _startTime ?? const TimeOfDay(hour: 10, minute: 0);
    final et = _endTime ?? const TimeOfDay(hour: 15, minute: 0);
    final date =
        _selectedDate ?? DateTime.now().add(const Duration(days: 3));

    // Map selected categories to short codes
    String mappedCategory = _selectedCategories.map((c) {
      switch (c) {
        case 'Coffee & tea': return 'Coffee';
        case 'Playdate': return 'Playdate';
        case 'Sports & exercise': return 'Sport';
        case 'Parks & Walks': return 'Walk';
        case 'Hanging out': return 'Social';
        case 'Pregnancy': return 'Social';
        case 'Food & nutrition': return 'Food';
        case 'Performance & shows': return 'Social';
        case 'Other': return 'Other';
        default: return 'Other';
      }
    }).first;

    const dayAbbr = [
      'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'
    ];
    const monthAbbr = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];

    final meetup = Meetup(
      id: id,
      title: _titleCtrl.text.trim(),
      description: _descriptionCtrl.text.trim().isEmpty
          ? 'Come along! Everyone welcome.'
          : _descriptionCtrl.text.trim(),
      category: mappedCategory,
      dateDisplay:
          '${dayAbbr[date.weekday - 1]}, ${monthAbbr[date.month - 1]} ${date.day}',
      timeDisplay: '${_formatTime(st)} - ${_formatTime(et)}',
      dateTime:
          DateTime(date.year, date.month, date.day, st.hour, st.minute),
      location: _locationCtrl.text.trim(),
      organiserName: organiserName,
      organiserId: FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
      attendeeCount: 1,
      maxAttendees: _maxAttendees,
      isGoing: true,
      isFree: _isFree,
      price: _isFree
          ? null
          : (_priceCtrl.text.isNotEmpty
              ? double.tryParse(
                  _priceCtrl.text.replaceAll('\u00A3', '').trim())
              : null),
      attendeeNames: [organiserName],
      imageUrl: _pickedImageUrl ?? '',
      privacy: privacy,
      repeat: repeat,
      repeatDisplay: _repeatOn ? _repeatFrequency : null,
      repeatEndDate:
          _repeatOn && _repeatEndOption == 'by_date' ? _repeatEndDate : null,
      groupId: _selectedGroupId,
      groupName: _selectedGroupName,
      invitedMemberIds: _privacy == 'private' ? _selectedMemberIds.toList() : [],
      isOnline: _isOnline,
      borough: _userBorough,
      targetAudience: _participants.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList(),
    );

    _meetupService.createMeetup(meetup);

    await _clearDraft();

    // Send messages for group or private meetups
    await _sendMeetupNotifications(meetup, organiserName);

    // Auto-create a meetup group chat under Messages for the creator
    await _createMeetupGroupChat(meetup);

    setState(() => _isCreating = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        const Expanded(child: Text('Meetup created!')),
      ]),
      backgroundColor: HuddlColors.textDark,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    // Record usage for subscription tracking
    subService.recordMeetupCreate();
    // Record free meetup lifetime usage (free tier only)
    if (_isFree && !subService.isPlusOrAbove) {
      await subService.recordFreeMeetupCreated();
    }
    // Navigate to the newly created meetup detail screen
    if (mounted) {
      Navigator.pop(context, meetup);
    }
  }

  /// Auto-create a group chat under Messages tab so the creator (and future
  /// attendees) have a place to discuss the meetup.
  /// Writes to Firestore so all attendees on any device can join the same chat.
  Future<void> _createMeetupGroupChat(Meetup meetup) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final groupKey = 'user_created_groups_v1';
    final meetupGroupId = 'meetup_group_${meetup.id}';

    // Use category fallback image for group chat (base64 too large)
    String chatImage = meetup.imageUrl;
    if (chatImage.startsWith('data:')) {
      chatImage = Meetup.categoryFallbackUrl(meetup.category);
    }

    // ── 1. Write to Firestore (shared, cross-device) ─────────────────────
    if (uid != null) {
      try {
        final groupRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(meetupGroupId);
        final snap = await groupRef.get();
        if (!snap.exists) {
          await groupRef.set({
            'id':           meetupGroupId,
            'name':         meetup.title,
            'description':  'Group chat for "${meetup.title}" on ${meetup.dateDisplay} at ${meetup.location}',
            'imageUrl':     chatImage,
            'category':     'MEETUP',
            'privacy':      'private',
            'creatorUid':   uid,
            'creatorName':  meetup.organiserName,
            'memberIds':    [uid],
            'memberCount':  1,
            'meetupId':     meetup.id,
            'lastMessage':  '${meetup.organiserName} created this meetup chat',
            'lastSenderName': 'System',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'createdAt':    FieldValue.serverTimestamp(),
          });
        } else {
          // Doc exists (e.g. this device already created it) — add self to members
          await groupRef.update({
            'memberIds':    FieldValue.arrayUnion([uid]),
            'memberCount':  FieldValue.increment(1),
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[createMeetupGroupChat] Firestore error: $e');
        // Fall through to local storage so the creator still sees the chat
      }
    }

    // ── 2. Also persist to local BrowserStorage (instant UI on this device) ─
    final existing = await BrowserStorage.getString(groupKey);
    List<dynamic> groups = [];
    if (existing != null) {
      groups = json.decode(existing) as List<dynamic>;
      final alreadyExists =
          groups.any((g) => (g as Map<String, dynamic>)['id'] == meetupGroupId);
      if (alreadyExists) return;
    }

    final newGroup = Group(
      id: meetupGroupId,
      name: meetup.title,
      description:
          'Group chat for "${meetup.title}" on ${meetup.dateDisplay} at ${meetup.location}',
      imageUrl: chatImage,
      memberCount: meetup.attendeeCount,
      category: 'MEETUP',
      isJoined: true,
      isImageLocked: false,
      targetAudience: const [],
      privacy: GroupPrivacy.private_,
      creatorId: meetup.organiserId,
      creatorName: meetup.organiserName,
      creatorBorough: _userBorough,
      lastMessage: '${meetup.organiserName} created this meetup chat',
      lastSenderName: 'System',
      lastMessageTime: DateTime.now(),
    );

    groups.add(newGroup.toJson());
    await BrowserStorage.setString(groupKey, json.encode(groups));
  }

  /// Sends group chat meetup card or DM meetup cards when a group/private meetup is created.
  Future<void> _sendMeetupNotifications(Meetup meetup, String organiserName) async {
    final dmService = DMService();
    await dmService.initialize();

    // Prepare meetup data for the card (serialise the Meetup to JSON)
    final meetupJson = meetup.toJson();
    // Ensure imageUrl is not a data: URI (too large for storage)
    if (meetupJson['imageUrl'] is String &&
        (meetupJson['imageUrl'] as String).startsWith('data:')) {
      meetupJson['imageUrl'] = '';
    }

    if (meetup.privacy == MeetupPrivacy.group && meetup.groupId != null) {
      await BrowserStorage.setString(
        'meetup_notification_${meetup.groupId}',
        json.encode({
          'type': 'meetup_card',
          'meetupId': meetup.id,
          'organiser': organiserName,
          'meetupTitle': meetup.title,
          'timestamp': DateTime.now().toIso8601String(),
          'meetupData': meetupJson,
        }),
      );
    } else if (meetup.privacy == MeetupPrivacy.private_) {
      for (final memberId in meetup.invitedMemberIds) {
        final member = _boroughMembers.firstWhere(
          (m) => m.id == memberId,
          orElse: () => const BoroughMember(
            id: '', name: 'Unknown', parentType: 'mum', stagesOfLife: [],
          ),
        );
        if (member.id.isEmpty) continue;

        await dmService.sendMeetupInvite(
          recipientId: member.id,
          recipientName: member.name,
          meetupId: meetup.id,
          meetupTitle: meetup.title,
          meetupData: meetupJson,
        );
      }
    } else if (meetup.privacy == MeetupPrivacy.public) {
      // ── Public meetup → notify all borough members ──────────────────────
      try {
        final borough = _onboardingService.borough ?? '';
        if (borough.isEmpty) return;

        // Query all borough users who have notifications enabled
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('borough', isEqualTo: borough)
            .where('notificationsEnabled', isEqualTo: true)
            .get();

        final boroughUserIds = snap.docs.map((d) => d.id).toList();

        // In-app Firestore notification to each borough member
        await HuddlNotificationService().newMeetupNearby(
          boroughUserIds: boroughUserIds,
          meetupTitle: meetup.title,
          meetupId: meetup.id,
          meetupDate: meetup.dateDisplay,
          meetupLocation: meetup.location,
          organiserId: meetup.organiserId,
        );

        // FCM push via backend for users with push tokens registered
        await BackendApiService().notifyNewMeetupNearby(
          meetupId: meetup.id,
          meetupTitle: meetup.title,
          meetupDate: meetup.dateDisplay,
          meetupLocation: meetup.location,
          borough: borough,
          organiserId: meetup.organiserId,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[CreateMeetup] newMeetupNearby error: $e');
        // Non-fatal — meetup was saved successfully, notification is best-effort
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // DESIGN TOKENS  (Figma-exact)
  // ─────────────────────────────────────────────────────────────────────
  static const _accentOrange = HuddlColors.primary;        // date/time/location icons + toggle — Figma #FF965C
  static const _accentBlue   = HuddlColors.nearBlack;      // category icons + selected pill fill — nearBlack
  static const _fieldBg      = HuddlColors.neutral50;     // text field fill — Figma #F6F6F6
  static const _fieldLine    = HuddlColors.divider;        // field bottom underline — Figma #D5D5D5
  static const _sectionText  = HuddlColors.textDark;       // section header — Figma #42464C
  static const _hintGray     = HuddlColors.textTertiary;   // placeholder hint text — Figma #949494
  static const _pillBorder   = HuddlColors.divider;        // unselected pill border — Figma #D5D5D5

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.surface,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BoroughGateMessage(featureLabel: 'Meetups'),
                    // Free meetup slot counter — visible to free users only
                    Builder(builder: (context) {
                      final ss = SubscriptionService();
                      if (ss.isPlusOrAbove) return const SizedBox.shrink();
                      final remaining = ss.freeMeetupsCreatedRemaining;
                      final max = ss.limits.maxFreeMeetupsLifetime;
                      final used = ss.freeMeetupsCreatedTotal;
                      return Container(
                        width: double.infinity,
                        color: remaining == 0
                            ? HuddlColors.primary.withValues(alpha: 0.08)
                            : HuddlColors.primary.withValues(alpha: 0.04),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          remaining == 0
                              ? 'Free meetup limit reached — upgrade for unlimited'
                              : 'Free meetup ${used + 1} of $max',
                          style: HuddlText.caption(
                              color: remaining == 0
                                  ? HuddlColors.primary
                                  : HuddlColors.textTertiary),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }),
                    _buildPhotoUpload(),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 22),
                          _sectionHeader('Meetup name'),
                          const SizedBox(height: 6),
                          _buildGrayField(
                            controller: _titleCtrl,
                            hint: 'Meetup name',
                            maxLength: 80,
                            onChanged: (_) { setState(() {}); _saveDraft(); },
                          ),

                          const SizedBox(height: 20),
                          _sectionHeader('Location'),
                          const SizedBox(height: 6),
                          _buildLocationField(),

                          const SizedBox(height: 20),
                          _sectionHeader('Date'),
                          const SizedBox(height: 8),
                          _buildDateBlock(),

                          const SizedBox(height: 20),
                          _buildRepeatRow(),

                          const SizedBox(height: 20),
                          _sectionHeader('Price'),
                          const SizedBox(height: 8),
                          _buildPriceSection(),

                          const SizedBox(height: 20),
                          _sectionHeader('Description'),
                          const SizedBox(height: 6),
                          _buildDescriptionField(),

                          const SizedBox(height: 20),
                          _sectionHeader('Category'),
                          const SizedBox(height: 10),
                          _buildCategoryChips(),

                          const SizedBox(height: 20),
                          _sectionHeader('Participants'),
                          const SizedBox(height: 10),
                          _buildParticipantsList(),

                          const SizedBox(height: 20),
                          _sectionHeader('Max Attendees'),
                          const SizedBox(height: 6),
                          _buildGrayField(
                            controller: _attendeesCtrl,
                            hint: 'No limit',
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() => _maxAttendees = int.tryParse(v)),
                          ),

                          const SizedBox(height: 20),
                          _sectionHeader('Privacy settings'),
                          const SizedBox(height: 10),
                          _buildPrivacySection(),

                          if (_privacy == 'public') _buildPublicInviteRow(),
                          if (_privacy == 'private') ...[
                            const SizedBox(height: 16),
                            _buildInviteMembersWidget(),
                          ],

                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildStickyCreateButton(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // APP BAR
  // ══════════════════════════════════════════════════════════════════════

  bool get _hasUnsavedChanges =>
      _titleCtrl.text.isNotEmpty ||
      _descriptionCtrl.text.isNotEmpty ||
      _locationCtrl.text.isNotEmpty ||
      _pickedImageUrl != null ||
      _selectedDate != null ||
      _startTime != null ||
      _selectedCategories.isNotEmpty;

  void _handleBackNavigation() {
    if (_hasUnsavedChanges) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.hc.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Discard changes?',
            style: HuddlText.heading(),
          ),
          content: Text(
            'Your meetup details will be lost if you go back now.',
            style: HuddlText.body(color: _hintGray),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Keep editing',
                style: HuddlText.body(weight: FontWeight.w600, color: _accentOrange),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: Text(
                'Discard',
                style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.error),
              ),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: GestureDetector(
        onTap: () => _handleBackNavigation(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(HuddlIcons.arrowBack, size: 18, color: _accentOrange),
          ),
        ),
      ),
      centerTitle: true,
      title: Text(
        'Create meetup',
        style: HuddlText.heading(),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: context.hc.divider),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // STICKY CTA
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildStickyCreateButton() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
      child: GestureDetector(
        onTap: _isFormValid && !_isCreating ? _createMeetup : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: _isFormValid
                ? const LinearGradient(
                    colors: [HuddlColors.primaryLight, HuddlColors.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: _isFormValid ? null : HuddlColors.divider,
            borderRadius: BorderRadius.circular(26),
            boxShadow: _isFormValid
                ? [BoxShadow(color: HuddlColors.primary.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Center(
            child: _isCreating
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(
                    'Create meetup',
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // SECTION HEADER — bold dark, matches Figma "Meetup name", "Location" etc.
  // ══════════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: HuddlText.body(weight: FontWeight.w700),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // GRAY FILLED TEXT FIELD — #F6F6F8 bg, bottom underline
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildGrayField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: _fieldBg,
        border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        style: HuddlText.body(color: _sectionText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: HuddlText.body(color: _hintGray),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          counterText: '', // hide character counter to keep clean UI
        ),
        onChanged: onChanged,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // LOCATION FIELD — orange pin icon prefix, online toggle below
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Location input — hidden when Online toggle is ON
        if (!_isOnline) ...[
          Container(
            decoration: const BoxDecoration(
              color: _fieldBg,
              border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Icon(HuddlIcons.locationPin, size: 20, color: _accentOrange),
                ),
                Expanded(
                  child: PlacesAutocompleteField(
                    controller: _locationCtrl,
                    accentColor: _accentOrange,
                    onPlaceSelected: (address) {
                      setState(() {});
                      _saveDraft();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ] else ...[
          // Online label shown instead of address field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _accentOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accentOrange.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(HuddlIcons.wifi, size: 18, color: _accentOrange),
                const SizedBox(width: 10),
                Text(
                  'Online meetup',
                  style: HuddlText.body(color: _accentOrange),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Transform.scale(
              scale: 0.85,
              alignment: Alignment.centerLeft,
              child: CupertinoSwitch(
                value: _isOnline,
                activeTrackColor: _accentOrange,
                onChanged: (v) {
                  setState(() {
                    _isOnline = v;
                    if (v) _locationCtrl.clear(); // clear address when switching to online
                  });
                  _saveDraft();
                },
              ),
            ),
            const SizedBox(width: 6),
            Text('Online meetup', style: HuddlText.body(color: _sectionText)),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DATE BLOCK — Date field (gray box, calendar icon right) +
  //              From / To (gray boxes, clock icon right)
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDateBlock() {
    return Column(
      children: [
        // Date row
        _buildIconRightTapField(
          value: _selectedDate != null ? _formatDate(_selectedDate!) : null,
          hint: 'Date',
          icon: HuddlIcons.calendar,
          onTap: _pickDate,
        ),
        const SizedBox(height: 10),
        // From / To side-by-side
        Row(
          children: [
            Expanded(
              child: _buildIconRightTapField(
                value: _startTime != null ? _formatTime(_startTime!) : null,
                hint: 'From',
                icon: HuddlIcons.clock,
                onTap: _pickStartTime,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildIconRightTapField(
                value: _endTime != null ? _formatTime(_endTime!) : null,
                hint: 'To',
                icon: HuddlIcons.clock,
                onTap: _pickEndTime,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Gray-background tappable field with icon on the RIGHT (Figma style)
  Widget _buildIconRightTapField({
    required String? value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
          color: _fieldBg,
          border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                hasValue ? value : hint,
                style: HuddlText.body(color: hasValue ? _sectionText : _hintGray),
              ),
            ),
            Icon(icon, size: 18, color: _accentOrange),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // REPEAT — label + toggle on same row; Frequency DROPDOWN below when on
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildRepeatRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Repeat', style: HuddlText.body(weight: FontWeight.w700, color: _sectionText)),
            Transform.scale(
              scale: 0.85,
              child: CupertinoSwitch(
                value: _repeatOn,
                activeTrackColor: _accentOrange,
                onChanged: (v) => setState(() {
                  _repeatOn = v;
                  if (!v) _repeatFrequency = 'Every week';
                }),
              ),
            ),
          ],
        ),

        // Frequency dropdown — shows below when repeat is ON
        if (_repeatOn) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: const BoxDecoration(
              color: _fieldBg,
              border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _repeatFrequency,
                isExpanded: true,
                hint: Text('Frequency', style: HuddlText.body(color: _hintGray)),
                icon: Icon(HuddlIcons.caretDown, color: _sectionText.withValues(alpha: 0.6)),
                style: HuddlText.body(color: _sectionText),
                items: _repeatOptions
                    .where((o) => o != 'Does not repeat')
                    .map((o) => DropdownMenuItem(
                          value: o,
                          child: Text(o, style: HuddlText.body(color: _sectionText)),
                        ))
                    .toList(),
                onChanged: (v) { if (v != null) setState(() => _repeatFrequency = v); },
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRICE — Free checkbox + price field
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            _isFree = !_isFree;
            if (_isFree) _priceCtrl.clear();
          }),
          child: Row(
            children: [
              _squareCheckbox(_isFree),
              const SizedBox(width: 12),
              Text('Free', style: HuddlText.body(color: _sectionText)),
            ],
          ),
        ),
        if (!_isFree && SubscriptionService().isFree)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text(
                  'Paid meetups require ',
                  style: HuddlText.caption(color: HuddlColors.textHint),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/subscription_plans'),
                  child: Text(
                    'Huddl Plus',
                    style: HuddlText.caption(color: HuddlColors.primary),
                  ),
                ),
              ],
            ),
          ),
        if (!_isFree) ...[
          const SizedBox(height: 10),
          Container(
            decoration: const BoxDecoration(
              color: _fieldBg,
              border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text('£', style: HuddlText.body(color: _sectionText.withValues(alpha: 0.6))),
                ),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    // Disable input for free users who've selected paid —
                    // the hint below explains the gate; they cannot type a price they can't use
                    enabled: !SubscriptionService().isFree,
                    style: HuddlText.body(
                      color: SubscriptionService().isFree
                          ? HuddlColors.textTertiary
                          : _sectionText,
                    ),
                    decoration: InputDecoration(
                      hintText: ' Price',
                      hintStyle: HuddlText.body(color: _hintGray),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => _saveDraft(),
                  ),
                ),
              ],
            ),
          ),
          if (!_isFree)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Parents arrange payment directly between themselves. '
                'Huddl shows the cost but is not involved in any payment.',
                style: HuddlText.caption(color: HuddlColors.textHint),
              ),
            ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DESCRIPTION FIELD — multiline gray box
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDescriptionField() {
    return Container(
      decoration: const BoxDecoration(
        color: _fieldBg,
        border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2)),
      ),
      child: TextField(
        controller: _descriptionCtrl,
        maxLines: 5,
        minLines: 3,
        style: HuddlText.body(color: _sectionText),
        decoration: InputDecoration(
          hintText: 'Meetup description',
          hintStyle: HuddlText.body(color: _hintGray),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
        onChanged: (_) => _saveDraft(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // CATEGORY CHIPS — gray bg + border + blue icon unselected;
  //                  blue fill + white text/icon selected
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildCategoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((cat) {
        final label = cat['label'] as String;
        final icon = cat['icon'] as IconData;
        final selected = _selectedCategories.contains(label);
        return GestureDetector(
          onTap: () => setState(() {
            // Single-select: clear previous selection first
            _selectedCategories.clear();
            if (!selected) {
              _selectedCategories.add(label);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? _accentBlue : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? _accentBlue : _pillBorder,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: selected ? Colors.white : _accentBlue),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: HuddlText.body(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PARTICIPANTS — plain square border checkbox (Figma style)
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildParticipantsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._participants.keys.map((key) {
          final checked = _participants[key]!;
          return GestureDetector(
            onTap: () => setState(() => _participants[key] = !checked),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _squareCheckbox(checked),
                  const SizedBox(width: 14),
                  Text(key, style: HuddlText.body(color: _sectionText)),
                ],
              ),
            ),
          );
        }),
        if (_participants['Kids'] == true) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildGrayField(
                  controller: _minAgeCtrl,
                  hint: 'Min. age',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGrayField(
                  controller: _maxAgeCtrl,
                  hint: 'Max. age',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRIVACY — inline radio buttons with subtitle
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPrivacySection() {
    return Column(
      children: [
        _privacyRadioTile(
          value: 'public',
          icon: HuddlIcons.language,
          title: 'Public',
          subtitle: 'Everyone in your local authority can see and join your event.',
        ),
        _privacyRadioTile(
          value: 'group',
          icon: HuddlIcons.usersThree,
          title: 'Group',
          subtitle: 'Only members of a specific group can see and join your event.',
        ),
        if (_privacy == 'group') ...[
          Padding(
            padding: const EdgeInsets.only(left: 34, bottom: 8),
            child: _buildSheetGroupPicker(
              selectedGroupId: _selectedGroupId,
              onChanged: (id, name) => setState(() { _selectedGroupId = id; _selectedGroupName = name; }),
            ),
          ),
        ],
        _privacyRadioTile(
          value: 'private',
          icon: HuddlIcons.lock,
          title: 'Private',
          subtitle: 'Invite specific friends.',
        ),
      ],
    );
  }

  Widget _privacyRadioTile({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _privacy == value;
    return GestureDetector(
      onTap: () => setState(() {
        _privacy = value;
        if (value != 'group') { _selectedGroupId = null; _selectedGroupName = null; }
        if (value != 'private') _selectedMemberIds.clear();
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio circle
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _accentOrange : _pillBorder,
                    width: selected ? 2 : 1.5,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 9, height: 9,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _accentOrange,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: HuddlText.caption(color: _hintGray),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PUBLIC INVITE ROW
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPublicInviteRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, left: 20, right: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: HuddlColors.neutral50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _pillBorder),
            ),
            child: Text(
              '${_selectedMemberIds.length} invited friend${_selectedMemberIds.length == 1 ? '' : 's'}',
              style: HuddlText.caption(color: _sectionText),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showInviteMembersSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: HuddlColors.nearBlack.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: HuddlColors.nearBlack.withValues(alpha: 0.20)),
              ),
              child: Row(
                children: [
                  const Icon(HuddlIcons.personAdd, size: 14, color: HuddlColors.nearBlack),
                  const SizedBox(width: 6),
                  Text('Invite friends +',
                      style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.nearBlack)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHOTO UPLOAD — flat solid #5B9DFF banner (Figma exact, user-confirmed)
  // ══════════════════════════════════════════════════════════════════════

  Widget _photoPlaceholder() {
    return Container(
      width: double.infinity,
      height: 200,
      color: HuddlColors.neutral50,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            HuddlIcons.photoLibrary,
            color: HuddlColors.neutral300,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text('Tap to add photo',
              style: HuddlText.body(color: HuddlColors.neutral600)),
        ],
      ),
    );
  }

  Widget _buildPhotoUpload() {
    if (_pickedImageUrl != null) {
      return GestureDetector(
        onTap: _pickImage,
        child: SizedBox(
          width: double.infinity,
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPickedImage(),
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(HuddlIcons.edit, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Change photo',
                          style: HuddlText.body(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(onTap: _pickImage, child: _photoPlaceholder());
  }

  // ══════════════════════════════════════════════════════════════════════
  // GROUP PICKER DROPDOWN
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildSheetGroupPicker({
    required String? selectedGroupId,
    required void Function(String? id, String name) onChanged,
  }) {
    if (_userGroups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('No groups found. Join a group first.',
            style: HuddlText.caption(color: _hintGray).copyWith(fontStyle: FontStyle.italic)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: _fieldBg,
        border: Border.all(color: selectedGroupId != null ? _accentBlue : _pillBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedGroupId,
          isExpanded: true,
          hint: Text('Select a group', style: HuddlText.body(color: _hintGray)),
          icon: Icon(HuddlIcons.caretDown, color: selectedGroupId != null ? _accentBlue : _hintGray),
          style: HuddlText.body(color: _sectionText),
          items: _userGroups.map((g) => DropdownMenuItem(
                value: g.id,
                child: Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(color: _accentBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                    child: const Icon(HuddlIcons.usersThree, size: 14, color: _accentBlue),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g.name, overflow: TextOverflow.ellipsis,
                      style: HuddlText.body(color: _sectionText))),
                ]),
              )).toList(),
          onChanged: (v) {
            final group = _userGroups.firstWhere((g) => g.id == v, orElse: () => _userGroups.first);
            onChanged(v, group.name);
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // INVITE MEMBERS WIDGET (private meetups)
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildInviteMembersWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedMemberIds.isNotEmpty) ...[
          Wrap(
            spacing: 6, runSpacing: 6,
            children: _selectedMemberIds.map((id) {
              final member = _boroughMembers.firstWhere(
                (m) => m.id == id,
                orElse: () => const BoroughMember(id: '', name: 'Unknown', parentType: 'mum', stagesOfLife: []),
              );
              final photoUrl = MemberPhotoService.getPhotoByName(member.name);
              return Chip(
                avatar: photoUrl != null
                    ? CircleAvatar(backgroundImage: NetworkImage(photoUrl), radius: 14)
                    : MemberAvatar(name: member.name, size: 28, parentType: member.parentType),
                label: Text(member.name, style: HuddlText.caption()),
                deleteIcon: const Icon(HuddlIcons.close, size: 16),
                onDeleted: () => setState(() => _selectedMemberIds.remove(id)),
                backgroundColor: _accentBlue.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: _accentBlue.withValues(alpha: 0.30)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
        GestureDetector(
          onTap: _showInviteMembersSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _fieldBg,
              border: Border.all(
                color: _selectedMemberIds.isNotEmpty
                    ? _accentBlue.withValues(alpha: 0.4)
                    : _pillBorder,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(HuddlIcons.personAdd, size: 18,
                    color: _selectedMemberIds.isNotEmpty ? _accentBlue : _hintGray),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedMemberIds.isEmpty
                        ? 'Invite friends to this meetup'
                        : '${_selectedMemberIds.length} member${_selectedMemberIds.length == 1 ? '' : 's'} invited',
                    style: HuddlText.body(color: _selectedMemberIds.isNotEmpty ? _sectionText : _hintGray),
                  ),
                ),
                Icon(HuddlIcons.caretRight, size: 18, color: _hintGray),
              ],
            ),
          ),
        ),
        if (_userBorough != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('From $_userBorough',
                style: HuddlText.caption(color: _hintGray).copyWith(fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }

  void _showInviteMembersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (outerCtx) {
        return GestureDetector(
          onTap: () => FocusScope.of(outerCtx).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(outerCtx).bottom),
            child: StatefulBuilder(
              builder: (sheetCtx, setSheetState) {
                final query = _memberSearchQuery.toLowerCase();
                final filtered = query.isEmpty
                    ? _boroughMembers
                    : _boroughMembers.where((m) =>
                        m.name.toLowerCase().contains(query) ||
                        m.parentType.toLowerCase().contains(query)).toList();
                return DraggableScrollableSheet(
                  initialChildSize: 0.75, maxChildSize: 0.9, minChildSize: 0.5, expand: false,
                  builder: (_, scrollCtrl) {
                    return Column(
                      children: [
                        Container(
                          width: 40, height: 4,
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          decoration: BoxDecoration(color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Invite members',
                                  style: HuddlText.heading(color: context.hc.textPrimary)),
                              if (_selectedMemberIds.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(12)),
                                  child: Text('${_selectedMemberIds.length}',
                                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.surface)),
                                ),
                            ],
                          ),
                        ),
                        if (_userBorough != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 16, top: 2, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Members in $_userBorough',
                                  style: HuddlText.caption(color: context.hc.textTertiary)),
                            ),
                          ),
                        if (_selectedMemberIds.isNotEmpty) ...[
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: _selectedMemberIds.map((id) {
                                final m = _boroughMembers.firstWhere(
                                  (b) => b.id == id,
                                  orElse: () => const BoroughMember(id: '', name: '?', parentType: 'mum', stagesOfLife: []),
                                );
                                final photoUrl = MemberPhotoService.getPhotoByName(m.name);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Chip(
                                    avatar: photoUrl != null
                                        ? CircleAvatar(backgroundImage: NetworkImage(photoUrl), radius: 12)
                                        : MemberAvatar(name: m.name, size: 24, parentType: m.parentType),
                                    label: Text(m.name.split(' ').first, style: HuddlText.caption()),
                                    deleteIcon: const Icon(HuddlIcons.close, size: 14),
                                    onDeleted: () { setSheetState(() => _selectedMemberIds.remove(id)); setState(() {}); },
                                    backgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _memberSearchController,
                            onChanged: (v) => setSheetState(() => _memberSearchQuery = v),
                            style: HuddlText.body(),
                            decoration: InputDecoration(
                              hintText: 'Search members...',
                              hintStyle: HuddlText.body(color: context.hc.textTertiary),
                              prefixIcon: Icon(HuddlIcons.search, color: context.hc.textTertiary, size: 20),
                              filled: true, fillColor: context.hc.scaffold,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final member = filtered[i];
                              final isSelected = _selectedMemberIds.contains(member.id);
                              final photoUrl = MemberPhotoService.getPhotoByName(member.name);
                              return ListTile(
                                leading: photoUrl != null
                                    ? Container(
                                        width: 40, height: 40,
                                        decoration: const BoxDecoration(shape: BoxShape.circle),
                                        clipBehavior: Clip.antiAlias,
                                        child: Image.network(photoUrl, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => MemberAvatar(name: member.name, size: 40, parentType: member.parentType)))
                                    : MemberAvatar(name: member.name, size: 40, parentType: member.parentType),
                                title: Text(member.name,
                                    style: HuddlText.body(color: context.hc.textPrimary)),
                                subtitle: Text(member.parentType == 'mum' ? 'Mum' : 'Dad',
                                    style: HuddlText.caption(color: context.hc.textTertiary)),
                                trailing: Icon(
                                  isSelected ? HuddlIcons.checkCircle : HuddlIcons.circle,
                                  color: isSelected ? HuddlColors.primary : HuddlColors.gray300, size: 24,
                                ),
                                onTap: () {
                                  setSheetState(() {
                                    if (isSelected) { _selectedMemberIds.remove(member.id); }
                                    else { _selectedMemberIds.add(member.id); }
                                  });
                                  setState(() {});
                                },
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(sheetCtx).padding.bottom + 12),
                          child: HuddlButton(
                            label: 'Done',
                            onPressed: () { _memberSearchController.clear(); _memberSearchQuery = ''; Navigator.pop(sheetCtx); },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // SQUARE CHECKBOX — orange fill when checked
  // ══════════════════════════════════════════════════════════════════════

  Widget _squareCheckbox(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? _accentOrange : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? _accentOrange : _pillBorder,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(HuddlIcons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}
