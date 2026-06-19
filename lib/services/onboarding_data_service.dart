import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'browser_storage.dart';
import 'secure_pii_storage.dart';

// =============================================================================
// ONBOARD-1 — Sensitive-field split
//
// SENSITIVE fields (written to SecurePiiStorage — Keychain/Keystore on mobile,
// in-memory only on web):
//   name, email, phone_number, country_code, postcode, previous_postcode,
//   children, due_date, bio
//
// NON-SENSITIVE fields (written to BrowserStorage = SharedPreferences as before):
//   borough, previous_borough, stages_of_life, parent_type, is_phone_verified,
//   profile_photo_path, profile_photo_object_url, assigned_group_count,
//   assigned_group_names
//
// Web behaviour: SecurePiiStorage holds PII in memory only — nothing written
// to localStorage.  On cold start the sensitive fields are blank until
// FirebaseAuthService.restoreProfileFromFirestore() re-hydrates from Firestore.
// =============================================================================

class OnboardingDataService {
  static final OnboardingDataService _instance = OnboardingDataService._internal();
  factory OnboardingDataService() => _instance;
  OnboardingDataService._internal();
  
  // BrowserStorage key for NON-SENSITIVE fields only (ONBOARD-1)
  static const String _storageKey = 'onboarding_data_v1';
  // Legacy key written by old code — used during one-shot migration (ONBOARD-1)
  static const String _legacyStorageKey = 'onboarding_data_v1';
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  // User onboarding data
  String? _name;
  String? _email; // Collected at step 1 of onboarding — used for transactional emails
  String? _parentType; // 'mum' or 'dad'
  List<String> _stagesOfLife = [];
  String? _postcode;
  String? _borough;     // Resolved via postcodes.io — the authoritative admin district
  String? _dueDate;
  List<Map<String, String>> _children = []; // List of children with name and birthday
  String? _phoneNumber;
  String? _countryCode;
  String? _password;
  bool _isPhoneVerified = false;
  String? _profilePhotoPath; // local file path or web file name
  String? _bio; // "About you" free-text from onboarding
  String? _profilePhotoObjectUrl; // Web Object URL for display (blob:...)
  String? _previousPostcode; // Previous postcode before a change
  String? _previousBorough; // Previous borough (derived from previous postcode)
  int _assignedGroupCount = 0; // Number of groups assigned during onboarding
  List<String> _assignedGroupNames = []; // Names of groups assigned during onboarding


  // Getters
  String? get name => _name;
  String? get email => _email;
  String? get parentType => _parentType;
  List<String> get stagesOfLife => _stagesOfLife;
  String? get postcode => _postcode;
  /// The borough (admin district) resolved from [postcode] via postcodes.io.
  /// Null until [setBorough] has been called (i.e. until onboarding completes
  /// or the profile is loaded from Firestore).
  String? get borough => _borough;
  String? get dueDate => _dueDate;
  List<Map<String, String>> get children => _children;
  String? get childName => _children.isNotEmpty ? _children.first['name'] : null;
  String? get childBirthday => _children.isNotEmpty ? _children.first['birthday'] : null;
  String? get phoneNumber => _phoneNumber;
  String? get countryCode => _countryCode;
  String? get fullPhoneNumber => _countryCode != null && _phoneNumber != null 
      ? '$_countryCode$_phoneNumber' 
      : null;
  String? get password => _password;
  bool get isPhoneVerified => _isPhoneVerified;
  String? get profilePhotoPath => _profilePhotoPath;
  String? get bio => _bio;
  String? get profilePhotoObjectUrl => _profilePhotoObjectUrl;
  String? get previousPostcode => _previousPostcode;
  String? get previousBorough => _previousBorough;
  int get assignedGroupCount => _assignedGroupCount;
  List<String> get assignedGroupNames => _assignedGroupNames;

  /// Whether the user has changed their postcode (moved to a different borough)
  bool get hasChangedBorough => _previousBorough != null && _previousBorough!.isNotEmpty;


  // Setters
  void setEmail(String email) {
    _email = email.trim().toLowerCase();
    _log('Email set (length: ${_email!.length})');
    _saveToStorage();
  }

  void setName(String name) {
    _name = name;
    _log('Name set: $name');
    _saveToStorage();
  }

  void setParentType(String type) {
    _parentType = type.toLowerCase();
    _log('Parent type set: $_parentType');
    _saveToStorage();
  }

  void setStagesOfLife(List<String> stages) {
    _stagesOfLife = stages;
    _log('Stages of life set: $stages');
    _saveToStorage();
  }

  void setPostcode(String postcode) {
    // If we already have a postcode and it's different, record the old one
    if (_postcode != null && _postcode != postcode && _postcode!.isNotEmpty) {
      _previousPostcode = _postcode;
      _log('Previous postcode saved: $_previousPostcode');
    }
    _postcode = postcode;
    _log('Postcode set: $postcode');
    _saveToStorage();
  }

