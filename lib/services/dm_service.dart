import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import '../models/direct_message.dart';
import 'borough_scope_guard.dart';
import 'user_privacy_prefs_service.dart';

/// Singleton service that manages DM conversations and messages.
///
/// HYPERLOCAL RULE: DMs are borough-only.
/// Users can only start conversations with other parents in the same
/// borough. The guard check is performed at conversation creation time.
///
/// In production these would live in Firestore with real-time listeners.
/// Here we use BrowserStorage + simulated replies so the demo is end-to-end.
class DMService {
  static final DMService _instance = DMService._internal();
  factory DMService() => _instance;
  DMService._internal();

  static const String _conversationsKey = 'dm_conversations_v2';
  static const String _messagesKeyPrefix = 'dm_messages_'; // + conversationId
  bool _isInitialized = false;
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  List<DMConversation> _conversations = [];

  List<DMConversation> get conversations => List.unmodifiable(_conversations);

  // ── Typing simulation timers ────────────────────────────────────────────
  final Map<String, Timer?> _typingTimers = {};
  final Map<String, Timer?> _replyTimers = {};

  // ── Callbacks for UI refresh ────────────────────────────────────────────
  final List<VoidCallback> _listeners = [];
  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notify() {
    for (final cb in _listeners) {
      cb();
    }
  }

  // ── Online status simulation ────────────────────────────────────────────
  /// Returns simulated online status for a given user.
  ///
  /// If the CURRENT user has "Show online status" turned off in Privacy
  /// settings, we always report them as offline to others. For other users
  /// we simulate ~40% online based on a name hash.
  bool isUserOnline(String recipientId) {
    // If this user is "the current user" appearing in their own DM list,
    // respect their privacy setting.
    if (!UserPrivacyPrefsService().showOnlineStatus) return false;
    // Simulate ~40% of users being online
    return recipientId.hashCode.abs() % 5 < 2;
  }

