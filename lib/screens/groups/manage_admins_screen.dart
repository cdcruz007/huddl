// ═══════════════════════════════════════════════════════════════════════════
// MANAGE ADMINS SCREEN — Section 6C
// Admin-only screen to promote members to admin and remove admin privileges.
// Accessed via Group Detail → three-dot menu → "Manage admins".
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/huddl_colors.dart';
import '../../widgets/huddl_widgets.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/common/huddl_button.dart';

class ManageAdminsScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const ManageAdminsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends State<ManageAdminsScreen> {
  bool _isLoading = true;
  String? _error;

  List<_AdminMember> _admins   = [];
  List<_AdminMember> _members  = []; // non-admin members
  String _memberSearch = '';

  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final db = FirebaseFirestore.instance;
      final groupDoc = await db.collection('groups').doc(widget.groupId).get();
      if (!groupDoc.exists) {
        if (mounted) setState(() { _isLoading = false; _error = 'Group not found.'; });
        return;
      }
      final data = groupDoc.data() ?? {};
      final admins  = List<String>.from(data['admins']  ?? []);
      final members = List<String>.from(data['members'] ?? []);
      final createdBy = data['createdBy'] as String? ?? data['creatorId'] as String? ?? '';

      // Collect all unique UIDs to fetch
      final allUids = {...admins, ...members}.toList();
      final Map<String, Map<String, dynamic>> userData = {};

      for (int i = 0; i < allUids.length; i += 10) {
        final batch = allUids.sublist(i, (i + 10).clamp(0, allUids.length));
        try {
          final snap = await db.collection('users').where(FieldPath.documentId, whereIn: batch).get();
          for (final doc in snap.docs) {
            userData[doc.id] = doc.data();
          }
        } catch (_) {}
      }

      _AdminMember buildMember(String uid) {
        final ud = userData[uid] ?? {};
        final name = (ud['name'] as String?)?.trim() ?? 'Member';
        final photo = (ud['photoUrl'] as String?)?.trim();
        final pt = (ud['parentType'] as String?)?.toLowerCase();
        return _AdminMember(
          uid: uid,
          name: uid == _currentUid ? 'You' : name,
          photoUrl: (photo != null && photo.isNotEmpty) ? photo : null,
          isCreator: uid == createdBy,
          parentType: pt,
        );
      }

