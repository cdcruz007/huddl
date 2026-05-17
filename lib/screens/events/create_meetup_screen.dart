import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/image_editor_widget.dart';
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
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/borough_badge.dart';

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
  String _repeatEndOption = 'no_end';
  DateTime? _repeatEndDate;
  DateTime? _endDate;
  bool _showEndDate = false;
  bool _showEndTime = false;
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
      _locationCtrl.text.trim().isNotEmpty &&
      _selectedDate != null &&
      _startTime != null &&
      _endTime != null &&
      _selectedCategories.isNotEmpty &&
      _pickedImageUrl != null; // Photo is required

  String get _repeatSummary {
    if (!_repeatOn || _repeatFrequency == 'Does not repeat') return 'Does not repeat';
    final end = _repeatEndOption == 'by_date' && _repeatEndDate != null
        ? ' · until ${_formatDate(_repeatEndDate!)}'
        : '';
    return '$_repeatFrequency$end';
  }

  String get _privacyLabel {
    switch (_privacy) {
      case 'public': return 'Public';
      case 'group': return _selectedGroupName != null ? 'Group · $_selectedGroupName' : 'Group';
      case 'private': return 'Private · invite only';
      default: return 'Choose privacy';
    }
  }

  IconData get _privacyIcon {
    switch (_privacy) {
      case 'public': return Icons.public;
      case 'group': return Icons.group_outlined;
      case 'private': return Icons.lock_outline;
      default: return Icons.shield_outlined;
    }
  }

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
          colorScheme: ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _endDate = date);
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
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.gray100,
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
                    // ── Borough gate note ──
                    const BoroughGateMessage(featureLabel: 'Meetups'),

                    // ── Cover photo ──
                    _buildPhotoUpload(),

                    const SizedBox(height: 16),

                    // ── Main details card ──
                    _buildSectionCard([
                      _buildTitleField(),
                      _sectionDivider(),
                      _buildLocationRow(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Date & time card ──
                    _buildSectionCard([
                      _buildDateTimeRow(
                        label: 'Start date',
                        icon: Icons.calendar_today_outlined,
                        value: _selectedDate != null ? _formatDate(_selectedDate!) : null,
                        onTap: _pickDate,
                      ),
                      _sectionDivider(),
                      _buildDateTimeRow(
                        label: 'Start time',
                        icon: Icons.access_time_outlined,
                        value: _startTime != null ? _formatTime(_startTime!) : null,
                        onTap: _pickStartTime,
                      ),
                      if (_showEndDate) ...[
                        _sectionDivider(),
                        _buildDateTimeRow(
                          label: 'End date',
                          icon: Icons.calendar_today_outlined,
                          value: _endDate != null ? _formatDate(_endDate!) : null,
                          onTap: _pickEndDate,
                        ),
                      ],
                      if (_showEndTime) ...[
                        _sectionDivider(),
                        _buildDateTimeRow(
                          label: 'End time',
                          icon: Icons.access_time_outlined,
                          value: _endTime != null ? _formatTime(_endTime!) : null,
                          onTap: _pickEndTime,
                        ),
                      ],
                      if (!_showEndDate || !_showEndTime) ...[
                        _sectionDivider(),
                        _buildAddRowsFooter(),
                      ],
                    ]),

                    const SizedBox(height: 12),

                    // ── Repeat row ──
                    _buildSectionCard([
                      _buildRepeatRow(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Category card ──
                    _buildSectionCard([
                      _buildCategorySection(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Participants card ──
                    _buildSectionCard([
                      _buildParticipantsSection(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Attendees card ──
                    _buildSectionCard([
                      _buildAttendeesSection(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Price card ──
                    _buildSectionCard([
                      _buildPriceSection(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Description card ──
                    _buildSectionCard([
                      _buildDescriptionSection(),
                    ]),

                    const SizedBox(height: 12),

                    // ── Privacy card ──
                    _buildSectionCard([
                      _buildPrivacyRow(),
                      if (_privacy == 'private') ...[
                        _sectionDivider(),
                        _buildInviteMembersWidget(),
                      ],
                    ]),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Sticky CTA ──
            _buildStickyCreateButton(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // APP BAR
  // ══════════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: context.hc.surface,
      automaticallyImplyLeading: false,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textSecondary),
            ),
          ),
        ),
      ),
      leadingWidth: 80,
      centerTitle: true,
      title: Text(
        'Create meetup',
        style: GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: context.hc.textPrimary,
        ),
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
      color: context.hc.surface,
      padding: EdgeInsets.fromLTRB(
        16, 10, 16, MediaQuery.of(context).padding.bottom + 12),
      child: GestureDetector(
        onTap: _isFormValid && !_isCreating ? _createMeetup : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: _isFormValid
                ? const LinearGradient(
                    colors: [Color(0xFFF8A15F), Color(0xFFF07030)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: _isFormValid ? null : HuddlColors.gray200,
            borderRadius: BorderRadius.circular(HuddlColors.radiusFull),
            boxShadow: _isFormValid
                ? [
                    BoxShadow(
                      color: HuddlColors.primary.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: _isCreating
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
                : Text(
                    'Create meetup',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isFormValid ? Colors.white : HuddlColors.gray500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // SECTION CARD WRAPPER
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(HuddlColors.radiusLG),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: HuddlColors.gray200,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHOTO UPLOAD
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPhotoUpload() {
    if (_pickedImageUrl != null) {
      return GestureDetector(
        onTap: _pickImage,
        child: SizedBox(
          width: double.infinity,
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPickedImage(),
              // Scrim gradient at bottom
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit_outlined, size: 14, color: HuddlColors.textDark),
                    const SizedBox(width: 4),
                    Text('Change photo',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark)),
                  ]),
                ),
              ),
              // Required badge
              if (_pickedImageUrl == null)
                Positioned(
                  top: 12, right: 14,
                  child: _requiredBadge(),
                ),
            ],
          ),
        ),
      );
    }

    // Empty state — gradient placeholder
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 220,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF3ED), Color(0xFFFFE8D5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: HuddlColors.primary.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 28,
                      color: HuddlColors.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Add cover photo',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Required · helps people recognise your meetup',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.primary.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: HuddlColors.primary.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 48, color: HuddlColors.primary),
      ),
    );
  }

  Widget _requiredBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HuddlColors.error.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Required',
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // TITLE FIELD
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildTitleField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionLabel('Meetup name'),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) { setState(() {}); _saveDraft(); },
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Sunday Park Playdate',
              hintStyle: GoogleFonts.poppins(
                fontSize: 15,
                color: context.hc.textTertiary,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // LOCATION ROW
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildLocationRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _cardSectionLabel('Location'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Online',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Transform.scale(
                    scale: 0.78,
                    child: CupertinoSwitch(
                      value: _isOnline,
                      onChanged: (v) => setState(() => _isOnline = v),
                      activeTrackColor: HuddlColors.teal,
                      inactiveTrackColor: HuddlColors.gray300,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationCtrl,
            onChanged: (_) { setState(() {}); _saveDraft(); },
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: context.hc.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: _isOnline ? 'Meeting link or platform' : 'Address or place name',
              hintStyle: GoogleFonts.poppins(
                fontSize: 14,
                color: context.hc.textTertiary,
              ),
              prefixIcon: Icon(
                _isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
                size: 18,
                color: HuddlColors.primary,
              ),
              filled: true,
              fillColor: HuddlColors.gray100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
            textInputAction: TextInputAction.next,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DATE / TIME ROWS
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDateTimeRow({
    required String label,
    required IconData icon,
    String? value,
    required VoidCallback onTap,
  }) {
    final hasValue = value != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: HuddlColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value ?? label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                    color: hasValue ? context.hc.textPrimary : context.hc.textTertiary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.hc.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddRowsFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (!_showEndDate)
            _addPillButton(
              label: '+ End date',
              onTap: () { HapticFeedback.selectionClick(); setState(() => _showEndDate = true); },
            ),
          if (!_showEndDate && !_showEndTime)
            const SizedBox(width: 8),
          if (!_showEndTime)
            _addPillButton(
              label: '+ End time',
              onTap: () { HapticFeedback.selectionClick(); setState(() => _showEndTime = true); },
            ),
        ],
      ),
    );
  }

  Widget _addPillButton({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: HuddlColors.gray300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.hc.textSecondary,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // REPEAT ROW — opens bottom sheet picker
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildRepeatRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); _showRepeatSheet(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: HuddlColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.repeat_rounded, size: 18, color: HuddlColors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Repeat',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: context.hc.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _repeatSummary,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _repeatOn ? HuddlColors.teal : context.hc.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // REPEAT BOTTOM SHEET
  // ══════════════════════════════════════════════════════════════════════

  void _showRepeatSheet() {
    String sheetFrequency = _repeatOn ? _repeatFrequency : 'Does not repeat';
    String sheetEndOption = _repeatEndOption;
    DateTime? sheetEndDate = _repeatEndDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final isRepeating = sheetFrequency != 'Does not repeat';

          return Container(
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.gray300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Repeat',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: HuddlColors.gray100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 18, color: context.hc.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Frequency options
                ..._repeatOptions.map((opt) {
                  final isSelected = sheetFrequency == opt;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setSheet(() => sheetFrequency = opt);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                opt,
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  color: isSelected
                                      ? HuddlColors.teal
                                      : context.hc.textPrimary,
                                ),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? HuddlColors.teal : Colors.transparent,
                                border: Border.all(
                                  color: isSelected ? HuddlColors.teal : HuddlColors.gray300,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // End date section (only when repeating)
                if (isRepeating) ...[
                  Divider(height: 1, color: HuddlColors.gray200, indent: 20, endIndent: 20),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      'Ends',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _repeatEndOptionRow(
                    ctx: ctx,
                    setSheet: setSheet,
                    label: 'No end date',
                    value: 'no_end',
                    current: sheetEndOption,
                    onTap: () => setSheet(() {
                      sheetEndOption = 'no_end';
                      sheetEndDate = null;
                    }),
                  ),
                  _repeatEndOptionRow(
                    ctx: ctx,
                    setSheet: setSheet,
                    label: 'End by a date',
                    value: 'by_date',
                    current: sheetEndOption,
                    onTap: () => setSheet(() => sheetEndOption = 'by_date'),
                  ),
                  if (sheetEndOption == 'by_date') ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: sheetEndDate ??
                                (_selectedDate ?? DateTime.now())
                                    .add(const Duration(days: 30)),
                            firstDate: _selectedDate ?? DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                            builder: (c, child) => Theme(
                              data: Theme.of(c).copyWith(
                                colorScheme: ColorScheme.light(primary: HuddlColors.teal),
                              ),
                              child: child!,
                            ),
                          );
                          if (date != null) setSheet(() => sheetEndDate = date);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: HuddlColors.gray100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sheetEndDate != null
                                  ? HuddlColors.teal
                                  : HuddlColors.gray300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_outlined,
                                size: 16,
                                color: sheetEndDate != null
                                    ? HuddlColors.teal
                                    : context.hc.textTertiary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                sheetEndDate != null
                                    ? _formatDate(sheetEndDate!)
                                    : 'Choose end date',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: sheetEndDate != null
                                      ? context.hc.textPrimary
                                      : context.hc.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 8),
                // Confirm button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        if (sheetFrequency == 'Does not repeat') {
                          _repeatOn = false;
                          _repeatFrequency = 'Every week';
                          _repeatEndOption = 'no_end';
                          _repeatEndDate = null;
                        } else {
                          _repeatOn = true;
                          _repeatFrequency = sheetFrequency;
                          _repeatEndOption = sheetEndOption;
                          _repeatEndDate = sheetEndDate;
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF8A15F), Color(0xFFF07030)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(HuddlColors.radiusFull),
                        boxShadow: [
                          BoxShadow(
                            color: HuddlColors.primary.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Confirm',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _repeatEndOptionRow({
    required BuildContext ctx,
    required StateSetter setSheet,
    required String label,
    required String value,
    required String current,
    required VoidCallback onTap,
  }) {
    final isSelected = current == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: context.hc.textPrimary,
                  ),
                ),
              ),
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? HuddlColors.teal : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? HuddlColors.teal : HuddlColors.gray300,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // CATEGORY SECTION
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildCategorySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionLabel('Category'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((cat) {
              final label = cat['label'] as String;
              final icon = cat['icon'] as IconData;
              final isSelected = _selectedCategories.contains(label);
              return _categoryChip(
                label: label, icon: icon,
                isSelected: isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSelected) {
                      _selectedCategories.remove(label);
                    } else {
                      _selectedCategories.add(label);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isYellowCategory = label == 'Food & nutrition';
    final chipColor = isYellowCategory ? HuddlColors.accentAmber : HuddlColors.teal;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? chipColor.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : HuddlColors.gray200,
            width: isSelected ? 1.5 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? chipColor : context.hc.textTertiary),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? chipColor : HuddlColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PARTICIPANTS SECTION
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildParticipantsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionLabel('Who\'s it for?'),
          const SizedBox(height: 10),
          ..._participants.keys.map((key) {
            final isChecked = _participants[key]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _participants[key] = !_participants[key]!);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        _checkbox(isChecked),
                        const SizedBox(width: 12),
                        Text(
                          key,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: context.hc.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (key == 'Kids' && isChecked) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 34, bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: _ageField(label: 'Min age', ctrl: _minAgeCtrl, hint: '0')),
                        const SizedBox(width: 16),
                        Expanded(child: _ageField(label: 'Max age', ctrl: _maxAgeCtrl, hint: '17')),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _ageField({required String label, required TextEditingController ctrl, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 11, color: context.hc.textTertiary)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
            filled: true,
            fillColor: HuddlColors.gray100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ATTENDEES SECTION
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildAttendeesSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionLabel('Attendee limit'),
          const SizedBox(height: 10),
          // No-limit toggle chip
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (_maxAttendees == null) {
                  _maxAttendees = 10;
                  _attendeesCtrl.text = '10';
                } else {
                  _maxAttendees = null;
                  _attendeesCtrl.clear();
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _maxAttendees == null
                    ? HuddlColors.primary.withValues(alpha: 0.1)
                    : HuddlColors.gray100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _maxAttendees == null
                      ? HuddlColors.primary
                      : HuddlColors.gray200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.all_inclusive,
                    size: 16,
                    color: _maxAttendees == null ? HuddlColors.primary : context.hc.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _maxAttendees == null ? 'No limit' : 'Set a limit',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _maxAttendees == null
                          ? HuddlColors.primary
                          : context.hc.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Stepper (only when cap is set)
          if (_maxAttendees != null) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: HuddlColors.gray200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // − button
                  GestureDetector(
                    onTap: () {
                      final current = _maxAttendees ?? 1;
                      if (current > 1) {
                        final next = current - 1;
                        setState(() => _maxAttendees = next);
                        _attendeesCtrl.text = next.toString();
                        _attendeesCtrl.selection = TextSelection.collapsed(
                            offset: _attendeesCtrl.text.length);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Icon(
                        Icons.remove,
                        size: 20,
                        color: (_maxAttendees ?? 1) > 1
                            ? HuddlColors.primary
                            : HuddlColors.gray300,
                      ),
                    ),
                  ),
                  // Number input
                  Expanded(
                    child: TextField(
                      controller: _attendeesCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: HuddlColors.textDark,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Number',
                        hintStyle: GoogleFonts.poppins(fontSize: 15, color: HuddlColors.textHint),
                        border: InputBorder.none,
                        suffixText: ' people',
                        suffixStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        setState(() {
                          _maxAttendees = (parsed != null && parsed > 0) ? parsed : 1;
                        });
                      },
                    ),
                  ),
                  // + button
                  GestureDetector(
                    onTap: () {
                      final next = (_maxAttendees ?? 0) + 1;
                      setState(() => _maxAttendees = next);
                      _attendeesCtrl.text = next.toString();
                      _attendeesCtrl.selection = TextSelection.collapsed(
                          offset: _attendeesCtrl.text.length);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: const Icon(Icons.add, color: HuddlColors.primary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRICE SECTION
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPriceSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionLabel('Price'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isFree = !_isFree;
                if (_isFree) _priceCtrl.clear();
              });
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
              children: [
                _checkbox(_isFree),
                const SizedBox(width: 12),
                Text(
                  'Free event',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: context.hc.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                if (_isFree)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: HuddlColors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Free',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.teal,
                      ),
                    ),
                  ),
              ],
            ),
            ),
          ),
          if (!_isFree) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.poppins(fontSize: 15, color: context.hc.textPrimary),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: GoogleFonts.poppins(fontSize: 15, color: context.hc.textTertiary),
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Text(
                    '\u00A3',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 48),
                filled: true,
                fillColor: HuddlColors.gray100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              onChanged: (_) => _saveDraft(),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DESCRIPTION SECTION
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDescriptionSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardSectionLabel('Description'),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            style: GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
            decoration: InputDecoration(
              hintText: 'Who is this meetup for? What\'s planned?',
              hintStyle: GoogleFonts.poppins(
                fontSize: 13,
                color: context.hc.textTertiary,
                height: 1.4,
              ),
              filled: true,
              fillColor: HuddlColors.gray100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
            onChanged: (_) => _saveDraft(),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRIVACY ROW — opens premium bottom sheet
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPrivacyRow() {
    final hasPrivacy = _privacy.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); _showPrivacySheet(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: HuddlColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_privacyIcon, size: 18, color: HuddlColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: context.hc.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _privacyLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: hasPrivacy ? context.hc.textPrimary : context.hc.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.hc.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ── Privacy bottom sheet ──────────────────────────────────────────────
  void _showPrivacySheet() {
    String sheetPrivacy = _privacy.isEmpty ? 'public' : _privacy;
    String? sheetGroupId = _selectedGroupId;
    String? sheetGroupName = _selectedGroupName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.gray300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Privacy settings',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.hc.textPrimary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: HuddlColors.gray100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 18, color: context.hc.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),

                // Options
                _privacyOptionTile(
                  ctx: ctx,
                  setSheet: setSheet,
                  value: 'public',
                  current: sheetPrivacy,
                  icon: Icons.public,
                  label: 'Public',
                  description: 'Anyone in your local community can see and join.',
                  onTap: () => setSheet(() => sheetPrivacy = 'public'),
                ),
                _privacyOptionTile(
                  ctx: ctx,
                  setSheet: setSheet,
                  value: 'group',
                  current: sheetPrivacy,
                  icon: Icons.group_outlined,
                  label: 'Group',
                  description: 'Only members of a specific group can see and join.',
                  onTap: () => setSheet(() {
                    sheetPrivacy = 'group';
                    if (_userGroups.isNotEmpty && sheetGroupId == null) {
                      sheetGroupId = _userGroups.first.id;
                      sheetGroupName = _userGroups.first.name;
                    }
                  }),
                ),
                // Group picker (inline, only when group is selected)
                if (sheetPrivacy == 'group') ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _buildSheetGroupPicker(
                      ctx: ctx,
                      setSheet: setSheet,
                      selectedGroupId: sheetGroupId,
                      onChanged: (id, name) => setSheet(() {
                        sheetGroupId = id;
                        sheetGroupName = name;
                      }),
                    ),
                  ),
                ],
                _privacyOptionTile(
                  ctx: ctx,
                  setSheet: setSheet,
                  value: 'private',
                  current: sheetPrivacy,
                  icon: Icons.lock_outline,
                  label: 'Private',
                  description: 'Invite only — you choose specific people.',
                  onTap: () => setSheet(() => sheetPrivacy = 'private'),
                ),

                const SizedBox(height: 8),

                // Confirm
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _privacy = sheetPrivacy;
                        if (sheetPrivacy == 'group') {
                          _selectedGroupId = sheetGroupId;
                          _selectedGroupName = sheetGroupName;
                        } else {
                          _selectedGroupId = null;
                          _selectedGroupName = null;
                        }
                        if (sheetPrivacy != 'private') {
                          _selectedMemberIds.clear();
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF8A15F), Color(0xFFF07030)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(HuddlColors.radiusFull),
                        boxShadow: [
                          BoxShadow(
                            color: HuddlColors.primary.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Confirm',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _privacyOptionTile({
    required BuildContext ctx,
    required StateSetter setSheet,
    required String value,
    required String current,
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    final isSelected = current == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? HuddlColors.primary.withValues(alpha: 0.12)
                      : HuddlColors.gray100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? HuddlColors.primary : context.hc.textTertiary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? HuddlColors.primary : context.hc.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textTertiary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? HuddlColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? HuddlColors.primary : HuddlColors.gray300,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetGroupPicker({
    required BuildContext ctx,
    required StateSetter setSheet,
    String? selectedGroupId,
    required Function(String? id, String? name) onChanged,
  }) {
    if (_userGroups.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: HuddlColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You don\'t have any groups yet. Join a group first.',
                style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.primary, height: 1.3),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: selectedGroupId != null ? HuddlColors.primary : HuddlColors.gray300,
        ),
        borderRadius: BorderRadius.circular(12),
        color: HuddlColors.gray100,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedGroupId,
          isExpanded: true,
          hint: Text('Select a group',
              style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textTertiary)),
          icon: Icon(Icons.keyboard_arrow_down,
              color: selectedGroupId != null ? HuddlColors.primary : HuddlColors.textHint),
          style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textPrimary),
          items: _userGroups.map((g) {
            return DropdownMenuItem(
              value: g.id,
              child: Row(
                children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: HuddlColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.people, size: 14, color: HuddlColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(g.name, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 13, color: context.hc.textPrimary)),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            final group = _userGroups.firstWhere((g) => g.id == v,
                orElse: () => _userGroups.first);
            onChanged(v, group.name);
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // INVITE MEMBERS WIDGET (inline when privacy = private)
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildInviteMembersWidget() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected member chips
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
                      ? CircleAvatar(backgroundImage: NetworkImage(photoUrl), radius: 14)
                      : MemberAvatar(name: member.name, size: 28),
                  label: Text(
                    member.name,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _selectedMemberIds.remove(id)),
                  backgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
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
                color: HuddlColors.gray100,
                border: Border.all(
                  color: _selectedMemberIds.isNotEmpty
                      ? HuddlColors.primary.withValues(alpha: 0.4)
                      : HuddlColors.gray200,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 18,
                    color: _selectedMemberIds.isNotEmpty
                        ? HuddlColors.primary
                        : context.hc.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedMemberIds.isEmpty
                          ? 'Invite friends to this meetup'
                          : '${_selectedMemberIds.length} member${_selectedMemberIds.length == 1 ? '' : 's'} invited',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _selectedMemberIds.isNotEmpty
                            ? HuddlColors.textDark
                            : context.hc.textTertiary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: context.hc.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_userBorough != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'From ${_userBorough!}',
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
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
                                            radius: 12)
                                        : MemberAvatar(name: m.name, size: 24),
                                    label: Text(m.name.split(' ').first,
                                        style: GoogleFonts.poppins(fontSize: 12)),
                                    deleteIcon: const Icon(Icons.close, size: 14),
                                    onDeleted: () {
                                      setSheetState(() => _selectedMemberIds.remove(id));
                                      setState(() {});
                                    },
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
                                              MemberAvatar(name: member.name, size: 40)))
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
                                  isSelected ? Icons.check_circle : Icons.circle_outlined,
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
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // SHARED COMPONENT HELPERS
  // ══════════════════════════════════════════════════════════════════════

  /// Card-internal section label — slightly smaller than page-level, uppercase tracking
  Widget _cardSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.hc.textTertiary,
        letterSpacing: 0.2,
      ),
    );
  }

  /// Custom checkbox — orange when checked
  Widget _checkbox(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: checked ? HuddlColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? HuddlColors.primary : HuddlColors.gray300,
          width: 1.5,
        ),
        boxShadow: checked
            ? [BoxShadow(
                color: HuddlColors.primary.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 1))]
            : null,
      ),
      child: checked
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }

}
