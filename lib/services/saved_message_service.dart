import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../models/saved_message.dart';
import 'browser_storage.dart';
import 'clearable_user_state.dart';

const String _savedMessagesKey = 'saved_messages_v2'; // v2 — per-item unique IDs
const String _savedThreadsKey  = 'saved_threads_v2';  // v2 — no merge logic
const String _savedEventsKey   = 'saved_events_v1';

/// Service to manage saved/bookmarked messages from groups and DMs.
///
/// ## Data model design
/// Every save operation creates a **brand-new document with a unique auto-generated
/// [id]**.  The [topicName] field on both [SavedMessage] and [SavedThread] is a
/// *display label only* — it controls how items are grouped in the UI but it is
/// never used as a lookup key or primary key.  Two saves with the same topicName
/// produce two independent records.  Deleting one never affects the other.
///
/// ## Firestore equivalent schema
/// ```
/// users/{uid}/saved_messages/{auto-id}   ← SavedMessage
///   id, messageId, message, senderName, timestamp, savedAt,
///   topicName, isFromGroup, groupId, groupName, groupImageUrl,
///   dmRecipientId, dmRecipientName, dmRecipientAvatarColor, dmConversationId
///
/// users/{uid}/saved_threads/{auto-id}    ← SavedThread
///   id, topicName, savedAt,
///   rootMessageId, rootMessageText, rootSenderName, rootTimestamp,
///   replies[], groupId, groupName, groupImageUrl
///
/// users/{uid}/saved_events/{auto-id}     ← SavedEvent
///   id, eventId, title, date, time, location, organiser, imageUrl,
///   isFree, price, category, isOnline, savedAt
/// ```
/// The [id] field on every document is the Firestore auto-ID (locally we
/// generate a timestamp-based surrogate that is equally unique per device).
class SavedMessageService extends ChangeNotifier implements ClearableUserState {
  // Singleton
  static final SavedMessageService _instance = SavedMessageService._internal();
  factory SavedMessageService() => _instance;
  SavedMessageService._internal() {
    UserStateRegistry.register(this);
  }

  List<SavedMessage> _savedMessages = [];
  List<SavedThread>  _savedThreads  = [];
  List<SavedEvent>   _savedEvents   = [];
  bool _initialized = false;

  List<SavedMessage> get savedMessages => List.unmodifiable(_savedMessages);
  List<SavedThread>  get savedThreads  => List.unmodifiable(_savedThreads);
  List<SavedEvent>   get savedEvents   => List.unmodifiable(_savedEvents);

