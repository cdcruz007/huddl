import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';

/// Data model for a created poll
class PollData {
  final String question;
  final List<String> options;
  final DateTime? expiresAt;
  final bool allowMultiple;
  final bool isCalendarMode;

  PollData({
    required this.question,
    required this.options,
    this.expiresAt,
    this.allowMultiple = false,
    this.isCalendarMode = false,
  });
}

/// Screen for creating a poll in a group chat.
/// Returns [PollData] on success, null on cancel.
class CreatePollScreen extends StatefulWidget {
  final String groupName;

  const CreatePollScreen({super.key, required this.groupName});

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowMultiple = false;
  bool _isCalendarMode = false;
  DateTime? _expiresAt;

  /// Selected date/time for each option (calendar mode)
  final List<DateTime?> _optionDates = [null, null];

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canCreate {
    if (_questionCtrl.text.trim().isEmpty) return false;
    if (_isCalendarMode) {
      final filled = _optionDates.where((d) => d != null).length;
      return filled >= 2;
    } else {
      final filled =
          _optionCtrls.where((c) => c.text.trim().isNotEmpty).length;
      return filled >= 2;
    }
  }

  void _addOption() {
    if (_optionCtrls.length >= 8) return;
    setState(() {
      _optionCtrls.add(TextEditingController());
      _optionDates.add(null);
    });
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
      _optionDates.removeAt(index);
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: HuddlColors.primary,
              onPrimary: HuddlColors.white,
              surface: HuddlColors.white,
              onSurface: HuddlColors.textDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null || !mounted) return;

    final time = await showSimpleTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _expiresAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    setState(() {
      _expiresAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// Show a Cupertino-style date/time picker for a specific option index
  void _pickOptionDate(int index) {
    final initial = _optionDates[index] ?? DateTime.now().add(const Duration(hours: 1));
    DateTime tempDate = initial;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: context.hc.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with Done button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.hc.divider)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          color: context.hc.textTertiary,
                        ),
                      ),
                    ),
                    Text(
                      'Choose date and time',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.hc.textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _optionDates[index] = tempDate;
                        });
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        'Done',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Cupertino date picker
              SizedBox(
                height: 220,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: initial,
                  minimumDate: DateTime.now(),
                  use24hFormat: true,
                  onDateTimeChanged: (DateTime newDate) {
                    tempDate = newDate;
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _create() {
    List<String> options;

    if (_isCalendarMode) {
      options = _optionDates
          .where((d) => d != null)
          .map((d) => _formatDateTime(d!))
          .toList();
    } else {
      options = _optionCtrls
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    if (_questionCtrl.text.trim().isEmpty || options.length < 2) return;

    Navigator.pop(
      context,
      PollData(
        question: _questionCtrl.text.trim(),
        options: options,
        expiresAt: _expiresAt,
        allowMultiple: _allowMultiple,
        isCalendarMode: _isCalendarMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: HuddlColors.white,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Poll',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.hc.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _canCreate ? _create : null,
              child: Text(
                'POST',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color:
                      _canCreate ? HuddlColors.primary : HuddlColors.textHint,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Group context
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HuddlColors.peachLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.people_outline,
                    size: 18, color: HuddlColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Poll for: ${widget.groupName}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Question
          Text(
            'What is your question?',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _buildField(
            controller: _questionCtrl,
            hint: 'e.g. When do we meet?',
            maxLines: 3,
          ),
          const SizedBox(height: 20),

          // ── Calendar toggle ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.hc.divider),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: _isCalendarMode
                      ? HuddlColors.primary
                      : HuddlColors.textHint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Calendar',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  value: _isCalendarMode,
                  onChanged: (v) => setState(() => _isCalendarMode = v),
                  activeThumbColor: HuddlColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Options
          Text(
            'Options',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(_optionCtrls.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: HuddlColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _isCalendarMode
                        ? _buildCalendarOptionField(i)
                        : _buildField(
                            controller: _optionCtrls[i],
                            hint: 'Option ${i + 1}',
                          ),
                  ),
                  if (_optionCtrls.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 22, color: HuddlColors.error),
                      onPressed: () => _removeOption(i),
                    ),
                ],
              ),
            );
          }),
          if (_optionCtrls.length < 8)
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add_circle_outline,
                  size: 20, color: HuddlColors.primary),
              label: Text(
                'Add poll option',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: HuddlColors.primary,
                ),
              ),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            ),
          const SizedBox(height: 20),

          // Expiration date
          Text(
            'Expiration date',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.hc.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickExpiry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: context.hc.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.hc.divider),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                    color: _expiresAt != null
                        ? HuddlColors.primary
                        : HuddlColors.textHint,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _expiresAt != null
                        ? _formatExpiry(_expiresAt!)
                        : 'Choose date and time',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _expiresAt != null
                          ? HuddlColors.textDark
                          : HuddlColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  if (_expiresAt != null)
                    GestureDetector(
                      onTap: () => setState(() => _expiresAt = null),
                      child: Icon(Icons.close,
                          size: 18, color: context.hc.textTertiary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Allow multiple answers toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: context.hc.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.hc.divider),
            ),
            child: Row(
              children: [
                Icon(Icons.check_box_outlined,
                    size: 20, color: context.hc.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Allow multiple answers',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: context.hc.textPrimary),
                  ),
                ),
                Switch(
                  value: _allowMultiple,
                  onChanged: (v) => setState(() => _allowMultiple = v),
                  activeThumbColor: HuddlColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          // Create button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _canCreate ? _create : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                disabledBackgroundColor:
                    HuddlColors.primary.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
                elevation: 0,
              ),
              child: Text(
                'Create Poll',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.hc.surface,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Calendar option field — tappable date/time selector
  Widget _buildCalendarOptionField(int index) {
    final date = _optionDates[index];
    return GestureDetector(
      onTap: () => _pickOptionDate(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.hc.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.hc.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date != null
                    ? _formatDateTime(date)
                    : 'Choose date and time',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: date != null
                      ? HuddlColors.textDark
                      : HuddlColors.textHint,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 20,
              color: date != null ? HuddlColors.primary : context.hc.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.hc.divider),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style:
            GoogleFonts.poppins(fontSize: 14, color: context.hc.textPrimary),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              GoogleFonts.poppins(fontSize: 14, color: context.hc.textTertiary),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  String _formatExpiry(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }

  String _formatDateTime(DateTime dt) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dayName = days[dt.weekday - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$dayName ${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }
}
