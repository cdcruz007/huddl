import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';

/// Data model for a created poll
class PollData {
  final String question;
  final List<String> options;
  final DateTime? expiresAt;
  final bool allowMultiple;

  PollData({
    required this.question,
    required this.options,
    this.expiresAt,
    this.allowMultiple = false,
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
  DateTime? _expiresAt;

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
    final filled = _optionCtrls.where((c) => c.text.trim().isNotEmpty).length;
    return filled >= 2;
  }

  void _addOption() {
    if (_optionCtrls.length >= 8) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
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

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          _expiresAt ?? now.add(const Duration(hours: 1))),
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
    if (time == null || !mounted) return;

    setState(() {
      _expiresAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  void _create() {
    final options = _optionCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (_questionCtrl.text.trim().isEmpty || options.length < 2) return;

    Navigator.pop(
      context,
      PollData(
        question: _questionCtrl.text.trim(),
        options: options,
        expiresAt: _expiresAt,
        allowMultiple: _allowMultiple,
      ),
    );
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
          'Create Poll',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _canCreate ? _create : null,
              child: Text(
                'Create',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _canCreate ? HuddlColors.primary : HuddlColors.textHint,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
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
                const Icon(Icons.people_outline, size: 18, color: HuddlColors.primary),
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
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          _buildField(
            controller: _questionCtrl,
            hint: 'e.g. What time works best?',
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Options
          Text(
            'Options',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: HuddlColors.textDark,
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
                    child: _buildField(
                      controller: _optionCtrls[i],
                      hint: 'Option ${i + 1}',
                    ),
                  ),
                  if (_optionCtrls.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 22, color: Colors.red),
                      onPressed: () => _removeOption(i),
                    ),
                ],
              ),
            );
          }),
          if (_optionCtrls.length < 8)
            TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add_circle_outline, size: 20, color: HuddlColors.primary),
              label: Text(
                'Add option',
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
              color: HuddlColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickExpiry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: HuddlColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: HuddlColors.divider),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 20,
                    color: _expiresAt != null ? HuddlColors.primary : HuddlColors.textHint,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _expiresAt != null ? _formatExpiry(_expiresAt!) : 'Set expiration (optional)',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: _expiresAt != null ? HuddlColors.textDark : HuddlColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  if (_expiresAt != null)
                    GestureDetector(
                      onTap: () => setState(() => _expiresAt = null),
                      child: const Icon(Icons.close, size: 18, color: HuddlColors.textHint),
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
              color: HuddlColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: HuddlColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_box_outlined, size: 20, color: HuddlColors.textHint),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Allow multiple answers',
                    style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
                  ),
                ),
                Switch(
                  value: _allowMultiple,
                  onChanged: (v) => setState(() => _allowMultiple = v),
                  activeColor: HuddlColors.primary,
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
                disabledBackgroundColor: HuddlColors.primary.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                elevation: 0,
              ),
              child: Text(
                'Create Poll',
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
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.divider),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  String _formatExpiry(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$m';
  }
}
