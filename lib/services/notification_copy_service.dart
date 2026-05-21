// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — NOTIFICATION COPY SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Responsibilities:
//   1. Define 7 Android notification channels (channel ID, name, description,
//      importance) — mirrors AndroidManifest channel declarations.
//   2. Provide warm, human copywriting for each notification type.
//   3. Route notification taps to the correct in-app screen via deep-link data.
//   4. FCM token lifecycle helpers (save on login, clear on logout).
//
// Usage:
//   // Show copy for a new message notification:
//   final copy = NotificationCopyService.copy(HuddlNotificationType.newMessage,
//       params: {'senderName': 'Sarah', 'groupName': 'Toddler Tuesdays'});
//
//   // Route a tapped notification to the correct screen:
//   NotificationCopyService.handleTap(message, navigatorKey);
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// ── Channel IDs ────────────────────────────────────────────────────────────────
// Must match the channel IDs declared in android/app/src/main/AndroidManifest.xml
abstract class HuddlChannels {
  static const String groupMessages  = 'huddl_group_messages';
  static const String dmMessages     = 'huddl_dm_messages';
  static const String meetupUpdates  = 'huddl_meetup_updates';
  static const String marketAlerts   = 'huddl_market_alerts';
  static const String communityPosts = 'huddl_community_posts';
  static const String sendAlerts     = 'huddl_send_alerts';
  static const String systemAlerts   = 'huddl_system_alerts';
}

// ── Channel metadata ───────────────────────────────────────────────────────────
class HuddlChannelConfig {
  final String id;
  final String name;
  final String description;
  final int importance; // 4 = HIGH, 3 = DEFAULT, 2 = LOW

  const HuddlChannelConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
  });
}

// ── Notification types ─────────────────────────────────────────────────────────
enum HuddlNotificationType {
  newGroupMessage,
  newDmMessage,
  meetupRsvpReminder,
  meetupCancelled,
  newMarketOffer,
  listingSold,
  newCommunityPost,
  sendDeadlineReminder,
  systemAnnouncement,
}

// ── Notification copy ──────────────────────────────────────────────────────────
class NotificationCopy {
  final String title;
  final String body;
  final String channelId;

  const NotificationCopy({
    required this.title,
    required this.body,
    required this.channelId,
  });
}

// ── Main service ───────────────────────────────────────────────────────────────
class NotificationCopyService {

  // ── 7 Android notification channels ────────────────────────────────────────
  static const List<HuddlChannelConfig> channels = [
    HuddlChannelConfig(
      id: HuddlChannels.groupMessages,
      name: 'Group Messages',
      description: 'New messages in groups you\'ve joined',
      importance: 4,
    ),
    HuddlChannelConfig(
      id: HuddlChannels.dmMessages,
      name: 'Direct Messages',
      description: 'Private messages from other parents',
      importance: 4,
    ),
    HuddlChannelConfig(
      id: HuddlChannels.meetupUpdates,
      name: 'Meet-up Updates',
      description: 'Reminders and changes to meet-ups you\'re attending',
      importance: 4,
    ),
    HuddlChannelConfig(
      id: HuddlChannels.marketAlerts,
      name: 'Market Alerts',
      description: 'Offers received on your listings and items you\'ve saved',
      importance: 4,
    ),
    HuddlChannelConfig(
      id: HuddlChannels.communityPosts,
      name: 'Community Posts',
      description: 'New posts and replies in your local community feed',
      importance: 3,
    ),
    HuddlChannelConfig(
      id: HuddlChannels.sendAlerts,
      name: 'SEND Support',
      description: 'Deadline reminders and updates for SEND support tasks',
      importance: 4,
    ),
    HuddlChannelConfig(
      id: HuddlChannels.systemAlerts,
      name: 'Huddl Updates',
      description: 'Important account and app updates from Huddl',
      importance: 3,
    ),
  ];

