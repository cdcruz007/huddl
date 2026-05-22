// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — BACKUP & RESTORE SCREEN
// ═══════════════════════════════════════════════════════════════════════════════
//
// Allows users to manually export and import all their Huddl data.
// Automatic backup behaviour (Android Auto Backup / iOS iCloud) is also
// explained here so users understand what is happening in the background.
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../services/backup_restore_service.dart';

// ─────────────────────────────────────────────────────────────────────────────

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  final BackupRestoreService _svc = BackupRestoreService();

  bool _isExporting = false;
  bool _isImporting = false;
  DateTime? _lastBackup;
  // backup JSON is passed directly to the result sheet

  @override
  void initState() {
    super.initState();
    _loadLastBackupTime();
  }

  Future<void> _loadLastBackupTime() async {
    final t = await _svc.lastManualBackupTime();
    if (mounted) setState(() => _lastBackup = t);
  }

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    try {
      final json = await _svc.exportBackup();
      await _svc.recordManualBackup();
      final t = await _svc.lastManualBackupTime();
      if (mounted) setState(() => _lastBackup = t);
      if (mounted) _showExportResult(json);
    } catch (e) {
      if (mounted) _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showExportResult(String json) {
    final metadata = _svc.validateBackupFile(json);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _ExportResultSheet(
        json: json,
        metadata: metadata,
        fileName: _svc.generateBackupFileName(),
      ),
    );
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _handleImport() async {
    // Show paste dialog — in production you would open the file picker here.
    // For full cross-platform compatibility (web + mobile) we use a paste field.
    final pasted = await _showPasteDialog();
    if (pasted == null || pasted.trim().isEmpty) return;

    setState(() => _isImporting = true);
    try {
      // Validate first
      final meta = _svc.validateBackupFile(pasted);
      if (meta == null) {
        _showError(
            'This file does not appear to be a valid Huddl backup.\n'
            'Make sure you paste the entire contents of your backup file.');
        return;
      }

      // Confirm
      final confirmed = await _showImportConfirmDialog(meta);
      if (confirmed != true) return;

      final result = await _svc.importBackup(pasted);

      if (mounted) {
        if (result.success) {
          _showSuccess(
              '${result.restoredKeys} items restored successfully.\n'
              'Please restart the app for all changes to take effect.');
        } else {
          _showError(result.error ??
              'Restore partially completed with ${result.skippedKeys} errors.');
        }
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<String?> _showPasteDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: context.hc.surface,
        title: Text('Paste backup file',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.hc.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open your backup file, copy all its contents, then paste them below.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: context.hc.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: '{ "_huddl_backup": true, ... }',
                hintStyle: GoogleFonts.poppins(
                    fontSize: 12, color: context.hc.textTertiary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.hc.divider)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: HuddlColors.primary, width: 2)),
                filled: true,
                fillColor: context.hc.scaffold,
                contentPadding: const EdgeInsets.all(12),
              ),
              style: GoogleFonts.sourceCodePro(
                  fontSize: 11, color: context.hc.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: Text('Restore',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showImportConfirmDialog(BackupMetadata meta) {
    final created = _formatDate(meta.createdAt);
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: context.hc.surface,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: HuddlColors.accentAmber, size: 22),
            const SizedBox(width: 8),
            Text('Restore backup?',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.hc.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will overwrite your current app data with the backup from:',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: context.hc.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 10),
            _InfoRow(label: 'Backup date', value: created),
            _InfoRow(label: 'Items', value: '${meta.keyCount}'),
            _InfoRow(label: 'Platform', value: meta.platform),
            _InfoRow(label: 'Backup version', value: meta.backupVersion),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: HuddlColors.errorLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Current data will be replaced. This cannot be undone.\n'
                'Restart the app after restoring.',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: HuddlColors.error,
                    fontWeight: FontWeight.w500,
                    height: 1.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.hc.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HuddlColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text('Yes, restore',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
      backgroundColor: HuddlColors.error,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg,
                  style:
                      GoogleFonts.poppins(fontSize: 13, color: Colors.white))),
        ],
      ),
      backgroundColor: HuddlColors.textDark,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: HuddlColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Backup & Restore',
            style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // ── Auto-backup status card ─────────────────────────────────
          _AutoBackupStatusCard(lastManualBackup: _lastBackup),

          const SizedBox(height: 20),

          // ── How automatic backup works ──────────────────────────────
          _SectionHeader(title: 'Automatic backup'),
          const SizedBox(height: 10),

          if (!kIsWeb) ...[
            _InfoCard(
              icon: Icons.cloud_outlined,
              iconColor: HuddlColors.nearBlack,
              title: Platform.isIOS
                  ? 'iCloud backup (iOS)'
                  : 'Google Drive backup (Android)',
              body: Platform.isIOS
                  ? 'iOS automatically backs up your Huddl data to iCloud when your '
                      'phone is idle, locked, and connected to Wi-Fi. If you install '
                      'Huddl on a new iPhone or restore your device, your data is '
                      'automatically recovered.\n\n'
                      'Enable: Settings → [Your Name] → iCloud → Backup → '
                      'Back Up Now.'
                  : 'Android automatically backs up your Huddl data to your Google '
                      'account. If you reinstall the app or switch to a new Android '
                      'device, your data is restored automatically.\n\n'
                      'Enable: Settings → System → Backup → Back up now.',
            ),
            const SizedBox(height: 10),
          ],

          if (kIsWeb)
            _InfoCard(
              icon: Icons.info_outline,
              iconColor: HuddlColors.nearBlack,
              title: 'Web — manual backup only',
              body: 'Automatic backup is not available in the web version. '
                  'Use the manual export below to save your data.',
            ),

          const SizedBox(height: 20),

          // ── Manual backup ───────────────────────────────────────────
          _SectionHeader(title: 'Manual backup & restore'),
          const SizedBox(height: 10),

          _InfoCard(
            icon: Icons.shield_outlined,
            iconColor: HuddlColors.nearBlack,
            title: 'What is included',
            body: 'All messages, photos, groups, polls, meetups, events, '
                'saved items, profile data, notification preferences, '
                'subscription state, and AI settings stored on this device.\n\n'
                'Passwords and authentication tokens are never stored or '
                'exported — you will need to log in again after restoring.',
          ),
          const SizedBox(height: 16),

          // Export card
          _ActionCard(
            icon: Icons.upload_outlined,
            iconColor: HuddlColors.textDark,
            title: 'Export backup',
            subtitle: _lastBackup != null
                ? 'Last backup: ${_formatDate(_lastBackup)}'
                : 'No backup made yet on this device',
            buttonLabel: 'Export now',
            isLoading: _isExporting,
            onTap: _handleExport,
          ),

          const SizedBox(height: 12),

          // Import card
          _ActionCard(
            icon: Icons.download_outlined,
            iconColor: HuddlColors.nearBlack,
            title: 'Restore from backup',
            subtitle: 'Paste the contents of a previous backup file to '
                'restore your data.',
            buttonLabel: 'Restore',
            isLoading: _isImporting,
            onTap: _handleImport,
            danger: true,
          ),

          const SizedBox(height: 20),

          // ── What is stored info ─────────────────────────────────────
          _SectionHeader(title: 'Storage details'),
          const SizedBox(height: 10),
          _StorageDetailCard(),

          const SizedBox(height: 20),

          // ── Tips ────────────────────────────────────────────────────
          _TipsCard(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTO-BACKUP STATUS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AutoBackupStatusCard extends StatelessWidget {
  final DateTime? lastManualBackup;
  const _AutoBackupStatusCard({this.lastManualBackup});

  @override
  Widget build(BuildContext context) {
    final isIos = !kIsWeb && Platform.isIOS;
    final label = kIsWeb
        ? 'Web — manual backup only'
        : isIos
            ? 'iCloud backup enabled'
            : 'Google Drive backup enabled';
    final desc = kIsWeb
        ? 'Automatic backup is not available on web.'
        : isIos
            ? 'Your data is automatically backed up to iCloud.'
            : 'Your data is automatically backed up to Google Drive.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: HuddlColors.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kIsWeb
                  ? HuddlColors.accentAmber.withValues(alpha: 0.15)
                  : HuddlColors.nearBlack.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              kIsWeb ? Icons.info_outline : Icons.cloud_done_outlined,
              color: kIsWeb ? HuddlColors.accentAmber : HuddlColors.nearBlack,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary)),
                const SizedBox(height: 4),
                Text(desc,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textSecondary,
                        height: 1.4)),
                if (lastManualBackup != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last manual backup: ${_fmt(lastManualBackup!)}',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: HuddlColors.nearBlack,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool isLoading;
  final bool danger;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.isLoading,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = danger ? HuddlColors.error : iconColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hc.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon + text row ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: context.hc.textSecondary,
                            height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Full-width button below so text never gets squeezed ────
          isLoading
              ? Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: btnColor, strokeWidth: 2),
                  ),
                )
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: btnColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onTap,
                    child: Text(buttonLabel),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT RESULT SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ExportResultSheet extends StatelessWidget {
  final String json;
  final BackupMetadata? metadata;
  final String fileName;

  const _ExportResultSheet({
    required this.json,
    required this.metadata,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.hc.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: HuddlColors.nearBlack.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: HuddlColors.nearBlack, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Backup created',
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.hc.textPrimary)),
                    if (metadata != null)
                      Text(
                        '${metadata!.keyCount} items • $fileName',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: context.hc.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Save your backup',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.hc.textPrimary)),
          const SizedBox(height: 8),
          Text(
            'Copy the backup below and save it to a safe location — your Files '
            'app, email, or cloud storage. You can use it to restore your data '
            'at any time.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: context.hc.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Preview box
          Container(
            height: 100,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.hc.scaffold,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.hc.divider, width: 1),
            ),
            child: SingleChildScrollView(
              child: Text(
                json.length > 500
                    ? '${json.substring(0, 500)}\n\n…[${json.length} characters total]'
                    : json,
                style: GoogleFonts.sourceCodePro(
                    fontSize: 10, color: context.hc.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Copy button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: HuddlColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle:
                    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy backup to clipboard'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: json));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Backup copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ));
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Done',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.hc.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STORAGE DETAIL CARD
// ─────────────────────────────────────────────────────────────────────────────

class _StorageDetailCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Messages & reactions', 'All group and DM conversations'),
      ('Photos & media', 'Media references stored locally'),
      ('Groups & membership', 'Joined groups, pins, mutes'),
      ('Polls', 'Votes and poll data per group'),
      ('Meetups & events', 'RSVPs, drafts, favourites'),
      ('Saved items', 'Saved messages, threads, events'),
      ('Profile & onboarding', 'Name, bio, location, preferences'),
      ('Subscription state', 'Active plan information'),
      ('AI settings', 'Personalisation and behaviour'),
      ('Blocked users', 'Your block list'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hc.divider, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.storage_outlined,
                      size: 16,
                      color: HuddlColors.textTertiary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(items[i].$1,
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.hc.textPrimary)),
                        Text(items[i].$2,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: context.hc.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle,
                      size: 16, color: HuddlColors.nearBlack),
                ],
              ),
            ),
            if (i < items.length - 1)
              Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: context.hc.divider),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIPS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TipsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const tips = [
      'Export a backup before switching phones or reinstalling the app.',
      'Store your backup file somewhere safe, like your email or cloud drive.',
      'Automatic backup runs daily on Android (Google Drive) and iOS (iCloud).',
      'After restoring a manual backup, restart the app for changes to apply.',
      'Passwords are never stored in backups — you will need to log in again.',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HuddlColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: HuddlColors.accentAmber.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: HuddlColors.accentAmber, size: 18),
              const SizedBox(width: 8),
              Text('Tips',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: HuddlColors.accentAmber)),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in tips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Icon(Icons.circle,
                      size: 5, color: HuddlColors.accentAmber),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tip,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: HuddlColors.textSecondary,
                          height: 1.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.hc.textTertiary,
            letterSpacing: 0.8),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  const _InfoCard(
      {required this.icon,
      required this.iconColor,
      required this.title,
      required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hc.divider, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.hc.textPrimary)),
                const SizedBox(height: 6),
                Text(body,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: context.hc.textSecondary,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.hc.textSecondary)),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: context.hc.textPrimary)),
        ],
      ),
    );
  }
}
