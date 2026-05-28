import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../widgets/common/huddl_button.dart';
import '../../services/meetup_service.dart';
import '../../services/member_photo_service.dart';
import '../../services/browser_storage.dart';
import '../../constants/app_text_styles.dart';

import '../../models/group.dart';
import '../groups/forward_message_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/backend_api_service.dart';
import 'edit_meetup_screen.dart';



class MeetupDetailScreen extends StatefulWidget {
  final Meetup meetup;
  /// Optional callback invoked when user taps a tag (participant or category).
  /// Receives the tag string (e.g. 'Mums', 'Coffee'). Parent can use it to
  /// apply a filter to the meetup feed after popping.
  final void Function(String tag)? onTagFilter;

  const MeetupDetailScreen({super.key, required this.meetup, this.onTagFilter});

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  final _meetupService = MeetupService();
  late Meetup _meetup;

  @override
  void initState() {
    super.initState();
    _meetup = widget.meetup;
    _meetupService.addListener(_refresh);
    // Ensure user-uploaded base64 images are restored into memory
    _meetupService.restoreCustomImages();
  }

  @override
  void dispose() {
    _meetupService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final updated = _meetupService.meetups
        .where((m) => m.id == _meetup.id)
        .toList();
    if (updated.isNotEmpty) {
      setState(() => _meetup = updated.first);
    }
  }

  void _toggleGoing() {
    HapticFeedback.mediumImpact();
    final wasGoing = _meetup.isGoing;
    _meetupService.toggleGoing(_meetup.id);

    // If user just said "Count Me In", create a meetup group chat
    if (!wasGoing) {
      _createMeetupGroupChat();
    }
  }

  /// Creates (or joins) a shared Firestore group chat for all meetup attendees.
  /// Uses a deterministic ID so every attendee resolves to the same document.
  Future<void> _createMeetupGroupChat() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final groupKey = 'user_created_groups_v1';
    final meetupGroupId = 'meetup_group_${_meetup.id}';
    final chatImage = _meetup.imageUrl.isNotEmpty && !_meetup.imageUrl.startsWith('data:')
        ? _meetup.imageUrl
        : _categoryFallbackImage(_meetup.category);

    // ── 1. Write/join the Firestore group doc (shared across all devices) ──
    if (uid != null) {
      try {
        final groupRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(meetupGroupId);
        final snap = await groupRef.get();
        if (!snap.exists) {
          // First joiner creates the shared group doc
          await groupRef.set({
            'id':            meetupGroupId,
            'name':          _meetup.title,
            'description':   'Group chat for "${_meetup.title}" on ${_meetup.dateDisplay} at ${_meetup.location}',
            'imageUrl':      chatImage,
            'category':      'MEETUP',
            'privacy':       'private',
            'creatorUid':    uid,
            'creatorName':   _meetup.organiserName,
            'memberIds':     [uid],
            'memberCount':   1,
            'meetupId':      _meetup.id,
            'lastMessage':   'Meetup group created',
            'lastSenderName': 'System',
            'lastMessageTime': FieldValue.serverTimestamp(),
            'createdAt':     FieldValue.serverTimestamp(),
          });
        } else {
          // Doc exists — add this user as a member (idempotent arrayUnion)
          await groupRef.update({
            'memberIds':   FieldValue.arrayUnion([uid]),
            'memberCount': FieldValue.increment(1),
          });
        }
      } catch (e) {
        if (mounted) debugPrint('[createMeetupGroupChat] Firestore error: $e');
        // Fall through to local storage so the user still sees the chat
      }
    }

    // ── 2. Persist to local BrowserStorage for instant visibility ──────────
    final existing = await BrowserStorage.getString(groupKey);
    List<dynamic> groups = [];
    if (existing != null) {
      groups = json.decode(existing) as List<dynamic>;
      final alreadyExists = groups.any((g) =>
          (g as Map<String, dynamic>)['id'] == meetupGroupId);
      if (alreadyExists) {
        // Already in local storage — nothing more to do (may still update Firestore above)
        return;
      }
    }