  /// Persist the borough resolved from the full postcode via postcodes.io.
  /// Must be called immediately after [lookupBoroughAsync] returns a value
  /// so that [borough] survives app restarts without a fresh API call.
  void setBorough(String borough) {
    _borough = borough;
    _log('Borough set: $borough');
    _saveToStorage();
  }

  /// Explicitly set the previous borough (called when borough is resolved from previous postcode)
  void setPreviousBorough(String borough) {
    _previousBorough = borough;
    _log('Previous borough set: $borough');
    _saveToStorage();
  }

  void setDueDate(String dueDate) {
    _dueDate = dueDate;
    _log('Due date set: $dueDate');
    _saveToStorage();
  }

  void setChildInfo(String name, String birthday) {
    _children.add({'name': name, 'birthday': birthday});
    _log('Child info added - Name: $name, Birthday: $birthday');
    _saveToStorage();
  }

  void setChildren(List<Map<String, String>> children) {
    _children = children;
    _log('Children set: ${children.length} children');
    _saveToStorage();
  }

  void setPhoneNumber(String phone, {String countryCode = '+44'}) {
    _phoneNumber = phone;
    _countryCode = countryCode;
    _log('Phone number set: $countryCode$phone');
    _saveToStorage();
  }

  void setPassword(String password) {
    // Store password in memory ONLY during the onboarding session.
    // It is NEVER written to persistent storage — passwords must only be
    // sent directly to Firebase Auth and then discarded.
    _password = password;
    _log('Password held in memory (length: ${password.length}) — NOT persisted');
    // Note: intentionally do NOT call _saveToStorage() here.
  }

  void setPhoneVerified(bool verified) {
    _isPhoneVerified = verified;
    _log('Phone verified status: $verified');
    _saveToStorage();
  }

  void setProfilePhotoPath(String? path) {
    _profilePhotoPath = path;
    _log('Profile photo path set: $path');
    _saveToStorage();
  }

  void setBio(String? bio) {
    _bio = bio;
    _log('Bio set: ${bio?.substring(0, bio.length > 30 ? 30 : bio.length)}...');
    _saveToStorage();
  }

  void setAssignedGroupCount(int count) {
    _assignedGroupCount = count;
    _log('Assigned group count set: $count');
    _saveToStorage();
  }

  void setAssignedGroupNames(List<String> names) {
    _assignedGroupNames = names;
    _log('Assigned group names set: $names');
    _saveToStorage();
  }

  void setProfilePhotoObjectUrl(String? url) {
    _profilePhotoObjectUrl = url;
    _log('Profile photo Object URL set: ${url != null ? "(blob url)" : "null"}');
    _saveToStorage();
  }


  // Check if user data is complete
  bool isComplete() {
    return _name != null &&
           _parentType != null &&
           _stagesOfLife.isNotEmpty &&
           _postcode != null &&
           _phoneNumber != null &&
           _password != null &&
           _isPhoneVerified;
  }

  // Get completion percentage
  double getCompletionPercentage() {
    int completed = 0;
    int total = 7; // Total required fields

    if (_name != null) completed++;
    if (_parentType != null) completed++;
    if (_stagesOfLife.isNotEmpty) completed++;
    if (_postcode != null) completed++;
    if (_phoneNumber != null) completed++;
    if (_password != null) completed++;
    if (_isPhoneVerified) completed++;

    return (completed / total) * 100;
  }

  // Get user data as Map
  Map<String, dynamic> toMap() {
    return {
      'name': _name,
      'parent_type': _parentType,
      'stages_of_life': _stagesOfLife,
      'postcode': _postcode,
      'due_date': _dueDate,
      'children': _children,
      'phone_number': fullPhoneNumber,
      'is_phone_verified': _isPhoneVerified,
      'completion_percentage': getCompletionPercentage(),
    };
  }

  /// Explicitly flush all in-memory state to persistent storage and wait for
  /// the write to complete before returning.
  ///
  /// Call this after a batch of set*() operations when another code path will
  /// immediately call initialize(forceReload:true) to re-read storage — the
  /// async set*() → _saveToStorage() fire-and-forget pattern races the reload.
  Future<void> flush() async {
    await _saveToStorage();
  }

