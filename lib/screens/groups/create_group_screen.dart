import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../models/group.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/invitation_service.dart';
import '../../services/member_photo_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE GROUP — single-page scrollable form matching Create Meetup design
// ═══════════════════════════════════════════════════════════════════════════════

const String _userGroupsKey = 'user_created_groups_v1';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _memberSearchController = TextEditingController();
  final _picker = ImagePicker();
  bool _isCreating = false;
  String? _pickedImageUrl;
  bool _showImageError = false;

  // ── "Who is this group for?" checkboxes ─────────────────────────────────
  final Map<String, bool> _audienceChecks = {
    'Aspiring parents': false,
    'Parents expecting a baby': false,
    'Mums': false,
    'Dads': false,
  };

  // ── Privacy setting ────────────────────────────────────────────────────
  bool _isPrivate = false;

  // ── Member picker (for private groups) ─────────────────────────────────
  List<BoroughMember> _boroughMembers = [];
  final Set<String> _selectedMemberIds = {};
  String _memberSearchQuery = '';
  String? _userBorough;

  @override
  void initState() {
    super.initState();
    _loadBoroughMembers();
  }

  Future<void> _loadBoroughMembers() async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();
    final postcode = onboarding.postcode;
    final borough = PostcodeService().getBoroughFromPostcode(postcode);
    final members = InvitationService.getBoroughMembers(borough);
    if (mounted) {
      setState(() {
        _userBorough = borough;
        _boroughMembers = members;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  // ── Image picker ──────────────────────────────────────────────────────
  Future<void> _pickGroupImage() async {
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
            Text('Add group photo',
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
                    color: HuddlColors.peachLight, shape: BoxShape.circle),
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
                    color: HuddlColors.peachLight, shape: BoxShape.circle),
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
        source: source, maxWidth: 1200, maxHeight: 800, imageQuality: 85,
      );
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        setState(() {
          _pickedImageUrl = 'data:$mimeType;base64,$base64Str';
          _showImageError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not access photos: $e'),
              backgroundColor: HuddlColors.error),
        );
      }
    }
  }

  bool get _isValid {
    final hasName = _nameController.text.trim().isNotEmpty;
    final hasDesc = _descriptionController.text.trim().isNotEmpty;
    final hasImage = _pickedImageUrl != null;
    return hasName && hasDesc && hasImage;
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
            errorBuilder: (_, __, ___) => _photoPlaceholder(),
          );
        }
      } catch (_) {}
    }
    return _photoPlaceholder();
  }

  // ── Show invite members bottom sheet ──────────────────────────────────
  void _showInviteMembersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HuddlColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => StatefulBuilder(
          builder: (context, setSheetState) {
            final q = _memberSearchQuery.toLowerCase();
            final filtered = q.isEmpty
                ? _boroughMembers
                : _boroughMembers
                    .where((m) => m.name.toLowerCase().contains(q))
                    .toList();

            return Column(
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: HuddlColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Invite members',
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textDark,
                          ),
                        ),
                      ),
                      if (_selectedMemberIds.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_selectedMemberIds.length} selected',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Select members in ${_userBorough ?? 'your borough'} to invite.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Selected chips
                if (_selectedMemberIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedMemberIds.map((id) {
                          final member = _boroughMembers.firstWhere(
                            (m) => m.id == id,
                            orElse: () => const BoroughMember(
                              id: '',
                              name: 'Unknown',
                              parentType: 'mum',
                              stagesOfLife: [],
                            ),
                          );
                          return Container(
                            padding: const EdgeInsets.only(
                                left: 12, top: 4, bottom: 4, right: 4),
                            decoration: BoxDecoration(
                              color: HuddlColors.peachLight,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: HuddlColors.primary
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  member.name,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: HuddlColors.textDark,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    setState(
                                        () => _selectedMemberIds.remove(id));
                                    setSheetState(() {});
                                  },
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: HuddlColors.primary
                                          .withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        size: 14, color: HuddlColors.primary),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                if (_selectedMemberIds.isNotEmpty) const SizedBox(height: 12),

                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: HuddlColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _memberSearchController,
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textDark),
                      decoration: InputDecoration(
                        hintText: 'Search members...',
                        hintStyle: GoogleFonts.poppins(
                            fontSize: 14, color: HuddlColors.textHint),
                        prefixIcon: const Icon(Icons.search,
                            size: 20, color: HuddlColors.textHint),
                        suffixIcon: _memberSearchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _memberSearchController.clear();
                                  setState(() => _memberSearchQuery = '');
                                  setSheetState(() {});
                                },
                                child: const Icon(Icons.close,
                                    size: 18, color: HuddlColors.textHint),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                      ),
                      onChanged: (val) {
                        setState(() => _memberSearchQuery = val);
                        setSheetState(() {});
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Member list
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      final isSelected =
                          _selectedMemberIds.contains(member.id);
                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedMemberIds.remove(member.id);
                            } else {
                              _selectedMemberIds.add(member.id);
                            }
                          });
                          setSheetState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                decoration: isSelected
                                    ? BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: HuddlColors.primary,
                                            width: 2),
                                      )
                                    : null,
                                child: MemberAvatar(
                                  name: member.name,
                                  imageUrl: member.avatarUrl,
                                  size: 42,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: HuddlColors.textDark,
                                      ),
                                    ),
                                    Text(
                                      member.parentType == 'mum'
                                          ? 'Mum'
                                          : 'Dad',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: HuddlColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? HuddlColors.primary
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? HuddlColors.primary
                                        : HuddlColors.divider,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check,
                                        size: 16, color: Colors.white)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Done button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: HuddlColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Done',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Invite members widget (matching Create Meetup private section) ──
  Widget _buildInviteMembersWidget() {
    return Container(
      margin: const EdgeInsets.only(left: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected members chips
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
                    ? CircleAvatar(
                        backgroundImage: NetworkImage(photoUrl),
                        radius: 14,
                      )
                    : MemberAvatar(name: member.name, size: 28),
                  label: Text(
                    member.name,
                    style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _selectedMemberIds.remove(id)),
                  backgroundColor: HuddlColors.peachLight,
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
                border: Border.all(
                  color: _selectedMemberIds.isNotEmpty
                      ? HuddlColors.primary
                      : HuddlColors.gray300,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 20,
                    color: _selectedMemberIds.isNotEmpty
                        ? HuddlColors.primary
                        : HuddlColors.textHint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _selectedMemberIds.isEmpty
                          ? 'Select members to invite'
                          : '${_selectedMemberIds.length} member${_selectedMemberIds.length == 1 ? '' : 's'} selected',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: _selectedMemberIds.isNotEmpty
                            ? HuddlColors.textDark
                            : HuddlColors.textHint,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: _selectedMemberIds.isNotEmpty
                        ? HuddlColors.primary
                        : HuddlColors.textHint,
                  ),
                ],
              ),
            ),
          ),
          if (_userBorough != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Members from ${_userBorough!}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: HuddlColors.textHint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Create group logic ────────────────────────────────────────────────
  Future<void> _createGroup() async {
    if (_pickedImageUrl == null) {
      setState(() => _showImageError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a group image before creating'),
          backgroundColor: HuddlColors.error,
        ),
      );
      return;
    }
    if (!_isValid) return;

    // ── Duplicate public group name check ─────────────────────────────
    if (!_isPrivate) {
      final newName = _nameController.text.trim().toLowerCase();

      final existing = await BrowserStorage.getString(_userGroupsKey);
      if (existing != null) {
        final groups = json.decode(existing) as List<dynamic>;
        final hasDupe = groups.any((g) {
          final name = (g as Map<String, dynamic>)['name'] as String? ?? '';
          return name.toLowerCase() == newName;
        });
        if (hasDupe) {
          if (mounted) _showDuplicateNameDialog();
          return;
        }
      }

      final defaultRaw = await BrowserStorage.getString('default_groups_v3');
      if (defaultRaw != null) {
        final defaultGroups = json.decode(defaultRaw) as List<dynamic>;
        final hasDupe = defaultGroups.any((g) {
          final name = (g as Map<String, dynamic>)['name'] as String? ?? '';
          return name.toLowerCase() == newName;
        });
        if (hasDupe) {
          if (mounted) _showDuplicateNameDialog();
          return;
        }
      }
    }

    setState(() => _isCreating = true);

    try {
      final onboarding = OnboardingDataService();
      await onboarding.initialize();
      final creatorName = onboarding.name ?? 'You';
      final postcode = onboarding.postcode;
      final creatorBorough =
          PostcodeService().getBoroughFromPostcode(postcode);

      final selectedAudience = _audienceChecks.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final newGroup = Group(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: _pickedImageUrl!,
        memberCount: _isPrivate ? 1 + _selectedMemberIds.length : 1,
        category: selectedAudience.isNotEmpty
            ? selectedAudience.join(', ').toUpperCase()
            : 'PARENTING',
        isJoined: true,
        isImageLocked: false,
        targetAudience: selectedAudience,
        isPrivate: _isPrivate,
        creatorId: 'current_user',
        creatorName: creatorName,
        creatorBorough: creatorBorough,
        lastMessage: '$creatorName created this group',
        lastSenderName: 'System',
        lastMessageTime: DateTime.now(),
      );

      final existingJson = await BrowserStorage.getString(_userGroupsKey);
      List<dynamic> groups = [];
      if (existingJson != null) {
        groups = json.decode(existingJson) as List<dynamic>;
      }
      groups.add(newGroup.toJson());
      await BrowserStorage.setString(_userGroupsKey, json.encode(groups));

      final invService = InvitationService();
      await invService.initialize();
      await invService.addSystemMessage(
        groupId: newGroup.id,
        userName: creatorName,
        type: 'joined',
      );

      if (_isPrivate && _selectedMemberIds.isNotEmpty) {
        await invService.sendInvitations(
          group: newGroup,
          invitedMemberIds: _selectedMemberIds.toList(),
          creatorName: creatorName,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_isPrivate
                    ? '"${newGroup.name}" created! Invitations sent to ${_selectedMemberIds.length} member(s).'
                    : '"${newGroup.name}" created and listed in Discover for ${creatorBorough != 'Unknown Borough' ? creatorBorough : 'your borough'}!'),
              ),
            ]),
            backgroundColor: HuddlColors.teal,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, newGroup);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showDuplicateNameDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: HuddlColors.primary, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Group Name Taken',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: HuddlColors.textDark,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'A group with this name already exists. Please use an alternative name.',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: HuddlColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: HuddlColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark)),
            ),
          ),
        ),
        leadingWidth: 80,
        centerTitle: true,
        title: Text(
          'Create group',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        actions: [
          GestureDetector(
            onTap: _isValid && !_isCreating ? _createGroup : null,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: _isCreating
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _isValid
                                ? HuddlColors.textDark
                                : HuddlColors.textHint)),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────── PHOTO UPLOAD (full-width banner) ───────────
            _buildPhotoUpload(),
            const SizedBox(height: 16),

            // ─────────── GROUP TITLE ───────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _sectionLabel('Group title'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _underlineTextField(
                controller: _nameController,
                hint: 'Group title',
              ),
            ),
            const SizedBox(height: 8),

            // ─────────── DESCRIPTION ───────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _sectionLabel('Group description'),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _descriptionController,
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: HuddlColors.textDark),
                decoration: InputDecoration(
                  hintText:
                      'e.g. who this group is for, what activities are planned.',
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
                    borderSide:
                        BorderSide(color: HuddlColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─────────── WHO IS THIS GROUP FOR? ───────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _sectionLabel('Who is this group for?'),
            ),
            const SizedBox(height: 8),
            ..._audienceChecks.keys.map((label) {
              final isChecked = _audienceChecks[label]!;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _audienceChecks[label] = !_audienceChecks[label]!;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _checkbox(isChecked),
                        const SizedBox(width: 10),
                        Text(label,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: HuddlColors.textDark)),
                      ],
                    ),
                  ),
                ),
              );
            }),

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
                        'Everyone can check the member list and group events.',
                    isSelected: !_isPrivate,
                    onTap: () => setState(() => _isPrivate = false),
                  ),
                  const SizedBox(height: 10),
                  _privacyRadio(
                    label: 'Private',
                    description:
                        'Only members of the group can check the member list and group events.',
                    isSelected: _isPrivate,
                    onTap: () => setState(() => _isPrivate = true),
                  ),
                  if (_isPrivate) ...[
                    const SizedBox(height: 12),
                    _buildInviteMembersWidget(),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMPONENT WIDGETS (matching Create Meetup design language)
  // ══════════════════════════════════════════════════════════════════════════

  /// Full-width peach photo upload banner matching Create Meetup style
  Widget _buildPhotoUpload() {
    if (_pickedImageUrl != null) {
      return GestureDetector(
        onTap: _pickGroupImage,
        child: SizedBox(
          width: double.infinity,
          height: 200,
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit, size: 14, color: Colors.white),
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
      onTap: _pickGroupImage,
      child: Container(
        width: double.infinity,
        height: 200,
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _showImageError
              ? HuddlColors.peachLight
              : HuddlColors.peachLight,
          border: _showImageError
              ? Border.all(color: HuddlColors.error, width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                border: Border.all(
                    color: HuddlColors.primary.withValues(alpha: 0.6),
                    width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 28,
                      color: HuddlColors.primary.withValues(alpha: 0.8)),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: HuddlColors.primary.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Click to add group photo',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: HuddlColors.primary,
              ),
            ),
            if (_showImageError) ...[
              const SizedBox(height: 4),
              Text(
                'A group image is required',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: HuddlColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    return Container(
      color: HuddlColors.peachLight,
      child: const Center(
        child:
            Icon(Icons.image_outlined, size: 48, color: HuddlColors.primary),
      ),
    );
  }

  /// Section label — bold dark text matching Create Meetup style
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

  /// Underline text field matching Create Meetup style
  Widget _underlineTextField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: HuddlColors.gray300),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: HuddlColors.gray300),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: HuddlColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      ),
    );
  }

  /// Custom checkbox — orange when checked, matching Create Meetup style
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

  /// Privacy radio — clean style matching Create Meetup's _privacyRadio
  Widget _privacyRadio({
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                    color: isSelected
                        ? HuddlColors.primary
                        : HuddlColors.gray300,
                    width: 2,
                  ),
                ),
                child: isSelected
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
