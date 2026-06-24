import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/huddl_icons.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../services/invitation_service.dart';
import '../../services/dm_service.dart';
import '../../services/realtime_dm_service.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/browser_storage.dart';
import 'dm_chat_screen.dart' show getProfilePhotoForMember;
import '../../constants/app_text_styles.dart';

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
  Uint8List? imageBytes,
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
  Map<String, dynamic>? eventData,
  bool isEventCard = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForwardSheet(
      messageText: messageText,
      imageUrl: imageUrl,
      imageBytes: imageBytes,
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
      eventData: eventData,
      isEventCard: isEventCard,
    ),
  );
}

class _ForwardSheet extends StatefulWidget {
  final String messageText;
  final String? imageUrl;
  final Uint8List? imageBytes;
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
  final Map<String, dynamic>? eventData;
  final bool isEventCard;

  const _ForwardSheet({
    required this.messageText,
    this.imageUrl,
    this.imageBytes,
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
    this.eventData,
    this.isEventCard = false,
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
      final membershipsRaw = await BrowserStorage.getString('user_memberships_v6');
      if (membershipsRaw != null) {
        final Map<String, dynamic> membershipsMap = json.decode(membershipsRaw);
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
        final groupIds = (membershipsMap[uid] as List<dynamic>?)?.cast<String>() ?? [];
        final groupsRaw = await BrowserStorage.getString('default_groups_v6');
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
        
        final msgData = {
          'id': 'gm_fwd_${DateTime.now().millisecondsSinceEpoch}',
          'senderId': 'current_user',
          'senderName': userName,
          'message': fwdText,
          'timestamp': DateTime.now().toIso8601String(),
          'isForwarded': true,
          'type': msgType,
          'imageUrl': widget.imageUrl,
          // Store bytes as base64 so the image can be rendered after reload
          if (widget.imageBytes != null) 'bytesBase64': base64Encode(widget.imageBytes!),
          'documentName': widget.documentName,
          'latitude': widget.latitude,
          'longitude': widget.longitude,
          'locationLabel': widget.locationLabel,
          'contactName': widget.contactName,
          'contactPhone': widget.contactPhone,
        };
        
        // Add card data if present
        if (widget.isMeetupCard && widget.meetupData != null) {
          msgData['isMeetupCard'] = true;
          msgData['meetupData'] = widget.meetupData;
          if (kDebugMode) {
            debugPrint('✅ Saving meetup card to group ${target.id}');
          }
        }
        if (widget.isGroupCard && widget.groupData != null) {
          msgData['isGroupCard'] = true;
          msgData['groupData'] = widget.groupData;
          if (kDebugMode) {
            debugPrint('✅ Saving group card to group ${target.id}');
          }
        }
        if (widget.isItemCard && widget.itemData != null) {
          msgData['isItemCard'] = true;
          msgData['itemData'] = widget.itemData;
          if (kDebugMode) {
            debugPrint('✅ Saving item card to group ${target.id}');
          }
        }
        if (widget.isEventCard && widget.eventData != null) {
          msgData['isEventCard'] = true;
          msgData['eventData'] = widget.eventData;
          if (kDebugMode) {
            debugPrint('✅ Saving event card to group ${target.id}');
          }
        }
        
        msgs.add(msgData);
        await BrowserStorage.setString(key, json.encode(msgs));
      } catch (_) {}
      return;
    }

    // Forward to DM — route through the moderated gate (MODERATION-COVERAGE-1).
    // RealtimeDMService.getOrCreateConversation creates/finds the Firestore
    // conversation doc and returns the conversation ID (or null on error).
    final realtimeDM = RealtimeDMService();
    final convId = await realtimeDM.getOrCreateConversation(target.id);
    if (convId == null || convId == 'blocked') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              convId == 'blocked'
                  ? 'You cannot send messages to this person.'
                  : 'Could not start conversation. Please try again.',
            ),
          ),
        );
      }
      return;
    }

    // Determine type string and message text matching existing conventions.
    // Type strings mirror MessageType.name values used by RealtimeDMMessage.fromFirestore.
    final SendDmResult result;
    if (widget.imageUrl != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: widget.messageText.isNotEmpty ? widget.messageText : 'Photo',
        type: 'image',
        imageUrl: widget.imageUrl,
        meetupData: widget.meetupData,
        groupData: widget.groupData,
        itemData: widget.itemData,
      );
    } else if (widget.documentName != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: widget.documentName!,
        type: 'document',
        documentName: widget.documentName,
        meetupData: widget.meetupData,
        groupData: widget.groupData,
        itemData: widget.itemData,
      );
    } else if (widget.latitude != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: widget.locationLabel ?? 'Location',
        type: 'location',
        latitude: widget.latitude,
        longitude: widget.longitude,
        locationLabel: widget.locationLabel,
        meetupData: widget.meetupData,
        groupData: widget.groupData,
        itemData: widget.itemData,
      );
    } else if (widget.contactName != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: widget.contactName!,
        type: 'contact',
        contactName: widget.contactName,
        contactPhone: widget.contactPhone,
        meetupData: widget.meetupData,
        groupData: widget.groupData,
        itemData: widget.itemData,
      );
    } else if (widget.isMeetupCard && widget.meetupData != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: widget.messageText,
        type: 'meetupInvite',
        meetupData: widget.meetupData,
      );
    } else if (widget.isGroupCard && widget.groupData != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: 'Shared a group',
        type: 'text',
        groupData: widget.groupData,
      );
    } else if (widget.isItemCard && widget.itemData != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: 'Shared an item for sale',
        type: 'text',
        itemData: widget.itemData,
      );
    } else if (widget.isEventCard && widget.eventData != null) {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: 'Shared an event',
        type: 'text',
        eventData: widget.eventData,
      );
    } else {
      result = await realtimeDM.sendMessageModerated(
        conversationId: convId,
        message: widget.messageText,
        type: 'text',
      );
    }

    // Per-target blocked handling: if this target blocked the sender, note it
    // but do NOT abort — caller continues with remaining targets.
    if (!target.isGroup && context.mounted) {
      if (result == SendDmResult.blocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Message to ${target.name} could not be sent — it may violate our community guidelines.',
            ),
          ),
        );
      } else {
        final cardType = widget.isGroupCard && widget.groupData != null
            ? 'GROUP CARD'
            : widget.isItemCard && widget.itemData != null
                ? 'ITEM CARD'
                : widget.isEventCard && widget.eventData != null
                    ? 'EVENT CARD'
                    : widget.isMeetupCard && widget.meetupData != null
                        ? 'MEETUP CARD'
                        : 'TEXT';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Sent $cardType to ${target.name}'),
            duration: const Duration(seconds: 3),
            backgroundColor: HuddlColors.success,
          ),
        );
      }
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                  style: HuddlText.heading(),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: HuddlText.body(),
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
                Icon(HuddlIcons.search, size: 20, color: context.hc.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textAlignVertical: TextAlignVertical.center,
                    style: HuddlText.body(color: context.hc.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search list',
                      hintStyle: HuddlText.body(color: context.hc.textTertiary),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
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
                      child: Icon(HuddlIcons.close,
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
              labelStyle: HuddlText.caption(weight: FontWeight.w600),
              unselectedLabelStyle: HuddlText.caption(),
              tabs: [
                Tab(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(HuddlIcons.user, size: 16),
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
                      const Icon(HuddlIcons.usersThree, size: 16),
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
                        CircularProgressIndicator(color: HuddlColors.textTertiary))
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
              Icon(HuddlIcons.searchOff,
                  size: 40, color: context.hc.textTertiary),
              const SizedBox(height: 12),
              Text(
                emptyLabel,
                style: HuddlText.body(),
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

  Widget _meetupPlaceholder() => Container(
        color: HuddlColors.neutral50,
        child: const Center(child: Icon(HuddlIcons.calendar, size: 24, color: HuddlColors.textDark)),
      );

  Widget _groupPlaceholder() => Container(
        color: HuddlColors.neutral50,
        child: const Center(child: Icon(HuddlIcons.usersThree, size: 24, color: HuddlColors.textDark)),
      );

  Widget _eventPlaceholder() => Container(
        color: HuddlColors.nearBlack.withValues(alpha: 0.12),
        child: const Center(child: Icon(HuddlIcons.calendar, size: 24, color: HuddlColors.nearBlack)),
      );

  /// Builds the preview section — image thumbnail + caption, or text preview.
  Widget _buildPreview() {
    // ── Meetup card preview ───────────────────────────────────────────────
    if (widget.isMeetupCard && widget.meetupData != null) {
      final data = widget.meetupData!;
      final title = data['title'] as String? ?? 'Meetup';
      final dateDisplay = data['dateDisplay'] as String? ?? '';
      final timeDisplay = data['timeDisplay'] as String? ?? '';
      final location = data['location'] as String? ?? '';
      final imageUrl = data['imageUrl'] as String? ?? '';
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Meetup thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: imageUrl.startsWith('http')
                    ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover,
                        width: 56, height: 56, memCacheWidth: 112,
                        errorWidget: (_, __, ___) => _meetupPlaceholder())
                    : imageUrl.startsWith('assets/')
                        ? Image.asset(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _meetupPlaceholder())
                        : _meetupPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (dateDisplay.isNotEmpty || timeDisplay.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(HuddlIcons.calendar, size: 11, color: HuddlColors.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$dateDisplay${timeDisplay.isNotEmpty ? '  ⏰ $timeDisplay' : ''}',
                              style: HuddlText.caption(color: context.hc.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (location.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(HuddlIcons.locationPin, size: 11, color: HuddlColors.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location,
                              style: HuddlText.caption(color: context.hc.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Group card preview ────────────────────────────────────────────────
    if (widget.isGroupCard && widget.groupData != null) {
      final data = widget.groupData!;
      final name = data['name'] as String? ?? 'Group';
      final memberCount = (data['memberCount'] as num?)?.toInt() ?? 0;
      final description = data['description'] as String? ?? '';
      final imageUrl = data['imageUrl'] as String? ?? '';
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Group thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: imageUrl.startsWith('http')
                    ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover,
                        width: 56, height: 56, memCacheWidth: 112,
                        errorWidget: (_, __, ___) => _groupPlaceholder())
                    : imageUrl.startsWith('assets/')
                        ? Image.asset(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _groupPlaceholder())
                        : _groupPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      children: [
                        const Icon(HuddlIcons.usersThree, size: 11, color: HuddlColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          '$memberCount members',
                          style: HuddlText.caption(color: context.hc.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        style: HuddlText.caption(color: context.hc.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Event card preview ────────────────────────────────────────────────
    if (widget.isEventCard && widget.eventData != null) {
      final data = widget.eventData!;
      final title = data['title'] as String? ?? 'Event';
      final date = data['date'] as String? ?? '';
      final time = data['time'] as String? ?? '';
      final location = data['location'] as String? ?? '';
      final imageUrl = data['imageUrl'] as String? ?? '';
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.hc.scaffold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Event thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: imageUrl.startsWith('http')
                    ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover,
                        width: 56, height: 56, memCacheWidth: 112,
                        errorWidget: (_, __, ___) => _eventPlaceholder())
                    : imageUrl.startsWith('assets/')
                        ? Image.asset(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _eventPlaceholder())
                        : _eventPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(HuddlIcons.calendar, size: 11, color: HuddlColors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        'Event',
                        style: HuddlText.label(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: HuddlText.body(weight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (date.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(HuddlIcons.calendar, size: 11, color: HuddlColors.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$date${time.isNotEmpty ? '  \u23f0 $time' : ''}',
                              style: HuddlText.caption(color: context.hc.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (location.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(HuddlIcons.locationPin, size: 11, color: HuddlColors.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              location,
                              style: HuddlText.caption(color: context.hc.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                memCacheWidth: 112,
                errorWidget: (_, __, ___) => Container(
                  width: 56,
                  height: 56,
                  color: HuddlColors.neutral50,
                  child: const Icon(HuddlIcons.image,
                      size: 24, color: HuddlColors.textDark),
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
                    style: HuddlText.body(),
                  ),
                  if (widget.messageText.isNotEmpty &&
                      widget.messageText != 'Photo')
                    Text(
                      widget.messageText,
                      style: HuddlText.caption(),
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
                color: HuddlColors.peachSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(HuddlIcons.locationPinFill,
                  size: 20, color: HuddlColors.error),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.locationLabel ?? 'Shared location',
                style: HuddlText.body(),
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
                color: HuddlColors.neutral50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(HuddlIcons.user,
                  size: 20, color: HuddlColors.textDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName!,
                    style: HuddlText.body(),
                  ),
                  if (widget.contactPhone != null)
                    Text(
                      widget.contactPhone!,
                      style: HuddlText.caption(),
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
                color: HuddlColors.nearBlack.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(HuddlIcons.file,
                  size: 20, color: HuddlColors.nearBlack),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.documentName!,
                style: HuddlText.body(),
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
          Icon(HuddlIcons.chat,
              size: 16, color: context.hc.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.messageText,
              style: HuddlText.body(),
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
                  style: HuddlText.body(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (target.isGroup)
                  Text(
                    'Group',
                    style: HuddlText.caption(),
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
      final gUrl = target.groupImageUrl ?? '';
      Widget groupImage;
      if (gUrl.startsWith('http')) {
        groupImage = CachedNetworkImage(
          imageUrl: gUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          memCacheWidth: (size * 2).toInt(),
          errorWidget: (_, __, ___) => _groupInitialsWidget(target.id, target.name, size),
        );
      } else if (gUrl.startsWith('assets/')) {
        groupImage = Image.asset(
          gUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => _groupInitialsWidget(target.id, target.name, size),
        );
      } else {
        // No image URL — show unique initials avatar
        groupImage = _groupInitialsWidget(target.id, target.name, size);
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: HuddlColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: groupImage,
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
          ? CachedNetworkImage(
              imageUrl: target.avatarUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              memCacheWidth: (size * 2).toInt(),
              errorWidget: (_, __, ___) => Center(
                child: Text(
                  target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                  style: HuddlText.heading(),
                ),
              ),
            )
          : Center(
              child: Text(
                target.name.isNotEmpty ? target.name[0].toUpperCase() : '?',
                style: HuddlText.heading(),
              ),
            ),
    );
  }

  /// Unique initials avatar for groups that have no image stored in Firestore.
  /// Uses the same deterministic color + initials logic as the main groups screen.
  Widget _groupInitialsWidget(String id, String name, double size) {
    // Use the canonical avatar palette from the design system token.
    const List<Color> palette = HuddlColors.avatarPalette;
    final seed = id.isNotEmpty ? id : name;
    int hash = 0;
    for (final c in seed.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    final bgColor = palette[hash % palette.length];

    // Build initials — up to 2 chars from significant words
    String initials;
    if (name.isEmpty) {
      initials = '?';
    } else {
      final words = name.trim().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      if (words.isEmpty) {
        initials = name[0].toUpperCase();
      } else if (words.length == 1) {
        initials = words[0].substring(0, words[0].length.clamp(1, 2)).toUpperCase();
      } else {
        initials = '${words[0][0]}${words[1][0]}'.toUpperCase();
      }
    }

    return Container(
      width: size,
      height: size,
      color: bgColor,
      child: Center(
        child: Text(
          initials,
          style: HuddlText.caption(weight: FontWeight.w600, color: Colors.white).copyWith(
            fontSize: size * (initials.length > 1 ? 0.30 : 0.38),
            letterSpacing: 0.5,
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
          style: HuddlText.caption(weight: FontWeight.w700, color: textColor),
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