  // ── Copy generator ─────────────────────────────────────────────────────────
  static NotificationCopy copy(
    HuddlNotificationType type, {
    Map<String, String> params = const {},
  }) {
    final sender    = params['senderName']  ?? 'Someone';
    final group     = params['groupName']   ?? 'your group';
    final item      = params['itemTitle']   ?? 'your item';
    final meetup    = params['meetupTitle'] ?? 'your meet-up';
    final price     = params['offerPrice']  ?? '';
    final deadline  = params['deadline']    ?? 'soon';

    switch (type) {
      case HuddlNotificationType.newGroupMessage:
        return NotificationCopy(
          title: '$sender in $group',
          body: 'Tap to see what\'s happening 💬',
          channelId: HuddlChannels.groupMessages,
        );

      case HuddlNotificationType.newDmMessage:
        return NotificationCopy(
          title: '$sender sent you a message',
          body: 'Reply and keep the conversation going',
          channelId: HuddlChannels.dmMessages,
        );

      case HuddlNotificationType.meetupRsvpReminder:
        return NotificationCopy(
          title: '$meetup is coming up!',
          body: 'Don\'t forget — you\'re going to this tomorrow 🗓️',
          channelId: HuddlChannels.meetupUpdates,
        );

      case HuddlNotificationType.meetupCancelled:
        return NotificationCopy(
          title: '$meetup has been cancelled',
          body: 'The organiser has called it off. Check the app for updates.',
          channelId: HuddlChannels.meetupUpdates,
        );

      case HuddlNotificationType.newMarketOffer:
        return NotificationCopy(
          title: 'Offer on $item',
          body: price.isNotEmpty
              ? 'Someone offered £$price — want to accept?'
              : 'You\'ve received a new offer on your listing 🛍️',
          channelId: HuddlChannels.marketAlerts,
        );

      case HuddlNotificationType.listingSold:
        return NotificationCopy(
          title: '$item has been rehomed! 🎉',
          body: 'Great news — your listing found a new home.',
          channelId: HuddlChannels.marketAlerts,
        );

      case HuddlNotificationType.newCommunityPost:
        return NotificationCopy(
          title: 'New post in your area',
          body: '$sender shared something in your community 📣',
          channelId: HuddlChannels.communityPosts,
        );

      case HuddlNotificationType.sendDeadlineReminder:
        return NotificationCopy(
          title: 'SEND deadline approaching',
          body: 'Your $deadline deadline is coming up — tap to review 📋',
          channelId: HuddlChannels.sendAlerts,
        );

      case HuddlNotificationType.systemAnnouncement:
        return NotificationCopy(
          title: 'A note from Huddl',
          body: params['body'] ?? 'We have something important to share with you.',
          channelId: HuddlChannels.systemAlerts,
        );
    }
  }

  // ── Deep-link routing ──────────────────────────────────────────────────────
  //
  // FCM message data payload conventions:
  //   type          → maps to a route (see switch below)
  //   groupId       → for /group_chat and /group_details routes
  //   groupName     → display name for group chat screen
  //   conversationId → for /dm_chat route
  //   recipientId   → for /dm_chat route
  //   recipientName → for /dm_chat route
  //   eventId       → for /event_detail route
  //   itemId        → for /item_detail route (requires RehomeItem lookup)
  //
  static void handleTap(
    RemoteMessage message,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    final data = message.data;
    final type = data['type'] as String? ?? '';

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {
      case 'group_message':
        nav.pushNamed('/group_chat', arguments: {
          'groupId':   data['groupId']   ?? '',
          'groupName': data['groupName'] ?? 'Group Chat',
          'groupImageUrl': data['groupImageUrl'] ?? '',
          'isDefaultGroup': false,
          'isPrivate': false,
          'targetAudience': <String>[],
          'groupCategory': '',
        });
        break;

      case 'dm_message':
        nav.pushNamed('/dm_chat', arguments: {
          'recipientId':   data['recipientId']   ?? '',
          'recipientName': data['recipientName'] ?? 'Chat',
          'conversationId': data['conversationId'],
          'recipientAvatarColor': data['avatarColor'] ?? '#FF975C',
        });
        break;

      case 'meetup_update':
      case 'meetup_reminder':
        nav.pushNamed('/home');
        break;

      case 'market_offer':
      case 'listing_sold':
        nav.pushNamed('/home');
        break;

      case 'community_post':
        nav.pushNamed('/home');
        break;

      case 'send_deadline':
        nav.pushNamed('/send');
        break;

      default:
        // Unknown type — go home
        nav.pushNamed('/home');
        break;
    }
  }
}