    final newGroup = Group(
      id: meetupGroupId,
      name: _meetup.title,
      description:
          'Group chat for "${_meetup.title}" meetup on ${_meetup.dateDisplay} at ${_meetup.location}',
      imageUrl: chatImage,
      memberCount: _meetup.attendeeCount,
      category: 'MEETUP',
      isJoined: true,
      isImageLocked: false,
      targetAudience: const [],
      privacy: GroupPrivacy.private_,
      creatorId: _meetup.organiserId,
      creatorName: _meetup.organiserName,
      creatorBorough: '',
      lastMessage: 'Meetup group created',
      lastSenderName: 'System',
      lastMessageTime: DateTime.now(),
    );

    groups.add(newGroup.toJson());
    await BrowserStorage.setString(groupKey, json.encode(groups));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.group, color: context.hc.surface, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Meetup group chat created under Messages tab'),
              ),
            ],
          ),
          backgroundColor: HuddlColors.textDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  /// Build the meetup data map used for rich card sharing.
  Map<String, dynamic> get _meetupShareData {
    final data = _meetup.toJson();
    // Strip large base64 images — card widget fetches them from MeetupService
    if ((data['imageUrl'] as String? ?? '').startsWith('data:')) {
      data['imageUrl'] = '';
    }
    return data;
  }

  /// Share meetup via forward sheet — opens the "Send to" sheet with
  /// Members and Groups tabs so the user picks recipients. A rich
  /// meetup card is sent (not plain text).
  void _shareMeetup() {
    HapticFeedback.mediumImpact();
    showForwardSheet(
      context: context,
      messageText: 'Check out this meetup: "${_meetup.title}"',
      isMeetupCard: true,
      meetupData: _meetupShareData,
    );
  }


  bool get _isOrganiser {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return myUid != null
        ? _meetup.organiserId == myUid
        : _meetup.organiserId == 'current_user';
  }

  bool get _isFull =>
      _meetup.maxAttendees != null &&
      _meetup.attendeeCount >= _meetup.maxAttendees! &&
      !_meetup.isGoing;

  bool get _hasEnded => _meetup.dateTime.isBefore(DateTime.now());

  /// Called when user taps a tag chip. Invokes the parent callback (if set)
  /// and pops back to the feed so the filter is visible immediately.
  void _handleTagTap(String tag) {
    if (widget.onTagFilter != null) {
      widget.onTagFilter!(tag);
      Navigator.pop(context);
    } else {
      // No parent callback — show bottom sheet with tag info + explore option
      showModalBottomSheet(
        context: context,
        backgroundColor: context.hc.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  tag,
                  style: HuddlText.display(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Go back to the Meetups feed to browse more "$tag" meetups.',
                  textAlign: TextAlign.center,
                  style: HuddlText.body(),
                ),
                const SizedBox(height: 20),
                HuddlButton(
                  label: 'Explore "$tag" meetups',
                  onPressed: () {
                    Navigator.pop(ctx); // close sheet
                    Navigator.pop(context); // pop back to feed
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  /// Show the more options bottom sheet (organiser controls)
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Meet-up Options',
                  style: HuddlText.body(weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.share_outlined, color: HuddlColors.textDark, size: 20),
                  ),
                  title: Text('Share Meet-up', style: HuddlText.body()),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareMeetup();
                  },
                ),
                ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: HuddlColors.blueBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.copy_outlined, color: HuddlColors.nearBlack, size: 20),
                  ),
                  title: Text('Copy Link', style: HuddlText.body()),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(
                      text: 'Join "${_meetup.title}" on ${_meetup.dateDisplay} at ${_meetup.location}',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Link copied to clipboard'),
                        backgroundColor: HuddlColors.textDark,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  },
                ),
                if (_isOrganiser) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.people_outline, color: HuddlColors.textDark, size: 20),
                    ),
                    title: Text('Manage Attendees', style: HuddlText.body()),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showManageAttendees();
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.blueBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_outlined, color: HuddlColors.nearBlack, size: 20),
                    ),
                    title: Text('Edit meetup', style: HuddlText.body()),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditMeetupScreen(meetup: _meetup),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: HuddlColors.errorLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline, color: HuddlColors.error, size: 20),
                    ),
                    title: Text('Cancel Meet-up', style: HuddlText.body(color: HuddlColors.error)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete();
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Show manage attendees bottom sheet
  void _showManageAttendees() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.hc.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: context.hc.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Attendees (${_meetup.attendeeCount})',
                  style: HuddlText.heading(),
                ),
                const SizedBox(height: 4),
                if (_meetup.maxAttendees != null)
                  Text(
                    '${_meetup.maxAttendees! - _meetup.attendeeCount} spots remaining',
                    style: HuddlText.body(color: context.hc.textTertiary),
                  ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                // Attendee list — only real RSVP'd users from Firestore.
                // No fake or pre-populated names are shown.
                Expanded(
                  child: _meetup.attendeeCount == 0
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.group_outlined,
                                  size: 48,
                                  color: HuddlColors.textTertiary),
                              const SizedBox(height: 12),
                              Text(
                                'No attendees yet',
                                style: HuddlText.body(weight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Be the first to RSVP!',
                                style: HuddlText.body(),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: [
                            // Organiser row (always shown when count > 0)
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4),
                              leading: _buildAttendeePhoto(_meetup.organiserName, 40),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _meetup.organiserName,
                                      style: HuddlText.body(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF7F7F7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Organiser',
                                      style: HuddlText.label(),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Host',
                                style: HuddlText.caption(),
                              ),
                            ),
                            // Remaining count shown as a summary row
                            if (_meetup.attendeeCount > 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                                child: Text(
                                  '+ ${_meetup.attendeeCount - 1} other ${(_meetup.attendeeCount - 1) == 1 ? 'parent' : 'parents'} going',
                                  style: HuddlText.body(color: HuddlColors.textTertiary),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Confirm delete dialog
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.hc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Meet-up?', style: HuddlText.heading(color: context.hc.textPrimary)),
        content: Text(
          'This will permanently remove "${_meetup.title}" and notify all attendees. This action cannot be undone.',
          style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textTertiary)),
          ),
          HuddlButton(
            label: 'Cancel Meet-up',
            variant: HuddlButtonVariant.destructive,
            fullWidth: false,
            onPressed: () async {
              Navigator.pop(ctx);
              await _cancelMeetupAndNotify();
            },
          ),
        ],
      ),
    );
  }

  /// Cancel the meetup, send cancellation messages to all confirmed attendees,
  /// and update the meetup group chat with a cancellation notice.
  Future<void> _cancelMeetupAndNotify() async {
    final cancelled = _meetupService.cancelMeetup(_meetup.id);
    if (cancelled == null) return;

    final meetupGroupId = 'meetup_group_${cancelled.id}';
    final cancellationMsg =
        'The creator of the meetup group has unfortunately cancelled this meetup. '
        'Please feel free to set one up as a replacement if you would still '
        'be keen to arrange a similar meetup.';

    // ── 1. Store cancellation notice in local group chat ──────────────────
    await BrowserStorage.setString(
      'meetup_cancelled_$meetupGroupId',
      json.encode({
        'type': 'cancellation',
        'meetupId': cancelled.id,
        'meetupTitle': cancelled.title,
        'message': cancellationMsg,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    // ── 2. Remove the meetup group chat from Messages ─────────────────────
    try {
      final groupKey = 'user_created_groups_v1';
      final existing = await BrowserStorage.getString(groupKey);
      if (existing != null) {
        final groups = (json.decode(existing) as List<dynamic>)
            .where((g) => (g as Map<String, dynamic>)['id'] != meetupGroupId)
            .toList();
        await BrowserStorage.setString(groupKey, json.encode(groups));
      }
    } catch (_) {}

    // ── 3. FCM push to all confirmed attendees ────────────────────────────
    // Step A: collect confirmed attendee UIDs from Firestore rsvps sub-collection
    // (invitedMemberIds covers private-invite list; rsvps covers public joiners)
    final attendeeUids = <String>{};
    try {
      // Pull from the meetup's rsvps sub-collection
      final rsvpSnap = await FirebaseFirestore.instance
          .collection('meetups')
          .doc(cancelled.id)
          .collection('rsvps')
          .where('going', isEqualTo: true)
          .get();
      for (final doc in rsvpSnap.docs) {
        attendeeUids.add(doc.id); // doc ID is the UID
      }
    } catch (_) {} // non-fatal — fallback to invitedMemberIds

    // Also include explicitly invited members (private meetups)
    attendeeUids.addAll(cancelled.invitedMemberIds);

    // Remove the organiser — no need to push to themselves
    final organiserId = FirebaseAuth.instance.currentUser?.uid ?? cancelled.organiserId;
    attendeeUids.remove(organiserId);

    // Step B: write a notifications_queue doc so Cloud Function also fires
    try {
      await FirebaseFirestore.instance
          .collection('notifications_queue')
          .add({
        'type': 'meetup_cancelled',
        'meetupId': cancelled.id,
        'meetupTitle': cancelled.title,
        'organiserName': cancelled.organiserName,
        'dateDisplay': cancelled.dateDisplay,
        'attendeeUids': attendeeUids.toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (_) {} // non-fatal

    // Step C: also dispatch directly via backend API (FCM v1)
    final organiserName = cancelled.organiserName.isNotEmpty
        ? cancelled.organiserName
        : 'Your organiser';
    unawaited(BackendApiService().notifyMeetupCancelled(
      meetupId: cancelled.id,
      meetupTitle: cancelled.title,
      organiserName: organiserName,
      dateDisplay: cancelled.dateDisplay,
      attendeeUids: attendeeUids.toList(),
    ));

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Meet-up cancelled — attendees have been notified'),
        backgroundColor: HuddlColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Design tokens (Figma-exact) ─────────────────────────────────────
  static const _detailOrange = HuddlColors.primary;      // brand orange — Figma #FF965C
  static const _detailBlue   = HuddlColors.nearBlack;      // selected blue — Figma #347FEF
  static const _detailText   = HuddlColors.textDark;      // primary dark — Figma #42464C
  static const _detailMeta   = HuddlColors.textTertiary;  // gray meta — Figma #949494

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // Price display
    final priceText = _meetup.isFree
        ? 'Free'
        : '\u00A3${_meetup.price?.toStringAsFixed(0) ?? ''}';

    // Tags: participant labels in blue, category labels in orange
    final participants = _meetup.targetAudience;
    final category = _meetup.category;
    // Build tappable tag chips — each calls onTagFilter then pops back to feed
    List<Widget> buildTagChips() {
      final chips = <Widget>[];
      for (final p in participants) {
        chips.add(_TagChip(
          label: p,
          color: _detailBlue,
          onTap: () => _handleTagTap(p),
        ));
      }
      if (category.isNotEmpty) {
        // Map short category code to display label
        const codeToLabel = {
          'Coffee': 'Coffee & tea', 'Playdate': 'Playdate',
          'Sport': 'Sports & exercise', 'Walk': 'Parks & Walks',
          'Social': 'Hanging out', 'Food': 'Food & nutrition',
          'Other': 'Other',
        };
        final label = codeToLabel[category] ?? category;
        chips.add(_TagChip(
          label: label,
          color: _detailOrange,
          onTap: () => _handleTagTap(category),
        ));
      }
      return chips;
    }
    final tagChips = buildTagChips();


    return Scaffold(
      backgroundColor: Colors.white,

      // ── Bottom CTA: locked Join button (matches Events detail pattern) ──────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: HuddlButton(
            key: ValueKey(_meetup.isGoing),
            label: _hasEnded
                ? 'Ended'
                : _isFull && !_meetup.isGoing
                    ? 'Full'
                    : _meetup.isGoing
                        ? "You're going!"
                        : "Count me in",
            variant: _meetup.isGoing
                ? HuddlButtonVariant.confirmed
                : HuddlButtonVariant.primary,
            leadingIcon: _hasEnded
                ? Icons.event_busy_outlined
                : _isFull
                    ? Icons.group_off_outlined
                    : _meetup.isGoing
                        ? Icons.check_circle
                        : Icons.group_add_outlined,
            fullWidth: true,
            onPressed: (_isFull && !_meetup.isGoing) || _hasEnded ? null : () {
              HapticFeedback.mediumImpact();
              if (!_meetup.isGoing) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You're going to ${_meetup.title}!",
                            style: HuddlText.body(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: HuddlColors.nearBlack,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              _toggleGoing();
            },
          ),
        ),
      ),

      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Full-bleed hero image ───────────────────────────────
            SizedBox(
              height: 270 + safeTop,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'meetup_cover_${_meetup.id}',
                    child: _buildDetailCoverImage(
                      imageUrl: _meetup.imageUrl.isNotEmpty
                          ? _meetup.imageUrl
                          : _categoryFallbackImage(_meetup.category),
                      fallbackIcon: _getCatStyle(_meetup.category).icon,
                      fallbackColor: _getCatStyle(_meetup.category).color,
                    ),
                  ),
                  // Subtle bottom scrim so badge is legible
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  // Back button — top-left
                  Positioned(
                    top: safeTop + 12,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new, size: 16, color: HuddlColors.textSecondary),
                      ),
                    ),
                  ),
                  // Options button — top-right
                  Positioned(
                    top: safeTop + 12,
                    right: 16,
                    child: GestureDetector(
                      onTap: _showMoreOptions,
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.more_vert, size: 20, color: HuddlColors.textSecondary),
                      ),
                    ),
                  ),
                  // Meetup category badge removed — redundant on detail screen
                ],
              ),
            ),

            // ── Content area — white background ────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date/time — small uppercase gray
                  Text(
                    '${_meetup.dateDisplay.toUpperCase()}  |  ${_meetup.timeDisplay}',
                    style: HuddlText.caption(color: _detailMeta),
                  ),
                  const SizedBox(height: 4),

                  // Title — bold dark 24px
                  Text(
                    _meetup.title,
                    style: HuddlText.display(color: _detailText),
                  ),
                  const SizedBox(height: 8),

                  // Tags row — tappable participant (blue) + category (orange) chips
                  if (tagChips.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: tagChips,
                    ),
                  const SizedBox(height: 16),

                  // Attendees row — avatar stack + "N interested" + chevron
                  GestureDetector(
                    onTap: _showManageAttendees,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 68,
                          height: 32,
                          child: Stack(
                            children: List.generate(3, (i) {
                              // Use real member photos from MemberPhotoService
                              final sampleNames = ['Sarah M.', 'Emma T.', 'James K.'];
                              return Positioned(
                                left: i * 18.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: _buildAttendeePhoto(sampleNames[i], 32),
                                ),
                              );
                            }).reversed.toList(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_meetup.attendeeCount} interested',
                          style: HuddlText.body(),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right, size: 20, color: _detailMeta),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: HuddlColors.divider),
                  const SizedBox(height: 16),

                  // Posted by row
                  Row(
                    children: [
                      _buildAttendeePhoto(_meetup.organiserName, 32),
                      const SizedBox(width: 10),
                      Text(
                        'Posted by ${_meetup.organiserName}',
                        style: HuddlText.body(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Location info row — show wifi banner for online meetups
                  if (_meetup.isOnline)
                    _InfoRow(
                      icon: Icons.wifi_outlined,
                      text: 'Online meetup',
                    )
                  else
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      text: _meetup.location.isEmpty ? 'Location TBC' : _meetup.location,
                    ),
                  const SizedBox(height: 12),

                  // Date/time info row
                  _InfoRow(
                    icon: Icons.access_time_outlined,
                    text: '${_meetup.dateDisplay}, ${_meetup.timeDisplay}',
                  ),
                  const SizedBox(height: 12),

                  // Price info row
                  Row(
                    children: [
                      const Icon(Icons.sell_outlined, size: 20, color: _detailMeta),
                      const SizedBox(width: 8),
                      Text(
                        'Price  ',
                        style: HuddlText.body(color: _detailMeta),
                      ),
                      if (_meetup.isFree)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _detailBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Free',
                            style: HuddlText.body(weight: FontWeight.w600),
                          ),
                        )
                      else
                        Text(
                          priceText,
                          style: HuddlText.body(weight: FontWeight.w700),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1, color: HuddlColors.divider),
                  const SizedBox(height: 16),

                  // Details section
                  Text(
                    'Details',
                    style: HuddlText.body(weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _meetup.description.isNotEmpty
                        ? _meetup.description
                        : 'No description provided.',
                    style: HuddlText.body(color: _detailMeta),
                  ),

                  // Repeat & Privacy info (if applicable)
                  if (_meetup.repeat != MeetupRepeat.none || _meetup.privacy != MeetupPrivacy.public) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: HuddlColors.divider),
                    const SizedBox(height: 16),
                    if (_meetup.repeat != MeetupRepeat.none)
                      _InfoRow(
                        icon: Icons.repeat,
                        text: _meetup.repeatDisplay ?? 'Repeating',
                      ),
                    if (_meetup.privacy != MeetupPrivacy.public) ...[
                      const SizedBox(height: 12),
                      _InfoRow(
                        icon: _meetup.privacy == MeetupPrivacy.group ? Icons.group : Icons.lock_outline,
                        text: _meetup.privacy == MeetupPrivacy.group
                            ? 'Group Meet-up${_meetup.groupName != null ? " · ${_meetup.groupName}" : ""}'
                            : 'Private Meet-up · Invite only',
                      ),
                    ],
                  ],

                  // Invitees section (if any)
                  if (_meetup.invitees.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: HuddlColors.divider),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Invited', style: HuddlText.body(weight: FontWeight.w600, color: _detailText)),
                        Text('${_meetup.invitees.length} people', style: HuddlText.body(color: _detailMeta)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._meetup.invitees.take(6).map((inv) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          MemberAvatar(name: inv.name, size: 32),
                          const SizedBox(width: 10),
                          Expanded(child: Text(inv.name, style: HuddlText.body(color: _detailText))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: inv.status == 'going'
                                  ? HuddlColors.nearBlack.withValues(alpha: 0.1)
                                  : inv.status == 'declined'
                                      ? HuddlColors.error.withValues(alpha: 0.1)
                                      : _detailOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              inv.status == 'going' ? 'Going'
                                  : inv.status == 'declined' ? 'Declined'
                                  : 'Invited',
                              style: HuddlText.caption(weight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    )),
                    if (_meetup.invitees.length > 6)
                      Text('+${_meetup.invitees.length - 6} more invited',
                        style: HuddlText.caption(color: _detailOrange)),
                  ],

                  SizedBox(height: safeBottom + 120),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build attendee photo from MemberPhotoService.
  /// For the current user, show their onboarding photo or local asset avatar.
  Widget _buildAttendeePhoto(String name, double size) {
    // Current user: use onboarding photo or local asset fallback
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isMeetupOrganiser = myUid != null
        ? (_meetup.organiserId == myUid && name == _meetup.organiserName)
        : (_meetup.organiserId == 'current_user' && name == _meetup.organiserName);
    if (MemberPhotoService.isCurrentUser(name) || isMeetupOrganiser) {
      final photoUrl = MemberPhotoService.getPhotoByName(name);
      if (photoUrl != null && photoUrl.isNotEmpty) {
        // User has an actual profile photo (e.g. data: URI or network URL)
        if (photoUrl.startsWith('data:')) {
          try {
            final parts = photoUrl.split(',');
            if (parts.length > 1) {
              final bytes = base64Decode(parts[1]);
              return Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: HuddlColors.divider, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(bytes, fit: BoxFit.cover, width: size, height: size),
              );
            }
          } catch (_) {}
        }
        return Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: HuddlColors.divider, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(photoUrl, fit: BoxFit.cover, width: size, height: size,
            errorBuilder: (_, __, ___) => _localAvatarFallback(size)),
        );
      }
      // No profile photo set — use local asset avatar
      return _localAvatarFallback(size);
    }

    // Known community member — use MemberPhotoService
    final photoUrl = MemberPhotoService.getPhotoByName(name);
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => MemberAvatar(name: name, size: size),
        ),
      );
    }
    return MemberAvatar(name: name, size: size);
  }

  /// Local asset avatar for the current user (gender-based)
  Widget _localAvatarFallback(double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HuddlColors.divider, width: 1.5),
      ),
      child: ClipOval(
        child: Image.asset(
          MemberPhotoService.currentUserAvatarAsset,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFF7F7F7),
            child: Center(child: Icon(Icons.person, size: size * 0.5, color: HuddlColors.textDark)),
          ),
        ),
      ),
    );
  }
}