  // Clear all data (GDPR Art. 17 / account deletion)
  // Also resets the initialization guard so that initialize() will re-read
  // storage correctly if the user starts a fresh onboarding session in the
  // same app lifecycle (e.g. after deleting their account).
  Future<void> clear() async {
    _name = null;
    _email = null;
    _parentType = null;
    _stagesOfLife = [];
    _postcode = null;
    _borough  = null;
    _dueDate  = null;
    _children = [];
    _phoneNumber = null;
    _countryCode = null;
    _password = null;
    _isPhoneVerified = false;
    _profilePhotoPath = null;
    _bio = null;
    _profilePhotoObjectUrl = null;
    _previousPostcode = null;
    _previousBorough = null;
    _assignedGroupCount = 0;
    _assignedGroupNames = [];
    // Reset initialization guards so a subsequent initialize() call will
    // re-read storage instead of returning the (now stale) cached future.
    _isInitialized = false;
    _initializationFuture = null;
    _log('All onboarding data cleared');
    // ONBOARD-1: clear BOTH stores
    await Future.wait([
      BrowserStorage.remove(_storageKey),
      SecurePiiStorage.clearPii(),
    ]);
  }
  
  /// Initialize and load data from persistent storage.
  ///
  /// Normally returns the cached result after the first call.
  /// Pass [forceReload] = true to discard the cache and re-read storage —
  /// useful when you know storage was just written by another code path
  /// (e.g. after restoreProfileFromFirestore sets the name).
  Future<void> initialize({bool forceReload = false}) async {
    if (forceReload) {
      // Discard existing cache so _loadFromStorage re-reads storage
      _isInitialized = false;
      _initializationFuture = null;
    }
    if (_initializationFuture != null) {
      return _initializationFuture;
    }
    _initializationFuture = _loadFromStorage();
    return _initializationFuture;
  }
  
