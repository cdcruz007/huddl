import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../theme/huddl_animations.dart';
import '../../services/announcement_service.dart';
import '../../services/browser_storage.dart';
import '../../services/onboarding_data_service.dart';
import '../../services/postcode_service.dart';
import '../../services/invitation_service.dart';
import '../../widgets/huddl_widgets.dart';
import '../../widgets/huddl_character.dart';
import '../../constants/app_text_styles.dart';

class NoticeboardScreen extends StatefulWidget {
  const NoticeboardScreen({super.key});
  @override
  State<NoticeboardScreen> createState() => _NoticeboardScreenState();
}

class _NoticeboardScreenState extends State<NoticeboardScreen> {
  final AnnouncementService _announcementService = AnnouncementService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcodeService = PostcodeService();
  String _borough = '';
  int _memberCount = 0;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  Future<void> _loadContext() async {
    await _onboarding.initialize();
    await _announcementService.initialize();
    final pc = _onboarding.postcode;
    final borough = pc != null ? (_postcodeService.getBoroughFromPostcode(pc) ?? '') : '';
    final members = pc != null ? InvitationService.getBoroughMembers(pc) : [];
    if (mounted) setState(() { _borough = borough; _memberCount = members.length; });
  }

  Future<void> _postToBoroughNoticeboard(String content) async {
    if (content.trim().isEmpty) return;
    try {
      await _announcementService.post(content.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Posted to ${_borough.isNotEmpty ? _borough : 'community'} community',
              style: HuddlText.body()),
          backgroundColor: HuddlColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        try {
          final raw = await BrowserStorage.getString('huddl_interaction_count');
          final count = (int.tryParse(raw ?? '') ?? 0) + 1;
          await BrowserStorage.setString('huddl_interaction_count', count.toString());
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to post. Please try again.', style: HuddlText.body()),
          backgroundColor: HuddlColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _openComposerSheet() {
    final hc = context.hc;
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HuddlBottomSheetHandle(),
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Post to ${_borough.isNotEmpty ? _borough : 'community'}',
                  style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: controller, autofocus: true, maxLength: 280, maxLines: 5, minLines: 3,
                decoration: InputDecoration(
                  hintText: 'Share something with your neighbours...',
                  hintStyle: HuddlText.body(color: hc.textTertiary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hc.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hc.divider)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: HuddlColors.primary)),
                  filled: true, fillColor: hc.scaffold, contentPadding: const EdgeInsets.all(12),
                ),
                style: HuddlText.body(color: hc.textPrimary),
                onChanged: (_) => setSheet(() {}),
              )),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: controller.text.trim().isEmpty ? null : () {
                    final content = controller.text.trim();
                    Navigator.pop(ctx);
                    _postToBoroughNoticeboard(content);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HuddlColors.primary, foregroundColor: Colors.white,
                    disabledBackgroundColor: HuddlColors.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13), elevation: 0,
                  ),
                  child: Text('Post to ${_borough.isNotEmpty ? _borough : 'community'}',
                      style: HuddlText.body(weight: FontWeight.w600)),
                ))),
          ])),
        ),
      )),
    );
  }

  void _dismissAnnouncement(Announcement ann) {
    _announcementService.delete(ann.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Post removed', style: HuddlText.body()),
      backgroundColor: HuddlColors.textDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: hc.scaffold,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_borough.isNotEmpty ? _borough : 'Borough'} Noticeboard',
              style: HuddlText.body(weight: FontWeight.w700, color: hc.textPrimary)),
          if (_memberCount > 0)
            Text('$_memberCount+ parents', style: HuddlText.caption(color: hc.textTertiary)),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: hc.divider),
        ),
      ),
      body: Column(children: [
        // Sticky composer bar
        GestureDetector(
          onTap: _openComposerSheet,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: hc.surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hc.divider),
              boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              Icon(Icons.campaign_outlined, size: 20, color: hc.textTertiary),
              const SizedBox(width: 10),
              Expanded(child: Text('Post something to ${_borough.isNotEmpty ? _borough : 'your community'}...',
                  style: HuddlText.body(color: hc.textTertiary).copyWith(fontStyle: FontStyle.italic))),
              Container(padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: HuddlColors.primary, borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.send_rounded, size: 14, color: Colors.white)),
            ]),
          ),
        ),
        // Stream feed
        Expanded(child: StreamBuilder<List<Announcement>>(
          stream: _announcementService.boroughStream,
          initialData: _announcementService.boroughAnnouncements,
          builder: (context, snapshot) {
            final posts = snapshot.data ?? [];
            if (posts.isEmpty) return _buildEmptyState(hc);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: posts.length,
              itemBuilder: (_, i) => Dismissible(
                key: ValueKey(posts[i].id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: HuddlColors.error,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) => _dismissAnnouncement(posts[i]),
                child: _buildPostCard(posts[i], hc, isDark),
              ),
            );
          },
        )),
      ]),
    );
  }

  Widget _buildPostCard(Announcement ann, dynamic hc, bool isDark) {
    final timeAgo = _timeAgo(ann.createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hc.surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hc.divider),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: HuddlColors.orangeIconBg, radius: 18,
            child: Text(ann.authorName.isNotEmpty ? ann.authorName[0].toUpperCase() : '?',
                style: HuddlText.body(weight: FontWeight.w700, color: HuddlColors.primary))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ann.authorName, style: HuddlText.body(weight: FontWeight.w600, color: hc.textPrimary)),
            Text(timeAgo, style: HuddlText.caption(color: hc.textTertiary)),
          ])),
          if (ann.isPinned) Icon(Icons.push_pin, size: 14, color: HuddlColors.textTertiary),
        ]),
        const SizedBox(height: 10),
        Text(ann.content, style: HuddlText.body(color: hc.textPrimary).copyWith(height: 1.45)),
        const SizedBox(height: 12),
        Row(children: [
          _actionBtn(icon: ann.isLiked ? Icons.favorite : Icons.favorite_border,
            color: ann.isLiked ? HuddlColors.error : hc.textTertiary,
            label: ann.likes > 0 ? ann.likes.toString() : 'Like',
            onTap: () async { await _announcementService.toggleLike(ann.id); setState(() {}); }),
          const SizedBox(width: 16),
          _actionBtn(icon: Icons.chat_bubble_outline, color: hc.textTertiary,
            label: ann.comments > 0 ? ann.comments.toString() : 'Comment', onTap: () {}),
          const SizedBox(width: 16),
          _actionBtn(icon: Icons.share_outlined, color: hc.textTertiary, label: 'Share',
            onTap: () { _announcementService.share(ann.id); setState(() {}); }),
        ]),
      ]),
    );
  }

  Widget _actionBtn({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HuddlAnimations.lightTap(); onTap(); },
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: HuddlText.caption(color: color)),
      ]),
    );
  }

  Widget _buildEmptyState(dynamic hc) {
    return HuddlEmptyState(
      mood: HuddlMood.noticeboard,
      title: 'No posts yet',
      subtitle: 'Be the first to post something to ${_borough.isNotEmpty ? _borough : 'your community'}.',
      ctaLabel: 'Post to community',
      onCtaTap: _openComposerSheet,
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