  /// All saved messages — used by GDPR data export.
  List<SavedMessage> get allSavedMessages => _savedMessages;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    await _load();
    _initialized = true;
  }

  Future<void> _load() async {
    // ── SavedMessages ────────────────────────────────────────────────────────
    try {
      // Try v2 key first; fall back to v1 to migrate existing data transparently.
      String? raw = await BrowserStorage.getString(_savedMessagesKey);
      raw ??= await BrowserStorage.getString('saved_messages_v1');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        _savedMessages = decoded
            .map((j) => SavedMessage.fromJson(j as Map<String, dynamic>))
            .toList();
        _savedMessages.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      }
    } catch (_) {
      _savedMessages = [];
    }

    // ── SavedThreads ─────────────────────────────────────────────────────────
    // v2: each thread is its own record — no consolidation / merge needed.
    // If only v1 data exists we load it as-is (existing threads are still valid
    // SavedThread objects; they just won't be further merged).
    try {
      String? raw = await BrowserStorage.getString(_savedThreadsKey);
      raw ??= await BrowserStorage.getString('saved_threads_v1');
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

    // ── SavedEvents ──────────────────────────────────────────────────────────
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

    // ── Firestore merge (cross-device restore on reinstall) ──────────────────
    // Runs after local load so local-only items aren't overwritten.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved_messages')
            .orderBy('savedAt', descending: true)
            .limit(200)
            .get();
        for (final doc in snap.docs) {
          final msg = SavedMessage.fromJson(doc.data());
          if (!_savedMessages.any((m) => m.id == msg.id)) {
            _savedMessages.add(msg);
          }
        }
        _savedMessages.sort((a, b) => b.savedAt.compareTo(a.savedAt));
        await _persistMessages();
      } catch (e) {
        if (kDebugMode) debugPrint('[SavedMsg] Firestore load error: $e');
      }
    }
  }

  // ── Persistence helpers ───────────────────────────────────────────────────

  Future<void> _persistMessages() async {
    try {
      await BrowserStorage.setString(
        _savedMessagesKey,
        json.encode(_savedMessages.map((m) => m.toJson()).toList()),
      );
    } catch (e, st) {
      // SAVE-PERSIST-1: failed write = bookmark vanishes on reload.
      // Swallow preserved (Firestore sync is backup path); just make it visible.
      if (kDebugMode) debugPrint('[SavedMsg] _persistMessages failed: $e');
      FirebaseCrashlytics.instance.recordError(
        e, st,
        reason: 'SavedMessageService._persistMessages',
        fatal: false,
      );
    }
  }

  Future<void> _persistThreads() async {
    try {
      await BrowserStorage.setString(
        _savedThreadsKey,
        json.encode(_savedThreads.map((t) => t.toJson()).toList()),
      );
    } catch (e, st) {
      // SAVE-PERSIST-1: failed write = saved thread vanishes on reload.
      if (kDebugMode) debugPrint('[SavedMsg] _persistThreads failed: $e');
      FirebaseCrashlytics.instance.recordError(
        e, st,
        reason: 'SavedMessageService._persistThreads',
        fatal: false,
      );
    }
  }

  Future<void> _persistEvents() async {
    try {
      await BrowserStorage.setString(
        _savedEventsKey,
        json.encode(_savedEvents.map((e) => e.toJson()).toList()),
      );
    } catch (e, st) {
      // SAVE-PERSIST-1: failed write = saved event vanishes on reload.
      if (kDebugMode) debugPrint('[SavedMsg] _persistEvents failed: $e');
      FirebaseCrashlytics.instance.recordError(
        e, st,
        reason: 'SavedMessageService._persistEvents',
        fatal: false,
      );
    }
  }

  // ── Firestore sync helpers ─────────────────────────────────────────────────

  /// Fire-and-forget write to Firestore. Errors are logged but never rethrown.
  void _syncToFirestore(SavedMessage msg) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('saved_messages')
        .doc(msg.id)
        .set(msg.toJson())
        .catchError((Object e) {
      if (kDebugMode) debugPrint('[SavedMsg] Firestore sync error: $e');
    });
  }

  /// Fire-and-forget delete from Firestore.
  void _deleteFromFirestore(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('saved_messages')
        .doc(id)
        .delete()
        .catchError((Object e) {
      if (kDebugMode) debugPrint('[SavedMsg] Firestore delete error: $e');
    });
  }

  // ── Clear all (GDPR) ──────────────────────────────────────────────────────

  Future<void> clearAll() async {
    _savedMessages.clear();
    _savedThreads.clear();
    _savedEvents.clear();
    await _persistMessages();
    await _persistThreads();
    await _persistEvents();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SAVED MESSAGES — individual messages (group or DM)
  // ──────────────────────────────────────────────────────────────────────────

  /// Save a message from a group chat under an optional [topicName] label.
  ///
  /// Each call always creates a new record — [topicName] is a grouping label,
  /// not a primary key.  The same [messageId] may be saved multiple times under
  /// different topic names (intentional: user may want to categorise the same
  /// message in two topics).
  Future<void> saveGroupMessage({
    required String messageId,
    required String message,
    required String senderName,
    required DateTime timestamp,
    required String groupId,
    required String groupName,
    required String groupImageUrl,
    String topicName = '',
  }) async {
    final saved = SavedMessage(
      id: 'smsg_${DateTime.now().microsecondsSinceEpoch}',
      messageId: messageId,
      message: message,
      senderName: senderName,
      timestamp: timestamp,
      savedAt: DateTime.now(),
      isFromGroup: true,
      topicName: topicName,
      groupId: groupId,
      groupName: groupName,
      groupImageUrl: groupImageUrl,
    );
    _savedMessages.insert(0, saved);
    await _persistMessages();
    _syncToFirestore(saved);
    notifyListeners();
  }

  /// Save a message from a DM conversation under an optional [topicName] label.
  Future<void> saveDMMessage({
    required String messageId,
    required String message,
    required String senderName,
    required DateTime timestamp,
    required String recipientId,
    required String recipientName,
    required String recipientAvatarColor,
    String? conversationId,
    String topicName = '',
  }) async {
    final saved = SavedMessage(
      id: 'smsg_${DateTime.now().microsecondsSinceEpoch}',
      messageId: messageId,
      message: message,
      senderName: senderName,
      timestamp: timestamp,
      savedAt: DateTime.now(),
      isFromGroup: false,
      topicName: topicName,
      dmRecipientId: recipientId,
      dmRecipientName: recipientName,
      dmRecipientAvatarColor: recipientAvatarColor,
      dmConversationId: conversationId,
    );
    _savedMessages.insert(0, saved);
    await _persistMessages();
    _syncToFirestore(saved);
    notifyListeners();
  }

  /// Remove a saved message by its unique [savedMessageId].
  /// Only removes that single record — other saves under the same topic are untouched.
  Future<void> unsaveMessage(String savedMessageId) async {
    _savedMessages.removeWhere((m) => m.id == savedMessageId);
    await _persistMessages();
    _deleteFromFirestore(savedMessageId);
    notifyListeners();
  }

  /// Check if a message (by original messageId) has been saved at all.
  bool isMessageSaved(String messageId) =>
      _savedMessages.any((m) => m.messageId == messageId);

  /// Get all saves for a specific group.
  List<SavedMessage> getSavedForGroup(String groupId) =>
      _savedMessages.where((m) => m.groupId == groupId).toList();

  /// Get all saves for a specific DM.
  List<SavedMessage> getSavedForDM(String recipientId) =>
      _savedMessages.where((m) => m.dmRecipientId == recipientId).toList();

  // ──────────────────────────────────────────────────────────────────────────
  // SAVED THREADS — reply threads
  // ──────────────────────────────────────────────────────────────────────────

  /// Save an entire reply thread under a [topicName] label.
  ///
  /// **Always creates a new record** — identical [topicName] values do NOT cause
  /// merging.  Each save produces its own unique document ID.
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
      id: 'sthrd_${DateTime.now().microsecondsSinceEpoch}',
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
    await _persistThreads();
    notifyListeners();
  }

  /// All unique topic names across saved threads (for autocomplete in the save dialog).
  List<String> get savedTopicNames =>
      _savedThreads.map((t) => t.topicName).where((n) => n.isNotEmpty).toSet().toList()..sort();

  /// Remove a single saved thread by its unique [threadId].
  /// Does NOT affect other threads that happen to share the same topic name.
  Future<void> unsaveThread(String threadId) async {
    _savedThreads.removeWhere((t) => t.id == threadId);
    await _persistThreads();
    notifyListeners();
  }

  /// Get all saved threads for a specific group.
  List<SavedThread> getSavedThreadsForGroup(String groupId) =>
      _savedThreads.where((t) => t.groupId == groupId).toList();

  // ──────────────────────────────────────────────────────────────────────────
  // SAVED EVENTS — bookmarked events
  // ──────────────────────────────────────────────────────────────────────────

  bool isEventSaved(String eventId) =>
      _savedEvents.any((e) => e.eventId == eventId);

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
    if (isEventSaved(eventId)) return;
    final saved = SavedEvent(
      id: 'sevt_${DateTime.now().microsecondsSinceEpoch}',
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
    await _persistEvents();
    notifyListeners();
  }

  Future<void> unsaveEvent(String eventId) async {
    _savedEvents.removeWhere((e) => e.eventId == eventId);
    await _persistEvents();
    notifyListeners();
  }

  /// [ClearableUserState] — wipes all saved-item state on sign-out.
  @override
  Future<void> clearUserState() async {
    _savedMessages.clear();
    _savedThreads.clear();
    _savedEvents.clear();
    await BrowserStorage.remove(_savedMessagesKey);
    await BrowserStorage.remove(_savedThreadsKey);
    await BrowserStorage.remove(_savedEventsKey);
    notifyListeners();
  }
}
