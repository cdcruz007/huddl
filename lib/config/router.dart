import 'package:flutter/material.dart';
import '../screens/onboarding/splash_screen.dart';
import '../screens/onboarding/not_available_screen.dart';
import '../screens/onboarding/onboarding_carousel_screen.dart';
import '../screens/onboarding/name_input_screen.dart';
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
import '../screens/onboarding/provider/provider_onboarding_screen.dart';
import '../screens/onboarding/provider/provider_complete_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/login_otp_screen.dart';
import '../screens/main_shell.dart';
import '../screens/groups/group_chat_screen.dart';
import '../screens/groups/group_details_screen.dart';
import '../screens/groups/group_members_screen.dart';
import '../screens/groups/create_group_screen.dart';
import '../screens/groups/dm_chat_screen.dart';
import '../screens/groups/new_dm_screen.dart';
import '../screens/groups/saved_messages_for_group_screen.dart';
import '../utils/page_transitions.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/splash':
        return FadePageRoute(page: const SplashScreen());

      case '/not_available':
        return FadePageRoute(page: const NotAvailableScreen());

      case '/onboarding':
        return FadePageRoute(page: const OnboardingCarouselScreen());

      case '/name_input':
        return SlidePageRoute(page: const NameInputScreen());

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

      case '/provider_onboarding':
        return SlidePageRoute(page: const ProviderOnboardingScreen());

      case '/provider_complete':
        return ScalePageRoute(page: const ProviderCompleteScreen());

      case '/login':
        return FadePageRoute(page: const LoginScreen());

      case '/login_otp':
        final args = settings.arguments as Map<String, String>?;
        return FadePageRoute(
          page: LoginOtpScreen(
            phoneNumber: args?['phoneNumber'] ?? '',
            generatedOtp: args?['generatedOtp'] ?? '123456',
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
            targetAudience: (args['targetAudience'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                const [],
            groupCategory: args['groupCategory'] as String? ?? '',
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
          ),
        );

      case '/group_members':
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return SlidePageRoute(
          page: GroupMembersScreen(
            groupName: args['groupName'] as String? ?? 'Group',
            memberCount: args['memberCount'] as int? ?? 0,
          ),
        );

      case '/create_group':
        return SlidePageRoute(
          page: const CreateGroupScreen(),
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
