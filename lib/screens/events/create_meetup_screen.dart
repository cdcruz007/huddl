import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
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
import '../../services/subscription_service.dart';
import '../../widgets/upgrade_prompt.dart';
import '../../widgets/borough_badge.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE MEETUP — single-page scrollable form matching design screenshots
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
  final _picker = ImagePicker();

  // ── Form state ──
  final Set<String> _selectedCategories = {};
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isFree = false;
  bool _isOnline = false;
  bool _repeatOn = false;
  String _repeatFrequency = 'Every week';
  String _repeatEndOption = 'no_end';
  DateTime? _repeatEndDate;
  DateTime? _endDate;
  bool _showEndDate = false;
  bool _showEndTime = false;
  String? _pickedImageUrl;
  bool _isCreating = false;
  int? _maxAttendees;

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
  String _privacy = '';
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
    {'label': 'Hanging out', 'icon': Icons.people_outline},
    {'label': 'Pregnancy', 'icon': Icons.pregnant_woman},
    {'label': 'Playdate', 'icon': Icons.child_care},
    {'label': 'Sports & exercise', 'icon': Icons.fitness_center},
    {'label': 'Coffee & tea', 'icon': Icons.coffee},
    {'label': 'Parks & Walks', 'icon': Icons.park},
    {'label': 'Food & nutrition', 'icon': Icons.restaurant},
    {'label': 'Performance & shows', 'icon': Icons.theater_comedy},
    {'label': 'Other', 'icon': Icons.more_horiz},
  ];

  static const _repeatOptions = [
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
    final defaultGroups = await _groupService.getUserGroups('current_user');
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
      _locationCtrl.text.trim().isNotEmpty &&
      _selectedDate != null &&
      _startTime != null &&
      _endTime != null &&
      _selectedCategories.isNotEmpty &&
      _pickedImageUrl != null; // Photo is required

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
          colorScheme:
              ColorScheme.light(primary: HuddlColors.primary),
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
    if (time != null) setState(() => _endTime = time);
  }

  void _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _selectedDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: _selectedDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _endDate = date);
  }

  void _pickRepeatEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _repeatEndDate ??
          (_selectedDate ?? DateTime.now()).add(const Duration(days: 30)),
      firstDate: _selectedDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _repeatEndDate = date);
  }

  // ── Image picker ──────────────────────────────────────────────────
  Future<void> _pickImage() async {
    if (kIsWeb) {
      await _pickFrom(ImageSource.gallery);
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Add cover photo',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: HuddlColors.peachLight,
                    shape: BoxShape.circle),
                child: const Icon(Icons.photo_library_outlined,
                    color: HuddlColors.primary),
              ),
              title: const Text('Choose from gallery',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFrom(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: HuddlColors.peachLight,
                    shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_outlined,
                    color: HuddlColors.primary),
              ),
              title: const Text('Take a photo',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFrom(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
          source: source, maxWidth: 1200, maxHeight: 800, imageQuality: 85);
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        setState(
            () => _pickedImageUrl = 'data:$mimeType;base64,$base64Str');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not access photos: $e'),
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
    // ── Subscription gate: meetup creation limit ────────────────────
    final subService = SubscriptionService();
    await subService.initialize();
    if (!subService.canCreateMeetup) {
      if (mounted) {
        showUpgradePrompt(
          context,
          feature: 'meetups',
          message: subService.limitReachedMessage('meetups'),
        );
      }
      return;
    }
    if (!mounted) return;

    if (!_isFormValid) {
      final missingPhoto = _pickedImageUrl == null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(missingPhoto
            ? 'Please add a cover photo for your meetup'
            : 'Please fill in all required fields'),
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
      organiserId: 'current_user',
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
      borough: _userBorough,
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
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text('"${meetup.title}" created — group chat added to Messages')),
      ]),
      backgroundColor: HuddlColors.teal,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    // Record usage for subscription tracking
    subService.recordMeetupCreate();
    Navigator.pop(context, meetup);
  }

  /// Auto-create a group chat under Messages tab so the creator (and future
  /// attendees) have a place to discuss the meetup.
  Future<void> _createMeetupGroupChat(Meetup meetup) async {
    final groupKey = 'user_created_groups_v1';
    final meetupGroupId = 'meetup_group_${meetup.id}';

    // Check if group already exists
    final existing = await BrowserStorage.getString(groupKey);
    List<dynamic> groups = [];
    if (existing != null) {
      groups = json.decode(existing) as List<dynamic>;
      final alreadyExists =
          groups.any((g) => (g as Map<String, dynamic>)['id'] == meetupGroupId);
      if (alreadyExists) return;
    }

    // Use category fallback image for group chat (base64 too large)
    String chatImage = meetup.imageUrl;
    if (chatImage.startsWith('data:')) {
      chatImage = Meetup.categoryFallbackUrl(meetup.category);
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
  /// Instead of sending a text message, this sends the full meetup data so the
  /// chat screens can render a clickable meetup card component.
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
      // For group meetups: store meetup card data so group chat renders a card
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
      // For private meetups: send a meetup card DM to each invited member
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
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.surface,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: context.hc.surface,
        automaticallyImplyLeading: false,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary)),
            ),
          ),
        ),
        leadingWidth: 80,
        centerTitle: true,
        title: Text(
          'Create meetup',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _isFormValid ? _createMeetup : null,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: _isCreating
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _isFormValid
                                ? HuddlColors.textDark
                                : HuddlColors.textHint)),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                  // ─────────── BOROUGH SCOPE NOTE ───────────
                  const BoroughGateMessage(
                    featureLabel: 'Meetups',
                  ),
                  // ─────────── PHOTO UPLOAD ───────────
                  _buildPhotoUpload(),
                  const SizedBox(height: 16),

                  // ─────────── MEETUP NAME ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _sectionLabel('Meetup name'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _underlineTextField(
                      controller: _titleCtrl,
                      hint: 'Meetup name',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ─────────── LOCATION ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionLabel('Location'),
                        Row(
                          children: [
                            Text('Online event',
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: context.hc.textSecondary)),
                            const SizedBox(width: 8),
                            Transform.scale(
                              scale: 0.8,
                              child: CupertinoSwitch(
                                value: _isOnline,
                                onChanged: (v) => setState(() => _isOnline = v),
                                activeTrackColor: HuddlColors.teal,
                                inactiveTrackColor: HuddlColors.disabledBorder,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _underlineTextField(
                      controller: _locationCtrl,
                      hint: _isOnline ? 'Link or platform' : 'Location',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ─────────── DATE / TIME ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _sectionLabel('Date / time'),
                  ),
                  const SizedBox(height: 4),

                  // Start date row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _dateTapField(
                      value: _selectedDate != null
                          ? _formatDate(_selectedDate!)
                          : null,
                      hint: 'Start date',
                      icon: Icons.calendar_today_outlined,
                      onTap: _pickDate,
                    ),
                  ),

                  // Start time row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _dateTapField(
                      value: _startTime != null
                          ? _formatTime(_startTime!)
                          : null,
                      hint: 'Start time',
                      icon: Icons.access_time,
                      onTap: _pickStartTime,
                    ),
                  ),

                  // Add end date (expandable)
                  if (!_showEndDate)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _addRowButton(
                        label: 'Add end date',
                        onTap: () => setState(() => _showEndDate = true),
                      ),
                    ),
                  if (_showEndDate)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _dateTapField(
                        value: _endDate != null
                            ? _formatDate(_endDate!)
                            : null,
                        hint: 'End date',
                        icon: Icons.calendar_today_outlined,
                        onTap: _pickEndDate,
                      ),
                    ),

                  // Add end time (expandable)
                  if (!_showEndTime)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _addRowButton(
                        label: 'Add end time',
                        onTap: () => setState(() => _showEndTime = true),
                      ),
                    ),
                  if (_showEndTime)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _dateTapField(
                        value: _endTime != null
                            ? _formatTime(_endTime!)
                            : null,
                        hint: 'End time',
                        icon: Icons.access_time,
                        onTap: _pickEndTime,
                      ),
                    ),

                  const SizedBox(height: 16),

                  // ─────────── REPEAT TOGGLE ───────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Repeat',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.hc.textPrimary)),
                        Transform.scale(
                          scale: 0.8,
                          child: CupertinoSwitch(
                            value: _repeatOn,
                            onChanged: (v) => setState(() {
                              _repeatOn = v;
                              if (!v) {
                                _repeatEndDate = null;
                                _repeatEndOption = 'no_end';
                              }
                            }),
                            activeTrackColor: HuddlColors.teal,
                            inactiveTrackColor: HuddlColors.disabledBorder,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Repeat expanded section ────────
                  if (_repeatOn) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Frequency'),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                    color: HuddlColors.gray300,
                                    width: 1),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _repeatFrequency,
                                isExpanded: true,
                                icon: Icon(Icons.keyboard_arrow_down,
                                    color: context.hc.textTertiary),
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: context.hc.textPrimary),
                                items: _repeatOptions.map((opt) {
                                  return DropdownMenuItem(
                                    value: opt,
                                    child: Text(opt),
                                  );
                                }).toList(),
                                onChanged: (v) => setState(() =>
                                    _repeatFrequency =
                                        v ?? 'Every week'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionLabel('End'),
                          const SizedBox(height: 10),
                          _radioOption(
                            label: 'No end date',
                            selected: _repeatEndOption == 'no_end',
                            onTap: () => setState(() {
                              _repeatEndOption = 'no_end';
                              _repeatEndDate = null;
                            }),
                          ),
                          const SizedBox(height: 6),
                          _radioOption(
                            label: 'End by a date',
                            selected: _repeatEndOption == 'by_date',
                            onTap: () => setState(() {
                              _repeatEndOption = 'by_date';
                            }),
                          ),
                          if (_repeatEndOption == 'by_date') ...[
                            const SizedBox(height: 10),
                            _dateTapField(
                              value: _repeatEndDate != null
                                  ? _formatDate(_repeatEndDate!)
                                  : null,
                              hint: 'Choose date',
                              icon: Icons.calendar_today_outlined,
                              onTap: _pickRepeatEndDate,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ─────────── PRICE ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _sectionLabel('Price'),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isFree = !_isFree;
                        if (_isFree) _priceCtrl.clear();
                      }),
                      child: Row(
                        children: [
                          _checkbox(_isFree),
                          const SizedBox(width: 10),
                          Text('Free',
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: context.hc.textPrimary)),
                        ],
                      ),
                    ),
                  ),
                  if (!_isFree) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      child: _underlineTextField(
                        controller: _priceCtrl,
                        hint: 'Price',
                        keyboardType: TextInputType.number,
                        prefix: '\u00A3  ',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ─────────── DESCRIPTION ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _sectionLabel('Description'),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: _descriptionCtrl,
                      maxLines: 4,
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. who this meetup is for, what attractions are planned.',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: context.hc.textTertiary,
                            height: 1.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: HuddlColors.gray300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: HuddlColors.gray300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: HuddlColors.primary, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─────────── CATEGORY ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _sectionLabel('Category'),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      children: _categories.map((cat) {
                        final label = cat['label'] as String;
                        final icon = cat['icon'] as IconData;
                        final isSelected = _selectedCategories.contains(label);
                        return _categoryChip(
                          label: label,
                          icon: icon,
                          isSelected: isSelected,
                          onTap: () => setState(() {
                            if (isSelected) {
                              _selectedCategories.remove(label);
                            } else {
                              _selectedCategories.add(label);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ─────────── PARTICIPANTS ───────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _sectionLabel('Participants'),
                  ),
                  const SizedBox(height: 8),
                  ..._participants.keys.map((key) {
                    final isChecked = _participants[key]!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              _participants[key] = !_participants[key]!;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  _checkbox(isChecked),
                                  const SizedBox(width: 10),
                                  Text(key,
                                      style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: context.hc.textPrimary)),
                                ],
                              ),
                            ),
                          ),
                          // Show age range fields when Kids is checked
                          if (key == 'Kids' && isChecked) ...[                            Padding(
                              padding: const EdgeInsets.only(left: 32, right: 0, bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Min. age',
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: context.hc.textTertiary)),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _minAgeCtrl,
                                          keyboardType: TextInputType.number,
                                          style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: context.hc.textPrimary),
                                          decoration: InputDecoration(
                                            hintText: '0',
                                            hintStyle: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: context.hc.textTertiary),
                                            border: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: HuddlColors.gray300),
                                            ),
                                            enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: HuddlColors.gray300),
                                            ),
                                            focusedBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: HuddlColors.primary,
                                                  width: 1.5),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Max. age',
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: context.hc.textTertiary)),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _maxAgeCtrl,
                                          keyboardType: TextInputType.number,
                                          style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: context.hc.textPrimary),
                                          decoration: InputDecoration(
                                            hintText: '17',
                                            hintStyle: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: context.hc.textTertiary),
                                            border: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: HuddlColors.gray300),
                                            ),
                                            enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: HuddlColors.gray300),
                                            ),
                                            focusedBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: HuddlColors.primary,
                                                  width: 1.5),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  // ─────────── NUMBER OF ATTENDEES ───────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _sectionLabel('Number of attendees'),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: HuddlColors.gray300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _maxAttendees != null
                                  ? '$_maxAttendees people'
                                  : 'Max number of people',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: _maxAttendees != null
                                    ? HuddlColors.textDark
                                    : HuddlColors.textHint,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _maxAttendees = (_maxAttendees ?? 0) + 5;
                              });
                            },
                            child: const Icon(Icons.add,
                                color: HuddlColors.primary, size: 22),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ─────────── PRIVACY SETTINGS ───────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _sectionLabel('Privacy settings'),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _privacyRadio(
                          label: 'Public',
                          description:
                              'Everyone in your local community can see and join your meetup.',
                          value: 'public',
                          icon: Icons.public,
                        ),
                        const SizedBox(height: 10),
                        _privacyRadio(
                          label: 'Group',
                          description:
                              'Only members of a specific group can see and join your meetup.',
                          value: 'group',
                          icon: Icons.group,
                        ),
                        if (_privacy == 'group') ...[                          const SizedBox(height: 12),
                          _buildGroupPicker(),
                        ],
                        const SizedBox(height: 10),
                        _privacyRadio(
                          label: 'Private',
                          description:
                              'Invite only — choose specific friends to invite.',
                          value: 'private',
                          icon: Icons.lock_outline,
                        ),
                        if (_privacy == 'private') ...[                          const SizedBox(height: 12),
                          _buildInviteMembersWidget(),
                        ],
                      ],
                    ),
                  ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // COMPONENT WIDGETS
  // ══════════════════════════════════════════════════════════════════════

  /// Photo upload banner — brand orange to match Create Group screen
  Widget _buildPhotoUpload() {
    if (_pickedImageUrl != null) {
      return GestureDetector(
        onTap: _pickImage,
        child: SizedBox(
          width: double.infinity,
          height: 240,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPickedImage(),
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('Change',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 240,
        margin: EdgeInsets.zero,
        decoration: const BoxDecoration(
          color: HuddlColors.peachLight,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.6),
                    width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 28,
                      color: HuddlColors.primary.withValues(alpha: 0.8)),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text('Click to add photo',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: HuddlColors.peachLight,
      child: const Center(
        child:
            Icon(Icons.image_outlined, size: 48, color: HuddlColors.primary),
      ),
    );
  }

  /// Section label — bold dark text matching screenshot
  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: context.hc.textPrimary,
      ),
    );
  }

  /// Underline text field matching screenshot style
  Widget _underlineTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? prefix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) { setState(() {}); _saveDraft(); },
      style:
          GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
            fontSize: 14, color: context.hc.textTertiary),
        prefixText: prefix,
        prefixStyle: GoogleFonts.poppins(
            fontSize: 14, color: context.hc.textPrimary),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: HuddlColors.gray300),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: HuddlColors.gray300),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide:
              BorderSide(color: HuddlColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      ),
    );
  }

  /// Tappable date/time field with underline and plain icon (matching target)
  Widget _dateTapField({
    String? value,
    required String hint,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // Calendar icons orange, clock icons gray — matching target design
    final Color iconColor = icon == Icons.calendar_today_outlined
        ? HuddlColors.primary
        : HuddlColors.textHint;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: HuddlColors.gray300),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: value != null
                      ? HuddlColors.textDark
                      : HuddlColors.textHint,
                ),
              ),
            ),
            Icon(icon, size: 20, color: iconColor),
          ],
        ),
      ),
    );
  }

  /// "Add end date" / "Add end time" button row (orange + icon)
  Widget _addRowButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: HuddlColors.gray300),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textTertiary,
                ),
              ),
            ),
            const Icon(Icons.add, size: 20, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }

  /// Category chip matching original target design — outlined only, never filled
  Widget _categoryChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    // Use amber accent for food/nutrition category per style guide
    final isYellowCategory = label == 'Food & nutrition';
    final chipColor = isYellowCategory ? HuddlColors.accentAmber : HuddlColors.blue;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : HuddlColors.gray300,
            width: isSelected ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? chipColor : context.hc.textTertiary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? chipColor : HuddlColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Custom checkbox — orange when checked, matching screenshot
  Widget _checkbox(bool checked) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? HuddlColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: checked ? HuddlColors.primary : HuddlColors.gray300,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  /// Radio option
  Widget _radioOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? HuddlColors.primary
                    : HuddlColors.gray300,
                width: 2,
              ),
            ),
            child: selected
                ? Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: HuddlColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textPrimary)),
        ],
      ),
    );
  }

  /// Group picker — shown when privacy = 'group'
  Widget _buildGroupPicker() {
    if (_userGroups.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(left: 32),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.peachLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 16, color: HuddlColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You don\'t belong to any groups yet. Join a group first to create group meetups.',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: HuddlColors.primary,
                    height: 1.3),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 32),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: _selectedGroupId != null
              ? HuddlColors.primary
              : HuddlColors.gray300,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGroupId,
          isExpanded: true,
          hint: Text('Select a group',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: context.hc.textTertiary)),
          icon: Icon(Icons.keyboard_arrow_down,
              color: _selectedGroupId != null
                  ? HuddlColors.primary
                  : HuddlColors.textHint),
          style:
              GoogleFonts.poppins(fontSize: 13, color: context.hc.textPrimary),
          items: _userGroups.map((g) {
            return DropdownMenuItem(
              value: g.id,
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: HuddlColors.peachLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Icon(Icons.people,
                          size: 14, color: HuddlColors.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(g.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: context.hc.textPrimary)),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            final group = _userGroups.firstWhere((g) => g.id == v,
                orElse: () => _userGroups.first);
            setState(() {
              _selectedGroupId = v;
              _selectedGroupName = group.name;
            });
          },
        ),
      ),
    );
  }

  /// Widget to show invited members for private meetups
  Widget _buildInviteMembersWidget() {
    return Container(
      margin: const EdgeInsets.only(left: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected members chips
          if (_selectedMemberIds.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedMemberIds.map((id) {
                final member = _boroughMembers.firstWhere(
                  (m) => m.id == id,
                  orElse: () => const BoroughMember(
                    id: '', name: 'Unknown', parentType: 'mum', stagesOfLife: [],
                  ),
                );
                final photoUrl = MemberPhotoService.getPhotoByName(member.name);
                return Chip(
                  avatar: photoUrl != null
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(photoUrl),
                        radius: 14,
                      )
                    : MemberAvatar(name: member.name, size: 28),
                  label: Text(
                    member.name,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _selectedMemberIds.remove(id)),
                  backgroundColor: HuddlColors.peachLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: HuddlColors.primary.withValues(alpha: 0.3)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          // Add members button
          GestureDetector(
            onTap: _showInviteMembersSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedMemberIds.isNotEmpty
                      ? HuddlColors.primary
                      : HuddlColors.gray300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 20,
                    color: _selectedMemberIds.isNotEmpty
                        ? HuddlColors.primary
                        : HuddlColors.textHint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedMemberIds.isEmpty
                          ? 'Select members to invite'
                          : '${_selectedMemberIds.length} member${_selectedMemberIds.length == 1 ? '' : 's'} selected',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: _selectedMemberIds.isNotEmpty
                            ? HuddlColors.textDark
                            : HuddlColors.textHint,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: _selectedMemberIds.isNotEmpty
                        ? HuddlColors.primary
                        : HuddlColors.textHint,
                  ),
                ],
              ),
            ),
          ),
          if (_userBorough != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Members from ${_userBorough!}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: context.hc.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Show bottom sheet to invite members for private meetups
  void _showInviteMembersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final query = _memberSearchQuery.toLowerCase();
            final filtered = query.isEmpty
                ? _boroughMembers
                : _boroughMembers.where((m) =>
                    m.name.toLowerCase().contains(query) ||
                    m.parentType.toLowerCase().contains(query)).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              maxChildSize: 0.9,
              minChildSize: 0.5,
              expand: false,
              builder: (_, scrollCtrl) {
                return Column(
                  children: [
                    // Handle bar
                    Container(
                      width: 40, height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      decoration: BoxDecoration(
                        color: context.hc.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Invite members',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.hc.textPrimary,
                            ),
                          ),
                          if (_selectedMemberIds.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: HuddlColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedMemberIds.length}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.hc.surface,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_userBorough != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, top: 2, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Members in ${_userBorough!}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: context.hc.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    // Selected chips
                    if (_selectedMemberIds.isNotEmpty) ...[
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: _selectedMemberIds.map((id) {
                            final m = _boroughMembers.firstWhere(
                              (b) => b.id == id,
                              orElse: () => const BoroughMember(
                                id: '', name: '?', parentType: 'mum', stagesOfLife: [],
                              ),
                            );
                            final photoUrl = MemberPhotoService.getPhotoByName(m.name);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Chip(
                                avatar: photoUrl != null
                                  ? CircleAvatar(
                                      backgroundImage: NetworkImage(photoUrl),
                                      radius: 12,
                                    )
                                  : MemberAvatar(name: m.name, size: 24),
                                label: Text(m.name.split(' ').first,
                                    style: GoogleFonts.poppins(fontSize: 12)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setSheetState(() => _selectedMemberIds.remove(id));
                                  setState(() {});
                                },
                                backgroundColor: HuddlColors.peachLight,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Search field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _memberSearchController,
                        onChanged: (v) {
                          setSheetState(() => _memberSearchQuery = v);
                        },
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search members...',
                          hintStyle: GoogleFonts.poppins(
                              fontSize: 14, color: context.hc.textTertiary),
                          prefixIcon: Icon(Icons.search,
                              color: context.hc.textTertiary, size: 20),
                          filled: true,
                          fillColor: context.hc.scaffold,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    // Member list
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
                                      errorBuilder: (_, __, ___) =>
                                          MemberAvatar(name: member.name, size: 40)),
                                  )
                                : MemberAvatar(name: member.name, size: 40),
                            title: Text(
                              member.name,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: context.hc.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              member.parentType == 'mum' ? 'Mum' : 'Dad',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: context.hc.textTertiary,
                              ),
                            ),
                            trailing: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: isSelected
                                  ? HuddlColors.primary
                                  : HuddlColors.gray300,
                              size: 24,
                            ),
                            onTap: () {
                              setSheetState(() {
                                if (isSelected) {
                                  _selectedMemberIds.remove(member.id);
                                } else {
                                  _selectedMemberIds.add(member.id);
                                }
                              });
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                    // Done button
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          16, 8, 16, MediaQuery.of(sheetCtx).padding.bottom + 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            _memberSearchController.clear();
                            _memberSearchQuery = '';
                            Navigator.pop(sheetCtx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                          ),
                          child: Text(
                            'Done',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.hc.surface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Privacy radio — clean style matching original target design (no container border)
  Widget _privacyRadio({
    required String label,
    required String description,
    required String value,
    IconData? icon,
  }) {
    final selected = _privacy == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _privacy = value;
          if (value != 'group') {
            _selectedGroupId = null;
            _selectedGroupName = null;
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? HuddlColors.primary
                        : HuddlColors.gray300,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: HuddlColors.primary,
                            shape: BoxShape.circle,
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
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.hc.textPrimary)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: context.hc.textTertiary,
                          height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
