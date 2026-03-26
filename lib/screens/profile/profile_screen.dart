import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../../theme/huddl_colors.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/default_group_service.dart';
import '../../services/postcode_service.dart';
import '../../services/browser_storage.dart';
import '../../models/group.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final OnboardingDataService _onboarding = OnboardingDataService();
  final DefaultGroupService _groupService = DefaultGroupService();
  final PostcodeService _postcodeService = PostcodeService();

  bool _isLoading = true;

  // Dynamic profile data
  String _name = '';
  String _borough = '';
  String? _bio;
  String? _photoUrl;
  String _parentType = '';
  List<String> _stagesOfLife = [];
  List<Map<String, String>> _children = [];
  String? _dueDate;
  String? _phone;

  // Groups the user belongs to
  List<Group> _userGroups = [];
  // Groups joined from Discover tab
  List<Group> _discoveredGroups = [];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      await _onboarding.initialize();
      await _groupService.initialize();

      // Resolve borough from postcode
      String borough = 'Not set';
      final pc = _onboarding.postcode;
      if (pc != null) {
        borough = _postcodeService.getBoroughFromPostcode(pc) ?? 'Unknown';
      }

      // Fetch user groups (default + discovered)
      final defaultGroups =
          await _groupService.getUserGroups('current_user');

      // Load user-created / discovered groups from storage
      final discoveredJson =
          await BrowserStorage.getString('user_created_groups_v1');
      List<Group> discovered = [];
      if (discoveredJson != null) {
        final List<dynamic> decoded = json.decode(discoveredJson);
        discovered =
            decoded.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
      }

      setState(() {
        _name = _onboarding.name ?? 'User';
        _borough = borough;
        _bio = _onboarding.bio;
        _photoUrl = _onboarding.profilePhotoObjectUrl;
        _parentType = _onboarding.parentType ?? '';
        _stagesOfLife = _onboarding.stagesOfLife;
        _children = _onboarding.children;
        _dueDate = _onboarding.dueDate;
        _phone = _onboarding.fullPhoneNumber;
        _userGroups = defaultGroups;
        _discoveredGroups = discovered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String get _stageLabel {
    final labels = <String>[];
    for (final s in _stagesOfLife) {
      switch (s) {
        case 'aspiring':
          labels.add('Trying for a baby');
        case 'expecting':
          if (_dueDate != null && _dueDate!.length >= 4) {
            labels.add('Expecting (due ${_dueDate!.substring(0, 4)})');
          } else {
            labels.add('Expecting');
          }
        case 'parent':
          if (_children.isNotEmpty) {
            final childInfo = _children.map((c) {
              final name = c['name'] ?? '';
              final year = c['birthday'] ?? '';
              if (name.isNotEmpty && year.isNotEmpty) return '$name ($year)';
              if (year.isNotEmpty) return 'Born $year';
              if (name.isNotEmpty) return name;
              return 'Child';
            }).join(', ');
            labels.add('Parent: $childInfo');
          } else {
            labels.add('Parent');
          }
        default:
          labels.add(s);
      }
    }
    return labels.join(' · ');
  }

  int get _totalGroupCount => _userGroups.length + _discoveredGroups.length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: HuddlColors.background,
        body: Center(child: CircularProgressIndicator(color: HuddlColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: HuddlColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: HuddlColors.primary,
          onRefresh: _loadProfileData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // ── Profile header ──────────────────────────────────────────
                Container(
                  color: HuddlColors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    children: [
                      // Top bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'My Profile',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined,
                                color: HuddlColors.textDark),
                            onPressed: () {},
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Avatar — show the onboarding photo if it exists
                      GestureDetector(
                        onTap: _changeProfilePhoto,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            _buildAvatar(),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: HuddlColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: HuddlColors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 14,
                                color: HuddlColors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Name
                      Text(
                        _name,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: HuddlColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Borough / location
                      Text(
                        _borough,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: HuddlColors.textHint,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Stage of life chips
                      if (_stageLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: HuddlColors.peachLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _stageLabel,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: HuddlColors.primary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Stats row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatItem(
                              count: '$_totalGroupCount', label: 'Groups'),
                          Container(
                            width: 1,
                            height: 32,
                            color: HuddlColors.divider,
                          ),
                          _StatItem(
                              count: '${_children.length}',
                              label: _children.length == 1
                                  ? 'Child'
                                  : 'Children'),
                          Container(
                            width: 1,
                            height: 32,
                            color: HuddlColors.divider,
                          ),
                          _StatItem(
                            count: _parentType == 'mum'
                                ? 'Mum'
                                : _parentType == 'dad'
                                    ? 'Dad'
                                    : _parentType.isNotEmpty
                                        ? _parentType[0].toUpperCase() +
                                            _parentType.substring(1)
                                        : '-',
                            label: 'Role',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── About me section ──────────────────────────────────────
                if (_bio != null && _bio!.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: HuddlColors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About me',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HuddlColors.textHint,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _bio!,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: HuddlColors.textDark,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_bio != null && _bio!.trim().isNotEmpty)
                  const SizedBox(height: 8),

                // ── My groups (real data) ─────────────────────────────────
                if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                  Container(
                    color: HuddlColors.white,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'My Groups',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.textHint,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$_totalGroupCount total',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: HuddlColors.textHint,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Horizontal scrollable group list
                        SizedBox(
                          height: 90,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ..._userGroups.map((g) => _GroupChip(group: g)),
                              ..._discoveredGroups
                                  .map((g) => _GroupChip(group: g)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_userGroups.isNotEmpty || _discoveredGroups.isNotEmpty)
                  const SizedBox(height: 8),

                // ── Account section ───────────────────────────────────────
                _MenuSection(
                  title: 'Account',
                  items: [
                    _MenuItem(
                      icon: Icons.person_outline,
                      title: 'Edit profile',
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.child_care,
                      title: 'Stage of life',
                      subtitle: _stageLabel.isNotEmpty ? _stageLabel : null,
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.location_on_outlined,
                      title: 'Location',
                      subtitle: _borough,
                      onTap: () {},
                    ),
                    if (_phone != null)
                      _MenuItem(
                        icon: Icons.phone_outlined,
                        title: 'Phone',
                        subtitle: _phone,
                        onTap: () {},
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                _MenuSection(
                  title: 'Activity',
                  items: [
                    _MenuItem(
                      icon: Icons.people_outline,
                      title: 'My groups',
                      trailing: _CountBadge(count: _totalGroupCount),
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.event_outlined,
                      title: 'My events',
                      trailing: const _CountBadge(count: 0),
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.storefront_outlined,
                      title: 'My listings',
                      trailing: const _CountBadge(count: 0),
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.bookmark_border,
                      title: 'Saved',
                      onTap: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                _MenuSection(
                  title: 'Settings',
                  items: [
                    _MenuItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.lock_outline,
                      title: 'Privacy',
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap: () {},
                    ),
                    _MenuItem(
                      icon: Icons.info_outline,
                      title: 'About huddl',
                      onTap: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Logout
                Container(
                  color: HuddlColors.white,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading:
                        const Icon(Icons.logout, color: HuddlColors.error),
                    title: Text(
                      'Log out',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: HuddlColors.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/splash',
                        (route) => false,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Version 1.0.0',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: HuddlColors.textHint,
                    ),
                  ),
                ),

                // Extra padding for bottom nav
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Change profile photo from the profile screen ─────────────────
  Future<void> _changeProfilePhoto() async {
    if (kIsWeb) {
      await _pickProfilePhoto(ImageSource.gallery);
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
              Text('Change profile photo',
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
                title: Text('Choose from gallery',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto(ImageSource.gallery);
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
                title: Text('Take a photo',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickProfilePhoto(ImageSource.camera);
                },
              ),
              if (_photoUrl != null && _photoUrl!.isNotEmpty)
                ListTile(
                  leading: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(
                      color: HuddlColors.errorLight, shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: HuddlColors.error),
                  ),
                  title: Text('Remove photo',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500, color: HuddlColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _removeProfilePhoto();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file != null && mounted) {
        _onboarding.setProfilePhotoPath(kIsWeb ? file.name : file.path);

        // Convert to base64 data URL so it persists across page reloads
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';
        _onboarding.setProfilePhotoObjectUrl(dataUrl);
        setState(() => _photoUrl = dataUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile photo updated'),
              backgroundColor: HuddlColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
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

  void _removeProfilePhoto() {
    _onboarding.setProfilePhotoPath(null);
    _onboarding.setProfilePhotoObjectUrl(null);
    setState(() => _photoUrl = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Profile photo removed'),
        backgroundColor: HuddlColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildAvatar() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: HuddlColors.primary, width: 2),
        ),
        child: ClipOval(
          child: _buildAvatarImage(),
        ),
      );
    }
    return _fallbackAvatar();
  }

  Widget _buildAvatarImage() {
    // Handle base64 data: URLs (persisted across page reloads)
    if (_photoUrl!.startsWith('data:')) {
      try {
        final dataUri = Uri.parse(_photoUrl!);
        final base64Str = dataUri.data?.contentAsBytes();
        if (base64Str != null) {
          return Image.memory(
            Uint8List.fromList(base64Str),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallbackAvatar(),
          );
        }
      } catch (_) {
        // Fall through to fallback
      }
      return _fallbackAvatar();
    }
    // Handle blob: or http URLs
    return Image.network(
      _photoUrl!,
      width: 84,
      height: 84,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallbackAvatar(),
    );
  }

  Widget _fallbackAvatar() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HuddlColors.peachLight,
        border: Border.all(color: HuddlColors.primary, width: 2),
      ),
      child: Center(
        child: Text(
          _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
          style: GoogleFonts.poppins(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: HuddlColors.primary,
          ),
        ),
      ),
    );
  }
}

// ── Group chip in horizontal list ─────────────────────────────────────────
class _GroupChip extends StatelessWidget {
  final Group group;
  const _GroupChip({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 14),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: HuddlColors.primary.withValues(alpha: 0.3), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: group.imageUrl.startsWith('assets/')
                ? Image.asset(group.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _iconFallback())
                : _iconFallback(),
          ),
          const SizedBox(height: 4),
          Text(
            group.name,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: HuddlColors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _iconFallback() {
    return Container(
      color: HuddlColors.peachLight,
      child: const Center(
        child: Icon(Icons.people, size: 24, color: HuddlColors.primary),
      ),
    );
  }
}

// ── Stat item ─────────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: HuddlColors.textDark,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: HuddlColors.textHint,
          ),
        ),
      ],
    );
  }
}

// ── Menu section ──────────────────────────────────────────────────────────
class _MenuSection extends StatelessWidget {
  final String title;
  final List<_MenuItem> items;
  const _MenuSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HuddlColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textHint,
              ),
            ),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HuddlColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: HuddlColors.textDark),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: HuddlColors.textDark,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: HuddlColors.textHint,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing ??
          const Icon(Icons.chevron_right, color: HuddlColors.textHint),
      onTap: onTap,
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: HuddlColors.peachLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: HuddlColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: HuddlColors.textHint),
      ],
    );
  }
}
