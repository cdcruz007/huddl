import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';
import '../../services/payment_service.dart';
import '../../widgets/common/huddl_button.dart';
import '../../constants/app_text_styles.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MANAGE SUBSCRIPTION — view usage, change plan, cancel, restore
//
// COMPLIANCE:
//   Apple 3.1.1:  Restore Purchases button present.
//   Apple 3.1.2:  Shows current plan, renewal date, auto-renewal status,
//                 cancellation instructions via system settings.
//   Google Play:  Shows manage/cancel in Google Play settings instructions.
//   Web:          Links to Stripe Customer Portal for management.
// ═══════════════════════════════════════════════════════════════════════════════

class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  final SubscriptionService _service = SubscriptionService();
  final PaymentService _payService = PaymentService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initServices();
    _service.addListener(_onUpdate);
  }

  Future<void> _initServices() async {
    // Both initialize() calls have their own internal timeouts, but we wrap
    // the whole block too so this screen never hangs if something slips through.
    try {
      await _service.initialize()
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    try {
      await _payService.initialize()
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _navigateToPlans() async {
    final result = await Navigator.pushNamed(context, '/subscription_plans');
    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    final restored = await _payService.restorePurchases();
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored
                ? 'Subscription restored!'
                : 'No previous purchases found.',
            style: HuddlText.body(color: HuddlColors.white),
          ),
          backgroundColor: restored ? HuddlColors.nearBlack : HuddlColors.textHint,
        ),
      );
    }
  }

  Future<void> _cancelSubscription() async {
    // Show exit survey first
    final reason = await _showExitSurvey();
    if (reason == null) return; // User cancelled the survey

    // Offer 1-month pause
    final wantsPause = await _offerPause();
    if (wantsPause == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Subscription paused for 1 month. Welcome back anytime!',
                style: HuddlText.body(color: HuddlColors.white)),
            backgroundColor: HuddlColors.textDark,
          ),
        );
      }
      return;
    }

    // Direct user to platform-specific cancellation
    if (!kIsWeb) {
      // On mobile, guide user to their store settings
      await _showStoreCancellationGuide();
    } else {
      // On web, open Stripe Customer Portal
      await _payService.openSubscriptionManagement();
    }

    // Actually cancel locally
    await _service.cancelSubscription();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Subscription cancelled. You\'ll keep access until the billing period ends.',
              style: HuddlText.body(color: HuddlColors.white)),
          backgroundColor: HuddlColors.textHint,
        ),
      );
    }
  }

  Future<void> _showStoreCancellationGuide() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel via Your Store',
            style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To cancel your subscription, please go to your device settings:',
              style: HuddlText.body(color: context.hc.textSecondary),
            ),
            const SizedBox(height: 16),
            if (defaultTargetPlatform == TargetPlatform.iOS) ...[
              _StepRow(step: '1', text: 'Open Settings on your iPhone'),
              _StepRow(step: '2', text: 'Tap your name at the top'),
              _StepRow(step: '3', text: 'Tap Subscriptions'),
              _StepRow(step: '4', text: 'Tap Huddl'),
              _StepRow(step: '5', text: 'Tap Cancel Subscription'),
            ] else ...[
              _StepRow(step: '1', text: 'Open Google Play Store'),
              _StepRow(step: '2', text: 'Tap your profile icon'),
              _StepRow(step: '3', text: 'Tap Payments & subscriptions'),
              _StepRow(step: '4', text: 'Tap Subscriptions'),
              _StepRow(step: '5', text: 'Find Huddl and tap Cancel'),
            ],
            const SizedBox(height: 12),
            Text(
              'Your current plan will remain active until the end of your billing period.',
              style: HuddlText.caption(color: context.hc.textTertiary).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Got it',
                style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.primary)),
          ),
          if (defaultTargetPlatform == TargetPlatform.iOS)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openAppStoreSubscriptions();
              },
              child: Text('Open Settings',
                  style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.nearBlack)),
            )
          else
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openGooglePlaySubscriptions();
              },
              child: Text('Open Play Store',
                  style: HuddlText.body(weight: FontWeight.w600, color: HuddlColors.nearBlack)),
            ),
        ],
      ),
    );
  }

  Future<void> _openAppStoreSubscriptions() async {
    // Deep link to iOS subscription management
    final url = Uri.parse('https://apps.apple.com/account/subscriptions');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openGooglePlaySubscriptions() async {
    // Deep link to Google Play subscription management
    final url = Uri.parse(
        'https://play.google.com/store/account/subscriptions');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<String?> _showExitSurvey() async {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => _ExitSurveyDialog(),
    );
  }

  Future<bool?> _offerPause() async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Wait \u2014 how about a free pause?',
            style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pause_circle_outline,
                      color: HuddlColors.textDark, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('1-Month Free Pause',
                            style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                        Text(
                          'Keep your data & groups. Resume when you\'re ready \u2014 no charge during the pause.',
                          style: HuddlText.caption(color: context.hc.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No, cancel my plan',
                style: HuddlText.body(color: HuddlColors.error)),
          ),
          HuddlButton(
            label: 'Pause Instead',
            variant: HuddlButtonVariant.primary,
            fullWidth: false,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = _service.subscription;
    final limits = sub.limits;
    final isPaid = sub.isPaid;

    return Scaffold(
      backgroundColor: context.hc.scaffold,
      appBar: AppBar(
        backgroundColor: context.hc.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.hc.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Subscription',
            style: HuddlText.heading(color: context.hc.textPrimary)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current plan card
              _CurrentPlanCard(subscription: sub),

              // Pending cancellation / scheduled change banner
              if (sub.isPendingCancellation || sub.hasScheduledChange) ...[
                const SizedBox(height: 12),
                _ManageScheduledBanner(
                  subscription: sub,
                  onRevert: () async {
                    if (sub.isPendingCancellation) {
                      await _service.reactivateSubscription();
                    } else {
                      await _service.revokeScheduledChange();
                    }
                    if (mounted) setState(() {});
                  },
                ),
              ],
              const SizedBox(height: 16),

              // Payment info card (for paid users)
              if (isPaid) ...[
                _PaymentInfoCard(paymentService: _payService),
                const SizedBox(height: 20),
              ],

              // Usage section
              Text('Your Usage',
                  style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
              const SizedBox(height: 12),
              _UsageCard(
                icon: Icons.people_outline,
                label: 'Groups Joined',
                used: _service.groupsJoined,
                limit: limits.maxGroups,
                color: HuddlColors.primary,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.add_circle_outline,
                label: 'Groups Created',
                used: _service.groupsCreated,
                limit: limits.maxGroupsCreated,
                color: HuddlColors.nearBlack,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.groups_outlined,
                label: 'Meetups This Month',
                used: _service.meetupsThisMonth,
                limit: limits.maxMeetupsPerMonth,
                color: HuddlColors.primary,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.chat_bubble_outline,
                label: 'DM Conversations',
                used: _service.dmConversations,
                limit: limits.maxDMConversations,
                color: HuddlColors.nearBlack,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.message_outlined,
                label: 'Messages This Month',
                used: _service.messagesThisMonth,
                limit: limits.maxMessagesPerMonth,
                color: HuddlColors.nearBlack,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.storefront_outlined,
                label: 'Marketplace Listings',
                used: _service.marketplaceListings,
                limit: limits.maxMarketplaceListings,
                color: HuddlColors.accentCoral,
              ),

              const SizedBox(height: 20),

              // AI Usage section
              Text('AI Usage',
                  style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
              const SizedBox(height: 12),
              _UsageCard(
                icon: Icons.star_rounded,
                label: 'AI Copilot Chats Today',
                used: _service.aiCopilotChatsToday,
                limit: limits.maxAiCopilotChatsPerDay,
                color: HuddlColors.primary,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.summarize_outlined,
                label: 'AI Chat Summaries Today',
                used: _service.aiChatSummariesToday,
                limit: limits.maxAiChatSummariesPerDay,
                color: HuddlColors.nearBlack,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.event_outlined,
                label: 'AI Event Discoveries This Week',
                used: _service.aiEventDiscoveriesThisWeek,
                limit: limits.maxAiEventDiscoveriesPerWeek,
                color: HuddlColors.primary,
              ),
              if (limits.aiListingGenerator) ...[
                const SizedBox(height: 8),
                _UsageCard(
                  icon: Icons.sell_outlined,
                  label: 'AI Listing Generations This Month',
                  used: _service.aiListingGenerationsThisMonth,
                  limit: limits.maxAiListingGenerationsPerMonth,
                  color: HuddlColors.nearBlack,
                ),
              ],
              if (limits.aiMeetupMatchmaker) ...[
                const SizedBox(height: 8),
                _UsageCard(
                  icon: Icons.handshake_outlined,
                  label: 'AI Matchmaker Requests This Month',
                  used: _service.aiMatchmakerRequestsThisMonth,
                  limit: limits.maxAiMatchmakerRequestsPerMonth,
                  color: HuddlColors.accentCoral,
                ),
              ],

              const SizedBox(height: 24),

              // Actions
              if (!isPaid) ...[
                // Upgrade CTA
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: HuddlColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: HuddlColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.rocket_launch,
                          color: HuddlColors.textDark, size: 36),
                      const SizedBox(height: 12),
                      Text('Unlock Your Full Community',
                          style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                      const SizedBox(height: 6),
                      Text(
                        'Unlimited groups, DMs, meetups, and full AI suite \u2014 from just \u00A34.99/mo.',
                        textAlign: TextAlign.center,
                        style: HuddlText.body(color: context.hc.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      HuddlButton(
                        label: 'View Plans',
                        onPressed: _navigateToPlans,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Restore purchases (Apple Guideline 3.1.1)
                Center(
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _restorePurchases,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore, size: 18),
                    label: Text('Restore Purchases',
                        style: HuddlText.body(color: context.hc.textTertiary)),
                  ),
                ),
              ] else ...[
                // Change plan / Cancel
                HuddlButton(
                  label: 'Change Plan',
                  variant: HuddlButtonVariant.secondary,
                  onPressed: _navigateToPlans,
                ),
                const SizedBox(height: 10),
                // Manage via store
                HuddlButton(
                  label: kIsWeb
                      ? 'Manage via Stripe'
                      : (defaultTargetPlatform == TargetPlatform.iOS
                          ? 'Manage in App Store'
                          : 'Manage in Google Play'),
                  variant: HuddlButtonVariant.secondary,
                  leadingIcon: kIsWeb
                      ? Icons.credit_card
                      : (defaultTargetPlatform == TargetPlatform.iOS
                          ? Icons.apple
                          : Icons.g_mobiledata),
                  onPressed: () {
                    if (kIsWeb) {
                      _payService.openSubscriptionManagement();
                    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
                      _openAppStoreSubscriptions();
                    } else {
                      _openGooglePlaySubscriptions();
                    }
                  },
                ),
                const SizedBox(height: 12),
                Center(
                  child: HuddlButton(
                    label: 'Cancel Subscription',
                    variant: HuddlButtonVariant.destructive,
                    onPressed: _cancelSubscription,
                  ),
                ),
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUBWIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _StepRow extends StatelessWidget {
  final String step;
  final String text;
  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              shape: BoxShape.circle,
            ),
            child: Text(step,
                style: HuddlText.caption(weight: FontWeight.w600, color: HuddlColors.textDark)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: HuddlText.body(color: context.hc.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Shows current payment billing info
class _PaymentInfoCard extends StatelessWidget {
  final PaymentService paymentService;
  const _PaymentInfoCard({required this.paymentService});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HuddlColors.gray200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HuddlColors.blueBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              kIsWeb
                  ? Icons.credit_card
                  : (defaultTargetPlatform == TargetPlatform.iOS
                      ? Icons.apple
                      : Icons.g_mobiledata),
              color: HuddlColors.nearBlack,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Billed via ${paymentService.paymentMethodName}',
                    style: HuddlText.body(weight: FontWeight.w600, color: context.hc.textPrimary)),
                Text(
                  kIsWeb
                      ? 'Managed through your Stripe account'
                      : 'Managed through your ${defaultTargetPlatform == TargetPlatform.iOS ? 'Apple ID' : 'Google'} account',
                  style: HuddlText.caption(color: context.hc.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right,
              color: context.hc.textTertiary, size: 20),
        ],
      ),
    );
  }
}

class _ExitSurveyDialog extends StatefulWidget {
  @override
  State<_ExitSurveyDialog> createState() => _ExitSurveyDialogState();
}

class _ExitSurveyDialogState extends State<_ExitSurveyDialog> {
  String? _selectedReason;
  final _otherCtrl = TextEditingController();

  static const _reasons = [
    'Too expensive',
    'Not using it enough',
    'Missing features I need',
    'Found a better alternative',
    'Technical issues',
    'Other',
  ];

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('We\'re sorry to see you go',
          style: HuddlText.heading(color: context.hc.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Help us improve \u2014 what\'s your main reason for cancelling?',
                style: HuddlText.body(color: context.hc.textSecondary)),
            const SizedBox(height: 12),
            ..._reasons.map((r) => GestureDetector(
                  onTap: () => setState(() => _selectedReason = r),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _selectedReason == r
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: _selectedReason == r
                              ? HuddlColors.primary
                              : HuddlColors.textHint,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(r,
                            style: HuddlText.body(color: context.hc.textPrimary)),
                      ],
                    ),
                  ),
                )),
            if (_selectedReason == 'Other') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _otherCtrl,
                decoration: InputDecoration(
                  hintText: 'Tell us more...',
                  hintStyle: HuddlText.body(color: context.hc.textTertiary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
                maxLines: 2,
                style: HuddlText.body(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Never mind',
              style: HuddlText.body(color: context.hc.textTertiary)),
        ),
        TextButton(
          onPressed: _selectedReason != null
              ? () => Navigator.pop(
                  context,
                  _selectedReason == 'Other'
                      ? _otherCtrl.text
                      : _selectedReason)
              : null,
          child: Text('Continue',
              style: HuddlText.body(color: HuddlColors.textLight)),
        ),
      ],
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final UserSubscription subscription;
  const _CurrentPlanCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final isPartner = subscription.isPartner;
    final isPlus = subscription.isPlus;
    final isFree = subscription.isFree;

    Color accentColor = HuddlColors.textHint;
    IconData icon = Icons.explore_outlined;
    if (isPlus) {
      accentColor = HuddlColors.primary;
      icon = Icons.home_outlined;
    } else if (isPartner) {
      accentColor = HuddlColors.nearBlack;
      icon = Icons.workspace_premium;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: HuddlColors.gray900.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(subscription.tierDisplayName,
                            style: HuddlText.heading(color: context.hc.textPrimary)),


                      ],
                    ),
                    const SizedBox(height: 2),
                    if (!isFree && subscription.renewalDate != null)
                      Text(
                        subscription.cancelledAtPeriodEnd
                            ? 'Cancels ${_formatDate(subscription.renewalDate!)}'
                            : 'Auto-renews ${_formatDate(subscription.renewalDate!)}',
                        style: HuddlText.caption(color: context.hc.textSecondary),
                      )
                    else
                      Text('Free plan \u2014 upgrade anytime',
                          style: HuddlText.caption(color: context.hc.textTertiary)),
                  ],
                ),
              ),
              if (!isFree)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    subscription.billingPeriod == BillingPeriod.annual
                        ? 'Annual'
                        : 'Monthly',
                    style: HuddlText.caption(weight: FontWeight.w600, color: accentColor),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _UsageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int used;
  final int limit;
  final Color color;

  const _UsageCard({
    required this.icon,
    required this.label,
    required this.used,
    required this.limit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isUnlimited = TierLimits.isUnlimited(limit);
    final percentage = isUnlimited ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final isNearLimit = percentage >= 0.8 && !isUnlimited;
    final isAtLimit = percentage >= 1.0 && !isUnlimited;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.hc.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isAtLimit
              ? HuddlColors.error.withValues(alpha: 0.3)
              : HuddlColors.gray200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label,
                        style: HuddlText.body(color: context.hc.textPrimary)),
                    Text(
                      isUnlimited ? '$used / \u221E' : '$used / $limit',
                      style: HuddlText.caption(weight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isUnlimited ? 0 : percentage,
                    backgroundColor: HuddlColors.gray100,
                    color: isAtLimit
                        ? HuddlColors.error
                        : isNearLimit
                            ? HuddlColors.warning
                            : color,
                    minHeight: 5,
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

class _ManageScheduledBanner extends StatelessWidget {
  final UserSubscription subscription;
  final VoidCallback onRevert;

  const _ManageScheduledBanner({
    required this.subscription,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final isCancellation = subscription.isPendingCancellation;
    final color =
        isCancellation ? HuddlColors.error : HuddlColors.nearBlack;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCancellation ? Icons.cancel_outlined : Icons.schedule,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCancellation
                      ? 'Subscription cancelling'
                      : 'Plan change scheduled',
                  style: HuddlText.body(weight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
          if (subscription.scheduledChangeSummary != null) ...[
            const SizedBox(height: 6),
            Text(
              subscription.scheduledChangeSummary!,
              style: HuddlText.caption(color: context.hc.textSecondary),
            ),
          ],
          if (subscription.daysUntilRenewal > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${subscription.daysUntilRenewal} days remaining in current period',
              style: HuddlText.caption(color: context.hc.textTertiary),
            ),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onRevert,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isCancellation ? 'Undo Cancellation' : 'Revert to Current Plan',
                style: HuddlText.caption(weight: FontWeight.w600, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
