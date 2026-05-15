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
// Security note: The Firestore security rule for `reports/` currently denies
// client-side reads (allow read: if false). To use this screen you must either:
//   (a) update Firestore rules to  `allow read: if request.auth.uid == <adminUid>;`
//   (b) use the Firebase Console or a server-side Admin SDK script for review.
//   See docs/admin_access.md for setup instructions.
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
          .update({'status': newStatus, 'reviewedAt': FieldValue.serverTimestamp()});
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
                    'Firestore security rules may need updating to allow admin reads.\n'
                    'See docs/admin_access.md.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 13, color: HuddlColors.disabledText, height: 1.6),
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
            );
          },
        );
      },
    );
  }
}

// ── Report Card ────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final String reportId;
  final Map<String, dynamic> data;
  final Future<void> Function(String reportId, String status) onAction;

  const _ReportCard({
    required this.reportId,
    required this.data,
    required this.onAction,
  });

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
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status    = data['status']       as String? ?? 'pending';
    final type      = data['type']         as String? ?? 'other';
    final ctx       = data['context']      as String? ?? '';
    final reporterId  = data['reporterId']   as String? ?? '';
    final targetId    = data['targetUserId'] as String? ?? '';
    final contentId   = data['messageId']   as String? ?? '';
    final groupId   = data['groupId']      as String?;
    final timestamp = data['timestamp'];

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
                      Text(
                        type.replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        ctx.replaceAll('_', ' '),
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

          // ── Details ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(label: 'Reporter UID', value: reporterId),
                const SizedBox(height: 4),
                _DetailRow(label: 'Target UID',   value: targetId),
                const SizedBox(height: 4),
                _DetailRow(label: 'Content ID',   value: contentId),
                if (groupId != null) ...[
                  const SizedBox(height: 4),
                  _DetailRow(label: 'Group ID', value: groupId),
                ],
                const SizedBox(height: 4),
                _DetailRow(label: 'Filed',         value: _formatTimestamp(timestamp)),
                const SizedBox(height: 4),
                _DetailRow(label: 'Report ID',     value: reportId, mono: true),
              ],
            ),
          ),

          // ── Action buttons (only for pending / reviewed) ───────────────
          if (status == 'pending' || status == 'reviewed')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  if (status == 'pending')
                    Expanded(
                      child: _ActionButton(
                        label: 'Mark reviewed',
                        icon: Icons.visibility_outlined,
                        color: HuddlColors.warning,
                        onTap: () => onAction(reportId, 'reviewed'),
                      ),
                    ),
                  if (status == 'pending') const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Action',
                      icon: Icons.gavel_outlined,
                      color: HuddlColors.primary,
                      onTap: () => onAction(reportId, 'actioned'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Dismiss',
                      icon: Icons.close,
                      color: HuddlColors.disabledText,
                      onTap: () => onAction(reportId, 'dismissed'),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _DetailRow({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
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
                    fontSize: 11,
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
