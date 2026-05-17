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
  // BUILD — Figma flat layout (no cards, underline inputs, inline controls)
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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

                    // ── Cover photo banner ──
                    _buildPhotoUpload(),

                    // ── Form body (white, flat, padded) ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24),

                          // Meetup name
                          _buildFlatTextField(
                            controller: _titleCtrl,
                            label: 'Meetup name',
                            hint: 'Give your meetup a name',
                            onChanged: (_) { setState(() {}); _saveDraft(); },
                          ),

                          _flatDivider(),

                          // Location
                          _buildFlatLocationField(),

                          _flatDivider(),

                          // Date row — single date field + From / To side-by-side
                          _buildFlatDateTimeBlock(),

                          _flatDivider(),

                          // Repeat — inline toggle switch
                          _buildFlatRepeatRow(),

                          _flatDivider(),

                          // Category chips
                          _buildFlatCategorySection(),

                          _flatDivider(),

                          // Participants (square checkboxes)
                          _buildFlatParticipantsSection(),

                          _flatDivider(),

                          // Max attendees
                          _buildFlatAttendeesSection(),

                          _flatDivider(),

                          // Price — Free checkbox + price field
                          _buildFlatPriceSection(),

                          _flatDivider(),

                          // Description textarea
                          _buildFlatDescriptionSection(),

                          _flatDivider(),

                          // Privacy — inline radio buttons
                          _buildFlatPrivacySection(),

                          // Invite friends section (public) / invite members (private)
                          if (_privacy == 'public') _buildPublicInviteRow(),
                          if (_privacy == 'private') ...[
                            _flatDivider(),
                            _buildInviteMembersWidget(),
                          ],

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
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
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
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
  // STICKY CTA — orange gradient button
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildStickyCreateButton() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
      child: GestureDetector(
        onTap: _isFormValid && !_isCreating ? _createMeetup : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: _isFormValid
                ? const LinearGradient(
                    colors: [Color(0xFFF8A15F), Color(0xFFE8601E)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: _isFormValid ? null : HuddlColors.gray200,
            borderRadius: BorderRadius.circular(26),
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
  // FLAT DIVIDER — lightweight horizontal rule between form sections
  // ══════════════════════════════════════════════════════════════════════

  Widget _flatDivider() {
    return Divider(
      height: 28,
      thickness: 1,
      color: HuddlColors.gray200,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // SECTION LABEL — uppercase small label above each section
  // ══════════════════════════════════════════════════════════════════════

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: HuddlColors.gray500,
        letterSpacing: 0.4,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PHOTO UPLOAD — blue gradient banner, "Click to add photo"
  // ══════════════════════════════════════════════════════════════════════

  Widget _photoPlaceholder() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A90E2), Color(0xFF6B6FC5)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.camera_alt_outlined,
                color: Colors.white, size: 26),
          ),
          const SizedBox(height: 10),
          Text(
            'Click to add photo',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a cover image for your meetup',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.80),
            ),
          ),
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
              // Bottom scrim + change label
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.60),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.edit_outlined,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Change photo',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
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

    return GestureDetector(
      onTap: _pickImage,
      child: _photoPlaceholder(),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // FLAT TEXT FIELD — underline style (no border box)
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? prefixText,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.hc.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              fontSize: 15,
              color: HuddlColors.gray400,
            ),
            prefixText: prefixText,
            prefixStyle: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.gray200, width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.primary, width: 1.5),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // LOCATION FIELD — underline with pin icon
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Location'),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.location_on_outlined,
                size: 20, color: HuddlColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _locationCtrl,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Add a location or address',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 15,
                    color: HuddlColors.gray400,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: HuddlColors.gray200, width: 1),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide:
                        BorderSide(color: HuddlColors.primary, width: 1.5),
                  ),
                ),
                onChanged: (_) { setState(() {}); _saveDraft(); },
              ),
            ),
          ],
        ),
        // Online toggle
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              height: 24,
              child: Transform.scale(
                scale: 0.85,
                child: CupertinoSwitch(
                  value: _isOnline,
                  activeTrackColor: HuddlColors.primary,
                  onChanged: (v) => setState(() => _isOnline = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Online meetup',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: context.hc.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DATE / TIME BLOCK — Date field + From/To side-by-side
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatDateTimeBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Date & Time'),
        const SizedBox(height: 10),

        // Date row
        GestureDetector(
          onTap: _pickDate,
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 18, color: HuddlColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selectedDate != null
                      ? _formatDate(_selectedDate!)
                      : 'Add date',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: _selectedDate != null
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: _selectedDate != null
                        ? context.hc.textPrimary
                        : HuddlColors.gray400,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // From / To time side-by-side
        Row(
          children: [
            // From
            Expanded(
              child: GestureDetector(
                onTap: _pickStartTime,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.gray500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_outlined,
                            size: 16, color: HuddlColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          _startTime != null
                              ? _formatTime(_startTime!)
                              : 'Start time',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: _startTime != null
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: _startTime != null
                                ? context.hc.textPrimary
                                : HuddlColors.gray400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 1,
                      color: HuddlColors.gray200,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 20),

            // To
            Expanded(
              child: GestureDetector(
                onTap: _pickEndTime,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HuddlColors.gray500,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_outlined,
                            size: 16, color: HuddlColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          _endTime != null
                              ? _formatTime(_endTime!)
                              : 'End time',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: _endTime != null
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: _endTime != null
                                ? context.hc.textPrimary
                                : HuddlColors.gray400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 1,
                      color: HuddlColors.gray200,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // REPEAT ROW — inline label + CupertinoSwitch + frequency picker
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatRepeatRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repeat',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                  if (_repeatOn)
                    Text(
                      _repeatFrequency,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: HuddlColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: CupertinoSwitch(
                value: _repeatOn,
                activeTrackColor: HuddlColors.primary,
                onChanged: (v) => setState(() {
                  _repeatOn = v;
                  if (!v) _repeatFrequency = 'Every week';
                }),
              ),
            ),
          ],
        ),

        // Frequency chips — visible when repeat is ON
        if (_repeatOn) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _repeatOptions.where((o) => o != 'Does not repeat').map((option) {
                final selected = _repeatFrequency == option;
                return GestureDetector(
                  onTap: () => setState(() => _repeatFrequency = option),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? HuddlColors.primary
                          : HuddlColors.gray100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? HuddlColors.primary
                            : HuddlColors.gray200,
                      ),
                    ),
                    child: Text(
                      option,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : context.hc.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // CATEGORY SECTION — rounded pill chips with icon + label
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Category'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((cat) {
            final label = cat['label'] as String;
            final icon = cat['icon'] as IconData;
            final selected = _selectedCategories.contains(label);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _selectedCategories.remove(label);
                } else {
                  _selectedCategories.add(label);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? HuddlColors.primary
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? HuddlColors.primary
                        : HuddlColors.gray300,
                    width: 1.2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: HuddlColors.primary.withValues(alpha: 0.20),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: selected ? Colors.white : HuddlColors.gray500,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : context.hc.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PARTICIPANTS — square checkboxes, Kids triggers age range fields
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatParticipantsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Participants'),
        const SizedBox(height: 10),
        ..._participants.keys.map((key) {
          final checked = _participants[key]!;
          return GestureDetector(
            onTap: () => setState(() => _participants[key] = !checked),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _squareCheckbox(checked),
                  const SizedBox(width: 12),
                  Text(
                    key,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        // Kids age range — appears when Kids is checked
        if (_participants['Kids'] == true) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Min age',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.gray500),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _minAgeCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: HuddlColors.gray400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        enabledBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: HuddlColors.gray200, width: 1),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: HuddlColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Max age',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.gray500),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _maxAgeCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: '16',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: HuddlColors.gray400),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        enabledBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: HuddlColors.gray200, width: 1),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: HuddlColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ATTENDEES — max count field
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatAttendeesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Max Attendees (optional)'),
        const SizedBox(height: 6),
        TextField(
          controller: _attendeesCtrl,
          keyboardType: TextInputType.number,
          style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: context.hc.textPrimary),
          decoration: InputDecoration(
            hintText: 'No limit',
            hintStyle:
                GoogleFonts.poppins(fontSize: 15, color: HuddlColors.gray400),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.gray200, width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.primary, width: 1.5),
            ),
          ),
          onChanged: (v) {
            setState(() {
              _maxAttendees = int.tryParse(v);
            });
          },
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRICE — Free checkbox + price field below
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Price'),
        const SizedBox(height: 10),

        // Free toggle row
        GestureDetector(
          onTap: () => setState(() {
            _isFree = !_isFree;
            if (_isFree) _priceCtrl.clear();
          }),
          child: Row(
            children: [
              _squareCheckbox(_isFree),
              const SizedBox(width: 12),
              Text(
                'Free',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textPrimary,
                ),
              ),
            ],
          ),
        ),

        // Price input — visible when not free
        if (!_isFree) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.hc.textPrimary),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle:
                  GoogleFonts.poppins(fontSize: 15, color: HuddlColors.gray400),
              prefixText: '£ ',
              prefixStyle: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.hc.textSecondary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: HuddlColors.gray200, width: 1),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: HuddlColors.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => _saveDraft(),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // DESCRIPTION — multiline textarea
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatDescriptionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Description'),
        const SizedBox(height: 6),
        TextField(
          controller: _descriptionCtrl,
          maxLines: 5,
          minLines: 3,
          style: GoogleFonts.poppins(
              fontSize: 14, color: context.hc.textPrimary),
          decoration: InputDecoration(
            hintText: 'Tell people what to expect at your meetup...',
            hintStyle:
                GoogleFonts.poppins(fontSize: 14, color: HuddlColors.gray400),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.gray200, width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HuddlColors.primary, width: 1.5),
            ),
          ),
          onChanged: (_) => _saveDraft(),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // PRIVACY — inline radio buttons directly in form
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildFlatPrivacySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Privacy'),
        const SizedBox(height: 10),

        // Public
        _privacyRadioTile(
          value: 'public',
          icon: Icons.public,
          title: 'Public',
          subtitle: 'Visible to all Huddl members in your area',
        ),
        const SizedBox(height: 2),

        // Group
        _privacyRadioTile(
          value: 'group',
          icon: Icons.group_outlined,
          title: 'Group',
          subtitle: 'Shared to a specific group you belong to',
        ),

        // Group picker — visible when group is selected
        if (_privacy == 'group') ...[
          const SizedBox(height: 10),
          _buildSheetGroupPicker(
            selectedGroupId: _selectedGroupId,
            onChanged: (id, name) {
              setState(() {
                _selectedGroupId = id;
                _selectedGroupName = name;
              });
            },
          ),
          const SizedBox(height: 4),
        ],

        const SizedBox(height: 2),

        // Private
        _privacyRadioTile(
          value: 'private',
          icon: Icons.lock_outline,
          title: 'Private — invite only',
          subtitle: 'Only invited people can see this meetup',
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
        if (value != 'group') {
          _selectedGroupId = null;
          _selectedGroupName = null;
        }
        if (value != 'private') {
          _selectedMemberIds.clear();
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Custom radio circle
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? HuddlColors.primary : HuddlColors.gray300,
                  width: selected ? 2 : 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: HuddlColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Icon(icon,
                size: 18,
                color: selected ? HuddlColors.primary : HuddlColors.gray400),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? context.hc.textPrimary
                          : context.hc.textSecondary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: HuddlColors.gray500,
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

  // ══════════════════════════════════════════════════════════════════════
  // PUBLIC INVITE ROW — "0 invited friends" + "Invite friends +"
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildPublicInviteRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: HuddlColors.gray100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HuddlColors.gray200),
            ),
            child: Text(
              '${_selectedMemberIds.length} invited friend${_selectedMemberIds.length == 1 ? '' : 's'}',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.hc.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Invite button
          GestureDetector(
            onTap: _showInviteMembersSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_add_outlined,
                      size: 14, color: HuddlColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Invite friends +',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // GROUP DROPDOWN PICKER (reused from old code, styling updated)
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildSheetGroupPicker({
    required String? selectedGroupId,
    required void Function(String? id, String name) onChanged,
  }) {
    if (_userGroups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No groups found. Join a group first.',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: context.hc.textTertiary,
            fontStyle: FontStyle.italic,
          ),
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
  // Preserved 1:1 from original — only padding adjusted
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildInviteMembersWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Invite members'),
        const SizedBox(height: 10),

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
              'From $_userBorough',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: context.hc.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  /// Show bottom sheet to invite members
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
                                'Members in $_userBorough',
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

  /// Square checkbox — orange when checked (Figma style)
  Widget _squareCheckbox(bool checked) {
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
            ? [
                BoxShadow(
                  color: HuddlColors.primary.withValues(alpha: 0.25),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
              ]
            : null,
      ),
      child: checked
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}
