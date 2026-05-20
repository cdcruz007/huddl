import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/image_editor_widget.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/default_group_service.dart';
import '../../services/browser_storage.dart';
import '../../widgets/huddl_widgets.dart';
import '../../models/group.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/places_autocomplete_field.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EDIT MEETUP — pre-populated form using existing meetup data
// Same field layout and validation as Create Meetup.
// ═══════════════════════════════════════════════════════════════════════════════

class EditMeetupScreen extends StatefulWidget {
  final Meetup meetup;
  const EditMeetupScreen({super.key, required this.meetup});

  @override
  State<EditMeetupScreen> createState() => _EditMeetupScreenState();
}

class _EditMeetupScreenState extends State<EditMeetupScreen> {
  // ── Controllers ──
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _attendeesCtrl;
  final _scrollController = ScrollController();

  // ── Form state ──
  late Set<String> _selectedCategories;
  late DateTime? _selectedDate;
  late TimeOfDay? _startTime;
  late TimeOfDay? _endTime;
  late bool _isFree;
  late bool _isOnline;
  late bool _repeatOn;
  late String _repeatFrequency;
  late String? _pickedImageUrl;
  bool _isSaving = false;
  late int? _maxAttendees;

  // ── Participants ──
  late Map<String, bool> _participants;

  // ── Privacy ──
  late String _privacy;
  String? _selectedGroupId;
  String? _selectedGroupName;
  List<Group> _userGroups = [];

