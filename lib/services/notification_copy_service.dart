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
//
// params keys used across notification types:
//   senderName      → person sending/creating
//   groupName       → group context
//   itemTitle       → marketplace item
//   meetupTitle     → meetup title
//   meetupLocation  → meetup venue / location string
//   meetupTime      → formatted time e.g. "10:30 AM"
//   offerPrice      → offer amount in pounds
//   deadline        → SEND deadline label
//   messagePreview  → actual message text preview
//   postPreview     → community post preview text
//   buyerName       → buyer name for sold notification
//   body            → custom body for system announcements
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
    final sender   = params['senderName']  ?? 'Someone';
    final group    = params['groupName']   ?? 'your group';
    final item     = params['itemTitle']   ?? 'your item';
    final meetup   = params['meetupTitle'] ?? 'your meet-up';
    final price    = params['offerPrice']  ?? '';
    final deadline = params['deadline']    ?? 'soon';

    switch (type) {

      // ── MESSAGING ────────────────────────────────────────────────────────────

      case HuddlNotificationType.newGroupMessage:
        // Shows the actual message preview — parents need to know WHAT was said
        return NotificationCopy(
          title: '$sender in $group',
          body: params['messagePreview']?.isNotEmpty == true
              ? params['messagePreview']!
              : 'Sent a message in $group',
          channelId: HuddlChannels.groupMessages,
        );

      case HuddlNotificationType.newDmMessage:
        // Shows the message preview so it feels personal
        return NotificationCopy(
          title: sender,
          body: params['messagePreview']?.isNotEmpty == true
              ? params['messagePreview']!
              : 'Sent you a message',
          channelId: HuddlChannels.dmMessages,
        );

      // ── MEETUPS & EVENTS ─────────────────────────────────────────────────────

      case HuddlNotificationType.meetupRsvpReminder:
        // Includes the time and location so parents can plan
        final location = params['meetupLocation'] ?? '';
        final time     = params['meetupTime'] ?? 'tomorrow';
        return NotificationCopy(
          title: '$meetup tomorrow 🗓️',
          body: location.isNotEmpty
              ? '$time · $location — you\'re going!'
              : 'You\'re going! Tap to see the details.',
          channelId: HuddlChannels.meetupUpdates,
        );

      case HuddlNotificationType.meetupCancelled:
        // Warmer, more direct, names the organiser
        return NotificationCopy(
          title: '$meetup has been cancelled',
          body: '$sender has called it off — check the app for alternatives nearby.',
          channelId: HuddlChannels.meetupUpdates,
        );

      // ── MARKETPLACE ──────────────────────────────────────────────────────────

      case HuddlNotificationType.newMarketOffer:
        // Shows the actual offer amount — sellers need to know the number
        return NotificationCopy(
          title: 'Offer on "$item"',
          body: price.isNotEmpty
              ? '$sender offered £$price — accept, decline, or counter?'
              : '$sender made an offer on your listing — tap to respond.',
          channelId: HuddlChannels.marketAlerts,
        );

      case HuddlNotificationType.listingSold:
        // Names the buyer — makes it feel like a real community exchange
        final buyer = params['buyerName'] ?? 'a local parent';
        return NotificationCopy(
          title: '"$item" has been rehomed 🎉',
          body: 'Going to $buyer — great sale!',
          channelId: HuddlChannels.marketAlerts,
        );

      case HuddlNotificationType.newCommunityPost:
        // Includes what was shared
        final postPreview = params['postPreview'] ?? '';
        return NotificationCopy(
          title: '$sender posted in your area',
          body: postPreview.isNotEmpty
              ? postPreview.length > 80
                  ? '${postPreview.substring(0, 77)}…'
                  : postPreview
              : 'Tap to see what\'s happening in your neighbourhood.',
          channelId: HuddlChannels.communityPosts,
        );

      case HuddlNotificationType.sendDeadlineReminder:
        // More urgent, actionable
        return NotificationCopy(
          title: 'SEND deadline: $deadline ⏰',
          body: 'This is coming up soon — tap to review your checklist.',
          channelId: HuddlChannels.sendAlerts,
        );

      case HuddlNotificationType.systemAnnouncement:
        return NotificationCopy(
          title: params['title'] ?? 'A note from Huddl',
          body: params['body'] ?? 'We have something to share with you.',
          channelId: HuddlChannels.systemAlerts,
        );
    }
  }

  // ── Deep-link routing ──────────────────────────────────────────────────────
  //
  // FCM message data payload conventions:
  //   type            → maps to a route (see switch below)
  //   groupId         → for /group_chat and /group_details routes
  //   groupName       → display name for group chat screen
  //   conversationId  → for /dm_chat route
  //   recipientId     → for /dm_chat route
  //   recipientName   → for /dm_chat route
  //   meetupId        → for /meetup_detail route
  //   itemId          → for /marketplace route
  //   tab             → marketplace tab ('buy' or 'sell')
  //
  static void handleTap(
    RemoteMessage message,
    GlobalKey<NavigatorState> navigatorKey,
  ) {
    final data = message.data;
    final type = data['type'] as String? ?? '';
    final nav  = navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {

      // ── GROUP CHAT ────────────────────────────────────────────────────────
      case 'group_message':
      case 'new_group_message':
      case 'voice_message_group':
      case 'poll_created':
        nav.pushNamed('/group_chat', arguments: {
          'groupId':        data['groupId']       ?? '',
          'groupName':      data['groupName']     ?? 'Group Chat',
          'groupImageUrl':  data['groupImageUrl'] ?? '',
          'isDefaultGroup': false,
          'isPrivate':      false,
          'targetAudience': <String>[],
          'groupCategory':  '',
        });
        break;

      // ── DIRECT MESSAGES ───────────────────────────────────────────────────
      case 'dm_message':
      case 'new_dm':
      case 'voice_message_dm':
        nav.pushNamed('/dm_chat', arguments: {
          'recipientId':          data['recipientId']    ?? '',
          'recipientName':        data['recipientName']  ?? 'Chat',
          'conversationId':       data['conversationId'],
          'recipientAvatarColor': data['avatarColor']    ?? '#FF975C',
        });
        break;

      // ── MEETUPS — route to specific meetup ────────────────────────────────
      case 'meetup_update':
      case 'meetup_reminder':
      case 'new_meetup_nearby':
      case 'meetup_rsvp':
        if (data['meetupId']?.isNotEmpty == true) {
          nav.pushNamed('/home');
          // After home loads, push to meetup detail via the meetupId
          Future.delayed(const Duration(milliseconds: 400), () {
            nav.pushNamed('/meetup_detail', arguments: {
              'meetupId': data['meetupId'],
            });
          });
        } else {
          nav.pushNamed('/home');
        }
        break;

      // ── MARKETPLACE — route to specific listing ───────────────────────────
      case 'market_offer':
      case 'offer_received':
      case 'offer_accepted':
      case 'offer_declined':
      case 'item_sold':
      case 'saved_item_sold':
      case 'saved_item_price_drop':
      case 'item_relisted':
        nav.pushNamed('/marketplace', arguments: {
          'tab':    data['tab']    ?? 'sell',
          'itemId': data['itemId'] ?? '',
        });
        break;

      // ── COMMUNITY ─────────────────────────────────────────────────────────
      case 'community_post':
      case 'new_community_post':
        nav.pushNamed('/home');
        break;

      // ── SEND ──────────────────────────────────────────────────────────────
      case 'send_deadline':
      case 'send_deadline_reminder':
        nav.pushNamed('/send');
        break;

      // ── GROUPS & SOCIAL ───────────────────────────────────────────────────
      case 'group_invitation':
      case 'group_member_joined':
        nav.pushNamed('/group_chat', arguments: {
          'groupId':        data['groupId']   ?? '',
          'groupName':      data['groupName'] ?? 'Group',
          'groupImageUrl':  '',
          'isDefaultGroup': false,
          'isPrivate':      false,
          'targetAudience': <String>[],
          'groupCategory':  '',
        });
        break;

      default:
        nav.pushNamed('/home');
        break;
    }
  }
}
