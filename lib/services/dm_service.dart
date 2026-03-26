import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import '../models/direct_message.dart';

/// Singleton service that manages DM conversations and messages.
///
/// In production these would live in Firestore with real-time listeners.
/// Here we use BrowserStorage + simulated replies so the demo is end-to-end.
class DMService {
  static final DMService _instance = DMService._internal();
  factory DMService() => _instance;
  DMService._internal();

  static const String _conversationsKey = 'dm_conversations_v1';
  static const String _messagesKeyPrefix = 'dm_messages_'; // + conversationId
  bool _isInitialized = false;

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
        return decoded
            .map((j) => DirectMessage.fromJson(j as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
    } catch (e) {
      _log('Error loading messages for $conversationId: $e');
    }
    return [];
  }

  // ── Get or create a conversation ────────────────────────────────────────
  Future<DMConversation> getOrCreateConversation({
    required String recipientId,
    required String recipientName,
    String? avatarColor,
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

    // Assign a consistent color based on name hash
    final color = avatarColor ?? _colorForName(recipientName);
    final conv = DMConversation(
      id: 'dm_$recipientId',
      recipientId: recipientId,
      recipientName: recipientName,
      recipientAvatarColor: color,
    );
    _conversations.add(conv);
    await _saveConversations();
    _notify();
    return conv;
  }

  // ── Send a message ──────────────────────────────────────────────────────
  Future<DirectMessage> sendMessage({
    required String conversationId,
    required String message,
    required String senderName,
  }) async {
    await initialize();

    // 1. Create the message with 'sending' status
    final msg = DirectMessage(
      id: 'dm_msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'current_user',
      senderName: senderName,
      message: message,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.sending,
    );

    // Save message
    final messages = await getMessages(conversationId);
    messages.add(msg);
    await _saveMessages(conversationId, messages);

    // Update conversation
    _updateConversationLastMessage(conversationId, message, senderName);

    // 2. Simulate sent status after brief delay
    _simulateMessageStatusProgression(conversationId, msg.id);

    // 3. Simulate typing + reply from recipient
    _simulateRecipientReply(conversationId);

    return msg;
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
      debugPrint('DMService: $message');
    }
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