// ── Info row — icon + text (Figma detail screen rows) ────────────────────

// ── Tappable tag chip used in detail screen ─────────────────────────────────
class _TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _TagChip({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(
          label,
          style: HuddlText.body(),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: HuddlColors.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: HuddlText.body(color: HuddlColors.textDark),
          ),
        ),
      ],
    );
  }
}

// ── Category style helper ─────────────────────────────────────────────────

class _CatStyleInfo {
  final Color color;
  final IconData icon;
  const _CatStyleInfo(this.color, this.icon);
}

_CatStyleInfo _getCatStyle(String category) {
  switch (category) {
    case 'Coffee':
      return const _CatStyleInfo(HuddlColors.primaryDark, Icons.coffee);
    case 'Playdate':
      return const _CatStyleInfo(HuddlColors.primary, Icons.child_care);
    case 'Sport':
      return const _CatStyleInfo(HuddlColors.nearBlack, Icons.sports_golf);
    case 'Walk':
      return const _CatStyleInfo(HuddlColors.paleBlue, Icons.directions_walk);
    case 'Social':
      return const _CatStyleInfo(HuddlColors.primary, Icons.celebration);
    case 'Food':
      return const _CatStyleInfo(HuddlColors.primary, Icons.restaurant);
    default:
      return const _CatStyleInfo(HuddlColors.nearBlack, Icons.groups);
  }
}

