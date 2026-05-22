// ═══════════════════════════════════════════════════════════════════════════
// EDIT GROUP SCREEN — Section 6B
// Admin-only screen to edit group name, description, audience, privacy,
// and group photo. Accessed via Group Detail → ⋮ → "Edit group".
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/image_editor_widget.dart';

class EditGroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupDescription;
  final String groupImageUrl;
  final bool isPrivate;
  /// Called when Save succeeds — passes new name, description, and imageUrl
  /// so the Group Detail screen can update its local state without a reload.
  final void Function(String newName, String newDescription,
      {String? newImageUrl})? onGroupUpdated;

  const EditGroupScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupDescription,
    required this.groupImageUrl,
    required this.isPrivate,
    this.onGroupUpdated,
  });

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  // Who is this group for? — loaded from Firestore on init
  final Set<String> _selectedAudience = {};
  static const _audienceOptions = [
    'Aspiring parents',
    'Parents expecting a baby',
    'Mums',
    'Dads',
  ];

  // Privacy
  String _privacy = 'public'; // 'public' | 'group' | 'private'

  // ── Photo state ───────────────────────────────────────────────────────────
  /// Non-null only when the admin has picked a new image this session.
  /// Stored as a base64 data-URI (same pattern as CreateGroupScreen).
  String? _newImageDataUri;
  bool _isUploadingImage = false;

  bool _isLoading = true;
  bool _isSaving  = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.groupName);
    _descCtrl = TextEditingController(text: widget.groupDescription);
    _nameCtrl.addListener(_onFieldChanged);
    _descCtrl.addListener(_onFieldChanged);
    _loadGroupData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final textChanged = _nameCtrl.text.trim() != widget.groupName ||
        _descCtrl.text.trim() != widget.groupDescription;
    if (textChanged != _hasChanges) setState(() => _hasChanges = textChanged);
  }

  Future<void> _loadGroupData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();
      if (!mounted) return;
      final data = doc.data() ?? {};
      final audience = List<String>.from(data['targetAudience'] ?? []);
      final privacy  = (data['privacy'] as String?) ??
          (widget.isPrivate ? 'private' : 'public');
      setState(() {
        _selectedAudience.addAll(audience);
        _privacy   = privacy;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.hc.divider, borderRadius: BorderRadius.circular(2)),
            ),
            Text('Change group photo',
              style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w700, color: context.hc.textPrimary)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: HuddlColors.background,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.photo_library_outlined, color: HuddlColors.textDark),
              ),
              title: Text('Choose from gallery',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                _pickFrom(ImageSource.gallery);
              },
            ),
            // Camera is only useful on real devices; skip on web
            if (!kIsWeb)
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: HuddlColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_outlined, color: HuddlColors.textDark),
                ),
                title: Text('Take a photo',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFrom(ImageSource.camera);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFrom(ImageSource source) async {
    setState(() => _isUploadingImage = true);
    try {
      final file = await ImageEditorWidget.pickGroupImageWithSource(context, source);
      if (file != null && mounted) {
        final bytes   = await file.readAsBytes();
        final base64  = base64Encode(bytes);
        final mime    = file.path.toLowerCase().endsWith('.png')
            ? 'image/png' : 'image/jpeg';
        setState(() {
          _newImageDataUri = 'data:$mime;base64,$base64';
          _hasChanges = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not update image: $e'),
          backgroundColor: HuddlColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // ── Discard confirmation ──────────────────────────────────────────────────

  void _onAudienceToggle(String option) {
    setState(() {
      _selectedAudience.contains(option)
          ? _selectedAudience.remove(option)
          : _selectedAudience.add(option);
      _hasChanges = true;
    });
  }

  void _onPrivacyChanged(String? value) {
    if (value == null) return;
    setState(() { _privacy = value; _hasChanges = true; });
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Discard changes?',
                style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: context.hc.textPrimary),
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('Your edits won\'t be saved.',
                style: GoogleFonts.poppins(
                  fontSize: 14, color: context.hc.textSecondary, height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text('Keep editing',
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: context.hc.textSecondary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text('Discard',
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: HuddlColors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return discard ?? false;
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      final Map<String, dynamic> update = {
        'name':          name,
        'description':   _descCtrl.text.trim(),
        'targetAudience': _selectedAudience.toList(),
        'privacy':       _privacy,
        'updatedAt':     FieldValue.serverTimestamp(),
        'updatedBy':     uid ?? '',
      };

      // Include new image if one was picked
      if (_newImageDataUri != null) {
        update['imageUrl'] = _newImageDataUri!;
      }

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .update(update);

      widget.onGroupUpdated?.call(
        name,
        _descCtrl.text.trim(),
        newImageUrl: _newImageDataUri,
      );

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Group updated successfully.'),
              ],
            ),
            backgroundColor: HuddlColors.nearBlack,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save changes. Please try again.'),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: context.hc.scaffold,
        appBar: AppBar(
          backgroundColor: context.hc.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) Navigator.pop(context);
            },
          ),
          title: Text(
            'Edit group',
            style: GoogleFonts.poppins(
              fontSize: 17, fontWeight: FontWeight.w600,
              color: context.hc.textPrimary),
          ),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: context.hc.divider),
          ),
        ),
        bottomNavigationBar: Container(
          color: context.hc.surface,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (!_hasChanges || _isSaving) ? null : _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                disabledBackgroundColor:
                    HuddlColors.primary.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      'Save changes',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: HuddlColors.textTertiary))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Group photo (tappable to change) ──────────────────
                      _buildPhotoSection(),
                      const SizedBox(height: 24),

                      // ── Group title ───────────────────────────────────────
                      _sectionLabel('Group title'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.poppins(
                            fontSize: 15, color: context.hc.textPrimary),
                        decoration: _inputDecoration(
                            'e.g. Hackney Toddler Playgroup'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Group title is required'
                            : null,
                        maxLength: 80,
                        onTap: () => HapticFeedback.selectionClick(),
                      ),

                      const SizedBox(height: 20),

                      // ── Group description ─────────────────────────────────
                      _sectionLabel('Group description'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.poppins(
                            fontSize: 15, color: context.hc.textPrimary),
                        decoration: _inputDecoration(
                            'e.g. who this group is for, activities planned…'),
                        maxLines: 4,
                        minLines: 3,
                        onTap: () => HapticFeedback.selectionClick(),
                      ),

                      const SizedBox(height: 28),

                      // ── Who is this group for? ────────────────────────────
                      _sectionLabel('Who is this group for?'),
                      const SizedBox(height: 12),
                      ..._audienceOptions.map(_audienceCheckbox),

                      const SizedBox(height: 28),

                      // ── Privacy settings ──────────────────────────────────
                      _sectionLabel('Privacy settings'),
                      const SizedBox(height: 12),
                      _privacyOption(
                        value: 'public',
                        label: 'Public',
                        description:
                            'Everyone in your local community can see and join.',
                      ),
                      _privacyOption(
                        value: 'group',
                        label: 'Group',
                        description:
                            'Only members of a specific group can see and join.',
                      ),
                      _privacyOption(
                        value: 'private',
                        label: 'Private',
                        description:
                            'Invite only — choose specific people to invite.',
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Photo section widget ──────────────────────────────────────────────────

  Widget _buildPhotoSection() {
    return GestureDetector(
      onTap: _isUploadingImage ? null : _showImageSourceSheet,
      child: Stack(
        children: [
          // ── Photo container ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            height: 160,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: HuddlColors.background,
            ),
            child: _buildPhotoContent(),
          ),

          // ── Overlay: "Change photo" affordance ──────────────────────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black.withValues(alpha: 0.30),
              ),
              child: _isUploadingImage
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.20),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Change photo',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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

  Widget _buildPhotoContent() {
    // Newly picked image (base64 data-URI)
    if (_newImageDataUri != null) {
      try {
        final dataUri = Uri.parse(_newImageDataUri!);
        final bytes   = dataUri.data?.contentAsBytes();
        if (bytes != null) {
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            width: double.infinity,
            height: 160,
          );
        }
      } catch (_) {}
    }
    // Existing Firestore image (network URL or data-URI from old save)
    if (widget.groupImageUrl.isNotEmpty) {
      if (widget.groupImageUrl.startsWith('data:')) {
        try {
          final dataUri = Uri.parse(widget.groupImageUrl);
          final bytes   = dataUri.data?.contentAsBytes();
          if (bytes != null) {
            return Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.cover,
              width: double.infinity,
              height: 160,
            );
          }
        } catch (_) {}
      } else {
        return Image.network(
          widget.groupImageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 160,
          errorBuilder: (_, __, ___) => _photoPlaceholder(),
        );
      }
    }
    return _photoPlaceholder();
  }

  Widget _photoPlaceholder() => Center(
    child: Icon(Icons.image_outlined, size: 48,
        color: HuddlColors.textTertiary),
  );

  // ── Helper widgets ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 14, fontWeight: FontWeight.w600,
      color: context.hc.textPrimary),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.poppins(
        fontSize: 14, color: context.hc.textTertiary),
    filled: true,
    fillColor: context.hc.surface,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.hc.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.hc.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: HuddlColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: HuddlColors.error),
    ),
    counterStyle: GoogleFonts.poppins(
        fontSize: 11, color: context.hc.textTertiary),
  );

  Widget _audienceCheckbox(String option) {
    final selected = _selectedAudience.contains(option);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _onAudienceToggle(option);
        },
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: selected ? HuddlColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: selected ? HuddlColors.primary : context.hc.divider,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              option,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: context.hc.textPrimary,
                fontWeight:
                    selected ? FontWeight.w500 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _privacyOption({
    required String value,
    required String label,
    required String description,
  }) {
    final isSelected = _privacy == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _onPrivacyChanged(value);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22, height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? HuddlColors.primary
                      : context.hc.divider,
                  width: isSelected ? 5 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? HuddlColors.primary
                          : context.hc.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textSecondary,
                      height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
