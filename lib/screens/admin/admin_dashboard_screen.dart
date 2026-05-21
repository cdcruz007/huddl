import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
// report_service.dart enums (ReportType/ReportContext) not needed client-side here

// =============================================================================
// ADMIN DASHBOARD — Report Review
//
// Accessible via route '/admin'.  Intended for internal Huddl moderators only.
//
// Access gate: Only Firebase-authenticated users whose Firestore document at
//   users/{uid}/roles.isAdmin == true  can use this screen.
//   All others see a "not authorised" message.
//
// Displays:
//   • Pending reports (status == 'pending') ordered by timestamp desc
//   • Each card shows: type, context, reporter, target, timestamp, message ID
//   • Action buttons: Mark Reviewed | Mark Actioned | Dismiss
//
// Firestore:  reports/{reportId}
//   status values:  'pending' | 'reviewed' | 'actioned' | 'dismissed'
//
// Security note: The Firestore security rule for `reports/` must allow admin reads.
// Add this rule in Firebase Console → Firestore → Rules:
//
//   match /reports/{reportId} {
//     allow create: if request.auth != null
//                   && request.resource.data.reporterId == request.auth.uid;
//     allow read, update: if request.auth != null
//                   && get(/databases/$(database)/documents/users/$(request.auth.uid))
//                        .data.roles.isAdmin == true;
//     allow delete: if false;
//   }
//
// Without this rule, the StreamBuilder will receive a permissions-denied error
// and show the "Could not load reports" message below.
// =============================================================================

/// Status filter for the report list.
enum _ReportFilter { pending, reviewed, actioned, dismissed, all }

extension _ReportFilterLabel on _ReportFilter {
  String get label => switch (this) {
        _ReportFilter.pending   => 'Pending',
        _ReportFilter.reviewed  => 'Reviewed',
        _ReportFilter.actioned  => 'Actioned',
        _ReportFilter.dismissed => 'Dismissed',
        _ReportFilter.all       => 'All',
      };

  String? get firestoreValue => switch (this) {
        _ReportFilter.all => null,
        _   => name,
      };
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  _ReportFilter _filter = _ReportFilter.pending;
  bool _isAdmin        = false;
  bool _adminChecked   = false;

  // ── Action sheet launcher ─────────────────────────────────────────────────

