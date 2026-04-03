import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../models/group.dart';

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
  String _category = '';
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isFree = false;
  bool _repeatOn = false;
  String _repeatFrequency = 'Every week';
  String _repeatEndOption = 'no_end';
  DateTime? _repeatEndDate;
  String? _pickedImageUrl;
  bool _isCreating = false;
  int? _maxAttendees;

  // ── Participants ──
  final Map<String, bool> _participants = {
    'For mums': false,
    'For dads': false,
    'For aspiring parents': false,
    'For expecting parents': false,
    'For kids': false,
  };

  // ── Privacy ──
  String _privacy = '';
  String? _selectedGroupId;
  String? _selectedGroupName;
  List<Group> _userGroups = [];

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
    _onboardingService.initialize();
    _loadUserGroups();
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
    super.dispose();
  }

  // ── More options menu ──────────────────────────────────────────────
  void _showMoreOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: HuddlColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_outlined,
                  color: HuddlColors.textDark),
              title: Text('Save as draft',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                if (_isFormValid) _createMeetup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: HuddlColors.error),
              title: Text('Discard',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
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
      _category.isNotEmpty;

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
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _startTime = time);
  }

  void _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime ?? const TimeOfDay(hour: 15, minute: 0),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _endTime = time);
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
      backgroundColor: HuddlColors.white,
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
                color: HuddlColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Add cover photo',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: HuddlColors.textDark)),
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
  void _createMeetup() {
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

    String mappedCategory = 'Social';
    if (_category == 'Coffee & tea') {
      mappedCategory = 'Coffee';
    } else if (_category == 'Playdate') {
      mappedCategory = 'Playdate';
    } else if (_category == 'Sports & exercise') {
      mappedCategory = 'Sport';
    } else if (_category == 'Parks & Walks') {
      mappedCategory = 'Walk';
    } else if (_category == 'Hanging out') {
      mappedCategory = 'Social';
    } else if (_category == 'Pregnancy') {
      mappedCategory = 'Social';
    } else if (_category == 'Food & nutrition') {
      mappedCategory = 'Food';
    } else if (_category == 'Performance & shows') {
      mappedCategory = 'Social';
    }

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
    );

    _meetupService.createMeetup(meetup);

    setState(() => _isCreating = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text('"${meetup.title}" created successfully!')),
      ]),
      backgroundColor: HuddlColors.teal,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    Navigator.pop(context, meetup);
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: HuddlColors.gray100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_left,
                    size: 26, color: HuddlColors.blue),
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Create meetup',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: GestureDetector(
                onTap: () => _showMoreOptions(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: HuddlColors.gray100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_horiz,
                      size: 22, color: HuddlColors.blue),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    child: _sectionLabel('Location'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _underlineTextField(
                      controller: _locationCtrl,
                      hint: 'Location',
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ─────────── DATE ───────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _sectionLabel('Date'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _dateTapField(
                      value: _selectedDate != null
                          ? _formatDate(_selectedDate!)
                          : null,
                      hint: 'Date',
                      icon: Icons.calendar_today_outlined,
                      onTap: _pickDate,
                    ),
                  ),

                  // ─────────── FROM / TO ───────────
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _timeTapField(
                            value: _startTime != null
                                ? _formatTime(_startTime!)
                                : null,
                            hint: 'From',
                            onTap: _pickStartTime,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: _timeTapField(
                            value: _endTime != null
                                ? _formatTime(_endTime!)
                                : null,
                            hint: 'To',
                            onTap: _pickEndTime,
                          ),
                        ),
                      ],
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
                                color: HuddlColors.textDark)),
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
                            inactiveTrackColor: const Color(0xFFE9E9EA),
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
                                    color: HuddlColors.textHint),
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: HuddlColors.textDark),
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
                                  color: HuddlColors.textDark)),
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
                          fontSize: 14, color: HuddlColors.textDark),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. who this meetup is for, what attractions are planned.',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: HuddlColors.textHint,
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
                        final isSelected = _category == label;
                        return _categoryChip(
                          label: label,
                          icon: icon,
                          isSelected: isSelected,
                          onTap: () =>
                              setState(() => _category = label),
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
                    final isOn = _participants[key]!;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(key,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: HuddlColors.textDark)),
                                Transform.scale(
                                  scale: 0.8,
                                  child: CupertinoSwitch(
                                    value: isOn,
                                    onChanged: (v) =>
                                        setState(() => _participants[key] = v),
                                    activeTrackColor: HuddlColors.teal,
                                    inactiveTrackColor: const Color(0xFFE9E9EA),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: HuddlColors.gray200),
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
                              'Everyone in your local community can see and join your event.',
                          value: 'public',
                          icon: Icons.public,
                        ),
                        const SizedBox(height: 10),
                        _privacyRadio(
                          label: 'Group',
                          description:
                              'Only members of a specific group can see and join your event.',
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
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // ─────────── CREATE MEETUP BUTTON ───────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isFormValid ? _createMeetup : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  disabledBackgroundColor:
                      HuddlColors.primary.withValues(alpha: 0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: _isCreating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        'Create meetup',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // COMPONENT WIDGETS
  // ══════════════════════════════════════════════════════════════════════

  /// Blue photo upload banner matching screenshot design
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
          color: HuddlColors.blue,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 28,
                      color: Colors.white.withValues(alpha: 0.8)),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add,
                          size: 12, color: HuddlColors.blue),
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
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: HuddlColors.blue,
      child: const Center(
        child:
            Icon(Icons.image_outlined, size: 48, color: Colors.white),
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
        color: HuddlColors.textDark,
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
      onChanged: (_) => setState(() {}),
      style:
          GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
            fontSize: 14, color: HuddlColors.textHint),
        prefixText: prefix,
        prefixStyle: GoogleFonts.poppins(
            fontSize: 14, color: HuddlColors.textDark),
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

  /// Tappable date field with underline and calendar icon
  Widget _dateTapField({
    String? value,
    required String hint,
    required IconData icon,
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
                value ?? hint,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: value != null
                      ? HuddlColors.textDark
                      : HuddlColors.textHint,
                ),
              ),
            ),
            Icon(icon, size: 20, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }

  /// Tappable time field with orange circle clock icon matching screenshot
  Widget _timeTapField({
    String? value,
    required String hint,
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
                value ?? hint,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: value != null
                      ? HuddlColors.textDark
                      : HuddlColors.textHint,
                ),
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.access_time,
                  size: 16, color: HuddlColors.primary),
            ),
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
                color: isSelected ? chipColor : HuddlColors.textHint),
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
                  fontSize: 14, color: HuddlColors.textDark)),
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
                  fontSize: 13, color: HuddlColors.textHint)),
          icon: Icon(Icons.keyboard_arrow_down,
              color: _selectedGroupId != null
                  ? HuddlColors.primary
                  : HuddlColors.textHint),
          style:
              GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textDark),
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
                            fontSize: 13, color: HuddlColors.textDark)),
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
                          color: HuddlColors.textDark)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textHint,
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
