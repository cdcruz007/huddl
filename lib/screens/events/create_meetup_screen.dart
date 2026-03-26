import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../services/meetup_service.dart';
import '../../services/onboarding_data_service.dart';

class CreateMeetupScreen extends StatefulWidget {
  const CreateMeetupScreen({super.key});

  @override
  State<CreateMeetupScreen> createState() => _CreateMeetupScreenState();
}

class _CreateMeetupScreenState extends State<CreateMeetupScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxAttendeesController = TextEditingController();

  String _category = 'Coffee';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 3));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 30);
  bool _hasMaxAttendees = false;
  String? _pickedImageUrl; // base64 data-URI or null
  final _picker = ImagePicker();

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

  bool get _isValid =>
      _titleController.text.trim().isNotEmpty &&
      _locationController.text.trim().isNotEmpty;

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
      context: context,
      initialTime: _startTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _startTime = time);
  }

  void _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: HuddlColors.primary),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _endTime = time);
  }

  String _formatDate(DateTime d) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final min = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  // ── Image picker ──────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    if (kIsWeb) {
      await _pickFrom(ImageSource.gallery);
      return;
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: HuddlColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Add cover photo',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: HuddlColors.textDark)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: HuddlColors.peachLight, shape: BoxShape.circle,
                  ),
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
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: HuddlColors.peachLight, shape: BoxShape.circle,
                  ),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source, maxWidth: 1200, maxHeight: 800, imageQuality: 85,
      );
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        setState(() => _pickedImageUrl = 'data:$mimeType;base64,$base64Str');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access photos: $e'),
              backgroundColor: Colors.red.shade400),
        );
      }
    }
  }

  Widget _buildPickedImage() {
    if (_pickedImageUrl != null && _pickedImageUrl!.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(_pickedImageUrl!);
        final bytes = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.camera_alt_outlined,
                    size: 36, color: HuddlColors.primary),
          );
        }
      } catch (_) {}
    }
    return const Icon(Icons.camera_alt_outlined,
        size: 36, color: HuddlColors.primary);
  }

  void _createMeetup() {
    if (!_isValid) return;

    final organiserName = _onboardingService.name ?? 'You';
    final id = 'mu_${DateTime.now().millisecondsSinceEpoch}';

    final meetup = Meetup(
      id: id,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? 'Come along! Everyone welcome.'
          : _descriptionController.text.trim(),
      category: _category,
      dateDisplay: _formatDate(_selectedDate),
      timeDisplay: '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
      dateTime: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _startTime.hour,
        _startTime.minute,
      ),
      location: _locationController.text.trim(),
      organiserName: organiserName,
      organiserId: 'current_user',
      attendeeCount: 1,
      maxAttendees: _hasMaxAttendees && _maxAttendeesController.text.isNotEmpty
          ? int.tryParse(_maxAttendeesController.text)
          : null,
      isGoing: true,
      attendeeNames: [organiserName],
      imageUrl: _pickedImageUrl ?? '',
    );

    _meetupService.createMeetup(meetup);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${meetup.title} created!'),
        backgroundColor: HuddlColors.teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Meet-up',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover photo picker ─────────────────────────────────
            _sectionTitle('Cover photo'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: HuddlColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: HuddlColors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: _pickedImageUrl != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPickedImage(),
                          Positioned(
                            bottom: 8, right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.edit, size: 14,
                                      color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Change',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 40,
                              color: HuddlColors.textHint.withValues(alpha: 0.6)),
                          const SizedBox(height: 8),
                          Text(
                            'Add a cover photo',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: HuddlColors.textHint,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to choose from gallery or camera',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: HuddlColors.textHint.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Category selector ───────────────────────────────────
            _sectionTitle('What kind of meet-up?'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final label = cat['label'] as String;
                final icon = cat['icon'] as IconData;
                final color = cat['color'] as Color;
                final selected = _category == label;
                return GestureDetector(
                  onTap: () => setState(() => _category = label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.15)
                          : HuddlColors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? color : HuddlColors.divider,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: color),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? color : HuddlColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // ── Title ───────────────────────────────────────────────
            _sectionTitle('Meet-up title'),
            const SizedBox(height: 8),
            _inputField(
              controller: _titleController,
              hint: 'e.g. Grab a Coffee, Dad\'s Golf Day...',
              maxLines: 1,
            ),

            const SizedBox(height: 20),

            // ── Description ─────────────────────────────────────────
            _sectionTitle('Description (optional)'),
            const SizedBox(height: 8),
            _inputField(
              controller: _descriptionController,
              hint: 'Tell people what to expect...',
              maxLines: 4,
            ),

            const SizedBox(height: 20),

            // ── Date & time ─────────────────────────────────────────
            _sectionTitle('When'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _dateTimeTile(
                  icon: Icons.calendar_today_outlined,
                  label: _formatDate(_selectedDate),
                  onTap: _pickDate,
                )),
                const SizedBox(width: 8),
                Expanded(child: _dateTimeTile(
                  icon: Icons.access_time,
                  label: _formatTime(_startTime),
                  onTap: _pickStartTime,
                )),
                const SizedBox(width: 8),
                Expanded(child: _dateTimeTile(
                  icon: Icons.access_time,
                  label: _formatTime(_endTime),
                  onTap: _pickEndTime,
                )),
              ],
            ),

            const SizedBox(height: 20),

            // ── Location ────────────────────────────────────────────
            _sectionTitle('Where'),
            const SizedBox(height: 8),
            _inputField(
              controller: _locationController,
              hint: 'e.g. Little Bean Cafe, Fitzroy',
              maxLines: 1,
              prefixIcon: Icons.location_on_outlined,
            ),

            const SizedBox(height: 20),

            // ── Max attendees (optional) ────────────────────────────
            Row(
              children: [
                Expanded(child: _sectionTitle('Limit attendees?')),
                Switch(
                  value: _hasMaxAttendees,
                  onChanged: (v) => setState(() => _hasMaxAttendees = v),
                  activeColor: HuddlColors.primary,
                ),
              ],
            ),
            if (_hasMaxAttendees) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: 120,
                child: _inputField(
                  controller: _maxAttendeesController,
                  hint: 'Max',
                  maxLines: 1,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.people_outline,
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── Create button ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isValid ? _createMeetup : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: HuddlColors.primary,
                  disabledBackgroundColor: HuddlColors.divider,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Create Meet-up',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: HuddlColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: HuddlColors.textDark,
        ),
      );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    IconData? prefixIcon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 20, color: HuddlColors.textHint)
            : null,
        filled: true,
        fillColor: HuddlColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HuddlColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HuddlColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _dateTimeTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: HuddlColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuddlColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: HuddlColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: HuddlColors.textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
