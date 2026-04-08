import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/invitation_service.dart';
import '../../services/dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/browser_storage.dart';
import '../../models/direct_message.dart';
import 'dm_chat_screen.dart' show getProfilePhotoForMember;

/// Represents a forwarding target — either a DM contact or a group.
class _ForwardTarget {
  final String id;
  final String name;
  final String? avatarUrl;
  final String avatarColor;
  final bool isGroup;
  final String? groupImageUrl;

  const _ForwardTarget({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.avatarColor = '#FF975C',
    this.isGroup = false,
    this.groupImageUrl,
  });
}

/// State of a forward-send for a target.
enum _SendState { idle, sending, sent, undo }

/// Shows a bottom sheet for forwarding a message/photo/document to
/// one or more DM contacts or groups.
///
/// Matches the design reference: white sheet, "Send to" header,
/// image thumbnail preview, search field, RECENTS list, orange
/// SEND button that becomes UNDO (5 sec) then SENT.
Future<void> showForwardSheet({
  required BuildContext context,
  required String messageText,
  String? imageUrl,
  String? documentName,
  double? latitude,
  double? longitude,
  String? locationLabel,
  String? contactName,
  String? contactPhone,
  Map<String, dynamic>? meetupData,
  bool isMeetupCard = false,
  Map<String, dynamic>? groupData,
  bool isGroupCard = false,
  Map<String, dynamic>? itemData,
  bool isItemCard = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForwardSheet(
      messageText: messageText,
      imageUrl: imageUrl,
      documentName: documentName,
      latitude: latitude,
      longitude: longitude,
      locationLabel: locationLabel,
      contactName: contactName,
      contactPhone: contactPhone,
      meetupData: meetupData,
      isMeetupCard: isMeetupCard,
      groupData: groupData,
      isGroupCard: isGroupCard,
      itemData: itemData,
      isItemCard: isItemCard,
    ),
  );
}

class _ForwardSheet extends StatefulWidget {
  final String messageText;
  final String? imageUrl;
  final String? documentName;
  final double? latitude;
  final double? longitude;
  final String? locationLabel;
  final String? contactName;
  final String? contactPhone;
  final Map<String, dynamic>? meetupData;
  final bool isMeetupCard;
  final Map<String, dynamic>? groupData;
  final bool isGroupCard;
  final Map<String, dynamic>? itemData;
  final bool isItemCard;

