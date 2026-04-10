import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/saved_message.dart';
import 'browser_storage.dart';

const String _savedMessagesKey = 'saved_messages_v1';
const String _savedThreadsKey = 'saved_threads_v1';
const String _savedEventsKey = 'saved_events_v1';

/// Service to manage saved/bookmarked messages from groups and DMs.
class SavedMessageService extends ChangeNotifier {
  // Singleton pattern
  static final SavedMessageService _instance = SavedMessageService._internal();
  factory SavedMessageService() => _instance;
  SavedMessageService._internal();

  List<SavedMessage> _savedMessages = [];
  List<SavedThread> _savedThreads = [];
  List<SavedEvent> _savedEvents = [];
  bool _initialized = false;

  List<SavedMessage> get savedMessages => List.unmodifiable(_savedMessages);
  List<SavedThread> get savedThreads => List.unmodifiable(_savedThreads);
  List<SavedEvent> get savedEvents => List.unmodifiable(_savedEvents);

  /// All saved messages (messages + threads combined count).
  /// Used by GDPR data compilation.
  List<SavedMessage> get allSavedMessages => _savedMessages;

  /// Clear all saved data — used for GDPR account deletion.
  Future<void> clearAll() async {
    _savedMessages.clear();
    _savedThreads.clear();
    _savedEvents.clear();
    await _save();
    await _saveThreads();
    await _saveEvents();
    notifyListeners();
  }

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
    // Load saved threads
    try {
      final raw = await BrowserStorage.getString(_savedThreadsKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _savedThreads = decoded
            .map((j) => SavedThread.fromJson(j as Map<String, dynamic>))
            .toList();
        _savedThreads.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      }
    } catch (_) {
      _savedThreads = [];
    }
    // Load saved events
    try {
      final raw = await BrowserStorage.getString(_savedEventsKey);
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _savedEvents = decoded
            .map((j) => SavedEvent.fromJson(j as Map<String, dynamic>))
            .toList();
        _savedEvents.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      }
    } catch (_) {
      _savedEvents = [];
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

  Future<void> _saveThreads() async {
    try {
      final encoded = json.encode(_savedThreads.map((t) => t.toJson()).toList());
      await BrowserStorage.setString(_savedThreadsKey, encoded);
    } catch (_) {
      // silently fail
    }
  }

  Future<void> _saveEvents() async {
    try {
      final encoded = json.encode(_savedEvents.map((e) => e.toJson()).toList());
      await BrowserStorage.setString(_savedEventsKey, encoded);
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

  // ── Thread Saving ──────────────────────────────────────────────────────

  /// Save an entire reply thread under a topic name.
  Future<void> saveThread({
    required String topicName,
    required String rootMessageId,
    required String rootMessageText,
    required String rootSenderName,
    required DateTime rootTimestamp,
    required List<SavedThreadMessage> replies,
    required String groupId,
    required String groupName,
    required String groupImageUrl,
  }) async {
    final thread = SavedThread(
      id: 'thread_${DateTime.now().millisecondsSinceEpoch}',
      topicName: topicName,
      savedAt: DateTime.now(),
      rootMessageId: rootMessageId,
      rootMessageText: rootMessageText,
      rootSenderName: rootSenderName,
      rootTimestamp: rootTimestamp,
      replies: replies,
      groupId: groupId,
      groupName: groupName,
      groupImageUrl: groupImageUrl,
    );

    _savedThreads.insert(0, thread);
    await _saveThreads();
    notifyListeners();
  }

  /// Remove a saved thread.
  Future<void> unsaveThread(String threadId) async {
    _savedThreads.removeWhere((t) => t.id == threadId);
    await _saveThreads();
    notifyListeners();
  }

  /// Get all saved threads for a specific group.
  List<SavedThread> getSavedThreadsForGroup(String groupId) {
    return _savedThreads.where((t) => t.groupId == groupId).toList();
  }

  // ── Event Bookmarking ────────────────────────────────────────────────────

  /// Whether the user has bookmarked a given event.
  bool isEventSaved(String eventId) =>
      _savedEvents.any((e) => e.eventId == eventId);

  /// Bookmark an event — saves all display data so it can be rendered
  /// in the Saved tab without needing the full event list.
  Future<void> saveEvent({
    required String eventId,
    required String title,
    required String date,
    required String time,
    required String location,
    required String organiser,
    required String imageUrl,
    required bool isFree,
    required String price,
    required String category,
    required bool isOnline,
  }) async {
    // Don't save duplicates
    if (isEventSaved(eventId)) return;

    final saved = SavedEvent(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      eventId: eventId,
      title: title,
      date: date,
      time: time,
      location: location,
      organiser: organiser,
      imageUrl: imageUrl,
      isFree: isFree,
      price: price,
      category: category,
      isOnline: isOnline,
      savedAt: DateTime.now(),
    );

    _savedEvents.insert(0, saved);
    await _saveEvents();
    notifyListeners();
  }

  /// Remove a bookmarked event by its original event id.
  Future<void> unsaveEvent(String eventId) async {
    _savedEvents.removeWhere((e) => e.eventId == eventId);
    await _saveEvents();
    notifyListeners();
  }
}
