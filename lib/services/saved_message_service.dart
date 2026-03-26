import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/saved_message.dart';
import 'browser_storage.dart';

const String _savedMessagesKey = 'saved_messages_v1';

/// Service to manage saved/bookmarked messages from groups and DMs.
class SavedMessageService extends ChangeNotifier {
  // Singleton pattern
  static final SavedMessageService _instance = SavedMessageService._internal();
  factory SavedMessageService() => _instance;
  SavedMessageService._internal();

  List<SavedMessage> _savedMessages = [];
  bool _initialized = false;

  List<SavedMessage> get savedMessages => List.unmodifiable(_savedMessages);

  Future<void> initialize() async {
    if (_initialized) return;
    await _load();
    _initialized = true;
  }

  Future<void> _load() async {
    try {
      final raw = await BrowserStorage.getString(_savedMessagesKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _savedMessages = decoded
            .map((j) => SavedMessage.fromJson(j as Map<String, dynamic>))
            .toList();
        // Sort by savedAt descending (newest first)
        _savedMessages.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      }
    } catch (_) {
      _savedMessages = [];
    }
  }

  Future<void> _save() async {
    try {
      final encoded = json.encode(_savedMessages.map((m) => m.toJson()).toList());
      await BrowserStorage.setString(_savedMessagesKey, encoded);
    } catch (_) {
      // silently fail
    }
  }

  /// Save a message from a group chat.
  Future<void> saveGroupMessage({
    required String messageId,
    required String message,
    required String senderName,
    required DateTime timestamp,
    required String groupId,
    required String groupName,
    required String groupImageUrl,
  }) async {
    // Check if already saved
    if (_savedMessages.any((m) => m.messageId == messageId && m.groupId == groupId)) {
      return;
    }

    final saved = SavedMessage(
      id: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      messageId: messageId,
      message: message,
      senderName: senderName,
      timestamp: timestamp,
      savedAt: DateTime.now(),
      isFromGroup: true,
      groupId: groupId,
      groupName: groupName,
      groupImageUrl: groupImageUrl,
    );

    _savedMessages.insert(0, saved);
    await _save();
    notifyListeners();
  }

  /// Save a message from a DM conversation.
  Future<void> saveDMMessage({
    required String messageId,
    required String message,
    required String senderName,
    required DateTime timestamp,
    required String recipientId,
    required String recipientName,
    required String recipientAvatarColor,
    String? conversationId,
  }) async {
    // Check if already saved
    if (_savedMessages.any((m) => m.messageId == messageId && m.dmRecipientId == recipientId)) {
      return;
    }

    final saved = SavedMessage(
      id: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      messageId: messageId,
      message: message,
      senderName: senderName,
      timestamp: timestamp,
      savedAt: DateTime.now(),
      isFromGroup: false,
      dmRecipientId: recipientId,
      dmRecipientName: recipientName,
      dmRecipientAvatarColor: recipientAvatarColor,
      dmConversationId: conversationId,
    );

    _savedMessages.insert(0, saved);
    await _save();
    notifyListeners();
  }

  /// Remove a saved message.
  Future<void> unsaveMessage(String savedMessageId) async {
    _savedMessages.removeWhere((m) => m.id == savedMessageId);
    await _save();
    notifyListeners();
  }

  /// Check if a message is saved.
  bool isMessageSaved(String messageId) {
    return _savedMessages.any((m) => m.messageId == messageId);
  }

  /// Get saved messages for a specific group.
  List<SavedMessage> getSavedForGroup(String groupId) {
    return _savedMessages.where((m) => m.groupId == groupId).toList();
  }

  /// Get saved messages for a specific DM.
  List<SavedMessage> getSavedForDM(String recipientId) {
    return _savedMessages.where((m) => m.dmRecipientId == recipientId).toList();
  }
}
