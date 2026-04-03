import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../services/event_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../models/group.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE EVENT — single-page scrollable form matching target design screenshots
// Header: Cancel (left) · Create event (centre) · Save (right)
// Blue photo banner, underline fields, CupertinoSwitch toggles, privacy radios
// ═══════════════════════════════════════════════════════════════════════════════

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  // ── Controllers ──
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();

  // ── Form state ──
  String _category = '';
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;
  bool _isFree = true;
  bool _isOnline = false;
  String? _pickedImageUrl;
  bool _isCreating = false;
  int? _maxAttendees;

  // Show/hide optional end date/time rows
  bool _showEndDate = false;
  bool _showEndTime = false;

  // ── Participants (matching target: "For mums", "For dads" etc.) ──
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

  // ── Categories ──
  static const _categories = [
    {'label': 'Workshop', 'icon': Icons.school},
    {'label': 'Class', 'icon': Icons.music_note},
    {'label': 'Play', 'icon': Icons.child_care},
    {'label': 'Health', 'icon': Icons.medical_services_outlined},
    {'label': 'Community', 'icon': Icons.celebration},
    {'label': 'Other', 'icon': Icons.event},
  ];

  final _eventService = EventService();
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
              leading: Icon(_isCreating ? Icons.hourglass_top : Icons.save_outlined,
                  color: HuddlColors.textDark),
              title: Text(_isCreating ? 'Saving...' : 'Save as draft',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w500)),
              onTap: _isCreating ? null : () {
                Navigator.pop(ctx);
                if (_isFormValid) _createEvent();
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
      _startDate != null &&
      _startTime != null;

  // ── Pickers ──────────────────────────────────────────────────────────
  void _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _startDate ?? DateTime.now().add(const Duration(days: 7)),
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
    if (date != null) setState(() => _startDate = date);
  }

  void _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: _startDate ?? DateTime.now(),
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
            Text('Add event photo',
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
  void _createEvent() {
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
    final id = 'ev_${DateTime.now().millisecondsSinceEpoch}';

    // Map category to color/icon for Event model
    Color catColor = HuddlColors.blue;
    IconData catIcon = Icons.event;
    for (final cat in _categories) {
      if (cat['label'] == _category) {
        catIcon = cat['icon'] as IconData;
        break;
      }
    }
    if (_category == 'Workshop') catColor = HuddlColors.primaryDark;
    if (_category == 'Class') catColor = HuddlColors.blue;
    if (_category == 'Play') catColor = HuddlColors.primary;
    if (_category == 'Health') catColor = HuddlColors.error;
    if (_category == 'Community') catColor = HuddlColors.lightBlue;

    const dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthAbbr = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];

    final date = _startDate ?? DateTime.now().add(const Duration(days: 7));
    final st = _startTime ?? const TimeOfDay(hour: 10, minute: 0);
    final et = _endTime ?? const TimeOfDay(hour: 11, minute: 30);

    final event = Event(
      id: id,
      title: _titleCtrl.text.trim(),
      description: _descriptionCtrl.text.trim().isEmpty
          ? 'Join us for this event!'
          : _descriptionCtrl.text.trim(),
      dateDisplay:
          '${dayAbbr[date.weekday - 1]}, ${monthAbbr[date.month - 1]} ${date.day}',
      timeDisplay: '${_formatTime(st)} - ${_formatTime(et)}',
      dateTime:
          DateTime(date.year, date.month, date.day, st.hour, st.minute),
      location: _isOnline
          ? (_locationCtrl.text.trim().isEmpty
              ? 'Online (Zoom)'
              : _locationCtrl.text.trim())
          : _locationCtrl.text.trim(),
      attendees: 1,
      isFree: _isFree,
      price: _isFree ? '' : '\u00A3${_priceCtrl.text.trim()}',
      isOnline: _isOnline,
      color: catColor,
      icon: catIcon,
      organiser: organiserName,
      imageUrl: _pickedImageUrl ?? '',
      isUserCreated: true,
    );

    _eventService.createEvent(event);

    if (kDebugMode && _selectedGroupName != null) {
      debugPrint('Event created for group: $_selectedGroupName');
    }

    setState(() => _isCreating = false);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text('"${event.title}" created successfully!')),
      ]),
      backgroundColor: HuddlColors.teal,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));

    Navigator.pop(context);
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
          'Create event',
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
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────── PHOTO UPLOAD (Blue banner — matching target) ───────────
            _buildPhotoUpload(),
            const SizedBox(height: 16),

            // ─────────── EVENT NAME ───────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _sectionLabel('Event name'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _underlineTextField(
                controller: _titleCtrl,
                hint: 'Event name',
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
                              color: HuddlColors.textSecondary)),
                      const SizedBox(width: 8),
                      Transform.scale(
                        scale: 0.8,
                        child: CupertinoSwitch(
                          value: _isOnline,
                          onChanged: (v) => setState(() => _isOnline = v),
                          activeTrackColor: HuddlColors.teal,
                          inactiveTrackColor: const Color(0xFFE9E9EA),
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
                value: _startDate != null
                    ? _formatDate(_startDate!)
                    : null,
                hint: 'Start date',
                icon: Icons.calendar_today_outlined,
                iconColor: HuddlColors.primary,
                onTap: _pickStartDate,
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
                iconColor: HuddlColors.textHint,
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
                  iconColor: HuddlColors.primary,
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
                  iconColor: HuddlColors.textHint,
                  onTap: _pickEndTime,
                ),
              ),

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
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      'e.g. what people can expect, who this is for.',
                  hintStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: HuddlColors.textHint,
                      height: 1.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: HuddlColors.gray300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: HuddlColors.gray300),
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
                child: Padding(
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
                  ),
                  const SizedBox(height: 10),
                  _privacyRadio(
                    label: 'Group',
                    description:
                        'Only members of a specific group can see and join your event.',
                    value: 'group',
                  ),
                  if (_privacy == 'group') ...[
                    const SizedBox(height: 12),
                    _buildGroupPicker(),
                  ],
                  const SizedBox(height: 10),
                  _privacyRadio(
                    label: 'Private',
                    description:
                        'Invite only \u2014 choose specific friends to invite.',
                    value: 'private',
                  ),
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
  // COMPONENT WIDGETS (identical to target design screenshots)
  // ══════════════════════════════════════════════════════════════════════

  /// Blue photo upload banner matching target
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

  /// Section label — bold dark text
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

  /// Underline text field matching target style
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

  /// Tappable date/time field with underline and icon
  Widget _dateTapField({
    String? value,
    required String hint,
    required IconData icon,
    required Color iconColor,
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
                  color: HuddlColors.textHint,
                ),
              ),
            ),
            const Icon(Icons.add, size: 20, color: HuddlColors.primary),
          ],
        ),
      ),
    );
  }

  /// Category chip — outlined only, never filled (matching target)
  Widget _categoryChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
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
            color: isSelected ? HuddlColors.blue : HuddlColors.gray300,
            width: isSelected ? 1.8 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? HuddlColors.blue : HuddlColors.textHint),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? HuddlColors.blue : HuddlColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Custom checkbox — orange when checked
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

  /// Privacy radio — clean style with radio circle + label + description
  Widget _privacyRadio({
    required String label,
    required String description,
    required String value,
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
                'You don\'t belong to any groups yet. Join a group first to create group events.',
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
}
