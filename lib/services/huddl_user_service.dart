// ═══════════════════════════════════════════════════════════════════════════════
// HUDDL — HUDDL USER SERVICE
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
    // ── Async uid resolution ─────────────────────────────────────────────────
    // On web, FirebaseAuth.instance.currentUser is null immediately after
    // Firebase.initializeApp() even for authenticated users because auth
    // rehydration is async. Waiting for authStateChanges().first bridges this
    // gap. If the stream times out (no network) we fall back to the synchronous
    // currentUser — if that is also null the function exits safely.
    String? uid = _uid;
    if (uid == null) {
      try {
        final user = await _auth
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5));
        uid = user?.uid;
      } catch (_) {
        uid = _uid; // last resort: synchronous check after timeout
      }
    }
    if (uid == null) {
      _log('syncCurrentUserProfile: no authenticated user');
      return;
    }

    await _onboarding.initialize(forceReload: true);

    // ── CRITICAL: Check if local onboarding data is populated ────────────────
    // If local data was cleared (e.g. fresh install, BrowserStorage reset) but
    // the user already has a Firestore profile, we must NOT push empty strings
    // back to Firestore — that would overwrite real data with blanks.
    //
    // Strategy: if the local name is empty, fetch the Firestore profile first
    // and restore local state, THEN push the merged result.
    final localName = _onboarding.name ?? '';
    if (localName.trim().isEmpty) {
      try {
        final doc = await _db
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 5));
        if (doc.exists) {
          final data = doc.data()!;
          // Restore local state from Firestore so subsequent reads are correct
          String firestoreName = (data['name'] as String?) ?? '';
          // ── Self-repair: if Firestore name is blank (previously overwritten
          //    by the BrowserStorage.clear bug), try firstName then phone ──
          if (firestoreName.trim().isEmpty) {
            final fn = (data['firstName'] as String?) ?? '';
            if (fn.trim().isNotEmpty) {
              firestoreName = fn.trim();
            } else {
              final authPhone = _auth.currentUser?.phoneNumber ?? '';
              if (authPhone.isNotEmpty) firestoreName = authPhone;
            }
            // Write the recovered name back to Firestore immediately
            if (firestoreName.trim().isNotEmpty) {
              try {
                final nameParts = firestoreName.trim().split(' ');
                await _db.collection('users').doc(uid).update({
                  'name': firestoreName.trim(),
                  'firstName': nameParts.first,
                  if (nameParts.length > 1) 'lastName': nameParts.sublist(1).join(' '),
                });
              } catch (_) {}
            }
          }
          if (firestoreName.trim().isNotEmpty) {
            _onboarding.setName(firestoreName.trim());
          }
          final firestorePostcode = (data['postcode'] as String?) ?? '';
          if (firestorePostcode.isNotEmpty && (_onboarding.postcode == null || _onboarding.postcode!.isEmpty)) {
            _onboarding.setPostcode(firestorePostcode);
          }
          final firestoreParentType = (data['parentType'] as String?) ?? '';
          if (firestoreParentType.isNotEmpty && _onboarding.parentType == null) {
            _onboarding.setParentType(firestoreParentType);
          }
          final firestoreStages = data['stagesOfLife'];
          if (firestoreStages is List && firestoreStages.isNotEmpty && _onboarding.stagesOfLife.isEmpty) {
            _onboarding.setStagesOfLife(List<String>.from(firestoreStages));
          }
          final firestorePhone = (data['phone'] as String?) ?? '';
          final firestoreCountry = (data['countryCode'] as String?) ?? '+44';
          if (firestorePhone.isNotEmpty && _onboarding.phoneNumber == null) {
            final subscriber = firestorePhone.startsWith(firestoreCountry)
                ? firestorePhone.substring(firestoreCountry.length)
                : firestorePhone;
            _onboarding.setPhoneNumber(subscriber, countryCode: firestoreCountry);
            _onboarding.setPhoneVerified(true);
          }
          // ── Restore children, bio, borough — missing from original restore ──
          final firestoreChildren = data['children'];
          if (firestoreChildren is List && firestoreChildren.isNotEmpty && _onboarding.children.isEmpty) {
            final parsed = firestoreChildren
                .whereType<Map>()
                .map((c) => {
                      'name': (c['name'] as String?) ?? '',
                      'birthday': (c['birthday'] as String?) ?? '',
                    })
                .where((c) => c['name']!.isNotEmpty)
                .toList();
            if (parsed.isNotEmpty) _onboarding.setChildren(parsed);
          }
          final firestoreBio = (data['bio'] as String?) ?? '';
          if (firestoreBio.isNotEmpty && (_onboarding.bio == null || _onboarding.bio!.isEmpty)) {
            _onboarding.setBio(firestoreBio);
          }
          final firestoreBorough = (data['borough'] as String?) ?? '';
          if (firestoreBorough.isNotEmpty && (_onboarding.borough == null || _onboarding.borough!.isEmpty)) {
            _onboarding.setBorough(firestoreBorough);
          }
          _log('syncCurrentUserProfile: restored local state from Firestore for uid=$uid');

          // ── CRITICAL: flush all set*() writes to SharedPreferences NOW ──────
          // set*() methods call _saveToStorage() without await (fire-and-forget).
          // If the profile screen calls initialize(forceReload:true) before those
          // futures settle it re-reads storage and gets the OLD (empty) values.
          // flush() awaits _saveToStorage() so storage is definitely up-to-date
          // before any subsequent reads.
          await _onboarding.flush();

          // Only update presence fields — DO NOT overwrite data-bearing fields
          // because we just restored them correctly from Firestore.
          await _db.collection('users').doc(uid).update({
            'isOnline': true,
            'lastActiveAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _log('syncCurrentUserProfile: presence-only update for uid=$uid (local was empty)');
          return;
        }
      } catch (e) {
        _log('syncCurrentUserProfile: Firestore restore failed: $e — skipping push to avoid overwrite');
        return; // Do not push empty data
      }
    }

    // ── Local data is populated — safe to push ────────────────────────────────
    final postcode = _onboarding.postcode ?? '';
    // Prefer the borough already stored from onboarding (set in postcode_screen
    // via postcodes.io full-postcode lookup); fall back to a fresh API call only
    // if the stored value is missing (e.g. existing accounts pre-dating this field).
    final borough = _onboarding.borough?.isNotEmpty == true
        ? _onboarding.borough!
        : await _postcodeService.lookupBoroughAsync(postcode) ?? '';
    // Persist back if we had to do a fresh lookup
    if (borough.isNotEmpty && (_onboarding.borough == null || _onboarding.borough!.isEmpty)) {
      _onboarding.setBorough(borough);
    }

    final name = _onboarding.name ?? '';
    final parts = name.trim().split(' ');
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    // Build the profile update — only include fields with real values
    // to avoid accidentally overwriting Firestore data with empty strings.
    final Map<String, dynamic> profile = {
      'uid': uid,
      'isPhoneVerified': true,
      'isOnline': true,
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only add fields to the update when they have meaningful values
    if (name.trim().isNotEmpty) {
      profile['name'] = name;
      profile['firstName'] = firstName;
      profile['lastName'] = lastName;
      // A real name being synced means the user has completed onboarding.
      // Clear the isOnboarding flag so cold starts go straight to /home.
      profile['isOnboarding'] = false;
    }
    final phone = _onboarding.fullPhoneNumber ?? _auth.currentUser?.phoneNumber ?? '';
    if (phone.isNotEmpty) {
      profile['phone'] = phone;
      profile['countryCode'] = _onboarding.countryCode ?? '+44';
    }
    if ((_onboarding.parentType ?? '').isNotEmpty) {
      profile['parentType'] = _onboarding.parentType!;
    }
    if (_onboarding.stagesOfLife.isNotEmpty) {
      profile['stagesOfLife'] = _onboarding.stagesOfLife;
    }
    if (postcode.isNotEmpty) {
      profile['postcode'] = postcode;
      // Additive geo fields — captured from the postcodes.io response that
      // already ran for the borough lookup above. No extra network call.
      final geo = _postcodeService.lookupGeoFromCacheSync(postcode);
      if (geo != null) {
        if (geo.ward?.isNotEmpty == true)         profile['ward']         = geo.ward!;
        if (geo.wardCode?.isNotEmpty == true)     profile['wardCode']     = geo.wardCode!;
        if (geo.districtCode?.isNotEmpty == true) profile['districtCode'] = geo.districtCode!;
        if (geo.region?.isNotEmpty == true)       profile['region']       = geo.region!;
      }
    }
    if (borough.isNotEmpty) {
      profile['borough'] = borough;
    }
    if (_onboarding.children.isNotEmpty) {
      profile['children'] = _onboarding.children;
    }
    if ((_onboarding.bio ?? '').isNotEmpty) {
      profile['bio'] = _onboarding.bio!;
    }
    // Only write photoUrl to Firestore when it is a permanent remote URL.
    // Local iOS/Android temp paths (/private/var/mobile/...) and blob: URLs
    // are device-specific and become broken links for every other user.
    // The PhotoUploadService uploads to Firebase Storage and stores the
    // resulting https:// download URL via setProfilePhotoPath().
    final photoPath = _onboarding.profilePhotoPath ?? '';
    if (photoPath.startsWith('https://') || photoPath.startsWith('http://')) {
      profile['photoUrl'] = photoPath;
    }
    // Sync email when present — captured at onboarding step 1 or updated in Profile
    if ((_onboarding.email ?? '').isNotEmpty) {
      profile['email'] = _onboarding.email!;
    }

    try {
      // Use set with merge so we don't overwrite fields set elsewhere
      // (e.g. createdAt set on first login, fcmToken set by messaging).
      await _db.collection('users').doc(uid).set(profile, SetOptions(merge: true));
      _log('Profile synced for uid=$uid name=$name borough=$borough');
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