  /// Load data from persistent storage (ONBOARD-1: merged load from two stores)
  Future<void> _loadFromStorage() async {
    if (_isInitialized) return;

    try {
      // ── ONBOARD-1 MIGRATION ───────────────────────────────────────────────
      // On the first run of the new code the old plaintext blob in BrowserStorage
      // may still contain sensitive fields.  Detect, promote to SecurePiiStorage,
      // then scrub the sensitive keys from the plaintext blob so the cleartext
      // copy doesn't linger.  Migration is one-shot: once the sensitive keys are
      // absent from the blob (or the blob is absent), it never re-runs.
      await _migrateLegacyPlaintextPii();

      // ── Read non-sensitive fields from BrowserStorage ─────────────────────
      final nsJson = await BrowserStorage.getString(_storageKey);
      final Map<String, dynamic> nsData =
          nsJson != null ? (json.decode(nsJson) as Map<String, dynamic>) : {};

      // ── Read sensitive fields from SecurePiiStorage ───────────────────────
      final Map<String, dynamic> piiData = await SecurePiiStorage.readPii();

      // ── Merge: PII takes precedence for its own keys ──────────────────────
      // Non-sensitive fields
      _parentType   = nsData['parent_type']   as String?;
      _stagesOfLife = List<String>.from(nsData['stages_of_life'] ?? []);
      _borough      = nsData['borough']       as String?;
      _previousBorough     = nsData['previous_borough']      as String?;
      _isPhoneVerified     = nsData['is_phone_verified']     as bool? ?? false;
      _profilePhotoPath    = nsData['profile_photo_path']    as String?;
      _profilePhotoObjectUrl = nsData['profile_photo_object_url'] as String?;
      _assignedGroupCount  = nsData['assigned_group_count']  as int? ?? 0;
      _assignedGroupNames  = List<String>.from(nsData['assigned_group_names'] ?? []);

      // Sensitive fields — from SecurePiiStorage (memory on web, Keychain on mobile)
      _name         = piiData['name']          as String?;
      _email        = piiData['email']         as String?;
      _phoneNumber  = piiData['phone_number']  as String?;
      _countryCode  = piiData['country_code']  as String?;
      _postcode     = piiData['postcode']      as String?;
      _previousPostcode = piiData['previous_postcode'] as String?;
      _bio          = piiData['bio']           as String?;
      // Sanitize legacy full-date values (e.g. '2027-01-01' → '2027')
      String? rawDue = piiData['due_date'] as String?;
      if (rawDue != null && rawDue.contains('-')) rawDue = rawDue.substring(0, 4);
      _dueDate = rawDue;
      _children = List<Map<String, String>>.from(
        (piiData['children'] as List? ?? [])
            .map((e) => Map<String, String>.from(e as Map)),
      );
      // 'password' is never loaded from storage (it was never saved there).
      _password = null;

      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('OnboardingData loaded (ONBOARD-1: split storage)');
        debugPrint('   Name present: ${_name != null}');
        debugPrint('   Postcode present: ${_postcode != null}');
        debugPrint('   Children count: ${_children.length}');
        debugPrint('   Stages: $_stagesOfLife');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingData] _loadFromStorage error: $e');
      _isInitialized = true; // don't retry forever on corrupt data
    }
  }

  // ── ONBOARD-1 Migration ────────────────────────────────────────────────────
  // Runs once: moves sensitive fields out of the old plaintext BrowserStorage
  // blob into SecurePiiStorage, then removes those keys from the plaintext blob.
  // Safe to call on every cold start — exits immediately if there is nothing to
  // migrate (no blob, or blob already has sensitive keys removed).
  static const List<String> _kSensitiveKeys = [
    'name', 'email', 'phone_number', 'country_code',
    'postcode', 'previous_postcode', 'children', 'due_date', 'bio',
  ];

  Future<void> _migrateLegacyPlaintextPii() async {
    try {
      final raw = await BrowserStorage.getString(_legacyStorageKey);
      if (raw == null) return; // nothing to migrate
      final Map<String, dynamic> blob = json.decode(raw) as Map<String, dynamic>;

      // Check whether any sensitive key is still present in the plaintext blob
      final hasSensitive = _kSensitiveKeys.any((k) => blob.containsKey(k));
      if (!hasSensitive) return; // already migrated

      _log('ONBOARD-1 migration: moving PII out of plaintext BrowserStorage');

      // Extract sensitive fields
      final Map<String, dynamic> pii = {};
      for (final k in _kSensitiveKeys) {
        if (blob.containsKey(k)) pii[k] = blob[k];
      }

      // Promote to SecurePiiStorage (Keychain/Keystore on mobile; memory on web)
      await SecurePiiStorage.writePii(pii);

      // Scrub sensitive keys from the plaintext blob
      for (final k in _kSensitiveKeys) {
        blob.remove(k);
      }

      // Write the scrubbed blob back so only non-sensitive fields remain
      await BrowserStorage.setString(_legacyStorageKey, json.encode(blob));

      _log('ONBOARD-1 migration complete — ${pii.keys.length} sensitive keys moved');
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingData] migration error (non-fatal): $e');
      // Non-fatal: worst case the old plaintext blob persists until next run
    }
  }
  
  /// Save data to persistent storage (ONBOARD-1: split into two stores)
  ///
  /// SENSITIVE PII → SecurePiiStorage (Keychain/Keystore on mobile; memory-only
  /// on web — nothing touches localStorage for these fields).
  ///
  /// NON-SENSITIVE → BrowserStorage (SharedPreferences) as before.
  Future<void> _saveToStorage() async {
    try {
      // ── 1. Sensitive PII → SecurePiiStorage ──────────────────────────────
      // ONBOARD-1: these fields MUST NOT appear in the BrowserStorage blob.
      final sensitiveData = <String, dynamic>{
        'name':              _name,
        'email':             _email,
        'phone_number':      _phoneNumber,
        'country_code':      _countryCode,
        'postcode':          _postcode,
        'previous_postcode': _previousPostcode,
        'children':          _children,
        'due_date':          _dueDate,
        'bio':               _bio,
        // 'password' intentionally excluded — never persisted anywhere.
      };
      await SecurePiiStorage.writePii(sensitiveData);

      // ── 2. Non-sensitive fields → BrowserStorage ──────────────────────────
      // These carry no PII meaningful enough to require Keychain protection.
      final nonSensitiveData = <String, dynamic>{
        'parent_type':              _parentType,
        'stages_of_life':           _stagesOfLife,
        'borough':                  _borough,
        'previous_borough':         _previousBorough,
        'is_phone_verified':        _isPhoneVerified,
        'profile_photo_path':       _profilePhotoPath,
        'profile_photo_object_url': _profilePhotoObjectUrl,
        'assigned_group_count':     _assignedGroupCount,
        'assigned_group_names':     _assignedGroupNames,
      };
      await BrowserStorage.setString(_storageKey, json.encode(nonSensitiveData));

      _log('Data saved (ONBOARD-1: PII → SecurePiiStorage, meta → BrowserStorage)');
    } catch (e) {
      if (kDebugMode) debugPrint('[OnboardingData] _saveToStorage error: $e');
    }
  }

  // Debug logging
  void _log(String message) {
    if (kDebugMode) {
      if (kDebugMode) {
        debugPrint('📝 OnboardingData: $message');
      }
    }
  }

  // Print summary
  void printSummary() {
    if (kDebugMode) {
      debugPrint('=== Onboarding Data Summary ===');
      debugPrint('Name: $_name');
      debugPrint('Parent Type: $_parentType');
      if (kDebugMode) {
        debugPrint('Stages: $_stagesOfLife');
      }
      if (kDebugMode) {
        debugPrint('Postcode: $_postcode');
      }
      if (kDebugMode) {
        debugPrint('Phone: $fullPhoneNumber');
      }
      if (kDebugMode) {
        debugPrint('Phone Verified: $_isPhoneVerified');
      }
      if (kDebugMode) {
        debugPrint('Completion: ${getCompletionPercentage().toStringAsFixed(1)}%');
      }
      debugPrint('==============================');
    }
  }
}
