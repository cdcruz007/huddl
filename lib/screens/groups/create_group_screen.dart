import 'dart:convert';
import '../../theme/huddl_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/image_editor_widget.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/common/huddl_button.dart';
import '../../widgets/huddl_widgets.dart';
import '../../models/group.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/invitation_service.dart';
import '../../services/member_photo_service.dart';
import '../../services/default_group_service.dart';
import '../../services/firestore_service.dart';
import '../../services/subscription_service.dart';
import '../../models/subscription.dart';
import '../../widgets/upgrade_prompt.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/borough_badge.dart';
import '../../services/ai_api_helper.dart';
import '../../services/huddl_user_service.dart';
import '../../constants/app_text_styles.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE GROUP — single-page scrollable form matching Create Meetup design
// Logic, Firebase, BrowserStorage: 100% unchanged.
// Only presentation layer updated to match Create Meetup Figma style.
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Design tokens (mirrors create_meetup_screen.dart) ───────────────────────
const _fieldBg      = HuddlColors.peachWarm;   // warm peach field fill
const _fieldLine    = HuddlColors.divider;       // #D5D5D5 bottom underline
const _sectionText  = HuddlColors.textDark;      // #42464C section headers
const _hintGray     = HuddlColors.textTertiary;  // #949494 placeholder text
const _accentOrange = HuddlColors.primary;       // #FF965C orange accent
const _bannerBg     = HuddlColors.peachWarm;  // warm peach photo banner bg

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
  // ImagePicker no longer needed - using ImageEditorWidget instead
  // final _picker = ImagePicker();
  bool _isCreating = false;
  String? _pickedImageUrl;
  bool _showImageError = false;

  // ── Inline duplicate-name detection ─────────────────────────────────────
  // True when the typed name closely matches an existing group.
  // Non-blocking: user sees a warning but can still proceed.
  bool _hasSimilarGroup = false;
  List<String> _similarGroupNames = [];

  // ── "Who is this group for?" checkboxes ─────────────────────────────────
  final Map<String, bool> _audienceChecks = {
    'Aspiring parents': false,
    'Parents expecting a baby': false,
    'Mums': false,
    'Dads': false,
  };

  // ── Privacy setting (3-tier: public / group / private) ─────────────────
  String _privacy = 'public';

  // ── Group picker (for "group" privacy) ────────────────────────────────
  String? _selectedParentGroupId;
  String? _selectedParentGroupName;
  List<Group> _userGroups = [];
  final DefaultGroupService _groupService = DefaultGroupService();

  // ── Member picker (for private groups) ─────────────────────────────────
  List<BoroughMember> _boroughMembers = [];
  final Set<String> _selectedMemberIds = {};
  String _memberSearchQuery = '';
  String? _userBorough;

  @override
  void initState() {
    super.initState();
    _loadBoroughMembers();
    _loadUserGroups();
    _nameController.addListener(_onNameChanged);
    _checkGroupCreationAllowance();
  }

  void _checkGroupCreationAllowance() {
    final ss = SubscriptionService();
    if (!ss.canCreateUserGroup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/subscription_gate',
            arguments: {
              'featureTitle': 'Group creation limit reached',
              'featureDescription': ss.limitReachedMessage('user_groups'),
              'requiredPlan': 'Huddl Plus',
              'featureIcon': HuddlIcons.diversity.codePoint,
            });
      });
    }
  }

  // ── Duplicate name check on each keystroke ───────────────────────────────
  void _onNameChanged() {
    final input = _nameController.text.trim().toLowerCase();
    if (input.length < 3) {
      if (_hasSimilarGroup) setState(() { _hasSimilarGroup = false; _similarGroupNames = []; });
      return;
    }
    final allNames = _userGroups.map((g) => g.name.toLowerCase()).toList();
    final matches = allNames
        .where((name) => name.contains(input) || input.contains(name) ||
            _levenshteinSimilar(name, input))
        .map((name) => _userGroups.firstWhere((g) => g.name.toLowerCase() == name).name)
        .take(2)
        .toList();
    setState(() {
      _hasSimilarGroup = matches.isNotEmpty;
      _similarGroupNames = matches;
    });
  }

  /// Returns true when two strings are within edit-distance 2 of each other
  /// (catches typos like "Hackney Mums" vs "Hackny Mums").
  bool _levenshteinSimilar(String a, String b) {
    if ((a.length - b.length).abs() > 3) return false;
    int m = a.length, n = b.length;
    final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) { dp[i][0] = i; }
    for (int j = 0; j <= n; j++) { dp[0][j] = j; }
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[m][n] <= 2;
  }

  Future<void> _loadUserGroups() async {
    await _groupService.initialize();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    final defaultGroups = await _groupService.getUserGroups(uid);
    List<Group> discovered = [];
    try {
      final discoveredJson =
          await BrowserStorage.getString(_userGroupsKey);
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

  Future<void> _loadBoroughMembers() async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();
    final postcode = onboarding.postcode;
    final borough = PostcodeService().getBoroughFromPostcode(postcode);
    if (borough == null) return;

    // Use HuddlUserService which queries Firestore for real borough members.
    // InvitationService.getBoroughMembers() returns an empty static list kept
    // only for API compatibility (see invitation_service.dart line ~513).
    try {
      final huddlUsers = await HuddlUserService().getBoroughMembers(borough);
      final members = huddlUsers
          .map((u) => BoroughMember(
                id: u.uid,
                name: u.name,
                avatarUrl: u.photoUrl.isNotEmpty ? u.photoUrl : null,
                parentType: u.parentType,
                stagesOfLife: u.stagesOfLife,
              ))
          .toList();
      if (mounted) {
        setState(() {
          _userBorough = borough;
          _boroughMembers = members;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CreateGroup] _loadBoroughMembers error: $e');
      if (mounted) setState(() => _userBorough = borough);
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Add group photo',
                style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textPrimary)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: HuddlColors.neutral50, shape: BoxShape.circle),
                child: const Icon(HuddlIcons.photoLibrary,
                    color: HuddlColors.textDark),
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
                decoration: BoxDecoration(
                    color: HuddlColors.neutral50, shape: BoxShape.circle),
                child: const Icon(HuddlIcons.camera,
                    color: HuddlColors.textDark),
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
      // Pass the already-chosen source so ImageEditorWidget skips its own
      // "Select Image Source" sheet and avoids a double-prompt.
      final file = await ImageEditorWidget.pickGroupImageWithSource(context, source);
      
      if (file != null && mounted) {
        final bytes = await file.readAsBytes();
        final base64Str = base64Encode(bytes);
        final mimeType = file.path.toLowerCase().endsWith('.png')
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
              content: Text('Could not update image: $e'),
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
            errorBuilder: (_, __, ___) => _emptyPhotoFallback(),
          );
        }
      } catch (_) {}
    }
    return _emptyPhotoFallback();
  }

  /// Inline fallback shown when picked image fails to decode.
  Widget _emptyPhotoFallback() => Container(
        color: _bannerBg,
        child: const Center(
          child: Icon(HuddlIcons.photoLibrary,
              size: 48, color: HuddlColors.primaryLight),   // HuddlColors.primaryLight
        ),
      );

  // ── Show invite members bottom sheet ──────────────────────────────────
  void _showInviteMembersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => GestureDetector(
        onTap: () => FocusScope.of(sheetCtx).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom),
          child: DraggableScrollableSheet(
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
                    color: context.hc.divider,
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
                          style: HuddlText.heading(),
                        ),
                      ),
                      if (_selectedMemberIds.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HuddlColors.neutral50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_selectedMemberIds.length} selected',
                            style: HuddlText.caption(weight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Select members in ${_userBorough ?? 'your borough'} to invite.',
                    style: HuddlText.caption(color: context.hc.textTertiary),
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
                              color: HuddlColors.primary.withValues(alpha: 0.08),
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
                                  style: HuddlText.body(),
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
                                    child: const Icon(HuddlIcons.close,
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
                      color: context.hc.scaffold,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _memberSearchController,
                      style: HuddlText.body(color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search members...',
                        hintStyle: HuddlText.body(color: context.hc.textTertiary),
                        prefixIcon: Icon(HuddlIcons.search,
                            size: 20, color: context.hc.textTertiary),
                        suffixIcon: _memberSearchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _memberSearchController.clear();
                                  setState(() => _memberSearchQuery = '');
                                  setSheetState(() {});
                                },
                                child: Icon(HuddlIcons.close,
                                    size: 18, color: context.hc.textTertiary),
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
                                      style: HuddlText.body(),
                                    ),
                                    Text(
                                      member.parentType == 'mum'
                                          ? 'Mum'
                                          : 'Dad',
                                      style: HuddlText.caption(),
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
                                    ? const Icon(HuddlIcons.check,
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
                  child: HuddlButton(
                    label: 'Done',
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
                    : MemberAvatar(name: member.name, size: 28, parentType: member.parentType),
                  label: Text(
                    member.name,
                    style: HuddlText.caption(),
                  ),
                  deleteIcon: const Icon(HuddlIcons.close, size: 16),
                  onDeleted: () => setState(() => _selectedMemberIds.remove(id)),
                  backgroundColor: HuddlColors.primary.withValues(alpha: 0.08),
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
                    HuddlIcons.personAdd,
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
                      style: HuddlText.body(),
                    ),
                  ),
                  Icon(
                    HuddlIcons.caretRight,
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
                style: HuddlText.caption(color: context.hc.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  // ── AI tagline generation ─────────────────────────────────────────────
  // Silently generates a one-line tagline from the user's group description.
  // Returns null on any failure so group creation is never blocked by AI.
  Future<String?> _generateAiTagline({
    required String groupName,
    required String description,
    required List<String> audience,
  }) async {
    if (description.trim().isEmpty) return null;
    try {
      final audienceLabel =
          audience.isNotEmpty ? audience.join(', ') : 'parents';
      final prompt =
          'Write a single short tagline (max 10 words, no quotes, no punctuation '
          'at the end) for a parenting community group called "$groupName" '
          'aimed at $audienceLabel. '
          'The creator described it as: "${description.trim()}". '
          'The tagline must capture the group\'s essence in plain, friendly language. '
          'Return only the tagline text — no explanation, no quotes.';
      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 40,
        },
      };
      final raw = await AiApiHelper.generateText(requestBody,
          timeout: const Duration(seconds: 15));
      if (raw == null) return null;
      // Strip any trailing punctuation / newlines
      final cleaned = raw.trim().replaceAll(RegExp(r'[\n\r"]+'), '');
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      if (kDebugMode) debugPrint('create_group: AI tagline failed — $e');
      return null;
    }
  }

  // ── Create group logic ────────────────────────────────────────────────
  Future<void> _createGroup() async {
    // ── Subscription gate: lifetime group creation limit ───────────────
    final subService = SubscriptionService();
    await subService.initialize();
    if (!subService.canCreateUserGroup) {
      if (mounted) {
        Navigator.pushNamed(context, '/subscription_gate', arguments: {
          'featureTitle': 'Group creation limit reached',
          'featureDescription': subService.limitReachedMessage('user_groups'),
          'requiredPlan': 'Huddl Plus',
          'featureIcon': HuddlIcons.diversity.codePoint,
        });
      }
      return;
    }
    // ── Subscription gate: private group ────────────────────────────
    if (_privacy == 'private' && !subService.canCreatePrivateGroup) {
      if (mounted) {
        showUpgradePrompt(
          context,
          feature: 'private_groups',
          message: subService.limitReachedMessage('private_groups'),
        );
      }
      return;
    }
    if (!mounted) return;

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
    if (_privacy == 'public') {
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

      final defaultRaw = await BrowserStorage.getString('default_groups_v6');
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
      // ── Firestore cross-device duplicate check ────────────────────────
      // Local BrowserStorage only covers groups cached on this device. Query
      // Firestore to prevent two users creating same-named public borough groups.
      try {
        final onboardingCheck = OnboardingDataService();
        await onboardingCheck.initialize();
        final checkBorough = PostcodeService()
            .getBoroughFromPostcode(onboardingCheck.postcode);
        if (checkBorough != null) {
          final fsSnap = await FirebaseFirestore.instance
              .collection('groups')
              .where('borough', isEqualTo: checkBorough)
              .where('name', isEqualTo: _nameController.text.trim())
              .where('isPrivate', isEqualTo: false)
              .limit(1)
              .get();
          if (fsSnap.docs.isNotEmpty) {
            if (mounted) _showDuplicateNameDialog();
            return;
          }
        }
      } catch (e) {
        // Non-fatal — offline or index not deployed; continue with creation
        if (kDebugMode) debugPrint('[CreateGroup] Firestore dupe check failed: $e');
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

      GroupPrivacy privacy = GroupPrivacy.public;
      if (_privacy == 'group') {
        privacy = GroupPrivacy.group;
      } else if (_privacy == 'private') {
        privacy = GroupPrivacy.private_;
      }

      // ── AI tagline: generate silently from the user's description ─────
      final aiTagline = await _generateAiTagline(
        groupName: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        audience: selectedAudience,
      );

      var newGroup = Group(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: _pickedImageUrl!,
        memberCount: _privacy == 'private' ? 1 + _selectedMemberIds.length : 1,
        category: selectedAudience.isNotEmpty
            ? selectedAudience.join(', ').toUpperCase()
            : 'PARENTING',
        isJoined: true,
        isImageLocked: false,
        targetAudience: selectedAudience,
        privacy: privacy,
        parentGroupId: _privacy == 'group' ? _selectedParentGroupId : null,
        parentGroupName: _privacy == 'group' ? _selectedParentGroupName : null,
        creatorId: FirebaseAuth.instance.currentUser?.uid ?? 'current_user',
        creatorName: creatorName,
        creatorBorough: creatorBorough,
        invitedMemberIds: _privacy == 'private' ? _selectedMemberIds.toList() : [],
        lastMessage: '$creatorName created this group',
        lastSenderName: 'System',
        lastMessageTime: DateTime.now(),
        aiTagline: aiTagline,
      );

      // ── Write to Firestore so the group survives reinstall ────────────
      // createGroup() assigns creatorId = real UID and memberIds = [uid],
      // returns the canonical Firestore doc ID.
      String persistedId = newGroup.id;
      try {
        final firestoreId = await FirestoreService().createGroup({
          'name': newGroup.name,
          'description': newGroup.description,
          'imageUrl': newGroup.imageUrl,
          'memberCount': newGroup.memberCount,
          'category': newGroup.category,
          'isImageLocked': newGroup.isImageLocked,
          'targetAudience': newGroup.targetAudience,
          'privacy': newGroup.privacy == GroupPrivacy.private_
              ? 'private'
              : newGroup.privacy == GroupPrivacy.group
                  ? 'group'
                  : 'public',
          'parentGroupId': newGroup.parentGroupId,
          'parentGroupName': newGroup.parentGroupName,
          'creatorName': creatorName,
          'borough': creatorBorough,          // canonical field going forward
          'creatorBorough': creatorBorough,   // legacy dual-write; remove after backfill
          'invitedMemberIds': newGroup.invitedMemberIds,
          'lastMessage': newGroup.lastMessage ?? '$creatorName created this group',
          'lastSenderName': 'System',
          'lastMessageTime': newGroup.lastMessageTime?.toIso8601String(),
          if (aiTagline != null && aiTagline.isNotEmpty) 'aiTagline': aiTagline,
          // ── Section 5H: Admin role fields ──────────────────────────────
          'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'admins': [FirebaseAuth.instance.currentUser?.uid ?? ''],
          'members': [FirebaseAuth.instance.currentUser?.uid ?? ''],
        });
        persistedId = firestoreId;
        // ── Section 5H: Write memberActivity sub-collection for creator ──
        final creatorUid = FirebaseAuth.instance.currentUser?.uid;
        if (creatorUid != null && firestoreId.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('groups')
                .doc(firestoreId)
                .collection('memberActivity')
                .doc(creatorUid)
                .set({
              'userId': creatorUid,
              'messageCount': 0,
              'joinedAt': FieldValue.serverTimestamp(),
              'lastActiveAt': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            if (kDebugMode) debugPrint('⚠️ create_group: memberActivity write failed: $e');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ create_group: Firestore write failed, using local ID: $e');
      }

      // ── Promote to real Firestore doc ID if we got one ─────────────────
      if (persistedId != newGroup.id) {
        newGroup = newGroup.copyWith(id: persistedId);
      }

      // ── Write to BrowserStorage (local cache / offline fallback) ─────────
      final existingJson = await BrowserStorage.getString(_userGroupsKey);
      List<dynamic> groups = [];
      if (existingJson != null) {
        groups = json.decode(existingJson) as List<dynamic>;
      }
      groups.add(newGroup.toJson());
      await BrowserStorage.setString(_userGroupsKey, json.encode(groups));

      // ── Also write public groups to the v2 key (home-feed discovery) ─────
      // Private/group-privacy groups are invite-only so they don't appear in
      // the home feed's suggested groups section.
      if (_privacy == 'public') {
        const homeFeedKey = 'user_created_groups_v2';
        final feedJson = await BrowserStorage.getString(homeFeedKey);
        List<dynamic> feedGroups = [];
        if (feedJson != null) {
          feedGroups = json.decode(feedJson) as List<dynamic>;
        }
        // Avoid duplicates
        feedGroups.removeWhere(
            (g) => (g as Map<String, dynamic>)['id'] == newGroup.id);
        feedGroups.add(newGroup.toJson());
        await BrowserStorage.setString(homeFeedKey, json.encode(feedGroups));
      }

      final invService = InvitationService();
      await invService.initialize();
      await invService.addSystemMessage(
        groupId: newGroup.id,
        userName: creatorName,
        type: 'joined',
      );

      if (_privacy == 'private' && _selectedMemberIds.isNotEmpty) {
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
              const Icon(HuddlIcons.checkCircle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_privacy == 'private'
                    ? '"${newGroup.name}" created! Invitations sent to ${_selectedMemberIds.length} member(s).'
                    : _privacy == 'group'
                        ? '"${newGroup.name}" created! Visible to members of ${_selectedParentGroupName ?? 'the selected group'}.'
                        : '"${newGroup.name}" created and listed in Discover for ${creatorBorough != 'Unknown Borough' ? creatorBorough : 'your borough'}!'),
              ),
            ]),
            backgroundColor: HuddlColors.textDark,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        // Record usage for subscription tracking
        await subService.recordUserGroupCreated();
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
            Icon(HuddlIcons.warning,
                color: HuddlColors.textDark, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Group Name Taken',
                style: HuddlText.heading(),
              ),
            ),
          ],
        ),
        content: Text(
          'A group with this name already exists. Please use an alternative name.',
          style: HuddlText.body(color: context.hc.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: HuddlText.body(weight: FontWeight.w600),
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
      backgroundColor: context.hc.surface,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─────────── BOROUGH SCOPE NOTE ───────────
                    const BoroughGateMessage(featureLabel: 'Groups'),

                    // ─────────── PHOTO UPLOAD (blue banner) ───────────
                    _buildPhotoUpload(),

                    // ─────────── GROUPS CREATED COUNTER (lifetime) ───────────
                    Builder(builder: (context) {
                      final ss = SubscriptionService();
                      if (TierLimits.isUnlimited(ss.limits.maxUserCreatedGroupsLifetime)) {
                        return const SizedBox.shrink();
                      }
                      final used = ss.userGroupsCreatedTotal;
                      final max = ss.limits.maxUserCreatedGroupsLifetime;
                      final remaining = ss.userGroupsCreatedRemaining;
                      return Container(
                        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: remaining == 0
                              ? HuddlColors.primary.withValues(alpha: 0.08)
                              : context.hc.inputBg,
                          borderRadius: BorderRadius.circular(10),
                          border: remaining == 0
                              ? Border.all(
                                  color: HuddlColors.primary.withValues(alpha: 0.20),
                                  width: 0.5)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              HuddlIcons.diversity,
                              size: 14,
                              color: remaining == 0
                                  ? HuddlColors.primary
                                  : context.hc.textTertiary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                remaining == 0
                                    ? 'Free group limit reached — upgrade for unlimited'
                                    : 'Free group ${used + 1} of $max',
                                style: HuddlText.caption(
                                  color: remaining == 0
                                      ? HuddlColors.primary
                                      : context.hc.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 22),

                          // ─────────── GROUP TITLE ───────────
                          _sectionHeader('Group title'),
                          const SizedBox(height: 6),
                          _buildGrayField(
                            controller: _nameController,
                            hint: 'e.g. Hackney Toddler Playgroup',
                            onChanged: (_) => setState(() {}),
                          ),
                          // Inline duplicate warning
                          if (_hasSimilarGroup) ...[  
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(HuddlIcons.info,
                                    size: 14, color: _accentOrange),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    'A similar group already exists: ${_similarGroupNames.join(', ')}. Consider joining it instead.',
                                    style: HuddlText.caption(color: _accentOrange).copyWith(height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 20),

                          // ─────────── DESCRIPTION ───────────
                          _sectionHeader('Group description'),
                          const SizedBox(height: 6),
                          _buildGrayField(
                            controller: _descriptionController,
                            hint: 'e.g. who this group is for, what activities are planned.',
                            maxLines: 4,
                            onChanged: (_) => setState(() {}),
                          ),

                          const SizedBox(height: 20),

                          // ─────────── WHO IS THIS GROUP FOR? ───────────
                          _sectionHeader('Who is this group for?'),
                          const SizedBox(height: 10),
                          ..._audienceChecks.keys.map((label) {
                            final isChecked = _audienceChecks[label]!;
                            return GestureDetector(
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
                                        style: HuddlText.body(color: context.hc.textPrimary)),
                                  ],
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 20),

                          // ─────────── PRIVACY SETTINGS ───────────
                          _sectionHeader('Privacy settings'),
                          const SizedBox(height: 10),
                          _privacyRadio(
                            label: 'Public',
                            description:
                                'Everyone in your local community can see and join your group.',
                            isSelected: _privacy == 'public',
                            icon: HuddlIcons.language,
                            onTap: () => setState(() {
                              _privacy = 'public';
                              _selectedParentGroupId = null;
                              _selectedParentGroupName = null;
                            }),
                          ),
                          const SizedBox(height: 10),
                          _privacyRadio(
                            label: 'Group',
                            description:
                                'Only members of a specific group can see and join your group.',
                            isSelected: _privacy == 'group',
                            icon: HuddlIcons.usersThree,
                            onTap: () => setState(() {
                              _privacy = 'group';
                            }),
                          ),
                          if (_privacy == 'group') ...[
                            const SizedBox(height: 12),
                            _buildGroupPicker(),
                          ],
                          const SizedBox(height: 10),
                          Builder(builder: (context) {
                            final canPrivate =
                                SubscriptionService().canCreatePrivateGroup;
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Greyed overlay when locked
                                if (!canPrivate)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                              alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                _privacyRadio(
                                  label: 'Private',
                                  description: canPrivate
                                      ? 'Invite only — choose specific people in ${_userBorough ?? 'your borough'} to invite.'
                                      : 'Invite only — upgrade to Huddl Plus to unlock.',
                                  isSelected: _privacy == 'private',
                                  icon: HuddlIcons.lock,
                                  onTap: canPrivate
                                      ? () => setState(() {
                                            _privacy = 'private';
                                            _selectedParentGroupId = null;
                                            _selectedParentGroupName = null;
                                          })
                                      : () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Upgrade to Huddl Plus to create private groups.',
                                              ),
                                            ),
                                          );
                                        },
                                ),
                                // Lock badge — top-right corner
                                if (!canPrivate)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: HuddlColors.nearBlack,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        HuddlIcons.lock,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          }),
                          if (_privacy == 'private') ...[
                            const SizedBox(height: 12),
                            _buildInviteMembersWidget(),
                          ],

                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ─────────── STICKY CREATE BUTTON ───────────
            _buildStickyCreateButton(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMPONENT WIDGETS (Create Meetup design language — Figma-aligned)
  // ══════════════════════════════════════════════════════════════════════════

  // ────────────────────────────────────────────────────────────────────────
  // APP BAR — adaptive bg, orange back arrow, centred title, bottom divider
  // ────────────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.hc.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(HuddlIcons.arrowBack, size: 18, color: _accentOrange),
          ),
        ),
      ),
      centerTitle: true,
      title: Text(
        'Create group',
        style: HuddlText.heading(),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: context.hc.divider),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // STICKY CREATE BUTTON — gradient orange, disabled grey, h52, r26
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildStickyCreateButton() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
      child: GestureDetector(
        onTap: _isValid && !_isCreating ? _createGroup : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: null,
            color: _isValid ? HuddlColors.primary : HuddlColors.neutral100,
            borderRadius: BorderRadius.circular(26),
            boxShadow: _isValid
                ? [
                    BoxShadow(
                        color: HuddlColors.primary.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ]
                : null,
          ),
          child: Center(
            child: _isCreating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text(
                    'Create group',
                    style: HuddlText.body(weight: FontWeight.w600, color: _isValid ? Colors.white : HuddlColors.neutral300),
                  ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // PHOTO UPLOAD — blue banner placeholder + picked-image overlay
  // ────────────────────────────────────────────────────────────────────────
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
                left: 0, right: 0, bottom: 0,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(HuddlIcons.edit,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Change photo',
                          style: HuddlText.body(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Placeholder: brand-colored photo banner
    return GestureDetector(
      onTap: _pickGroupImage,
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: BoxDecoration(
          color: _bannerBg,
          border: _showImageError
              ? Border.all(color: HuddlColors.error, width: 2)
              : Border.all(
                  color: HuddlColors.divider,
                  width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              HuddlIcons.photoLibrary,
              color: HuddlColors.primaryLight,   // HuddlColors.primaryLight
              size: 48,
            ),
            const SizedBox(height: 10),
            Text(
              'Click to add group photo',
              style: HuddlText.body(color: HuddlColors.neutral600)),
            if (_showImageError) ...[
              const SizedBox(height: 4),
              Text(
                'A group image is required',
                style: HuddlText.caption(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // SECTION HEADER — 16/w700 matching Create Meetup Figma
  // ────────────────────────────────────────────────────────────────────────
  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: HuddlText.body(weight: FontWeight.w700),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // GRAY FILLED TEXT FIELD — #F6F6F8 bg, bottom underline (Figma)
  // ────────────────────────────────────────────────────────────────────────
  Widget _buildGrayField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
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
        keyboardType: keyboardType,
        textInputAction:
            maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
        style: HuddlText.body(color: _sectionText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: HuddlText.body(color: _hintGray),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
        onChanged: onChanged,
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
          ? const Icon(HuddlIcons.check, size: 16, color: Colors.white)
          : null,
    );
  }

  /// Group picker — shown when privacy = 'group'
  Widget _buildGroupPicker() {
    if (_userGroups.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(left: 32),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HuddlColors.neutral50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(HuddlIcons.info,
                size: 16, color: HuddlColors.textDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You don\'t belong to any groups yet. Join a group first to use group privacy.',
                style: HuddlText.caption(color: HuddlColors.textDark).copyWith(height: 1.3),
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
          color: _selectedParentGroupId != null
              ? HuddlColors.primary
              : HuddlColors.gray300,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedParentGroupId,
          isExpanded: true,
          hint: Text('Select a parent group',
              style: HuddlText.body(color: context.hc.textTertiary)),
          icon: Icon(HuddlIcons.caretDown,
              color: _selectedParentGroupId != null
                  ? HuddlColors.primary
                  : HuddlColors.textHint),
          style:
              HuddlText.body(color: context.hc.textPrimary),
          items: _userGroups.map((g) {
            return DropdownMenuItem(
              value: g.id,
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: HuddlColors.neutral50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Icon(HuddlIcons.usersThree,
                          size: 14, color: HuddlColors.textDark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(g.name,
                        overflow: TextOverflow.ellipsis,
                        style: HuddlText.body(color: context.hc.textPrimary)),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            final group = _userGroups.firstWhere((g) => g.id == v,
                orElse: () => _userGroups.first);
            setState(() {
              _selectedParentGroupId = v;
              _selectedParentGroupName = group.name;
            });
          },
        ),
      ),
    );
  }

  /// Privacy radio — clean style matching Create Meetup's _privacyRadio
  Widget _privacyRadio({
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
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
                      style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: HuddlText.caption(color: context.hc.textTertiary).copyWith(height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