  const _ForwardSheet({
    required this.messageText,
    this.imageUrl,
    this.documentName,
    this.latitude,
    this.longitude,
    this.locationLabel,
    this.contactName,
    this.contactPhone,
    this.meetupData,
    this.isMeetupCard = false,
    this.groupData,
    this.isGroupCard = false,
    this.itemData,
    this.isItemCard = false,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final DMService _dmService = DMService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  late final TabController _tabCtrl;

  String _query = '';
  bool _loading = true;

  /// Per-target send state, keyed by target.id
  final Map<String, _SendState> _sendStates = {};
  final Map<String, Timer?> _undoTimers = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      // Re-apply filter when tab changes so search is scoped
      if (!_tabCtrl.indexIsChanging) {
        _applyFilter(_query);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    for (final t in _undoTimers.values) {
      t?.cancel();
    }
    super.dispose();
  }

  /// Separate lists for members and groups, for sectioned display.
  List<_ForwardTarget> _memberTargets = [];
  List<_ForwardTarget> _groupTargets = [];
  List<_ForwardTarget> _filteredMembers = [];
  List<_ForwardTarget> _filteredGroupsList = [];

  Future<void> _load() async {
    await _dmService.initialize();
    await _onboarding.initialize();

    final memberList = <_ForwardTarget>[];
    final groupList = <_ForwardTarget>[];

    // Recent DM conversations first
    for (final conv in _dmService.conversations) {
      memberList.add(_ForwardTarget(
        id: conv.recipientId,
        name: conv.recipientName,
        avatarUrl: getProfilePhotoForMember(conv.recipientId),
        avatarColor: conv.recipientAvatarColor,
      ));
    }

    // Borough members that aren't already in conversations
    final existingIds = memberList.map((t) => t.id).toSet();
    final boroughMembers = InvitationService.getBoroughMembers(null);
    for (final m in boroughMembers) {
      if (!existingIds.contains(m.id)) {
        memberList.add(_ForwardTarget(
          id: m.id,
          name: m.name,
          avatarUrl: getProfilePhotoForMember(m.id),
        ));
      }
    }

    // Joined groups (from InvitationService)
    final invService = InvitationService();
    await invService.initialize();
    for (final g in invService.joinedGroups) {
      groupList.add(_ForwardTarget(
        id: g.id,
        name: g.name,
        isGroup: true,
        groupImageUrl: g.imageUrl,
      ));
    }

    // Also include user-created groups from local storage
    try {
      final raw = await BrowserStorage.getString('user_created_groups_v1');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        for (final j in decoded) {
          final g = j as Map<String, dynamic>;
          final gId = g['id'] as String;
          if (!groupList.any((t) => t.id == gId)) {
            groupList.add(_ForwardTarget(
              id: gId,
              name: g['name'] as String? ?? 'Group',
              isGroup: true,
              groupImageUrl: g['imageUrl'] as String?,
            ));
          }
        }
      }
    } catch (_) {}

    // Also include default groups the user is in
    try {
      final membershipsRaw = await BrowserStorage.getString('user_memberships_v4');
      if (membershipsRaw != null) {
        final Map<String, dynamic> membershipsMap = json.decode(membershipsRaw);
        final groupIds = (membershipsMap['current_user'] as List<dynamic>?)?.cast<String>() ?? [];
        final groupsRaw = await BrowserStorage.getString('default_groups_v4');
        if (groupsRaw != null && groupIds.isNotEmpty) {
          final Map<String, dynamic> groupsMap = json.decode(groupsRaw);
          for (final entry in groupsMap.entries) {
            final g = entry.value as Map<String, dynamic>;
            final gId = g['id'] as String;
            if (groupIds.contains(gId) && !groupList.any((t) => t.id == gId)) {
              groupList.add(_ForwardTarget(
                id: gId,
                name: g['name'] as String? ?? 'Group',
                isGroup: true,
                groupImageUrl: g['imageUrl'] as String?,
              ));
            }
          }
        }
      }
    } catch (_) {}

    setState(() {
      _memberTargets = memberList;
      _groupTargets = groupList;
      _filteredMembers = List.from(memberList);
      _filteredGroupsList = List.from(groupList);
      _loading = false;
    });
  }

  void _applyFilter(String q) {
    setState(() {
      _query = q;
      if (q.isEmpty) {
        _filteredMembers = List.from(_memberTargets);
        _filteredGroupsList = List.from(_groupTargets);
      } else {
        final lower = q.toLowerCase();
        _filteredMembers = _memberTargets
            .where((t) => t.name.toLowerCase().contains(lower))
            .toList();
        _filteredGroupsList = _groupTargets
            .where((t) => t.name.toLowerCase().contains(lower))
            .toList();
      }
    });
  }

  void _onSend(_ForwardTarget target) {
    setState(() => _sendStates[target.id] = _SendState.sending);

    // Simulate send
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _sendStates[target.id] = _SendState.undo);

      // Start 5-second undo window
      _undoTimers[target.id]?.cancel();
      _undoTimers[target.id] = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _sendStates[target.id] = _SendState.sent);
          // Actually forward the message (simulate)
          _doForward(target);
        }
      });
    });
  }

  void _onUndo(_ForwardTarget target) {
    _undoTimers[target.id]?.cancel();
    setState(() => _sendStates[target.id] = _SendState.idle);
  }

  Future<void> _doForward(_ForwardTarget target) async {
    final userName = _onboarding.name ?? 'You';

    if (target.isGroup) {
      // Forward to group chat — store in group messages
      try {
        final key = 'group_messages_${target.id}';
        List<Map<String, dynamic>> msgs = [];
        final raw = await BrowserStorage.getString(key);
        if (raw != null) {
          msgs = (json.decode(raw) as List<dynamic>)
              .cast<Map<String, dynamic>>();
        }
        String fwdText = widget.messageText;
        String msgType = 'text';
        if (widget.imageUrl != null) {
          fwdText = widget.messageText.isNotEmpty ? widget.messageText : 'Photo';
          msgType = 'image';
        } else if (widget.documentName != null) {
          fwdText = widget.documentName!;
          msgType = 'document';
        } else if (widget.latitude != null) {
          fwdText = widget.locationLabel ?? 'Location';
          msgType = 'location';
        } else if (widget.contactName != null) {
          fwdText = '\u{1F464} Contact: ${widget.contactName} - ${widget.contactPhone ?? ''}';
          msgType = 'contact';
        }
        msgs.add({
          'id': 'gm_fwd_${DateTime.now().millisecondsSinceEpoch}',
          'senderId': 'current_user',
          'senderName': userName,
          'message': fwdText,
          'timestamp': DateTime.now().toIso8601String(),
          'isForwarded': true,
          'type': msgType,
          'imageUrl': widget.imageUrl,
          'documentName': widget.documentName,
          'latitude': widget.latitude,
          'longitude': widget.longitude,
          'locationLabel': widget.locationLabel,
          'contactName': widget.contactName,
          'contactPhone': widget.contactPhone,
        });
        await BrowserStorage.setString(key, json.encode(msgs));
      } catch (_) {}
      return;
    }

    // Forward to DM
    final conv = await _dmService.getOrCreateConversation(
      recipientId: target.id,
      recipientName: target.name,
      avatarColor: target.avatarColor,
    );

    if (widget.imageUrl != null) {
      await _dmService.sendMessage(
        conversationId: conv.id,
        message: widget.messageText.isNotEmpty ? widget.messageText : 'Photo',
        senderName: userName,
        type: MessageType.image,
        imageUrl: widget.imageUrl,
      );
    } else if (widget.documentName != null) {
      await _dmService.sendMessage(
        conversationId: conv.id,
        message: widget.documentName!,
        senderName: userName,
        type: MessageType.document,
        documentName: widget.documentName,
      );
    } else if (widget.latitude != null) {
      await _dmService.sendMessage(
        conversationId: conv.id,
        message: widget.locationLabel ?? 'Location',
        senderName: userName,
        type: MessageType.location,
        latitude: widget.latitude,
        longitude: widget.longitude,
        locationLabel: widget.locationLabel,
      );
    } else if (widget.contactName != null) {
      await _dmService.sendMessage(
        conversationId: conv.id,
        message: widget.contactName!,
        senderName: userName,
        type: MessageType.contact,
        contactName: widget.contactName,
        contactPhone: widget.contactPhone,
      );
    } else {
      await _dmService.sendMessage(
        conversationId: conv.id,
        message: widget.messageText,
        senderName: userName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ───────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.hc.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // ── Header — "Send to" + Cancel ──────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Send to',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: HuddlColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Image / message preview ─────────────────────
          _buildPreview(),
          const SizedBox(height: 12),

          // ── Search bar ─────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 44,
            decoration: BoxDecoration(
              color: context.hc.scaffold,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search, size: 20, color: context.hc.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: context.hc.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search list',
                      hintStyle: GoogleFonts.poppins(
                          fontSize: 14, color: context.hc.textTertiary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: _applyFilter,
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      _applyFilter('');
                    },
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close,
                          size: 18, color: context.hc.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // ── Members / Groups tab bar ────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.hc.scaffold,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(3),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                color: HuddlColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: context.hc.textSecondary,
              labelStyle: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: [
                Tab(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.person_outline, size: 16),
                      const SizedBox(width: 6),
                      Text('Members (${_memberTargets.length})'),
                    ],
                  ),
                ),
                Tab(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline, size: 16),
                      const SizedBox(width: 6),
                      Text('Groups (${_groupTargets.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ── Tab content ─────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: HuddlColors.primary))
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      // ── Members tab ──────────────────
                      _buildTargetList(
                        targets: _filteredMembers,
                        emptyLabel: 'No members found',
                        bottomPad: bottomPad,
                      ),
                      // ── Groups tab ───────────────────
                      _buildTargetList(
                        targets: _filteredGroupsList,
                        emptyLabel: 'No groups found',
                        bottomPad: bottomPad,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Builds one tab's target list (Members or Groups).
  Widget _buildTargetList({
    required List<_ForwardTarget> targets,
    required String emptyLabel,
    required double bottomPad,
  }) {
    if (targets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  size: 40, color: context.hc.textTertiary),
              const SizedBox(height: 12),
              Text(
                emptyLabel,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.hc.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(top: 4, bottom: bottomPad + 20),
      itemCount: targets.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 72,
        color: context.hc.divider,
      ),
      itemBuilder: (_, i) {
        final target = targets[i];
        final state = _sendStates[target.id] ?? _SendState.idle;
        return _ForwardContactTile(
          target: target,
          sendState: state,
          onSend: () => _onSend(target),
          onUndo: () => _onUndo(target),
        );
      },
    );
  }

  /// Builds the preview section — image thumbnail + caption, or text preview.
  Widget _buildPreview() {
    // If forwarding an image, show the image thumbnail (matching the design)
    if (widget.imageUrl != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                widget.imageUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: HuddlColors.peachLight,
                  child: const Icon(Icons.image,
                      size: 24, color: HuddlColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                  if (widget.messageText.isNotEmpty &&
                      widget.messageText != 'Photo')
                    Text(
                      widget.messageText,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // If forwarding a location
    if (widget.latitude != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.blueBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.location_on,
                  size: 20, color: HuddlColors.error),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.locationLabel ?? 'Shared location',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: context.hc.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // If forwarding a contact
    if (widget.contactName != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person,
                  size: 20, color: HuddlColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName!,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.hc.textPrimary,
                    ),
                  ),
                  if (widget.contactPhone != null)
                    Text(
                      widget.contactPhone!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // If forwarding a document
    if (widget.documentName != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HuddlColors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.insert_drive_file,
                  size: 20, color: HuddlColors.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.documentName!,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: context.hc.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Text message preview
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.hc.scaffold,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 16, color: context.hc.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.messageText,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: context.hc.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FORWARD CONTACT TILE — avatar + name + SEND/UNDO/SENT button
// ═══════════════════════════════════════════════════════════════════════════════

class _ForwardContactTile extends StatelessWidget {
  final _ForwardTarget target;
  final _SendState sendState;
  final VoidCallback onSend;
  final VoidCallback onUndo;

  const _ForwardContactTile({
    required this.target,
    required this.sendState,
    required this.onSend,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: context.hc.surface,
      child: Row(
        children: [
          // Avatar
          _buildAvatar(),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.hc.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (target.isGroup)
                  Text(
                    'Group',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: context.hc.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          // Send / Undo / Sent button
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const size = 44.0;

    if (target.isGroup) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: HuddlColors.peachLight,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: target.groupImageUrl != null &&
                target.groupImageUrl!.startsWith('http')
            ? Image.network(
                target.groupImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.people,
                    size: 22, color: HuddlColors.primary),
              )
            : const Icon(Icons.people, size: 22, color: HuddlColors.primary),
      );
    }

    final color = _colorFromHex(target.avatarColor);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: target.avatarUrl != null
          ? Image.network(
              target.avatarUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
    );
  }

  Widget _buildActionButton() {
    switch (sendState) {
      case _SendState.idle:
        return _pill(
          label: 'SEND',
          color: HuddlColors.primary,
          textColor: HuddlColors.white,
          onTap: onSend,
        );
      case _SendState.sending:
        return const SizedBox(
          width: 72,
          height: 34,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HuddlColors.primary,
              ),
            ),
          ),
        );
      case _SendState.undo:
        return _pill(
          label: 'UNDO',
          color: HuddlColors.primary,
          textColor: HuddlColors.white,
          onTap: onUndo,
        );
      case _SendState.sent:
        return _pill(
          label: 'SENT',
          color: HuddlColors.primary.withValues(alpha: 0.12),
          textColor: HuddlColors.primary,
        );
    }
  }

  Widget _pill({
    required String label,
    required Color color,
    required Color textColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(17),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

Color _colorFromHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length == 6) {
    return Color(int.parse('FF$clean', radix: 16));
  }
  return HuddlColors.primary;
}
