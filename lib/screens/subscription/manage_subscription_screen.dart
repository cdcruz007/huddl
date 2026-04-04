import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/huddl_colors.dart';
import '../../models/subscription.dart';
import '../../services/subscription_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MANAGE SUBSCRIPTION — view usage, change plan, cancel
// ═══════════════════════════════════════════════════════════════════════════════

class ManageSubscriptionScreen extends StatefulWidget {
  const ManageSubscriptionScreen({super.key});

  @override
  State<ManageSubscriptionScreen> createState() =>
      _ManageSubscriptionScreenState();
}

class _ManageSubscriptionScreenState extends State<ManageSubscriptionScreen> {
  final SubscriptionService _service = SubscriptionService();

  @override
  void initState() {
    super.initState();
    _service.initialize();
    _service.addListener(_onUpdate);
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

  Future<void> _cancelSubscription() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Subscription?',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: HuddlColors.textDark)),
        content: Text(
          'Your subscription will remain active until the end of your current billing period. '
          'After that, you\'ll be moved to the Free plan and may lose access to premium features.',
          style:
              GoogleFonts.poppins(fontSize: 14, color: HuddlColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Plan',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, color: HuddlColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel Plan',
                style: GoogleFonts.poppins(color: HuddlColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.cancelSubscription();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscription cancelled',
                style: GoogleFonts.poppins(color: HuddlColors.white)),
            backgroundColor: HuddlColors.textHint,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _service.subscription;
    final limits = sub.limits;
    final isPaid = sub.isPaid;

    return Scaffold(
      backgroundColor: HuddlColors.background,
      appBar: AppBar(
        backgroundColor: HuddlColors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: HuddlColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Subscription',
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: HuddlColors.textDark)),
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
              const SizedBox(height: 20),

              // Usage section
              Text('Your Usage',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: HuddlColors.textDark)),
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
                color: HuddlColors.teal,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.groups_outlined,
                label: 'Meetups This Month',
                used: _service.meetupsThisMonth,
                limit: limits.maxMeetupsPerMonth,
                color: HuddlColors.accentAmber,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.chat_bubble_outline,
                label: 'DM Conversations',
                used: _service.dmConversations,
                limit: limits.maxDMConversations,
                color: HuddlColors.blue,
              ),
              const SizedBox(height: 8),
              _UsageCard(
                icon: Icons.storefront_outlined,
                label: 'Marketplace Listings',
                used: _service.marketplaceListings,
                limit: limits.maxMarketplaceListings,
                color: HuddlColors.accentCoral,
              ),

              const SizedBox(height: 24),

              // Actions
              if (!isPaid) ...[
                // Upgrade CTA
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF0E6), Color(0xFFFFF8F0)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: HuddlColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.rocket_launch,
                          color: HuddlColors.primary, size: 36),
                      const SizedBox(height: 12),
                      Text('Unlock More with Plus or Pro',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HuddlColors.textDark)),
                      const SizedBox(height: 6),
                      Text(
                        'Create private groups, host more meetups, go ad-free and more.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: HuddlColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _navigateToPlans,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: HuddlColors.primary,
                            foregroundColor: HuddlColors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('View Plans',
                              style: GoogleFonts.poppins(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Change plan / Cancel
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _navigateToPlans,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HuddlColors.primary,
                      side: const BorderSide(color: HuddlColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Change Plan',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _cancelSubscription,
                    child: Text('Cancel Subscription',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.error)),
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

class _CurrentPlanCard extends StatelessWidget {
  final UserSubscription subscription;
  const _CurrentPlanCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final isPro = subscription.isPro;
    final isPlus = subscription.isPlus;
    final isFree = subscription.isFree;

    Color accentColor = HuddlColors.textHint;
    IconData icon = Icons.person_outline;
    if (isPlus) {
      accentColor = HuddlColors.primary;
      icon = Icons.star;
    } else if (isPro) {
      accentColor = HuddlColors.teal;
      icon = Icons.workspace_premium;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HuddlColors.white,
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
      child: Row(
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
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: HuddlColors.textDark)),
                    if (subscription.isTrial) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: HuddlColors.accentAmber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Trial',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: HuddlColors.yellowDark)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (!isFree && subscription.renewalDate != null)
                  Text(
                    subscription.isTrial
                        ? 'Trial ends ${_formatDate(subscription.renewalDate!)}'
                        : 'Renews ${_formatDate(subscription.renewalDate!)}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: HuddlColors.textSecondary),
                  )
                else
                  Text('No active subscription',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: HuddlColors.textHint)),
              ],
            ),
          ),
          if (!isFree)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                subscription.billingPeriod == BillingPeriod.annual
                    ? 'Annual'
                    : 'Monthly',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor),
              ),
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
        color: HuddlColors.white,
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
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: HuddlColors.textDark)),
                    Text(
                      isUnlimited ? '$used / \u221E' : '$used / $limit',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isAtLimit
                            ? HuddlColors.error
                            : isNearLimit
                                ? HuddlColors.warning
                                : HuddlColors.textSecondary,
                      ),
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