// ── Category-based fallback image for meetups ────────────────────────────
String _categoryFallbackImage(String category) {
  switch (category.toLowerCase()) {
    case 'coffee':
    case 'coffee & chat':
      return 'https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'playdate':
    case 'play':
      return 'https://images.pexels.com/photos/3933239/pexels-photo-3933239.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'walk':
    case 'outdoor':
      return 'https://images.pexels.com/photos/1325735/pexels-photo-1325735.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'sport':
    case 'fitness':
    case 'exercise':
      return 'https://images.pexels.com/photos/3822864/pexels-photo-3822864.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'class':
    case 'workshop':
      return 'https://images.pexels.com/photos/3662667/pexels-photo-3662667.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'music':
      return 'https://images.pexels.com/photos/3662770/pexels-photo-3662770.jpeg?auto=compress&cs=tinysrgb&w=600';
    case 'social':
      return 'https://images.pexels.com/photos/3184418/pexels-photo-3184418.jpeg?auto=compress&cs=tinysrgb&w=600';
    default:
      return 'https://images.pexels.com/photos/3933250/pexels-photo-3933250.jpeg?auto=compress&cs=tinysrgb&w=600';
  }
}

// ── Universal cover-image builder for detail screens ───────────────────────
Widget _buildDetailCoverImage({
  required String imageUrl,
  required IconData fallbackIcon,
  required Color fallbackColor,
}) {
  Widget gradientFallback({bool showIcon = true}) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [fallbackColor, fallbackColor.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: showIcon
            ? Center(
                child:
                    Icon(fallbackIcon, size: 48, color: HuddlColors.white))
            : null,
      );

  if (imageUrl.isEmpty) return gradientFallback();

  // base64 data-URI (user-uploaded)
  if (imageUrl.startsWith('data:')) {
    try {
      final dataUri = Uri.parse(imageUrl);
      final bytes = dataUri.data?.contentAsBytes();
      if (bytes != null) {
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => gradientFallback(),
        );
      }
    } catch (_) {}
    return gradientFallback();
  }

  // http(s) URL — use Image.network for reliable web rendering
  if (imageUrl.startsWith('http')) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return gradientFallback(showIcon: false);
      },
      errorBuilder: (_, __, ___) => gradientFallback(),
    );
  }

  // asset path
  if (imageUrl.startsWith('assets/')) {
    return Image.asset(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => gradientFallback(),
    );
  }

  return gradientFallback();
}
