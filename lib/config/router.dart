import 'package:flutter/material.dart';
import '../screens/onboarding/splash_screen.dart';
import '../screens/onboarding/not_available_screen.dart';
import '../screens/onboarding/onboarding_carousel_screen.dart';
import '../screens/onboarding/name_input_screen.dart';
import '../screens/onboarding/data_consent_screen.dart';
import '../screens/onboarding/parent_type_screen.dart';
import '../screens/onboarding/stage_of_life_screen.dart';
import '../screens/onboarding/postcode_screen.dart';
import '../screens/onboarding/due_date_screen.dart';
import '../screens/onboarding/child_info_screen.dart';
import '../screens/onboarding/phone_number_screen.dart';
import '../screens/onboarding/password_screen.dart';
import '../screens/onboarding/verification_screen.dart';
import '../screens/onboarding/welcome_complete_screen.dart';
import '../screens/onboarding/add_photo_screen.dart';
import '../screens/onboarding/about_you_screen.dart';
import '../screens/onboarding/email_pending_verification_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/login_otp_screen.dart';
import '../screens/auth/biometric_lock_screen.dart';
import '../screens/ai/ai_copilot_screen.dart';
import '../screens/main_shell.dart';
import '../screens/groups/group_chat_screen.dart';
import '../screens/groups/group_details_screen.dart';
import '../screens/groups/group_members_screen.dart';
import '../screens/groups/create_group_screen.dart';
import '../screens/groups/dm_chat_screen.dart';
import '../screens/groups/new_dm_screen.dart';
import '../screens/groups/saved_messages_for_group_screen.dart';
import '../screens/legal/terms_of_service_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/insights/insights_screen.dart';
import '../screens/insights/send_hub_screen.dart';
import '../screens/services/services_screen.dart';
import '../screens/legal/privacy_policy_detail_screen.dart';
import '../screens/marketplace/item_detail_screen.dart';
import '../screens/rehome/create_listing_screen.dart';
import '../screens/subscription/subscription_plans_screen.dart';
import '../screens/subscription/subscription_checkout_screen.dart';
import '../screens/subscription/manage_subscription_screen.dart';
import '../services/rehome_service.dart';
import '../services/payment_service.dart';
import '../models/subscription.dart';
import '../screens/home/journey_map_screen.dart';
import '../screens/profile/backup_restore_screen.dart';
import '../screens/noticeboard/noticeboard_screen.dart';
import '../screens/subscription/business_verification_screen.dart';
import '../screens/partner/partner_profile_screen.dart';
import '../screens/partner/partner_analytics_screen.dart';
import '../screens/partner/create_partner_listing_screen.dart';
import '../utils/page_transitions.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      // '/' is pushed automatically by Flutter's Navigator as a prefix of
      // any initialRoute that begins with '/'. Map it to the splash screen
      // so the app never shows "No route defined for /".
      case '/':
      case '/splash':
        return FadePageRoute(page: const SplashScreen());

      case '/not_available':
        return FadePageRoute(page: const NotAvailableScreen());

      case '/onboarding':
        return FadePageRoute(page: const OnboardingCarouselScreen());

      case '/name_input':
        return SlidePageRoute(page: const NameInputScreen());

      case '/consent':
        return SlidePageRoute(page: const DataConsentScreen());

      case '/parent_type':
        return SlidePageRoute(page: const ParentTypeScreen());

      case '/stage_of_life':
        return SlidePageRoute(page: const StageOfLifeScreen());

      case '/postcode':
        return SlidePageRoute(page: const PostcodeScreen());

      case '/due_date':
        return SlidePageRoute(page: const DueDateScreen());

      case '/child_info':
        return SlidePageRoute(page: const ChildInfoScreen());

      case '/phone_number':
        return SlidePageRoute(page: const PhoneNumberScreen());

      case '/password':
        return SlidePageRoute(page: const PasswordScreen());

      case '/verification':
        return SlidePageRoute(page: const VerificationScreen());

      case '/welcome_complete':
        return ScalePageRoute(page: const WelcomeCompleteScreen());

      case '/add_photo':
        return SlidePageRoute(page: const AddPhotoScreen());

      case '/about_you':
        return SlidePageRoute(page: const AboutYouScreen());

      case '/email_pending_verification':
        return FadePageRoute(page: const EmailPendingVerificationScreen());

      case '/login':
        return FadePageRoute(page: const LoginScreen());

      case '/biometric_lock':
        return FadePageRoute(page: const BiometricLockScreen());

      case '/login_otp':
        final args = settings.arguments as Map<String, String>?;
        return FadePageRoute(
          page: LoginOtpScreen(
            phoneNumber: args?['phoneNumber'] ?? '',
            generatedOtp: args?['generatedOtp'] ?? '',
          ),
        );

      case '/home':
        return FadePageRoute(
          page: MainShell(key: MainShell.shellKey),
        );

      // ── Group feature routes ──────────────────────────────────────
      case '/group_chat':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: GroupChatScreen(
            groupId: args['groupId'] as String? ?? '',
            groupName: args['groupName'] as String? ?? 'Group Chat',
            groupImageUrl: args['groupImageUrl'] as String? ?? '',
            isDefaultGroup: args['isDefaultGroup'] as bool? ?? false,
            isPrivate: args['isPrivate'] as bool? ?? false,
            creatorId: args['creatorId'] as String?,
            creatorBorough: args['creatorBorough'] as String?,
            targetAudience: (args['targetAudience'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                const [],
            groupCategory: args['groupCategory'] as String? ?? '',
            openThreadForMessageId: args['openThreadForMessageId'] as String?,
          ),
        );

      case '/group_details':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: GroupDetailsScreen(
            groupId: args['groupId'] as String? ?? '',
            groupName: args['groupName'] as String? ?? 'Group',
            groupImageUrl: args['groupImageUrl'] as String? ?? '',
            groupDescription: args['groupDescription'] as String?,
            memberCount: args['memberCount'] as int?,
            isPrivate: args['isPrivate'] as bool? ?? false,
            creatorId: args['creatorId'] as String?,
            isJoined: args['isJoined'] as bool? ?? true,
            creatorBorough: args['creatorBorough'] as String?,
          ),
        );

      case '/group_members':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: GroupMembersScreen(
            groupId: args['groupId'] as String? ?? '',
            groupName: args['groupName'] as String? ?? 'Group',
            memberCount: args['memberCount'] as int? ?? 0,
            creatorId: args['creatorId'] as String?,
          ),
        );

      case '/create_group':
        return SlidePageRoute(
          page: const CreateGroupScreen(),
          direction: SlideDirection.up,
        );

      case '/copilot':
        final copilotArgs = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: AiCopilotScreen(
            initialMessage: copilotArgs['initialMessage'] as String?,
            autoSend: copilotArgs['autoSend'] as bool? ?? false,
          ),
          direction: SlideDirection.up,
        );

      // ── DM feature routes ──────────────────────────────────────────
      case '/dm_chat':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: DMChatScreen(
            recipientId: args['recipientId'] as String? ?? '',
            recipientName: args['recipientName'] as String? ?? 'Chat',
            recipientAvatarColor: args['recipientAvatarColor'] as String? ?? '#FF975C',
            conversationId: args['conversationId'] as String?,
          ),
        );

      case '/new_dm':
        return SlidePageRoute(
          page: const NewDMScreen(),
          direction: SlideDirection.up,
        );

      case '/saved_messages_for_group':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: SavedMessagesForGroupScreen(
            groupId: args['groupId'] as String? ?? '',
            groupName: args['groupName'] as String? ?? 'Group',
          ),
        );

      case '/terms':
        return SlidePageRoute(page: const TermsOfServiceScreen());

      case '/privacy':
        return SlidePageRoute(page: const PrivacyPolicyDetailScreen());

      // ── Rehome feature routes ────────────────────────────────────────
      case '/create_listing':
        return SlidePageRoute(
          page: const CreateListingScreen(),
          direction: SlideDirection.up,
        );

      // ── Subscription feature routes ──────────────────────────────────
      case '/subscription_plans':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        SubscriptionTier? highlightTier;
        final hlStr = args['highlightTier'] as String?;
        if (hlStr != null) {
          highlightTier = SubscriptionTier.values.firstWhere(
            (t) => t.name == hlStr,
            orElse: () => SubscriptionTier.neighbourhood,
          );
        }
        return SlidePageRoute(
          page: SubscriptionPlansScreen(
            highlightTier: highlightTier,
            gateMessage: args['gateMessage'] as String?,
          ),
          direction: SlideDirection.up,
        );

      case '/subscription_checkout':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: SubscriptionCheckoutScreen(
            tier: SubscriptionTier.values.firstWhere(
              (t) => t.name == (args['tier'] as String? ?? 'neighbourhood'),
              orElse: () => SubscriptionTier.neighbourhood,
            ),
            period: BillingPeriod.values.firstWhere(
              (b) => b.name == (args['period'] as String? ?? 'annual'),
              orElse: () => BillingPeriod.annual,
            ),
            isScheduled: args['isScheduled'] as bool? ?? false,
          ),
        );

      case '/manage_subscription':
        return SlidePageRoute(
          page: const ManageSubscriptionScreen(),
        );

      // ── Stripe web payment return routes ────────────────────────────
      // Stripe redirects here after a successful checkout.
      // Calls notifyStripeSuccess() so the checkout screen shows the
      // success dialog and SubscriptionService updates the local tier.
      case '/subscription/success':
        // Extract session_id from arguments if passed by the web router
        final successArgs = settings.arguments as Map<String, dynamic>? ?? {};
        // Notify PaymentService — triggers onPurchaseSuccess callback
        // which calls SubscriptionService.purchase() and shows success dialog
        Future.microtask(() {
          PaymentService().notifyStripeSuccess(
            successArgs['productId'] as String? ?? '',
          );
        });
        // Navigate to home — the checkout screen listener will show the dialog
        return FadePageRoute(
          page: MainShell(key: MainShell.shellKey),
        );

      case '/subscription/cancel':
        // User clicked Back on Stripe Checkout — just go to home
        return FadePageRoute(
          page: MainShell(key: MainShell.shellKey),
        );

      case '/item_detail':
        final item = settings.arguments;
        if (item is! RehomeItem) {
          return MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Item not found')),
            ),
          );
        }
        return SlidePageRoute(
          page: ItemDetailScreen(item: item),
        );

      case '/journey_maps':
        return SlidePageRoute(page: const JourneyMapScreen());

      case '/backup_restore':
        return SlidePageRoute(page: const BackupRestoreScreen());

      case '/admin':
        return SlidePageRoute(page: const AdminDashboardScreen());

      case '/insights':
        return SlidePageRoute(page: const InsightsScreen());

      case '/send':
        return SlidePageRoute(page: const SendHubScreen());

      case '/services':
        return SlidePageRoute(
          page: ServicesScreen(searchTrigger: ValueNotifier<bool>(false)),
          direction: SlideDirection.up,
        );

      case '/noticeboard':
        return SlidePageRoute(page: const NoticeboardScreen());

      // ── Partner feature routes ──────────────────────────────────
      case '/business_verification':
        return SlidePageRoute(
          page: const BusinessVerificationScreen(),
          direction: SlideDirection.up,
        );

      case '/partner_profile':
        final ppArgs = settings.arguments as Map<String, dynamic>? ?? {};
        final partnerUid = ppArgs['partnerUid'] as String? ?? '';
        return SlidePageRoute(
          page: PartnerProfileScreen(partnerUid: partnerUid),
        );

      case '/partner_analytics':
        return SlidePageRoute(
          page: const PartnerAnalyticsScreen(),
        );

      case '/create_partner_listing':
        return SlidePageRoute(
          page: const CreatePartnerListingScreen(),
          direction: SlideDirection.up,
        );

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