  /// Opens the Action sub-sheet (Warn user / Remove content / Suspend user).
  /// Sets report status to 'actioned' and logs the action taken in Firestore.
  void _showActionSheet(String reportId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionSheet(
        onConfirm: (actionLabel) async {
          try {
            await FirebaseFirestore.instance
                .collection('reports')
                .doc(reportId)
                .update({
              'status'     : 'actioned',
              'reviewedAt' : FieldValue.serverTimestamp(),
              'actionTaken': actionLabel,
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Report actioned: $actionLabel'),
                  backgroundColor: HuddlColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to action report: $e'),
                  backgroundColor: HuddlColors.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  // ── Admin access check ────────────────────────────────────────────────────

  Future<void> _checkAdminAccess() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _adminChecked = true);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final roles = doc.data()?['roles'] as Map<String, dynamic>?;
      final isAdmin = roles?['isAdmin'] == true;
      if (mounted) setState(() { _isAdmin = isAdmin; _adminChecked = true; });
    } catch (e) {
      if (kDebugMode) debugPrint('[AdminDashboard] admin check failed: $e');
      if (mounted) setState(() => _adminChecked = true);
    }
  }

  // ── Report actions ────────────────────────────────────────────────────────

  Future<void> _updateStatus(String reportId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(reportId)
          .update({
        'status'    : newStatus,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report marked as $newStatus'),
            backgroundColor: HuddlColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: HuddlColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  // ── Firestore query ───────────────────────────────────────────────────────

  Query<Map<String, dynamic>> get _query {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('reports');
    final statusVal = _filter.firestoreValue;
    if (statusVal != null) {
      q = q.where('status', isEqualTo: statusVal);
    }
    // Sort in memory after fetching to avoid composite index requirements
    return q;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: HuddlColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Report Dashboard',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: !_adminChecked
          ? const Center(child: CircularProgressIndicator())
          : !_isAdmin
              ? _buildNotAuthorised()
              : Column(
                  children: [
                    _buildFilterBar(),
                    Expanded(child: _buildReportList()),
                  ],
                ),
    );
  }

  Widget _buildNotAuthorised() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: HuddlColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline, size: 36, color: HuddlColors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Not authorised',
              style: GoogleFonts.poppins(
                fontSize: 20, fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This area is restricted to Huddl moderators.\n'
              'If you believe this is an error, contact the engineering team.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14, color: HuddlColors.disabledText, height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _ReportFilter.values.map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                f.label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: HuddlColors.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
              checkmarkColor: Colors.white,
              side: BorderSide(
                color: selected ? HuddlColors.primary : Theme.of(context).dividerColor,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReportList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: HuddlColors.error),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load reports.\n\n'
                    'The Firestore security rule for the reports collection needs '
                    'updating to allow admin reads.\n\n'
                    'In Firebase Console → Firestore → Rules, update the reports '
                    'match block to allow read/update when roles.isAdmin == true.\n\n'
                    'See the comment at the top of admin_dashboard_screen.dart '
                    'for the exact rule syntax.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 12, color: HuddlColors.disabledText, height: 1.6),
                  ),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        // Sort in memory by timestamp desc (avoids composite index requirement)
        final sorted = [...docs]..sort((a, b) {
          final tsA = (a.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tsB = (b.data()['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return tsB.compareTo(tsA);
        });

        if (sorted.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 56, color: Theme.of(context).dividerColor),
                const SizedBox(height: 16),
                Text(
                  'No ${_filter.label.toLowerCase()} reports',
                  style: GoogleFonts.poppins(
                    fontSize: 16, color: HuddlColors.disabledText, fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc  = sorted[index];
            final data = doc.data();
            return _ReportCard(
              reportId: doc.id,
              data: data,
              onAction: _updateStatus,
              onActionSheet: _showActionSheet,
            );
          },
        );
      },
    );
  }
}

// ── Report Card ────────────────────────────────────────────────────────────────

/// Resolved human-readable details fetched async after the card renders.
class _ReportDetails {
  final String reporterName;
  final String reporterPhone;
  final String reporterEmail;
  final String targetName;
  final String targetPhone;
  final String targetEmail;
  final String? chatName; // group name, or null for DMs/listings/profiles

  const _ReportDetails({
    required this.reporterName,
    required this.reporterPhone,
    required this.reporterEmail,
    required this.targetName,
    required this.targetPhone,
    required this.targetEmail,
    this.chatName,
  });
}

class _ReportCard extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final Future<void> Function(String reportId, String status) onAction;
  final void Function(String reportId) onActionSheet;

  const _ReportCard({
    required this.reportId,
    required this.data,
    required this.onAction,
    required this.onActionSheet,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  _ReportDetails? _details;
  bool _showRawIds = false;

  void _openActionSheet() => widget.onActionSheet(widget.reportId);

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final reporterId = widget.data['reporterId']  as String? ?? '';
    final targetId   = widget.data['targetUserId'] as String? ?? '';
    final groupId    = widget.data['groupId']      as String?;
    final context    = widget.data['context']      as String? ?? '';

    final db = FirebaseFirestore.instance;

    // Fire all three lookups in parallel
    final futures = await Future.wait([
      reporterId.isNotEmpty
          ? db.collection('users').doc(reporterId).get()
          : Future.value(null),
      targetId.isNotEmpty
          ? db.collection('users').doc(targetId).get()
          : Future.value(null),
      groupId != null && context == 'group_message'
          ? db.collection('groups').doc(groupId).get()
          : Future.value(null),
    ]);

    Map<String, dynamic>? rData;
    Map<String, dynamic>? tData;
    Map<String, dynamic>? gData;

    final rSnap = futures[0];
    if (rSnap is DocumentSnapshot<Map<String, dynamic>>) rData = rSnap.data();

    final tSnap = futures[1];
    if (tSnap is DocumentSnapshot<Map<String, dynamic>>) tData = tSnap.data();

    final gSnap = futures[2];
    if (gSnap is DocumentSnapshot<Map<String, dynamic>>) gData = gSnap.data();

    String displayName(Map<String, dynamic>? d) {
      if (d == null) return 'Unknown user';
      final n = (d['name'] as String? ?? '').trim();
      if (n.isNotEmpty) return n;
      final fn = (d['firstName'] as String? ?? '').trim();
      final ln = (d['lastName']  as String? ?? '').trim();
      return '$fn $ln'.trim().isNotEmpty ? '$fn $ln'.trim() : 'Unknown user';
    }

    String? chatName;
    if (gData != null) {
      chatName = gData['name'] as String?;
    } else if (context == 'dm_message') {
      final tName = displayName(tData);
      chatName = 'Direct message with $tName';
    }

    if (mounted) {
      setState(() {
        _details = _ReportDetails(
          reporterName:  displayName(rData),
          reporterPhone: rData?['phone'] as String? ?? '—',
          reporterEmail: rData?['email'] as String? ?? '—',
          targetName:    displayName(tData),
          targetPhone:   tData?['phone'] as String? ?? '—',
          targetEmail:   tData?['email'] as String? ?? '—',
          chatName:      chatName,
        );
      });
    }
  }

  Color _statusColor(String status) => switch (status) {
        'pending'   => HuddlColors.error,
        'reviewed'  => HuddlColors.warning,
        'actioned'  => HuddlColors.primary,
        'dismissed' => HuddlColors.disabledText,
        _           => HuddlColors.disabledText,
      };

  IconData _typeIcon(String type) => switch (type) {
        'spam'                  => Icons.mark_email_unread_outlined,
        'harassment'            => Icons.person_off_outlined,
        'hate_speech'           => Icons.record_voice_over_outlined,
        'inappropriate_content' => Icons.visibility_off_outlined,
        'misinformation'        => Icons.fact_check_outlined,
        'scam'                  => Icons.money_off_outlined,
        'child_safety_concern'  => Icons.child_care_outlined,
        _                       => Icons.flag_outlined,
      };

  String _formatTimestamp(dynamic ts) {
    if (ts is! Timestamp) return 'Unknown time';
    final dt = ts.toDate().toLocal();
    final date = '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
    final time = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    return '$date at $time';
  }

  String _contextLabel(String ctx) => switch (ctx) {
        'group_message' => 'Group chat',
        'dm_message'    => 'Direct message',
        'listing'       => 'Marketplace listing',
        'user_profile'  => 'User profile',
        _               => ctx.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) {
    final status         = widget.data['status']         as String? ?? 'pending';
    final type           = widget.data['type']           as String? ?? 'other';
    final ctx            = widget.data['context']        as String? ?? '';
    final reporterId     = widget.data['reporterId']     as String? ?? '';
    final targetId       = widget.data['targetUserId']   as String? ?? '';
    final contentId      = widget.data['messageId']      as String? ?? '';
    final groupId        = widget.data['groupId']        as String?;
    final timestamp      = widget.data['timestamp'];
    // Fields denormalised at report-submission time (present on new reports)
    final docReason      = widget.data['reason']         as String?;
    final docChatName    = widget.data['chatName']       as String?;
    final docMsgPreview  = widget.data['messagePreview'] as String?;
    final d = _details;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_typeIcon(type), size: 18, color: _statusColor(status)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reason: prefer human label stored at submit time,
                      // fall back to raw type string for older reports
                      Text(
                        docReason ?? type.replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        _contextLabel(ctx),
                        style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.disabledText),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: _statusColor(status),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: Theme.of(context).dividerColor),

          // ── Human-readable details ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Filed timestamp — always at the top
                _DetailRow(
                  label: 'Filed',
                  value: _formatTimestamp(timestamp),
                  icon: Icons.schedule_outlined,
                ),
                const SizedBox(height: 10),

                // ── Reason / what the reporter said was wrong ───────────
                if (docReason != null) ...[
                  _DetailRow(
                    label: 'Reason',
                    value: docReason,
                    icon: Icons.flag_outlined,
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Where it happened ───────────────────────────────────
                // Prefer denormalised chatName from the document; fall back
                // to the async-resolved name from _details for older reports.
                () {
                  final name = docChatName ?? d?.chatName;
                  if (name == null) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow(
                        label: _contextLabel(ctx),
                        value: name,
                        icon: ctx == 'dm_message'
                            ? Icons.chat_bubble_outline
                            : Icons.group_outlined,
                      ),
                      const SizedBox(height: 10),
                    ],
                  );
                }(),

                // ── Reported message / content preview ──────────────────
                if (docMsgPreview != null && docMsgPreview.trim().isNotEmpty) ...[
                  _SectionLabel(label: 'Reported message'),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HuddlColors.error.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: HuddlColors.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      docMsgPreview,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Reported-by person ──────────────────────────────────
                _SectionLabel(label: 'Reported by'),
                const SizedBox(height: 6),
                if (d == null)
                  const _LoadingRow()
                else ...[
                  _DetailRow(label: 'Name',  value: d.reporterName,  icon: Icons.person_outline),
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Phone', value: d.reporterPhone, icon: Icons.phone_outlined),
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Email', value: d.reporterEmail, icon: Icons.email_outlined),
                ],
                const SizedBox(height: 10),

                // ── Reported user ───────────────────────────────────────
                _SectionLabel(label: 'Reported user'),
                const SizedBox(height: 6),
                if (d == null)
                  const _LoadingRow()
                else ...[
                  _DetailRow(label: 'Name',  value: d.targetName,  icon: Icons.person_outline),
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Phone', value: d.targetPhone, icon: Icons.phone_outlined),
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Email', value: d.targetEmail, icon: Icons.email_outlined),
                ],
              ],
            ),
          ),

          // ── Raw IDs — collapsed by default ─────────────────────────────
          InkWell(
            onTap: () => setState(() => _showRawIds = !_showRawIds),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Row(
                children: [
                  Icon(
                    _showRawIds ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: HuddlColors.disabledText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showRawIds ? 'Hide technical IDs' : 'Show technical IDs',
                    style: GoogleFonts.poppins(
                      fontSize: 11, color: HuddlColors.disabledText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showRawIds)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: 'Reporter UID', value: reporterId, mono: true),
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Target UID',   value: targetId,   mono: true),
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Content ID',   value: contentId,  mono: true),
                  if (groupId != null) ...[
                    const SizedBox(height: 4),
                    _DetailRow(label: 'Group ID',   value: groupId,    mono: true),
                  ],
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Report ID',    value: widget.reportId, mono: true),
                ],
              ),
            ),

          Divider(height: 1, color: Theme.of(context).dividerColor),

          // ── Action buttons (only for pending / reviewed) ───────────────
          if (status == 'pending' || status == 'reviewed')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  if (status == 'pending')
                    Expanded(
                      child: _ActionButton(
                        label: 'Mark reviewed',
                        icon: Icons.visibility_outlined,
                        color: HuddlColors.warning,
                        onTap: () => widget.onAction(widget.reportId, 'reviewed'),
                      ),
                    ),
                  if (status == 'pending') const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Action',
                      icon: Icons.gavel_outlined,
                      color: HuddlColors.primary,
                      // Opens Warn / Remove content / Suspend sub-sheet
                      onTap: _openActionSheet,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Dismiss',
                      icon: Icons.close,
                      color: HuddlColors.disabledText,
                      onTap: () => widget.onAction(widget.reportId, 'dismissed'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: HuddlColors.disabledText,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: HuddlColors.disabledText,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Loading…',
          style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.disabledText),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final IconData? icon;
  const _DetailRow({required this.label, required this.value, this.mono = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: HuddlColors.disabledText),
          ),
          const SizedBox(width: 6),
        ],
        SizedBox(
          width: icon != null ? 46 : 100,
          child: Text(
            label,
            style: GoogleFonts.poppins(fontSize: 11, color: HuddlColors.disabledText),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: mono
                ? const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: HuddlColors.textDark,
                  )
                : GoogleFonts.poppins(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Action Sub-Sheet ──────────────────────────────────────────────────────────

/// Bottom sheet with three moderation actions: Warn user, Remove content,
/// Suspend user.  On tap, [onConfirm] is called with the human-readable label
/// so the parent can update Firestore status → 'actioned' + log actionTaken.
class _ActionSheet extends StatelessWidget {
  final void Function(String actionLabel) onConfirm;
  const _ActionSheet({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        icon: Icons.warning_amber_rounded,
        color: HuddlColors.warning,
        label: 'Warn user',
        sublabel: 'Send the user an official warning',
      ),
      (
        icon: Icons.delete_outline,
        color: HuddlColors.error,
        label: 'Remove content',
        sublabel: 'Delete the reported message or listing',
      ),
      (
        icon: Icons.block_outlined,
        color: Colors.red.shade800,
        label: 'Suspend user',
        sublabel: 'Temporarily suspend the reported account',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Take Action',
            style: GoogleFonts.poppins(
              fontSize: 18, fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select the moderation action for this report.',
            style: GoogleFonts.poppins(
              fontSize: 13, color: HuddlColors.disabledText,
            ),
          ),
          const SizedBox(height: 20),
          ...actions.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.pop(context);
                onConfirm(a.label);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: a.color.withValues(alpha: 0.3)),
                  color: a.color.withValues(alpha: 0.05),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: a.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(a.icon, size: 20, color: a.color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.label,
                              style: GoogleFonts.poppins(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: a.color)),
                          Text(a.sublabel,
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: HuddlColors.disabledText)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: a.color.withValues(alpha: 0.5)),
                  ],
                ),
              ),
            ),
          )),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: HuddlColors.disabledText)),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label, required this.icon,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