  // ── Initialisation ──────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      final raw = await BrowserStorage.getString(_conversationsKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _conversations = decoded
            .map((j) => DMConversation.fromJson(j as Map<String, dynamic>))
            .toList();
      }
      // Migrate from old key if empty
      if (_conversations.isEmpty) {
        final oldRaw = await BrowserStorage.getString('dm_conversations_v1');
        if (oldRaw != null) {
          final List<dynamic> decoded = json.decode(oldRaw);
          _conversations = decoded
              .map((j) => DMConversation.fromJson(j as Map<String, dynamic>))
              .toList();
          await _saveConversations();
        }
      }
      _isInitialized = true;
      _log('Loaded ${_conversations.length} DM conversation(s)');
    } catch (e) {
      _log('Error loading conversations: $e');
      _isInitialized = true;
    }
  }

  Future<void> _saveConversations() async {
    await BrowserStorage.setString(
      _conversationsKey,
      json.encode(_conversations.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _saveMessages(String convId, List<DirectMessage> msgs) async {
    await BrowserStorage.setString(
      '$_messagesKeyPrefix$convId',
      json.encode(msgs.map((m) => m.toJson()).toList()),
    );
  }

  // ── Load messages for a conversation ────────────────────────────────────
  Future<List<DirectMessage>> getMessages(String conversationId) async {
    await initialize();
    try {
      final raw = await BrowserStorage.getString(
          '$_messagesKeyPrefix$conversationId');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        final messages = <DirectMessage>[];
        for (final j in decoded) {
          try {
            // Safe cast: json.decode may return Map<dynamic,dynamic>
            final Map<String, dynamic> map = (j is Map<String, dynamic>)
                ? j
                : Map<String, dynamic>.from(j as Map);
            messages.add(DirectMessage.fromJson(map));
          } catch (parseErr) {
            _log('Skipping malformed message: $parseErr');
          }
        }
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return messages;
      }
    } catch (e) {
      _log('Error loading messages for $conversationId: $e');
    }
    return [];
  }

  // ── Get or create a conversation ────────────────────────────────────────
  /// Find an existing conversation by recipientId without creating one.
  /// Returns null if no conversation exists yet.
  Future<DMConversation?> findConversation(String recipientId) async {
    await initialize();
    try {
      return _conversations.firstWhere((c) => c.recipientId == recipientId);
    } catch (_) {
      return null;
    }
  }

  Future<DMConversation> getOrCreateConversation({
    required String recipientId,
    required String recipientName,
    String? avatarColor,
    String? recipientBorough,
  }) async {
    await initialize();
    final existing = _conversations.firstWhere(
      (c) => c.recipientId == recipientId,
      orElse: () => DMConversation(
        id: '',
        recipientId: '',
        recipientName: '',
        recipientAvatarColor: '',
      ),
    );
    if (existing.id.isNotEmpty) return existing;

    // ── HYPERLOCAL GATE: block cross-borough DMs ─────────────────────
    // If we know the recipient's borough and it doesn't match, block.
    if (recipientBorough != null && recipientBorough.isNotEmpty) {
      if (!_guard.canInteract(
        feature: HuddlFeature.directMessages,
        targetBorough: recipientBorough,
        targetName: recipientName,
      )) {
        // Return a placeholder that signals "blocked" to the UI
        return DMConversation(
          id: 'blocked',
          recipientId: recipientId,
          recipientName: recipientName,
          recipientAvatarColor: avatarColor ?? _colorForName(recipientName),
        );
      }
    }

    // Assign a consistent color based on name hash
    final color = avatarColor ?? _colorForName(recipientName);
    final conv = DMConversation(
      id: 'dm_$recipientId',
      recipientId: recipientId,
      recipientName: recipientName,
      recipientAvatarColor: color,
      isOnline: isUserOnline(recipientId),
    );
    _conversations.add(conv);
    await _saveConversations();
    _notify();
    return conv;
  }

  // ── Send a message (text or rich type) ──────────────────────────────────
  Future<DirectMessage> sendMessage({
    required String conversationId,
    required String message,
    required String senderName,
    String? replyToText,
    String? replyToSender,
    MessageType type = MessageType.text,
    String? imageUrl,
    String? documentName,
    int? documentSize,
    double? latitude,
    double? longitude,
    String? locationLabel,
    String? contactName,
    String? contactPhone,
    Map<String, dynamic>? meetupData,
    Map<String, dynamic>? groupData,
    Map<String, dynamic>? itemData,
    Map<String, dynamic>? eventData,
  }) async {
    await initialize();

    if (kDebugMode) {
      debugPrint('💾 DMService.sendMessage called:');
      debugPrint('   convId: $conversationId');
      debugPrint('   type: ${type.name}');
      if (kDebugMode) {
        debugPrint('   meetupData: ${meetupData != null ? 'YES (${meetupData.keys.length} keys)' : 'NO'}');
      }
      debugPrint('   groupData: ${groupData != null ? 'YES (${groupData.keys.length} keys)' : 'NO'}');
      debugPrint('   itemData: ${itemData != null ? 'YES (${itemData.keys.length} keys)' : 'NO'}');
    }

    // 1. Create the message with 'sending' status
    final msg = DirectMessage(
      id: 'dm_msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
      senderName: senderName,
      message: message,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.sending,
      replyToText: replyToText,
      replyToSender: replyToSender,
      type: type,
      imageUrl: imageUrl,
      documentName: documentName,
      documentSize: documentSize,
      latitude: latitude,
      longitude: longitude,
      locationLabel: locationLabel,
      contactName: contactName,
      contactPhone: contactPhone,
      meetupData: meetupData,
      groupData: groupData,
      itemData: itemData,
      eventData: eventData,
    );

    // Save message
    final messages = await getMessages(conversationId);
    messages.add(msg);
    await _saveMessages(conversationId, messages);
    
    if (kDebugMode) {
      if (kDebugMode) {
        debugPrint('💾 Message saved to storage:');
      }
      final json = msg.toJson();
      debugPrint('   groupData in JSON: ${json['groupData'] != null ? 'YES' : 'NO'}');
      debugPrint('   itemData in JSON: ${json['itemData'] != null ? 'YES' : 'NO'}');
      if (kDebugMode) debugPrint('   meetupData in JSON: ${json["meetupData"] != null ? "YES" : "NO"}');
    }

    // Determine display text for conversation list
    String displayText = message;
    
    // Check for card data first (takes priority)
    if (groupData != null) {
      displayText = '\u{1F465} Group: ${groupData['name'] ?? 'Group'}';
    } else if (itemData != null) {
      displayText = '\u{1F4E6} Item: ${itemData['title'] ?? 'Item'}';
    } else if (meetupData != null) {
      displayText = '\u{1F4C5} Meetup: ${meetupData['title'] ?? 'Meetup'}';
    } else if (eventData != null) {
      displayText = '\u{1F4C5} Event: ${eventData['title'] ?? 'Event'}';
    } else {
      // Fallback to message type
      switch (type) {
        case MessageType.image:
          displayText = '\u{1F4F7} Photo';
          break;
        case MessageType.document:
          displayText = '\u{1F4C4} ${documentName ?? 'Document'}';
          break;
        case MessageType.location:
          displayText = '\u{1F4CD} Location';
          break;
        case MessageType.contact:
          displayText = '\u{1F464} ${contactName ?? 'Contact'}';
          break;
        case MessageType.meetupInvite:
          displayText = '\u{1F4C5} Meetup invite';
          break;
        case MessageType.voiceNote:
          displayText = '\u{1F3A4} Voice message';
          break;
        case MessageType.text:
          break;
      }
    }

    // Update conversation
    _updateConversationLastMessage(conversationId, displayText, senderName);

    // 2. Simulate sent status after brief delay
    _simulateMessageStatusProgression(conversationId, msg.id);

    // 3. Only simulate reply for text messages
    if (type == MessageType.text) {
      _simulateRecipientReply(conversationId);
    }

    return msg;
  }

  // ── Toggle emoji reaction on a message ──────────────────────────────────
  Future<void> toggleReaction(
      String conversationId, String messageId, String emoji) async {
    final messages = await getMessages(conversationId);
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final msg = messages[idx];
      final rxn = Map<String, int>.from(msg.reactions);
      if (rxn.containsKey(emoji) && rxn[emoji]! > 0) {
        rxn.remove(emoji);
      } else {
        rxn[emoji] = (rxn[emoji] ?? 0) + 1;
      }
      messages[idx] = msg.copyWith(reactions: rxn);
      await _saveMessages(conversationId, messages);
      _notify();
    }
  }

  // ── Toggle mute on a conversation ───────────────────────────────────────
  Future<void> toggleMute(String conversationId) async {
    await initialize();
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx != -1) {
      _conversations[idx] =
          _conversations[idx].copyWith(isMuted: !_conversations[idx].isMuted);
      await _saveConversations();
      _notify();
    }
  }

  bool isMuted(String conversationId) {
    try {
      return _conversations.firstWhere((c) => c.id == conversationId).isMuted;
    } catch (_) {
      return false;
    }
  }

  // ── Update message status ───────────────────────────────────────────────
  Future<void> updateMessageStatus(
      String conversationId, String messageId, MessageStatus newStatus) async {
    final messages = await getMessages(conversationId);
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      messages[idx] = messages[idx].copyWith(status: newStatus);
      await _saveMessages(conversationId, messages);
    }
  }

  // ── Simulate message status changes ─────────────────────────────────────
  void _simulateMessageStatusProgression(
      String conversationId, String messageId) {
    // sending → sent (0.5s)
    Future.delayed(const Duration(milliseconds: 500), () async {
      await updateMessageStatus(conversationId, messageId, MessageStatus.sent);
      _notify();
    });

    // sent → delivered (1.5s)
    Future.delayed(const Duration(milliseconds: 1500), () async {
      await updateMessageStatus(
          conversationId, messageId, MessageStatus.delivered);
      _notify();
    });

    // delivered → read (3s) — simulates recipient opening the chat
    Future.delayed(const Duration(milliseconds: 3000), () async {
      await updateMessageStatus(conversationId, messageId, MessageStatus.read);
      _notify();
    });
  }

  // ── Simulate typing indicator + automated reply ─────────────────────────
  void _simulateRecipientReply(String conversationId) {
    // Cancel any existing timer for this conversation
    _typingTimers[conversationId]?.cancel();
    _replyTimers[conversationId]?.cancel();

    // Show typing after 2 seconds
    _typingTimers[conversationId] =
        Timer(const Duration(seconds: 2), () {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx != -1) {
        _conversations[idx] = _conversations[idx].copyWith(isTyping: true);
        _notify();
      }
    });

    // Send reply after 4 seconds
    _replyTimers[conversationId] =
        Timer(const Duration(seconds: 4), () async {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx == -1) return;
      final conv = _conversations[idx];

      // Stop typing
      _conversations[idx] = conv.copyWith(isTyping: false);

      // Generate contextual reply
      final reply = _generateAutoReply(conv.recipientName);
      final replyMsg = DirectMessage(
        id: 'dm_msg_${DateTime.now().millisecondsSinceEpoch}',
        senderId: conv.recipientId,
        senderName: conv.recipientName,
        message: reply,
        timestamp: DateTime.now(),
        isMe: false,
        status: MessageStatus.read,
      );

      final messages = await getMessages(conversationId);
      messages.add(replyMsg);
      await _saveMessages(conversationId, messages);

      // Update conversation
      _conversations[idx] = _conversations[idx].copyWith(
        lastMessage: reply,
        lastSenderName: conv.recipientName,
        lastMessageTime: DateTime.now(),
        unreadCount: (_conversations[idx].unreadCount) + 1,
      );
      await _saveConversations();
      _notify();
    });
  }

  // ── Mark conversation as read ───────────────────────────────────────────
  Future<void> markConversationRead(String conversationId) async {
    await initialize();
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx != -1) {
      _conversations[idx] = _conversations[idx].copyWith(unreadCount: 0);
      await _saveConversations();
      _notify();
    }
  }

  // ── Mark conversation as unread ─────────────────────────────────────────
  Future<void> markConversationUnread(String conversationId) async {
    await initialize();
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx != -1) {
      // Set unread to 1 if it was 0 so the bold treatment shows
      if (_conversations[idx].unreadCount == 0) {
        _conversations[idx] = _conversations[idx].copyWith(unreadCount: 1);
        await _saveConversations();
        _notify();
      }
    }
  }

  // ── Delete conversation ─────────────────────────────────────────────────
  Future<void> deleteConversation(String conversationId) async {
    await initialize();
    _conversations.removeWhere((c) => c.id == conversationId);
    await _saveConversations();
    await BrowserStorage.remove('$_messagesKeyPrefix$conversationId');
    _notify();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  void _updateConversationLastMessage(
      String convId, String message, String senderName) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx != -1) {
      _conversations[idx] = _conversations[idx].copyWith(
        lastMessage: message,
        lastSenderName: senderName,
        lastMessageTime: DateTime.now(),
      );
      _saveConversations();
      _notify();
    }
  }

  String _generateAutoReply(String recipientName) {
    final replies = [
      'Hey! Great to hear from you. How are things going?',
      'Oh nice! Thanks for reaching out. What\'s on your mind?',
      'Hi there! I was just thinking about you. How\'s the little one?',
      'Hey! Good to hear from you. We should catch up soon!',
      'That\'s lovely! I\'m doing well, thanks for asking.',
      'Thanks for the message! Let me know if you need anything.',
      'Absolutely! We should definitely chat more about this.',
      'That sounds great! When works best for you?',
      'Of course! I\'d love to help out with that.',
      'Ha, I know right! The joys of parenting.',
    ];
    final hash = recipientName.hashCode;
    final baseIdx = hash.abs() % replies.length;
    final timeIdx = DateTime.now().second % replies.length;
    return replies[(baseIdx + timeIdx) % replies.length];
  }

  String _colorForName(String name) {
    final colours = [
      '#FF975C',
      '#3580F0',
      '#199A85',
      '#A16AE9',
      '#5B9DFF',
      '#E8A838',
      '#FF7575',
      '#34C759',
    ];
    return colours[name.hashCode.abs() % colours.length];
  }

  void _log(String message) {
    if (kDebugMode) {
      if (kDebugMode) {
        debugPrint('DMService: $message');
      }
    }
  }

  /// Send a meetup invite DM as a clickable meetup card to a specific member.
  /// Creates or finds the conversation and inserts a rich meetup invite card message.
  Future<void> sendMeetupInvite({
    required String recipientId,
    required String recipientName,
    required String meetupId,
    required String meetupTitle,
    required Map<String, dynamic> meetupData,
  }) async {
    await initialize();

    final conv = await getOrCreateConversation(
      recipientId: recipientId,
      recipientName: recipientName,
    );

    final msg = DirectMessage(
      id: 'dm_msg_meetup_${DateTime.now().millisecondsSinceEpoch}_$recipientId',
      senderId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
      senderName: 'You',
      message: meetupTitle,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.sent,
      type: MessageType.meetupInvite,
      meetupData: meetupData,
    );

    final messages = await getMessages(conv.id);
    messages.add(msg);
    await _saveMessages(conv.id, messages);

    _updateConversationLastMessage(conv.id, '\u{1F4C5} Meetup: $meetupTitle', 'You');
  }

  /// Clear all DM data — used for GDPR account deletion.
  Future<void> clearAll() async {
    // Remove each conversation's messages
    for (final conv in _conversations) {
      await BrowserStorage.remove('$_messagesKeyPrefix${conv.id}');
    }
    _conversations.clear();
    await BrowserStorage.remove(_conversationsKey);
    _notify();
  }

  void dispose() {
    for (final t in _typingTimers.values) {
      t?.cancel();
    }
    for (final t in _replyTimers.values) {
      t?.cancel();
    }
    _typingTimers.clear();
    _replyTimers.clear();
  }
}
