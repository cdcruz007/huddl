import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/onboarding_data_service.dart';
import 'meetup_detail_screen.dart';
import '../groups/forward_message_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE MEETUP — full multi-step creation flow matching wireframe
// Form → Date → Time → Repeat → Privacy → Invite → Success
// ═══════════════════════════════════════════════════════════════════════════════

class CreateMeetupScreen extends StatefulWidget {
  const CreateMeetupScreen({super.key});

  @override
  State<CreateMeetupScreen> createState() => _CreateMeetupScreenState();
}

class _CreateMeetupScreenState extends State<CreateMeetupScreen> {
  // ── Controllers ──
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxAttendeesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // ── Form state ──
  String _category = 'Coffee';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 30);
  bool _hasMaxAttendees = false;
  String? _pickedImageUrl;
  final _picker = ImagePicker();

  // ── Repeat state ──
  MeetupRepeat _repeat = MeetupRepeat.none;
  List<int> _repeatWeekDays = []; // 0=Mon...6=Sun
  DateTime? _repeatEndDate;
  int _customInterval = 1;
  String _customUnit = 'weeks';

  // ── Privacy state ──
  MeetupPrivacy _privacy = MeetupPrivacy.public;
  String? _selectedGroupId;
  String? _selectedGroupName;
  final Set<String> _selectedInviteeIds = {};

  // ── Multi-step page state ──
  int _currentStep = 0; // 0=form, 1=review/privacy, 2=invite, 3=success
  bool _isCreating = false;
  final Map<String, String> _errors = {};

  final _meetupService = MeetupService();
  final _onboardingService = OnboardingDataService();

  final _categories = [
    {'label': 'Coffee', 'icon': Icons.coffee, 'color': const Color(0xFF8D6E63)},
    {'label': 'Playdate', 'icon': Icons.child_care, 'color': HuddlColors.primary},
    {'label': 'Sport', 'icon': Icons.sports_golf, 'color': const Color(0xFF43A047)},
    {'label': 'Walk', 'icon': Icons.directions_walk, 'color': const Color(0xFF00897B)},
    {'label': 'Social', 'icon': Icons.celebration, 'color': HuddlColors.purple},
    {'label': 'Other', 'icon': Icons.groups, 'color': HuddlColors.blue},
  ];

  // Sample contacts for invite screen
  static final List<_InviteContact> _sampleContacts = [
    _InviteContact(id: 'mem_emma', name: 'Emma Watson', avatarColor: const Color(0xFFFF975C)),
    _InviteContact(id: 'mem_sophie', name: 'Sophie Turner', avatarColor: const Color(0xFF3580F0)),
    _InviteContact(id: 'mem_kate', name: 'Kate Middleton', avatarColor: const Color(0xFF199A85)),
    _InviteContact(id: 'mem_lucy', name: 'Lucy Chen', avatarColor: const Color(0xFFA16AE9)),
    _InviteContact(id: 'mem_james', name: 'James Smith', avatarColor: const Color(0xFF5B9DFF)),
    _InviteContact(id: 'mem_anna', name: 'Anna Taylor', avatarColor: const Color(0xFFE8A838)),
    _InviteContact(id: 'mem_mia', name: 'Mia Johnson', avatarColor: const Color(0xFFFF7575)),
    _InviteContact(id: 'mem_oliver', name: 'Oliver Brown', avatarColor: const Color(0xFF199A85)),
    _InviteContact(id: 'mem_sarah', name: 'Sarah Williams', avatarColor: const Color(0xFFA16AE9)),
    _InviteContact(id: 'mem_mark', name: 'Mark Thompson', avatarColor: const Color(0xFF3580F0)),
    _InviteContact(id: 'mem_david', name: 'David Parker', avatarColor: const Color(0xFFE8A838)),
    _InviteContact(id: 'mem_tom', name: 'Tom Richardson', avatarColor: const Color(0xFF43A047)),
  ];

  static final List<_GroupOption> _sampleGroups = [
    _GroupOption(id: 'grp_mums', name: 'First Time Mums', memberCount: 24, imageUrl: 'https://images.pexels.com/photos/3242264/pexels-photo-3242264.jpeg?auto=compress&cs=tinysrgb&w=100'),
    _GroupOption(id: 'grp_dads', name: 'Dads Connect', memberCount: 18, imageUrl: 'https://images.pexels.com/photos/1648387/pexels-photo-1648387.jpeg?auto=compress&cs=tinysrgb&w=100'),
    _GroupOption(id: 'grp_local', name: 'Local Parents Network', memberCount: 52, imageUrl: 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=100'),
    _GroupOption(id: 'grp_fitness', name: 'Postnatal Fitness', memberCount: 31, imageUrl: 'https://images.pexels.com/photos/3094222/pexels-photo-3094222.jpeg?auto=compress&cs=tinysrgb&w=100'),
  ];

  @override
  void initState() {
    super.initState();
    _onboardingService.initialize();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxAttendeesController.dispose();
    super.dispose();
  }

  bool get _isFormValid =>
      _titleController.text.trim().isNotEmpty &&
      _locationController.text.trim().isNotEmpty;

  // ── Validation ──────────────────────────────────────────────────────
  bool _validateForm() {
    _errors.clear();
    if (_titleController.text.trim().isEmpty) {
      _errors['title'] = 'Please enter a meet-up title';
    }
    if (_locationController.text.trim().isEmpty) {
      _errors['location'] = 'Please enter a location';
    }
    if (_startTime.hour > _endTime.hour ||
        (_startTime.hour == _endTime.hour && _startTime.minute >= _endTime.minute)) {
      _errors['time'] = 'End time must be after start time';
    }
    if (_hasMaxAttendees && _maxAttendeesController.text.isNotEmpty) {
      final max = int.tryParse(_maxAttendeesController.text);
      if (max == null || max < 2) {
        _errors['max'] = 'Must be at least 2 people';
      }
    }
    setState(() {});
    return _errors.isEmpty;
  }

  // ── Date/Time formatting ──
  String _formatDate(DateTime d) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatDateShort(DateTime d) {
    return '${d.day}/${d.month}/${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  String get _repeatDisplayText {
    switch (_repeat) {
      case MeetupRepeat.none: return 'Does not repeat';
      case MeetupRepeat.daily: return 'Every day${_repeatEndDate != null ? ' until ${_formatDateShort(_repeatEndDate!)}' : ''}';
      case MeetupRepeat.weekly:
        if (_repeatWeekDays.isEmpty) return 'Every week';
        const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final days = _repeatWeekDays.map((d) => dayNames[d]).join(', ');
        return 'Weekly on $days';
      case MeetupRepeat.monthly: return 'Monthly on the ${_selectedDate.day}${_daySuffix(_selectedDate.day)}';
      case MeetupRepeat.custom: return 'Every $_customInterval $_customUnit';
    }
  }

  String _daySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  String get _privacyDisplayText {
    switch (_privacy) {
      case MeetupPrivacy.public: return 'Public — visible to everyone';
      case MeetupPrivacy.group: return 'Group${_selectedGroupName != null ? ' — $_selectedGroupName' : ''}';
      case MeetupPrivacy.private_: return 'Private — invite only';
    }
  }

  // ── Date / time pickers ──────────────────────────────────────────
  void _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  void _pickStartTime() async {
    final time = await showTimePicker(
      context: context, initialTime: _startTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: HuddlColors.primary)),
        child: child!,
      ),
    );
    if (time != null) setState(() => _startTime = time);
  }

  void _pickEndTime() async {
    final time = await showTimePicker(
      context: context, initialTime: _endTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: HuddlColors.primary)),
        child: child!,
      ),
    );
    if (time != null) setState(() => _endTime = time);
  }

  // ── Image picker ──────────────────────────────────────────────────
  Future<void> _pickImage() async {
    if (kIsWeb) { await _pickFrom(ImageSource.gallery); return; }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: HuddlColors.divider, borderRadius: BorderRadius.circular(2))),
            Text('Add cover photo', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(width: 44, height: 44, decoration: const BoxDecoration(color: HuddlColors.peachLight, shape: BoxShape.circle),
                child: const Icon(Icons.photo_library_outlined, color: HuddlColors.primary)),
              title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () { Navigator.pop(ctx); _pickFrom(ImageSource.gallery); },
            ),
            ListTile(
              leading: Container(width: 44, height: 44, decoration: const BoxDecoration(color: HuddlColors.peachLight, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_outlined, color: HuddlColors.primary)),
              title: const Text('Take a photo', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () { Navigator.pop(ctx); _pickFrom(ImageSource.camera); },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1200, maxHeight: 800, imageQuality: 85);
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
        setState(() => _pickedImageUrl = 'data:$mimeType;base64,$base64Str');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access photos: $e'), backgroundColor: Colors.red.shade400));
      }
    }
  }

  Widget _buildPickedImage() {
    if (_pickedImageUrl != null && _pickedImageUrl!.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(_pickedImageUrl!);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.camera_alt_outlined, size: 36, color: HuddlColors.primary));
        }
      } catch (_) {}
    }
    return const Icon(Icons.camera_alt_outlined, size: 36, color: HuddlColors.primary);
  }

  Meetup? _createdMeetup;

  // ── Create meetup ──────────────────────────────────────────────────
  void _createMeetup() {
    if (!_validateForm()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Please fix the errors above'),
          backgroundColor: Colors.red.shade400, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      return;
    }

    setState(() => _isCreating = true);

    final organiserName = _onboardingService.name ?? 'You';
    final id = 'mu_${DateTime.now().millisecondsSinceEpoch}';

    final invitees = _selectedInviteeIds.map((invId) {
      final contact = _sampleContacts.firstWhere((c) => c.id == invId);
      return MeetupAttendee(id: contact.id, name: contact.name, status: 'invited');
    }).toList();

    final meetup = Meetup(
      id: id,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? 'Come along! Everyone welcome.' : _descriptionController.text.trim(),
      category: _category,
      dateDisplay: _formatDate(_selectedDate),
      timeDisplay: '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
      dateTime: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startTime.hour, _startTime.minute),
      location: _locationController.text.trim(),
      organiserName: organiserName,
      organiserId: 'current_user',
      attendeeCount: 1,
      maxAttendees: _hasMaxAttendees && _maxAttendeesController.text.isNotEmpty
          ? int.tryParse(_maxAttendeesController.text) : null,
      isGoing: true,
      attendeeNames: [organiserName],
      imageUrl: _pickedImageUrl ?? '',
      privacy: _privacy,
      repeat: _repeat,
      repeatDisplay: _repeat != MeetupRepeat.none ? _repeatDisplayText : null,
      repeatDays: _repeatWeekDays.isNotEmpty ? _repeatWeekDays : null,
      repeatEndDate: _repeatEndDate,
      groupId: _selectedGroupId,
      groupName: _selectedGroupName,
      invitees: invitees,
    );

    _meetupService.createMeetup(meetup);
    _createdMeetup = meetup;

    // Show success step
    setState(() {
      _isCreating = false;
      _currentStep = 3;
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: _currentStep == 3 ? null : AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: Icon(_currentStep == 0 ? Icons.close : Icons.arrow_back, color: HuddlColors.textDark),
          onPressed: () {
            if (_currentStep > 0 && _currentStep < 3) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _currentStep == 0 ? 'Create Meet-up'
              : _currentStep == 1 ? 'Privacy & Repeat'
              : 'Invite People',
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: HuddlColors.textDark),
        ),
        bottom: _currentStep < 3 ? PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Column(children: [
            Container(height: 1, color: HuddlColors.divider),
            // Step indicator
            Container(
              height: 4,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (_currentStep + 1) / 3,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: HuddlColors.primaryGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ]),
        ) : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _currentStep == 0 ? _buildFormStep()
            : _currentStep == 1 ? _buildPrivacyRepeatStep()
            : _currentStep == 2 ? _buildInviteStep()
            : _buildSuccessStep(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // STEP 0 — Form
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildFormStep() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Cover photo ─────────────────────────────────
                  _sectionTitle('Cover photo'),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: double.infinity, height: 160,
                      decoration: BoxDecoration(
                        color: HuddlColors.white, borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HuddlColors.divider)),
                      clipBehavior: Clip.antiAlias,
                      child: _pickedImageUrl != null
                          ? Stack(fit: StackFit.expand, children: [
                              _buildPickedImage(),
                              Positioned(bottom: 8, right: 8, child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.edit, size: 14, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text('Change', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
                                ]),
                              )),
                            ])
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.add_photo_alternate_outlined, size: 40, color: HuddlColors.textHint.withValues(alpha: 0.6)),
                              const SizedBox(height: 8),
                              Text('Add a cover photo', style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint)),
                              const SizedBox(height: 2),
                              Text('Tap to choose from gallery or camera', style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.textHint.withValues(alpha: 0.6))),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Category ────────────────────────────────────
                  _sectionTitle('What kind of meet-up?'),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: _categories.map((cat) {
                    final label = cat['label'] as String;
                    final icon = cat['icon'] as IconData;
                    final color = cat['color'] as Color;
                    final selected = _category == label;
                    return GestureDetector(
                      onTap: () => setState(() => _category = label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected ? color.withValues(alpha: 0.15) : HuddlColors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: selected ? color : HuddlColors.divider, width: selected ? 2 : 1)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 6),
                          Text(label, style: GoogleFonts.poppins(fontSize: 13,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? color : HuddlColors.textSecondary)),
                        ]),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 24),

                  // ── Title ───────────────────────────────────────
                  _sectionTitle('Meet-up title'),
                  if (_errors.containsKey('title')) _errorText(_errors['title']!),
                  const SizedBox(height: 8),
                  _inputField(controller: _titleController, hint: "e.g. Grab a Coffee, Dad's Golf Day...", maxLines: 1, hasError: _errors.containsKey('title')),
                  const SizedBox(height: 20),

                  // ── Description ─────────────────────────────────
                  _sectionTitle('Description (optional)'),
                  const SizedBox(height: 8),
                  _inputField(controller: _descriptionController, hint: 'Tell people what to expect...', maxLines: 4),
                  const SizedBox(height: 20),

                  // ── Date & time ─────────────────────────────────
                  _sectionTitle('When'),
                  if (_errors.containsKey('time')) _errorText(_errors['time']!),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _dateTimeTile(icon: Icons.calendar_today_outlined, label: _formatDate(_selectedDate), onTap: _pickDate)),
                    const SizedBox(width: 8),
                    Expanded(child: _dateTimeTile(icon: Icons.access_time, label: _formatTime(_startTime), onTap: _pickStartTime)),
                    const SizedBox(width: 8),
                    Expanded(child: _dateTimeTile(icon: Icons.access_time, label: _formatTime(_endTime), onTap: _pickEndTime)),
                  ]),
                  const SizedBox(height: 20),

                  // ── Location ────────────────────────────────────
                  _sectionTitle('Where'),
                  if (_errors.containsKey('location')) _errorText(_errors['location']!),
                  const SizedBox(height: 8),
                  _inputField(controller: _locationController, hint: 'e.g. Little Bean Cafe, Fitzroy', maxLines: 1, prefixIcon: Icons.location_on_outlined, hasError: _errors.containsKey('location')),
                  const SizedBox(height: 20),

                  // ── Max attendees ───────────────────────────────
                  Row(children: [
                    Expanded(child: _sectionTitle('Limit attendees?')),
                    Switch(value: _hasMaxAttendees, onChanged: (v) => setState(() => _hasMaxAttendees = v),
                      activeThumbColor: HuddlColors.white, activeTrackColor: HuddlColors.primary),
                  ]),
                  if (_hasMaxAttendees) ...[
                    if (_errors.containsKey('max')) _errorText(_errors['max']!),
                    const SizedBox(height: 8),
                    SizedBox(width: 120, child: _inputField(controller: _maxAttendeesController, hint: 'Max', maxLines: 1,
                      keyboardType: TextInputType.number, prefixIcon: Icons.people_outline, hasError: _errors.containsKey('max'))),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
        // ── Next button ─────────────────────────────────────
        _bottomButton(
          label: 'Next',
          onPressed: () {
            if (_validateForm()) {
              setState(() => _currentStep = 1);
            }
          },
          enabled: _isFormValid,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // STEP 1 — Privacy & Repeat
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildPrivacyRepeatStep() {
    return Column(children: [
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Privacy selection ─────────────────────────────────
          _sectionTitle('Who can see this meet-up?'),
          const SizedBox(height: 12),
          _privacyOption(
            icon: Icons.public, label: 'Public',
            subtitle: 'Visible to everyone in your area',
            value: MeetupPrivacy.public,
          ),
          _privacyOption(
            icon: Icons.group, label: 'Group',
            subtitle: 'Visible to members of a specific group',
            value: MeetupPrivacy.group,
          ),
          _privacyOption(
            icon: Icons.lock_outline, label: 'Private',
            subtitle: 'Only people you invite can see this',
            value: MeetupPrivacy.private_,
          ),

          // ── Group selector (if group privacy) ──────────────────
          if (_privacy == MeetupPrivacy.group) ...[
            const SizedBox(height: 16),
            _sectionTitle('Select a group'),
            const SizedBox(height: 10),
            ..._sampleGroups.map((g) => _groupTile(g)),
          ],

          const SizedBox(height: 32),
          const Divider(color: HuddlColors.divider),
          const SizedBox(height: 20),

          // ── Repeat section ───────────────────────────────────
          Row(children: [
            const Icon(Icons.repeat, size: 20, color: HuddlColors.primary),
            const SizedBox(width: 8),
            Text('Repeat', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
          ]),
          const SizedBox(height: 14),

          _repeatOption(MeetupRepeat.none, 'Does not repeat', Icons.close),
          _repeatOption(MeetupRepeat.daily, 'Every day', Icons.today),
          _repeatOption(MeetupRepeat.weekly, 'Every week', Icons.view_week_outlined),
          _repeatOption(MeetupRepeat.monthly, 'Every month', Icons.calendar_month),
          _repeatOption(MeetupRepeat.custom, 'Custom', Icons.tune),

          // ── Weekly day selector ───────────────────────────────
          if (_repeat == MeetupRepeat.weekly) ...[
            const SizedBox(height: 14),
            Text('Repeat on:', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.textSecondary)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: List.generate(7, (i) {
              const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
              final isSelected = _repeatWeekDays.contains(i);
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSelected) { _repeatWeekDays.remove(i); } else { _repeatWeekDays.add(i); }
                }),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: isSelected ? HuddlColors.primary : HuddlColors.white,
                  child: Text(dayLabels[i], style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : HuddlColors.textSecondary)),
                ),
              );
            })),
          ],

          // ── Custom interval ──────────────────────────────────
          if (_repeat == MeetupRepeat.custom) ...[
            const SizedBox(height: 14),
            Row(children: [
              Text('Every ', style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark)),
              SizedBox(width: 60, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(border: Border.all(color: HuddlColors.divider), borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                  value: _customInterval, isDense: true,
                  items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                  onChanged: (v) => setState(() => _customInterval = v ?? 1),
                )),
              )),
              const SizedBox(width: 8),
              SizedBox(width: 100, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(border: Border.all(color: HuddlColors.divider), borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: _customUnit, isDense: true,
                  items: ['days', 'weeks', 'months'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => setState(() => _customUnit = v ?? 'weeks'),
                )),
              )),
            ]),
          ],

          // ── Repeat end date ──────────────────────────────────
          if (_repeat != MeetupRepeat.none) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final date = await showDatePicker(context: context,
                  initialDate: _repeatEndDate ?? _selectedDate.add(const Duration(days: 30)),
                  firstDate: _selectedDate, lastDate: DateTime.now().add(const Duration(days: 730)),
                  builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(
                    colorScheme: ColorScheme.light(primary: HuddlColors.primary)), child: child!));
                if (date != null) setState(() => _repeatEndDate = date);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HuddlColors.divider)),
                child: Row(children: [
                  const Icon(Icons.event_outlined, size: 18, color: HuddlColors.textHint),
                  const SizedBox(width: 10),
                  Text(_repeatEndDate != null ? 'Ends ${_formatDateShort(_repeatEndDate!)}' : 'Set end date (optional)',
                    style: GoogleFonts.poppins(fontSize: 14, color: _repeatEndDate != null ? HuddlColors.textDark : HuddlColors.textHint)),
                  const Spacer(),
                  if (_repeatEndDate != null) GestureDetector(
                    onTap: () => setState(() => _repeatEndDate = null),
                    child: const Icon(Icons.close, size: 16, color: HuddlColors.textHint)),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ]),
      )),
      _bottomButton(
        label: _privacy == MeetupPrivacy.public && _repeat == MeetupRepeat.none ? 'Create Meet-up' : 'Next',
        onPressed: () {
          if (_privacy == MeetupPrivacy.group && _selectedGroupId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: const Text('Please select a group'), backgroundColor: Colors.red.shade400,
                behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
            return;
          }
          if (_privacy == MeetupPrivacy.private_ || _privacy == MeetupPrivacy.group) {
            setState(() => _currentStep = 2);
          } else {
            _createMeetup();
          }
        },
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════
  // STEP 2 — Invite People
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildInviteStep() {
    final searchController = TextEditingController();
    return StatefulBuilder(builder: (context, setLocalState) {
      final query = searchController.text.toLowerCase();
      final filtered = query.isEmpty ? _sampleContacts
          : _sampleContacts.where((c) => c.name.toLowerCase().contains(query)).toList();

      return Column(children: [
        // ── Search bar ──
        Container(
          color: HuddlColors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(22)),
            child: TextField(
              controller: searchController,
              onChanged: (_) => setLocalState(() {}),
              style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
              decoration: InputDecoration(
                hintText: 'Search people...', hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                prefixIcon: const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
                border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
            ),
          ),
        ),
        // ── Selected count ──
        if (_selectedInviteeIds.isNotEmpty) Container(
          color: HuddlColors.peachLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.check_circle, size: 18, color: HuddlColors.primary),
            const SizedBox(width: 8),
            Text('${_selectedInviteeIds.length} people selected', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
            const Spacer(),
            GestureDetector(
              onTap: () { setState(() => _selectedInviteeIds.clear()); setLocalState(() {}); },
              child: Text('Clear all', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
            ),
          ]),
        ),
        // ── Contact list ──
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final contact = filtered[i];
            final isSelected = _selectedInviteeIds.contains(contact.id);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CircleAvatar(
                backgroundColor: contact.avatarColor,
                child: Text(contact.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              title: Text(contact.name, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: HuddlColors.textDark)),
              trailing: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) { _selectedInviteeIds.remove(contact.id); } else { _selectedInviteeIds.add(contact.id); }
                  });
                  setLocalState(() {});
                },
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: isSelected ? HuddlColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? HuddlColors.primary : HuddlColors.divider, width: 2)),
                  child: isSelected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                ),
              ),
              onTap: () {
                setState(() {
                  if (isSelected) { _selectedInviteeIds.remove(contact.id); } else { _selectedInviteeIds.add(contact.id); }
                });
                setLocalState(() {});
              },
            );
          },
        )),
        _bottomButton(
          label: 'Create Meet-up${_selectedInviteeIds.isNotEmpty ? ' & Invite' : ''}',
          onPressed: _createMeetup,
        ),
      ]);
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // STEP 3 — Success
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildSuccessStep() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                gradient: HuddlColors.primaryGradient, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: HuddlColors.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.check_rounded, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 32),
            Text('Meet-up Created!', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: HuddlColors.textDark)),
            const SizedBox(height: 12),
            Text(
              '"${_titleController.text.trim()}" has been created and ${_selectedInviteeIds.isNotEmpty ? '${_selectedInviteeIds.length} people have been invited' : 'is ready to share'}.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 15, color: HuddlColors.textSecondary, height: 1.5),
            ),
            if (_repeat != MeetupRepeat.none) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: HuddlColors.peachLight, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.repeat, size: 16, color: HuddlColors.primary),
                  const SizedBox(width: 6),
                  Text(_repeatDisplayText, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: HuddlColors.primary)),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: HuddlColors.background, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_privacy == MeetupPrivacy.public ? Icons.public : _privacy == MeetupPrivacy.group ? Icons.group : Icons.lock_outline,
                  size: 16, color: HuddlColors.textSecondary),
                const SizedBox(width: 6),
                Text(_privacyDisplayText, style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.textSecondary)),
              ]),
            ),
            const SizedBox(height: 40),
            SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: HuddlColors.primary, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))),
              child: Text('Done', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.white)),
            )),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                if (_createdMeetup != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetupDetailScreen(meetup: _createdMeetup!),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.visibility_outlined, size: 18, color: HuddlColors.primary),
              label: Text('View Meet-up', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.primary)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                if (_createdMeetup != null) {
                  showForwardSheet(
                    context: context,
                    messageText: 'Join "${_createdMeetup!.title}" on ${_createdMeetup!.dateDisplay} at ${_createdMeetup!.location}',
                  );
                }
              },
              icon: const Icon(Icons.share_outlined, size: 18, color: HuddlColors.teal),
              label: Text('Share with Friends', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.teal)),
            ),
          ]),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ══════════════════════════════════════════════════════════════════════

  Widget _bottomButton({required String label, required VoidCallback onPressed, bool enabled = true}) {
    return Container(
      color: HuddlColors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: HuddlColors.primary,
            disabledBackgroundColor: HuddlColors.divider,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            elevation: 0),
          child: _isCreating
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Text(label, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: HuddlColors.white)),
        ),
      ),
    );
  }

  Widget _privacyOption({required IconData icon, required String label, required String subtitle, required MeetupPrivacy value}) {
    final isSelected = _privacy == value;
    return GestureDetector(
      onTap: () => setState(() {
        _privacy = value;
        if (value != MeetupPrivacy.group) { _selectedGroupId = null; _selectedGroupName = null; }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? HuddlColors.peachLight : HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? HuddlColors.primary : HuddlColors.divider, width: isSelected ? 2 : 1)),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: isSelected ? HuddlColors.primary.withValues(alpha: 0.15) : HuddlColors.background,
              shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: isSelected ? HuddlColors.primary : HuddlColors.textHint),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600,
              color: isSelected ? HuddlColors.primary : HuddlColors.textDark)),
            Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
          ])),
          if (isSelected) const Icon(Icons.check_circle, size: 24, color: HuddlColors.primary),
        ]),
      ),
    );
  }

  Widget _groupTile(_GroupOption group) {
    final isSelected = _selectedGroupId == group.id;
    return GestureDetector(
      onTap: () => setState(() { _selectedGroupId = group.id; _selectedGroupName = group.name; }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? HuddlColors.peachLight : HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? HuddlColors.primary : HuddlColors.divider, width: isSelected ? 2 : 1)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(group.imageUrl, width: 44, height: 44, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 44, height: 44, color: HuddlColors.background,
                child: const Icon(Icons.group, color: HuddlColors.textHint))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(group.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
            Text('${group.memberCount} members', style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.textSecondary)),
          ])),
          if (isSelected) const Icon(Icons.check_circle, size: 22, color: HuddlColors.primary)
          else const Icon(Icons.radio_button_unchecked, size: 22, color: HuddlColors.divider),
        ]),
      ),
    );
  }

  Widget _repeatOption(MeetupRepeat value, String label, IconData icon) {
    final isSelected = _repeat == value;
    return GestureDetector(
      onTap: () => setState(() {
        _repeat = value;
        if (value == MeetupRepeat.none) { _repeatWeekDays.clear(); _repeatEndDate = null; }
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? HuddlColors.peachLight : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? HuddlColors.primary.withValues(alpha: 0.3) : Colors.transparent)),
        child: Row(children: [
          Icon(icon, size: 18, color: isSelected ? HuddlColors.primary : HuddlColors.textHint),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.poppins(fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? HuddlColors.primary : HuddlColors.textDark)),
          const Spacer(),
          if (isSelected) const Icon(Icons.check_circle, size: 20, color: HuddlColors.primary),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: HuddlColors.textDark));

  Widget _errorText(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade600)),
  );

  Widget _inputField({
    required TextEditingController controller, required String hint, int maxLines = 1,
    IconData? prefixIcon, TextInputType? keyboardType, bool hasError = false,
  }) {
    return TextField(
      controller: controller, maxLines: maxLines, keyboardType: keyboardType,
      onChanged: (_) => setState(() { _errors.clear(); }),
      style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
      decoration: InputDecoration(
        hintText: hint, hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20, color: HuddlColors.textHint) : null,
        filled: true, fillColor: HuddlColors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: hasError ? Colors.red : HuddlColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: hasError ? Colors.red : HuddlColors.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: hasError ? Colors.red : HuddlColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
    );
  }

  Widget _dateTimeTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: HuddlColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: HuddlColors.divider)),
        child: Row(children: [
          Icon(icon, size: 16, color: HuddlColors.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: HuddlColors.textDark), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

// ── Helper models ──────────────────────────────────────────────────────────

class _InviteContact {
  final String id;
  final String name;
  final Color avatarColor;
  const _InviteContact({required this.id, required this.name, required this.avatarColor});
}

class _GroupOption {
  final String id;
  final String name;
  final int memberCount;
  final String imageUrl;
  const _GroupOption({required this.id, required this.name, required this.memberCount, required this.imageUrl});
}
