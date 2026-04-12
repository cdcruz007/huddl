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
        final loaded = decoded
            .map((j) => SavedThread.fromJson(j as Map<String, dynamic>))
            .toList();
        // ── Consolidate duplicates that were stored before the merge fix ──
        // Group by normalised topic name, then merge all entries under each name
        // into one thread (oldest root + combined replies, deduped by messageId).
        _savedThreads = _consolidateThreads(loaded);
        _savedThreads.sort((a, b) => b.savedAt.compareTo(a.savedAt));
        // If we collapsed any duplicates, immediately persist the cleaner list.
        if (_savedThreads.length < loaded.length) {
          await _saveThreads();
        }
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

  /// Consolidate a raw list of [SavedThread]s so that every unique topic name
  /// (case-insensitive) is represented by exactly ONE thread.  All messages from
  /// duplicate entries are merged into the earliest entry's replies list and
  /// deduped by messageId.  This migration runs once on load and permanently
  /// fixes data stored before the merge-on-save logic was introduced.
  List<SavedThread> _consolidateThreads(List<SavedThread> raw) {
    // Keep insertion order: process oldest-first so the root stays the first
    // message of each topic.
    final chronological = List<SavedThread>.from(raw)
      ..sort((a, b) => a.savedAt.compareTo(b.savedAt));

    // Map from normalised topic name → merged thread.
    final Map<String, SavedThread> byTopic = {};

    for (final thread in chronological) {
      final key = thread.topicName.trim().toLowerCase();
      if (!byTopic.containsKey(key)) {
        // First time we see this topic — use it as the canonical base.
        byTopic[key] = thread;
      } else {
        // Merge: append the incoming thread's root + replies to the existing
        // thread, skipping any messageIds already present.
        final existing = byTopic[key]!;
        final seenIds = <String>{
          existing.rootMessageId,
          ...existing.replies.map((r) => r.messageId),
        };

        // Treat the incoming root as the first message of the new batch.
        final incomingBatch = <SavedThreadMessage>[
          SavedThreadMessage(
            messageId: thread.rootMessageId,
            message: thread.rootMessageText,
            senderName: thread.rootSenderName,
            timestamp: thread.rootTimestamp,
          ),
          ...thread.replies,
        ];

        final newReplies = <SavedThreadMessage>[
          ...existing.replies,
          ...incomingBatch.where((m) => !seenIds.contains(m.messageId)),
        ];

        byTopic[key] = existing.copyWithReplies(newReplies);
      }
    }

    return byTopic.values.toList();
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
  ///
  /// **Merge behaviour**: if a thread with the same [topicName] already exists
  /// (case-insensitive match), the new root message + replies are appended to
  /// that existing thread instead of creating a duplicate entry.  The merged
  /// thread is moved to the top of the list and [savedAt] is updated.
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
    final normName = topicName.trim().toLowerCase();

    // ── Check for an existing thread with the same topic name ──────────────
    final existingIdx = _savedThreads.indexWhere(
      (t) => t.topicName.trim().toLowerCase() == normName,
    );

    if (existingIdx >= 0) {
      // Merge: build the new "root" message as the first SavedThreadMessage of
      // this batch, append all replies after it, then combine with existing.
      final newBatch = <SavedThreadMessage>[
        SavedThreadMessage(
          messageId: rootMessageId,
          message: rootMessageText,
          senderName: rootSenderName,
          timestamp: rootTimestamp,
          isMe: false, // root author; caller can override if needed
        ),
        ...replies,
      ];

      // Deduplicate by messageId so repeated saves of the same message don't
      // add it twice.
      final existingThread = _savedThreads[existingIdx];
      final existingIds =
          {existingThread.rootMessageId, ...existingThread.replies.map((r) => r.messageId)};
      final dedupedBatch =
          newBatch.where((m) => !existingIds.contains(m.messageId)).toList();

      final mergedReplies = [...existingThread.replies, ...dedupedBatch];
      final updated = existingThread.copyWithReplies(mergedReplies);

      // Remove old entry and re-insert at top so it surfaces first.
      _savedThreads.removeAt(existingIdx);
      _savedThreads.insert(0, updated);
    } else {
      // Brand-new topic — create a fresh entry.
      final thread = SavedThread(
        id: 'thread_${DateTime.now().millisecondsSinceEpoch}',
        topicName: topicName.trim(),
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
    }

    await _saveThreads();
    notifyListeners();
  }

  /// All unique topic names across all saved threads (for autocomplete).
  List<String> get savedTopicNames =>
      _savedThreads.map((t) => t.topicName).toSet().toList()..sort();

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