      if (mounted) {
        setState(() {
          _admins  = admins.map(buildMember).toList();
          _members = members.where((id) => !admins.contains(id)).map(buildMember).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _error = 'Could not load members. Tap to retry.'; });
    }
  }

  Future<void> _promoteToAdmin(_AdminMember member) async {
    final confirmed = await _confirmDialog(
      title: 'Make ${member.name} an admin?',
      body: 'They will be able to edit group details and manage members.',
      confirmLabel: 'Confirm',
      confirmColor: HuddlColors.primary,
    );
    if (!confirmed) return;

    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'admins': FieldValue.arrayUnion([member.uid]),
      });
      if (mounted) {
        setState(() {
          _members.removeWhere((m) => m.uid == member.uid);
          _admins.add(member);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${member.name} is now an admin.'),
          backgroundColor: HuddlColors.textDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update admin. Please try again.'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  Future<void> _removeAdmin(_AdminMember member) async {
    // ── Sole-admin guard ────────────────────────────────────────────────────
    // If this member is the only admin, removing them would leave the group
    // without any admin.  Two sub-cases:
    //
    //   • Current user is the sole admin and is self-demoting:
    //     Trigger auto-promotion (promote most-active member → then remove
    //     self from admins), mirroring the leave-flow Case 2 logic.
    //
    //   • A different admin is the sole admin and the current user is somehow
    //     trying to remove them (should not happen via normal UI, but guarded
    //     defensively):
    //     Block the operation and explain.
    if (_admins.length == 1) {
      if (member.uid == _currentUid) {
        // Self-demotion as sole admin → auto-promote most active member first
        await _autoPromoteAndDemoteSelf();
      } else {
        // Attempting to remove the last remaining admin → block
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
              'This is the only admin. Assign another admin first before removing them.'),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
      return;
    }
    // ── Normal demotion ─────────────────────────────────────────────────────

    final confirmed = await _confirmDialog(
      title: 'Remove ${member.name} as admin?',
      body: 'They will become a regular member of the group.',
      confirmLabel: 'Confirm',
      confirmColor: HuddlColors.error,
    );
    if (!confirmed) return;

    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'admins': FieldValue.arrayRemove([member.uid]),
      });
      if (mounted) {
        setState(() {
          _admins.removeWhere((m) => m.uid == member.uid);
          _members.add(member);
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${member.name} is no longer an admin.'),
          backgroundColor: HuddlColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update admin. Please try again.'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  /// Sole-admin self-demotion path: promote the most active non-admin member
  /// (by messageCount DESC, joinedAt ASC from the memberActivity sub-collection)
  /// then remove the current user from the admins array.
  Future<void> _autoPromoteAndDemoteSelf() async {
    final uid = _currentUid;
    if (uid == null) return;

    final db = FirebaseFirestore.instance;

    // Show a blocking dialog explaining what is about to happen
    final proceed = await _confirmDialog(
      title: 'You are the only admin',
      body: 'Before stepping down, the most active member will automatically '
            'become the new admin. Proceed?',
      confirmLabel: 'Proceed',
      confirmColor: HuddlColors.primary,
    );
    if (!proceed) return;

    try {
      // ── Step 1: Find most active non-admin member ──────────────────────
      String? promoteeId;
      try {
        final actSnap = await db
            .collection('groups')
            .doc(widget.groupId)
            .collection('memberActivity')
            .orderBy('messageCount', descending: true)
            .orderBy('joinedAt', descending: false)
            .limit(10)
            .get();

        for (final doc in actSnap.docs) {
          final id = doc.data()['userId'] as String? ?? doc.id;
          if (id != uid) {
            promoteeId = id;
            break;
          }
        }
      } catch (_) {
        // Composite index may not exist yet — fall through to members fallback
      }

      if (promoteeId == null) {
        // Fallback: pick any member who is not the current user
        final groupDoc = await db.collection('groups').doc(widget.groupId).get();
        final allMembers = List<String>.from(groupDoc.data()?['members'] ?? []);
        promoteeId = allMembers.firstWhere((id) => id != uid, orElse: () => '');
      }

      // At this point promoteeId is guaranteed non-null (fallback assigned '' above)
      final resolvedPromoteeId = promoteeId;

      // ── Step 2: Promote selected member and demote self ─────────────────
      if (resolvedPromoteeId.isNotEmpty) {
        await db.collection('groups').doc(widget.groupId).update({
          'admins': FieldValue.arrayUnion([resolvedPromoteeId]),
        });
      }

      await db.collection('groups').doc(widget.groupId).update({
        'admins': FieldValue.arrayRemove([uid]),
      });

      // ── Step 3: Reflect changes in local state ───────────────────────────
      if (mounted) {
        setState(() {
          // Remove self from admins list
          final selfMember = _admins.firstWhere(
            (m) => m.uid == uid,
            orElse: () => _AdminMember(uid: uid, name: 'You', isCreator: false),
          );
          _admins.removeWhere((m) => m.uid == uid);
          _members.add(selfMember);

          // Move promotee from members to admins
          if (resolvedPromoteeId.isNotEmpty) {
            final idx = _members.indexWhere((m) => m.uid == resolvedPromoteeId);
            if (idx != -1) {
              final promoted = _members.removeAt(idx);
              _admins.insert(0, promoted);
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Admin role transferred successfully.'),
          backgroundColor: HuddlColors.textDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to transfer admin role. Please try again.'),
          backgroundColor: HuddlColors.error,
        ));
      }
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                style: HuddlText.heading(color: context.hc.textPrimary),
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(body,
                style: HuddlText.body(color: context.hc.textSecondary).copyWith(height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Divider(height: 1, color: context.hc.divider),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text('Cancel',
                        style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textSecondary)),
                    ),
                  ),
                  Container(width: 1, height: 40, color: context.hc.divider),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(confirmLabel,
                        style: HuddlText.body(weight: FontWeight.w600, color: confirmColor)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  List<_AdminMember> get _filteredMembers {
    if (_memberSearch.isEmpty) return _members;
    final q = _memberSearch.toLowerCase();
    return _members.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manage admins',
          style: HuddlText.heading(color: context.hc.textPrimary),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.hc.divider),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: HuddlColors.textTertiary))
          : _error != null
              ? GestureDetector(
                  onTap: _loadData,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh, size: 40, color: context.hc.textTertiary),
                        const SizedBox(height: 12),
                        Text(_error!,
                          style: HuddlText.body(color: context.hc.textTertiary),
                          textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [

        // ── Current Admins section ──────────────────────────────────────
        _sectionHeader('Current admins'),
        if (_admins.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text('No admins found.',
              style: HuddlText.body(color: context.hc.textTertiary)),
          )
        else
          ..._admins.map((admin) => _AdminTile(
            member: admin,
            isCurrentUser: admin.uid == _currentUid,
            actionLabel: 'Remove admin',
            actionColor: HuddlColors.textSecondary,
            onAction: () => _removeAdmin(admin),
          )),

        const SizedBox(height: 8),

        // ── Add Admins section ──────────────────────────────────────────
        _sectionHeader('Add admins'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Choose members to promote to admin',
            style: HuddlText.body(color: context.hc.textSecondary)),
        ),

        // Search field (shown when > 10 members)
        if (_members.length > 10)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: context.hc.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.hc.divider),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, size: 18, color: context.hc.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _memberSearch = v),
                      style: HuddlText.body(color: context.hc.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search members',
                        border: InputBorder.none,
                        hintStyle: HuddlText.body(color: context.hc.textTertiary),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_filteredMembers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              _members.isEmpty
                  ? 'All members are already admins.'
                  : 'No members match your search.',
              style: HuddlText.body(color: context.hc.textTertiary)),
          )
        else
          ..._filteredMembers.map((member) => _AdminTile(
            member: member,
            isCurrentUser: member.uid == _currentUid,
            actionLabel: 'Make admin',
            actionColor: HuddlColors.textDark,
            onAction: () => _promoteToAdmin(member),
          )),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeader(String text) => Container(
    color: context.hc.scaffold,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: HuddlText.body(weight: FontWeight.w700, color: context.hc.textTertiary),
    ),
  );
}

// ── Tile widget for both sections ──────────────────────────────────────────
class _AdminTile extends StatelessWidget {
  final _AdminMember member;
  final bool isCurrentUser;
  final String actionLabel;
  final Color actionColor;
  final VoidCallback onAction;

  const _AdminTile({
    required this.member,
    required this.isCurrentUser,
    required this.actionLabel,
    required this.actionColor,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.hc.surface,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: MemberAvatar(
          name: member.name,
          size: 44,
          accentColor: HuddlColors.primary,
          imageUrl: member.photoUrl,
          parentType: member.parentType,
        ),
        title: Row(
          children: [
            Text(
              member.name,
              style: HuddlText.body(color: context.hc.textPrimary),
            ),
            if (member.isCreator) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Creator',
                  style: HuddlText.label(color: HuddlColors.nearBlack)),
              ),
            ],
          ],
        ),
        trailing: isCurrentUser
            ? Text('(You)',
                style: HuddlText.caption(color: context.hc.textTertiary))
            : HuddlButton(
                label: actionLabel,
                variant: HuddlButtonVariant.secondary,
                fullWidth: false,
                onPressed: onAction,
              ),
      ),
    );
  }
}

class _AdminMember {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool isCreator;
  final String? parentType;

  const _AdminMember({
    required this.uid,
    required this.name,
    this.photoUrl,
    required this.isCreator,
    this.parentType,
  });
}
