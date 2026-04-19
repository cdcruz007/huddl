// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL CONNECT — HUDDL USER SERVICE
// ═══════════════════════════════════════════════════════════════════════════════
//
// This service is the single source of truth for:
//   1. Writing the current user's profile (including borough) to Firestore
//      whenever it changes (login, postcode update, profile edit).
//   2. Reading other users in the same borough from Firestore for the
//      member picker (New DM screen, matchmaker, etc.).
//   3. Providing a real-time stream of borough members.
//
// Collection: users/{uid}
//   Fields written:
//     uid, name, firstName, lastName, phone, parentType, stagesOfLife,
//     postcode, borough, children, bio, photoUrl, tier, createdAt,
//     lastActiveAt, isOnline, fcmToken
//
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

class HuddlUserService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final HuddlUserService _instance = HuddlUserService._internal();
  factory HuddlUserService() => _instance;
  HuddlUserService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcodeService = PostcodeService();

  String? get _uid => _auth.currentUser?.uid;

  // ── Sync current user profile to Firestore ────────────────────────────────

  /// Call this after successful login/OTP verification or after onboarding
  /// completes. Writes all profile fields including the resolved borough.
  Future<void> syncCurrentUserProfile() async {
    final uid = _uid;
    if (uid == null) {
      _log('syncCurrentUserProfile: no authenticated user');
      return;
    }

    await _onboarding.initialize();

    final postcode = _onboarding.postcode ?? '';
    // Use the async lookup so the borough is resolved via postcodes.io
    // rather than the outward-code fallback map.
    final borough = await _postcodeService.lookupBoroughAsync(postcode) ?? '';

    final name = _onboarding.name ?? '';
    final parts = name.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final Map<String, dynamic> profile = {
      'uid': uid,
      'name': name,
      'firstName': firstName,
      'lastName': lastName,
      'phone': _onboarding.fullPhoneNumber ?? _auth.currentUser?.phoneNumber ?? '',
      'countryCode': _onboarding.countryCode ?? '+44',
      'parentType': _onboarding.parentType ?? '',
      'stagesOfLife': _onboarding.stagesOfLife,
      'postcode': postcode,
      'borough': borough,
      'children': _onboarding.children,
      'bio': _onboarding.bio ?? '',
      'photoUrl': _onboarding.profilePhotoPath ?? '',
      'tier': 'explorer',
      'isPhoneVerified': true,
      'isOnline': true,
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      // Use set with merge so we don't overwrite fields set elsewhere
      // (e.g. createdAt set on first login, fcmToken set by messaging).
      await _db.collection('users').doc(uid).set(profile, SetOptions(merge: true));
      _log('Profile synced for uid=$uid borough=$borough');
    } catch (e) {
      _log('ERROR syncing profile: $e');
    }
  }

  /// Mark the user offline (call in app lifecycle pause/detach).
  Future<void> setOffline() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({
        'isOnline': false,
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Mark the user online (call in app lifecycle resume).
  Future<void> setOnline() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({
        'isOnline': true,
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ── Get current user's borough from Firestore ──────────────────────────────

  Future<String?> getCurrentUserBorough() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['borough'] as String?;
    } catch (e) {
      _log('ERROR getting borough: $e');
      return null;
    }
  }

  // ── Query borough members (for New DM screen / member picker) ─────────────

  /// Returns all users in [borough] EXCEPT the current user.
  /// Used by NewDMScreen and the matchmaker.
  Future<List<HuddlUser>> getBoroughMembers(String borough) async {
    final uid = _uid;
    if (borough.isEmpty) return [];

    try {
      final snap = await _db
          .collection('users')
          .where('borough', isEqualTo: borough)
          .get();

      final members = snap.docs
          .map((doc) => HuddlUser.fromFirestore(doc.data(), doc.id))
          .where((u) => u.uid != uid) // exclude self
          .toList();

      // Sort: online first, then by name
      members.sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.compareTo(b.name);
      });

      _log('getBoroughMembers($borough): found ${members.length} member(s)');
      return members;
    } catch (e) {
      _log('ERROR getBoroughMembers: $e');
      return [];
    }
  }

  /// Real-time stream of borough members.
  Stream<List<HuddlUser>> boroughMembersStream(String borough) {
    final uid = _uid;
    if (borough.isEmpty) return Stream.value([]);

    return _db
        .collection('users')
        .where('borough', isEqualTo: borough)
        .snapshots()
        .map((snap) {
      final members = snap.docs
          .map((doc) => HuddlUser.fromFirestore(doc.data(), doc.id))
          .where((u) => u.uid != uid)
          .toList();
      members.sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return members;
    });
  }

  // ── Get a single user profile ─────────────────────────────────────────────

  Future<HuddlUser?> getUser(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (!doc.exists) return null;
      return HuddlUser.fromFirestore(doc.data()!, doc.id);
    } catch (e) {
      _log('ERROR getUser($userId): $e');
      return null;
    }
  }

  // ── Update FCM token (called by notification service) ─────────────────────

  Future<void> updateFcmToken(String token) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({'fcmToken': token});
    } catch (_) {}
  }

  // ── Logging ───────────────────────────────────────────────────────────────

  void _log(String msg) {
    if (kDebugMode) debugPrint('[HuddlUserService] $msg');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HUDDL USER MODEL
// ═════════════════════════════════════════════════════════════════════════════

class HuddlUser {
  final String uid;
  final String name;
  final String firstName;
  final String lastName;
  final String phone;
  final String parentType;
  final List<String> stagesOfLife;
  final String postcode;
  final String borough;
  final String photoUrl;
  final String bio;
  final bool isOnline;
  final DateTime? lastActiveAt;

  const HuddlUser({
    required this.uid,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.parentType,
    required this.stagesOfLife,
    required this.postcode,
    required this.borough,
    required this.photoUrl,
    required this.bio,
    required this.isOnline,
    this.lastActiveAt,
  });

  factory HuddlUser.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime? lastActive;
    final lat = data['lastActiveAt'];
    if (lat is Timestamp) {
      lastActive = lat.toDate();
    }

    return HuddlUser(
      uid: id,
      name: data['name'] as String? ?? '',
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      parentType: data['parentType'] as String? ?? '',
      stagesOfLife: List<String>.from(data['stagesOfLife'] ?? []),
      postcode: data['postcode'] as String? ?? '',
      borough: data['borough'] as String? ?? '',
      photoUrl: data['photoUrl'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      isOnline: data['isOnline'] as bool? ?? false,
      lastActiveAt: lastActive,
    );
  }

  /// Stable avatar colour derived from UID hash
  String get avatarColor {
    const colors = [
      '#FF975C', '#3580F0', '#199A85', '#A16AE9',
      '#5B9DFF', '#E8A838', '#FF7575', '#34C759',
    ];
    return colors[uid.hashCode.abs() % colors.length];
  }
}
