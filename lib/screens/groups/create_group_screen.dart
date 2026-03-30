import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/huddl_colors.dart';
import '../../models/group.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/invitation_service.dart';

// ── Design tokens — use HuddlColors as single source of truth ────────

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
  String? _pickedImageUrl; // Object URL for web display
  bool _showImageError = false; // Show error when trying to create without image

  // ── "Who is this group for?" checkboxes ─────────────────────────────────
  final Map<String, bool> _audienceChecks = {
    'Aspiring parents': false,
    'Parents expecting a baby': false,
    'Mums': false,
    'Dads': false,
  };

  // ── Privacy setting ────────────────────────────────────────────────────
  bool _isPrivate = false; // false = Public, true = Private

  // ── Member picker (for private groups) ─────────────────────────────────
  List<BoroughMember> _boroughMembers = [];
  final Set<String> _selectedMemberIds = {};
  String _memberSearchQuery = '';
  String? _userBorough;
  String? _userName;

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
        _userName = onboarding.name;
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
              Text('Add group photo',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: HuddlColors.textDark)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
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
                  decoration: BoxDecoration(
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
        source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85,
      );
      if (file != null && mounted) {
        // Convert to base64 data URL for persistence
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';
        setState(() {
          _pickedImageUrl = dataUrl;
          _showImageError = false;
        });
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

  bool get _isValid {
    final hasName = _nameController.text.trim().isNotEmpty;
    final hasDesc = _descriptionController.text.trim().isNotEmpty;
    final hasImage = _pickedImageUrl != null;
    if (_isPrivate) {
      // Private groups must have at least one invited member + image
      return hasName && hasDesc && hasImage && _selectedMemberIds.isNotEmpty;
    }
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
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.camera_alt_outlined,
                    size: 36, color: HuddlColors.primary),
          );
        }
      } catch (_) {
        // fall through
      }
    }
    return Image.network(
      _pickedImageUrl ?? '',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.camera_alt_outlined,
              size: 36, color: HuddlColors.primary),
    );
  }

  Future<void> _createGroup() async {
    // Validate image is present
    if (_pickedImageUrl == null) {
      setState(() => _showImageError = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a group image before creating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_isValid) return;

    // ── Duplicate public group name check ─────────────────────────────
    if (!_isPrivate) {
      final newName = _nameController.text.trim().toLowerCase();

      // Check user-created groups
      final existing = await BrowserStorage.getString(_userGroupsKey);
      if (existing != null) {
        final groups = json.decode(existing) as List<dynamic>;
        final hasDupe = groups.any((g) {
          final name = (g as Map<String, dynamic>)['name'] as String? ?? '';
          return name.toLowerCase() == newName;
        });
        if (hasDupe) {
          if (mounted) {
            _showDuplicateNameDialog();
          }
          return;
        }
      }

      // Check default/system groups
      final defaultRaw = await BrowserStorage.getString('default_groups_v3');
      if (defaultRaw != null) {
        final defaultGroups = json.decode(defaultRaw) as List<dynamic>;
        final hasDupe = defaultGroups.any((g) {
          final name = (g as Map<String, dynamic>)['name'] as String? ?? '';
          return name.toLowerCase() == newName;
        });
        if (hasDupe) {
          if (mounted) {
            _showDuplicateNameDialog();
          }
          return;
        }
      }
    }

    setState(() => _isCreating = true);

    try {
      // Load creator info
      final onboarding = OnboardingDataService();
      await onboarding.initialize();
      final creatorName = onboarding.name ?? 'You';
      final postcode = onboarding.postcode;
      final creatorBorough = PostcodeService().getBoroughFromPostcode(postcode);

      // Build selected audience list
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

      // Save to local storage
      final existing = await BrowserStorage.getString(_userGroupsKey);
      List<dynamic> groups = [];
      if (existing != null) {
        groups = json.decode(existing) as List<dynamic>;
      }
      groups.add(newGroup.toJson());
      await BrowserStorage.setString(_userGroupsKey, json.encode(groups));

      // Add system message for group creation
      final invService = InvitationService();
      await invService.initialize();
      await invService.addSystemMessage(
        groupId: newGroup.id,
        userName: creatorName,
        type: 'joined',
      );

      // ── Send invitations if private ──────────────────────────────
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
            content: Text(_isPrivate
                ? '${newGroup.name} created! Invitations sent to ${_selectedMemberIds.length} member(s).'
                : '${newGroup.name} created and listed in Discover for ${creatorBorough != 'Unknown Borough' ? creatorBorough : 'your borough'}!'),
            backgroundColor: HuddlColors.primary,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: HuddlColors.primary, size: 24),
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

  // ── Filtered list for the member search ─────────────────────────────────
  List<BoroughMember> get _filteredMembers {
    if (_memberSearchQuery.isEmpty) return _boroughMembers;
    final q = _memberSearchQuery.toLowerCase();
    return _boroughMembers
        .where((m) => m.name.toLowerCase().contains(q))
        .toList();
  }

  // ── Build the member picker section (only shown for private groups) ─────
  Widget _buildMemberPicker() {
    return Container(
      color: HuddlColors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invite members',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: HuddlColors.textDark,
                  ),
                ),
              ),
              if (_selectedMemberIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          const SizedBox(height: 4),
          Text(
            'Select members in ${_userBorough ?? 'your borough'} to invite to this private group.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: HuddlColors.textHint,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          // ── Selected member chips ──────────────────────────────────
          if (_selectedMemberIds.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedMemberIds.map((id) {
                final member = _boroughMembers.firstWhere(
                  (m) => m.id == id,
                  orElse: () => const BoroughMember(
                    id: '', name: 'Unknown', parentType: 'mum', stagesOfLife: [],
                  ),
                );
                return Container(
                  padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
                  decoration: BoxDecoration(
                    color: HuddlColors.peachLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: HuddlColors.primary.withValues(alpha: 0.3)),
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
                        onTap: () => setState(() => _selectedMemberIds.remove(id)),
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: HuddlColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 14, color: HuddlColors.primary),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // ── Search field ───────────────────────────────────────────
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: HuddlColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _memberSearchController,
              style: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
              decoration: InputDecoration(
                hintText: 'Search members...',
                hintStyle: GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textHint),
                prefixIcon: const Icon(Icons.search, size: 20, color: HuddlColors.textHint),
                suffixIcon: _memberSearchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _memberSearchController.clear();
                          setState(() => _memberSearchQuery = '');
                        },
                        child: const Icon(Icons.close, size: 18, color: HuddlColors.textHint),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              ),
              onChanged: (val) => setState(() => _memberSearchQuery = val),
            ),
          ),
          const SizedBox(height: 8),

          // ── Member list ────────────────────────────────────────────
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filteredMembers.length,
              itemBuilder: (context, index) {
                final member = _filteredMembers[index];
                final isSelected = _selectedMemberIds.contains(member.id);
                final initials = member.name.split(' ').map((w) => w[0]).take(2).join();
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedMemberIds.remove(member.id);
                      } else {
                        _selectedMemberIds.add(member.id);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? HuddlColors.primary.withValues(alpha: 0.15)
                                : HuddlColors.background,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: HuddlColors.primary, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? HuddlColors.primary
                                    : HuddlColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Name + type tag
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
                                member.parentType == 'mum' ? 'Mum' : 'Dad',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: HuddlColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Check indicator
                        Container(
                          width: 26, height: 26,
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
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: HuddlColors.textDark,
            ),
          ),
        ),
        leadingWidth: 80,
        title: Text(
          'Create group',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isValid && !_isCreating ? _createGroup : null,
            child: Text(
              'CREATE',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _isValid && !_isCreating
                    ? HuddlColors.textDark
                    : HuddlColors.textHint,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: HuddlColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── Group photo (MANDATORY) ──────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickGroupImage,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: HuddlColors.peachLight,
                          borderRadius: BorderRadius.circular(24),
                          border: _showImageError
                              ? Border.all(color: Colors.red, width: 2)
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _pickedImageUrl != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildPickedImage(),
                                  Positioned(
                                    bottom: 4, right: 4,
                                    child: Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        color: HuddlColors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: HuddlColors.white, width: 2),
                                      ),
                                      child: const Icon(Icons.edit,
                                          size: 14, color: HuddlColors.white),
                                    ),
                                  ),
                                ],
                              )
                            : const Icon(Icons.camera_alt_outlined,
                                size: 36, color: HuddlColors.primary),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _pickedImageUrl != null
                          ? 'Change group photo'
                          : 'Add group photo *',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _showImageError ? Colors.red : HuddlColors.primary,
                        fontWeight: _showImageError ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (_showImageError) ...[
                      const SizedBox(height: 4),
                      Text(
                        'A group image is required',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Name field ──────────────────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Group name',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    style:
                        GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
                    decoration: InputDecoration(
                      hintText: 'e.g. Cambridge Parents 2024',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textHint),
                      filled: true,
                      fillColor: HuddlColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Description field ───────────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Description',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    onChanged: (_) => setState(() {}),
                    maxLines: 4,
                    style:
                        GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textDark),
                    decoration: InputDecoration(
                      hintText:
                          'What is this group about? Who should join?',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: HuddlColors.textHint),
                      filled: true,
                      fillColor: HuddlColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Who is this group for? ──────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Who is this group for?',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._audienceChecks.keys.map((label) {
                    return InkWell(
                      onTap: () => setState(() {
                        _audienceChecks[label] = !_audienceChecks[label]!;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _audienceChecks[label],
                                onChanged: (v) => setState(() {
                                  _audienceChecks[label] = v ?? false;
                                }),
                                activeColor: HuddlColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                side: BorderSide(
                                  color: _audienceChecks[label]!
                                      ? HuddlColors.primary
                                      : HuddlColors.textHint,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              label,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: HuddlColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Privacy settings ────────────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Privacy settings',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Public
                  InkWell(
                    onTap: () => setState(() => _isPrivate = false),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Radio<bool>(
                            value: false,
                            groupValue: _isPrivate,
                            onChanged: (v) => setState(() => _isPrivate = v!),
                            activeColor: HuddlColors.primary,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Public',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: HuddlColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'All users within your Borough can see the group listed under the Discover tab and click to join.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: HuddlColors.textHint,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Private
                  InkWell(
                    onTap: () => setState(() => _isPrivate = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Radio<bool>(
                            value: true,
                            groupValue: _isPrivate,
                            onChanged: (v) => setState(() => _isPrivate = v!),
                            activeColor: HuddlColors.primary,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Private',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: HuddlColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'These groups will not be listed under the Discover tab. Members invited will need to accept the invite to join the group. Once they accept, this group will be listed under the Messages tab with a \u201CPrivate Group\u201D tag.',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: HuddlColors.textHint,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Member picker (visible only when Private is selected) ─
            if (_isPrivate) ...[
              const SizedBox(height: 8),
              _buildMemberPicker(),
            ],

            const SizedBox(height: 8),

            // ── Member count (read-only) ────────────────────────────
            Container(
              color: HuddlColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isPrivate && _selectedMemberIds.isNotEmpty
                        ? '${_selectedMemberIds.length + 1} member${_selectedMemberIds.length + 1 != 1 ? 's' : ''}'
                        : _isPrivate ? '1 member (you)' : '1 member (you)',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: HuddlColors.textDark,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: HuddlColors.textHint),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Create button ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: !_isCreating ? _createGroup : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isValid ? HuddlColors.primary : HuddlColors.divider,
                    disabledBackgroundColor: HuddlColors.divider,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                    elevation: 0,
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: HuddlColors.white),
                        )
                      : Text(
                          _isPrivate
                              ? 'Create & Send Invites'
                              : 'Create Group',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _isValid ? HuddlColors.white : HuddlColors.textHint,
                          ),
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
}