  // ── Track whether any field has been changed ──
  bool _isDirty = false;

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
    'Does not repeat', 'Every day', 'Every week', 'Every 2 weeks', 'Every month',
  ];

  // Reverse mapping from short code back to display label for pre-population
  static const _codeLabelMap = {
    'Coffee': 'Coffee & tea',
    'Playdate': 'Playdate',
    'Sport': 'Sports & exercise',
    'Walk': 'Parks & Walks',
    'Social': 'Hanging out',
    'Food': 'Food & nutrition',
    'Other': 'Other',
  };

  final _meetupService = MeetupService();
  final _groupService = DefaultGroupService();

  // ── Design tokens ──
  static const _bannerBlue   = HuddlColors.blueUI;
  static const _accentOrange = HuddlColors.primary;
  static const _accentBlue   = HuddlColors.blueUI;
  static const _fieldBg      = HuddlColors.background;
  static const _fieldLine    = HuddlColors.divider;
  static const _sectionText  = HuddlColors.textDark;
  static const _hintGray     = HuddlColors.textTertiary;
  static const _pillBorder   = HuddlColors.divider;

  @override
  void initState() {
    super.initState();
    _populateFromMeetup();
    _loadUserGroups();
  }

  void _populateFromMeetup() {
    final m = widget.meetup;

    _titleCtrl = TextEditingController(text: m.title);
    _descriptionCtrl = TextEditingController(text: m.description == 'Come along! Everyone welcome.' ? '' : m.description);
    _locationCtrl = TextEditingController(text: m.location == 'Online' ? '' : m.location);
    _priceCtrl = TextEditingController(text: m.price != null && !m.isFree ? m.price.toString() : '');
    _attendeesCtrl = TextEditingController(text: m.maxAttendees?.toString() ?? '');
    _maxAttendees = m.maxAttendees;

    _isFree = m.isFree;
    _isOnline = m.isOnline || m.location.toLowerCase() == 'online';
    _selectedDate = m.dateTime;
    _pickedImageUrl = m.imageUrl.isNotEmpty ? m.imageUrl : null;

    // Reverse-map category code to display label
    final displayLabel = _codeLabelMap[m.category] ?? 'Other';
    _selectedCategories = {displayLabel};

    // Privacy
    switch (m.privacy) {
      case MeetupPrivacy.group:
        _privacy = 'group';
        _selectedGroupId = m.groupId;
        _selectedGroupName = m.groupName;
        break;
      case MeetupPrivacy.private_:
        _privacy = 'private';
        break;
      case MeetupPrivacy.public:
        _privacy = 'public';
        break;
    }

    // Repeat
    _repeatOn = m.repeat != MeetupRepeat.none;
    _repeatFrequency = m.repeatDisplay ?? 'Every week';

    // Parse start/end time from timeDisplay (e.g. "10:00 AM - 3:00 PM")
    _startTime = null;
    _endTime = null;
    final timeParts = m.timeDisplay.split(' - ');
    if (timeParts.isNotEmpty) _startTime = _parseTimeOfDay(timeParts[0].trim());
    if (timeParts.length > 1) _endTime = _parseTimeOfDay(timeParts[1].trim());

    // Participants
    _participants = {
      'Mums': m.targetAudience.contains('Mums'),
      'Dads': m.targetAudience.contains('Dads'),
      'Aspiring parents': m.targetAudience.contains('Aspiring parents'),
      'Expecting parents': m.targetAudience.contains('Expecting parents'),
      'Kids': m.targetAudience.contains('Kids'),
    };
  }

  TimeOfDay? _parseTimeOfDay(String s) {
    try {
      final parts = s.split(':');
      if (parts.length < 2) return null;
      final hour12 = int.parse(parts[0].trim());
      final rest = parts[1].split(' ');
      final minute = int.parse(rest[0]);
      final isPm = rest.length > 1 && rest[1].toUpperCase() == 'PM';
      final hour24 = isPm ? (hour12 == 12 ? 12 : hour12 + 12) : (hour12 == 12 ? 0 : hour12);
      return TimeOfDay(hour: hour24, minute: minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadUserGroups() async {
    await _groupService.initialize();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final defaultGroups = await _groupService.getUserGroups(uid);
    List<Group> discovered = [];
    try {
      final discoveredJson = await BrowserStorage.getString('user_created_groups_v1');
      if (discoveredJson != null) {
        final List<dynamic> decoded = json.decode(discoveredJson);
        discovered = decoded.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _userGroups = [...defaultGroups, ...discovered]);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _locationCtrl.dispose();
    _priceCtrl.dispose();
    _attendeesCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Helpers ──
  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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
      _selectedCategories.isNotEmpty;

  // ── Pickers ──
  void _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: HuddlColors.primary)),
        child: child!,
      ),
    );
    if (date != null) setState(() { _selectedDate = date; _isDirty = true; });
  }

  void _pickStartTime() async {
    final time = await showSimpleTimePicker(context: context, initialTime: _startTime ?? const TimeOfDay(hour: 10, minute: 0));
    if (time != null) setState(() { _startTime = time; _isDirty = true; });
  }

  void _pickEndTime() async {
    final time = await showSimpleTimePicker(context: context, initialTime: _endTime ?? const TimeOfDay(hour: 15, minute: 0));
    if (time != null) {
      if (_startTime != null) {
        final startMins = _startTime!.hour * 60 + _startTime!.minute;
        final endMins = time.hour * 60 + time.minute;
        if (endMins <= startMins) {
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
      setState(() { _endTime = time; _isDirty = true; });
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImageEditorWidget.pickMeetupImage(context);
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
        setState(() {
          _pickedImageUrl = 'data:$mimeType;base64,$base64Str';
          _isDirty = true;
        });
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
          return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _photoPlaceholder());
        }
      } catch (_) {}
    }
    if (_pickedImageUrl != null && _pickedImageUrl!.isNotEmpty) {
      return Image.network(_pickedImageUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _photoPlaceholder());
    }
    return _photoPlaceholder();
  }

  // ── Save ──
  Future<void> _saveMeetup() async {
    if (!_isFormValid || _isSaving) return;
    setState(() => _isSaving = true);

    final st = _startTime ?? const TimeOfDay(hour: 10, minute: 0);
    final et = _endTime ?? const TimeOfDay(hour: 15, minute: 0);
    final date = _selectedDate ?? DateTime.now().add(const Duration(days: 1));

    const dayAbbr  = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
    const monthAbbr = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

    String mappedCategory = _selectedCategories.map((c) {
      switch (c) {
        case 'Coffee & tea':        return 'Coffee';
        case 'Playdate':            return 'Playdate';
        case 'Sports & exercise':   return 'Sport';
        case 'Parks & Walks':       return 'Walk';
        case 'Food & nutrition':    return 'Food';
        default:                    return 'Social';
      }
    }).first;

    MeetupRepeat repeat = MeetupRepeat.none;
    if (_repeatOn) {
      if (_repeatFrequency == 'Every day') {
        repeat = MeetupRepeat.daily;
      } else if (_repeatFrequency == 'Every week' || _repeatFrequency == 'Every 2 weeks') {
        repeat = MeetupRepeat.weekly;
      } else if (_repeatFrequency == 'Every month') {
        repeat = MeetupRepeat.monthly;
      }
    }

    MeetupPrivacy privacy = MeetupPrivacy.public;
    if (_privacy == 'group') privacy = MeetupPrivacy.group;
    if (_privacy == 'private') privacy = MeetupPrivacy.private_;

    final updated = Meetup(
      id: widget.meetup.id,
      title: _titleCtrl.text.trim(),
      description: _descriptionCtrl.text.trim().isEmpty
          ? 'Come along! Everyone welcome.'
          : _descriptionCtrl.text.trim(),
      category: mappedCategory,
      dateDisplay: '${dayAbbr[date.weekday - 1]}, ${monthAbbr[date.month - 1]} ${date.day}',
      timeDisplay: '${_formatTime(st)} - ${_formatTime(et)}',
      dateTime: DateTime(date.year, date.month, date.day, st.hour, st.minute),
      location: _isOnline ? 'Online' : _locationCtrl.text.trim(),
      organiserName: widget.meetup.organiserName,
      organiserId: widget.meetup.organiserId,
      attendeeCount: widget.meetup.attendeeCount,
      maxAttendees: _maxAttendees,
      isGoing: widget.meetup.isGoing,
      isFree: _isFree,
      price: _isFree ? null : double.tryParse(_priceCtrl.text.replaceAll('£', '').trim()),
      attendeeNames: widget.meetup.attendeeNames,
      imageUrl: _pickedImageUrl ?? widget.meetup.imageUrl,
      privacy: privacy,
      repeat: repeat,
      repeatDisplay: _repeatOn ? _repeatFrequency : null,
      groupId: _selectedGroupId,
      groupName: _selectedGroupName,
      invitedMemberIds: widget.meetup.invitedMemberIds,
      isOnline: _isOnline,
      borough: widget.meetup.borough,
      targetAudience: _participants.entries.where((e) => e.value).map((e) => e.key).toList(),
      createdAt: widget.meetup.createdAt,
    );

    _meetupService.updateMeetup(updated);

    setState(() => _isSaving = false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        const Expanded(child: Text('Meetup updated!')),
      ]),
      backgroundColor: HuddlColors.teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    Navigator.pop(context, updated);
  }

  // ── Back navigation with discard guard ──
  bool get _hasUnsavedChanges => _isDirty;

  void _handleBack() {
    if (_hasUnsavedChanges) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.hc.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Discard changes?', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          content: Text('Your edits will be lost if you go back now.', style: GoogleFonts.poppins(fontSize: 14, color: _hintGray)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Keep editing', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: _accentOrange)),
            ),
            TextButton(
              onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
              child: Text('Discard', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: HuddlColors.error)),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════════════
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
                            onChanged: (_) => setState(() => _isDirty = true),
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
                            onChanged: (v) => setState(() {
                              _maxAttendees = int.tryParse(v);
                              _isDirty = true;
                            }),
                          ),
                          const SizedBox(height: 20),
                          _sectionHeader('Privacy settings'),
                          const SizedBox(height: 10),
                          _buildPrivacySection(),
                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildSaveCTA(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      automaticallyImplyLeading: false,
      leading: GestureDetector(
        onTap: _handleBack,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.arrow_back_ios, size: 18, color: _accentOrange),
          ),
        ),
      ),
      centerTitle: true,
      title: Text(
        'Edit meetup',
        style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: _sectionText),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: context.hc.divider),
      ),
    );
  }

  Widget _buildSaveCTA() {
    final canSave = _isFormValid && _isDirty && !_isSaving;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
      child: GestureDetector(
        onTap: canSave ? _saveMeetup : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: canSave
                ? const LinearGradient(
                    colors: [HuddlColors.primaryLight, HuddlColors.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: canSave ? null : HuddlColors.divider,
            borderRadius: BorderRadius.circular(26),
            boxShadow: canSave
                ? [BoxShadow(color: HuddlColors.primary.withValues(alpha: 0.30), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Center(
            child: _isSaving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(
                    'Save changes',
                    style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600,
                      color: canSave ? Colors.white : HuddlColors.textTertiary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(text, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: _sectionText));
  }

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
        style: GoogleFonts.poppins(fontSize: 15, color: _sectionText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(fontSize: 15, color: _hintGray),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          counterText: '',
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  child: Icon(Icons.location_on_outlined, size: 20, color: _accentOrange),
                ),
                Expanded(
                  child: PlacesAutocompleteField(
                    controller: _locationCtrl,
                    accentColor: _accentOrange,
                    onPlaceSelected: (address) {
                      setState(() => _isDirty = true);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _accentOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accentOrange.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi, size: 18, color: _accentOrange),
                const SizedBox(width: 10),
                Text('Online meetup', style: GoogleFonts.poppins(fontSize: 14, color: _accentOrange, fontWeight: FontWeight.w500)),
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
                  setState(() { _isOnline = v; _isDirty = true; if (v) _locationCtrl.clear(); });
                },
              ),
            ),
            const SizedBox(width: 6),
            Text('Online meetup', style: GoogleFonts.poppins(fontSize: 14, color: _sectionText)),
          ],
        ),
      ],
    );
  }

  Widget _buildDateBlock() {
    return Column(
      children: [
        _buildIconRightTapField(
          value: _selectedDate != null ? _formatDate(_selectedDate!) : null,
          hint: 'Date',
          icon: Icons.calendar_today_outlined,
          onTap: _pickDate,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildIconRightTapField(
              value: _startTime != null ? _formatTime(_startTime!) : null,
              hint: 'From',
              icon: Icons.access_time_outlined,
              onTap: _pickStartTime,
            )),
            const SizedBox(width: 12),
            Expanded(child: _buildIconRightTapField(
              value: _endTime != null ? _formatTime(_endTime!) : null,
              hint: 'To',
              icon: Icons.access_time_outlined,
              onTap: _pickEndTime,
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildIconRightTapField({required String? value, required String hint, required IconData icon, required VoidCallback onTap}) {
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
            Expanded(child: Text(
              hasValue ? value : hint,
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: hasValue ? _sectionText : _hintGray,
                fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
              ),
            )),
            Icon(icon, size: 18, color: _accentOrange),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Repeat', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: _sectionText)),
            Transform.scale(
              scale: 0.85,
              child: CupertinoSwitch(
                value: _repeatOn,
                activeTrackColor: _accentOrange,
                onChanged: (v) => setState(() { _repeatOn = v; _isDirty = true; }),
              ),
            ),
          ],
        ),
        if (_repeatOn) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: const BoxDecoration(color: _fieldBg, border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2))),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _repeatFrequency,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down, color: _sectionText.withValues(alpha: 0.6)),
                style: GoogleFonts.poppins(fontSize: 15, color: _sectionText),
                items: _repeatOptions.where((o) => o != 'Does not repeat').map((o) =>
                    DropdownMenuItem(value: o, child: Text(o, style: GoogleFonts.poppins(fontSize: 15, color: _sectionText)))).toList(),
                onChanged: (v) { if (v != null) setState(() { _repeatFrequency = v; _isDirty = true; }); },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() { _isFree = !_isFree; if (_isFree) _priceCtrl.clear(); _isDirty = true; }),
          child: Row(
            children: [
              _squareCheckbox(_isFree),
              const SizedBox(width: 12),
              Text('Free', style: GoogleFonts.poppins(fontSize: 15, color: _sectionText)),
            ],
          ),
        ),
        if (!_isFree) ...[
          const SizedBox(height: 10),
          Container(
            decoration: const BoxDecoration(color: _fieldBg, border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2))),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text('£', style: GoogleFonts.poppins(fontSize: 15, color: _sectionText.withValues(alpha: 0.6))),
                ),
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.poppins(fontSize: 15, color: _sectionText),
                    decoration: InputDecoration(
                      hintText: ' Price',
                      hintStyle: GoogleFonts.poppins(fontSize: 15, color: _hintGray),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() => _isDirty = true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: const BoxDecoration(color: _fieldBg, border: Border(bottom: BorderSide(color: _fieldLine, width: 1.2))),
      child: TextField(
        controller: _descriptionCtrl,
        maxLines: 5,
        minLines: 3,
        style: GoogleFonts.poppins(fontSize: 14, color: _sectionText),
        decoration: InputDecoration(
          hintText: 'Meetup description',
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: _hintGray),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
        onChanged: (_) => setState(() => _isDirty = true),
      ),
    );
  }

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
            _selectedCategories.clear();
            if (!selected) _selectedCategories.add(label);
            _isDirty = true;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? _accentBlue : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? _accentBlue : _pillBorder, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: selected ? Colors.white : _accentBlue),
                const SizedBox(width: 6),
                Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: selected ? Colors.white : _sectionText)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildParticipantsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._participants.keys.map((key) {
          final checked = _participants[key]!;
          return GestureDetector(
            onTap: () => setState(() { _participants[key] = !checked; _isDirty = true; }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _squareCheckbox(checked),
                  const SizedBox(width: 14),
                  Text(key, style: GoogleFonts.poppins(fontSize: 15, color: _sectionText)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPrivacySection() {
    return Column(
      children: [
        _privacyRadioTile(value: 'public', icon: Icons.public, title: 'Public', subtitle: 'Everyone in your local authority can see and join your event.'),
        _privacyRadioTile(value: 'group', icon: Icons.group_outlined, title: 'Group', subtitle: 'Only members of a specific group can see and join your event.'),
        if (_privacy == 'group' && _userGroups.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 34, bottom: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedGroupId,
                isExpanded: true,
                hint: Text('Select a group', style: GoogleFonts.poppins(fontSize: 14, color: _hintGray)),
                items: _userGroups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name, style: GoogleFonts.poppins(fontSize: 14)))).toList(),
                onChanged: (id) {
                  final group = _userGroups.firstWhere((g) => g.id == id, orElse: () => _userGroups.first);
                  setState(() { _selectedGroupId = id; _selectedGroupName = group.name; _isDirty = true; });
                },
              ),
            ),
          ),
        ],
        _privacyRadioTile(value: 'private', icon: Icons.lock_outline, title: 'Private', subtitle: 'Invite specific friends.'),
      ],
    );
  }

  Widget _privacyRadioTile({required String value, required IconData icon, required String title, required String subtitle}) {
    final selected = _privacy == value;
    return GestureDetector(
      onTap: () => setState(() {
        _privacy = value;
        _isDirty = true;
        if (value != 'group') { _selectedGroupId = null; _selectedGroupName = null; }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? _accentOrange : _pillBorder, width: selected ? 2 : 1.5),
                ),
                child: selected
                    ? Center(child: Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: _accentOrange)))
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: _sectionText)),
                  Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: _hintGray)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Square checkbox (Figma style) ──
  Widget _squareCheckbox(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 26, height: 26,
      decoration: BoxDecoration(
        color: checked ? _accentOrange : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: checked ? _accentOrange : _pillBorder, width: 1.5),
      ),
      child: checked
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  // ── Photo upload section ──
  Widget _buildPhotoUpload() {
    return GestureDetector(
      onTap: _pickImage,
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: _pickedImageUrl != null ? _buildPickedImage() : _photoPlaceholder(),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: const BoxDecoration(color: _bannerBlue),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_photo_alternate_outlined, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text('Click to add photo', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}
