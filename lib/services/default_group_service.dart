import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group.dart';
import 'postcode_service.dart';
import 'onboarding_data_service.dart';
import 'browser_storage.dart';
import 'borough_scope_guard.dart';

class DefaultGroupService {
  static final DefaultGroupService _instance = DefaultGroupService._internal();
  factory DefaultGroupService() => _instance;
  DefaultGroupService._internal();

  final PostcodeService _postcodeService = PostcodeService();
  final OnboardingDataService _onboardingService = OnboardingDataService();
  final BoroughScopeGuard _guard = BoroughScopeGuard();

  // Store all default groups (simulating database)
  final Map<String, Group> _defaultGroups = {};
  
  // Store user group memberships
  final Map<String, List<String>> _userGroupMemberships = {};
  
  // Persistence keys — bump version to force re-creation with year-based naming
  // v7: each Cambridge year now gets a fully unique image (no range collisions)
  static const String _groupsKey = 'default_groups_v7';
  static const String _membershipsKey = 'user_memberships_v7';
  
  bool _isInitialized = false;

  // Tracks how many groups have been created per borough pool key,
  // so each new group in the same borough gets the NEXT image in the pool.
  // Key = pool key (e.g. 'cambridge'), Value = next index to assign.
  final Map<String, int> _boroughImageCounters = {};

  // Persistence key for the image counters
  // v6: reset counters to align with v7 per-year unique image assignment
  static const String _countersKey = 'borough_image_counters_v6';

  /// Generate group name based on criteria
  String generateGroupName({
    required String parentCategory,
    required String borough,
    String? childYearOfBirth,
  }) {
    if (childYearOfBirth != null) {
      // Format: "2017 Cambridge Parents"
      return '$childYearOfBirth $borough $parentCategory';
    } else {
      // Format: "Cambridge Expecting Parents" or "Cambridge Aspiring Parents"
      return '$borough $parentCategory';
    }
  }

  /// Generate group ID from name
  String _generateGroupId(String groupName) {
    return groupName
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }

  /// Determine parent category from stages of life
  ///
  /// Stage IDs come from the onboarding UI (stage_of_life_screen.dart):
  ///   'aspiring'  – Trying for a baby
  ///   'expecting' – Expecting a baby
  ///   'parent'    – I have a child
  String _determineParentCategory(List<String> stagesOfLife) {
    if (stagesOfLife.contains('aspiring')) {
      return 'Aspiring Parents';
    } else if (stagesOfLife.contains('expecting')) {
      return 'Expecting Parents';
    } else if (stagesOfLife.contains('parent') ||
               stagesOfLife.contains('newborn') || 
               stagesOfLife.contains('toddler') || 
               stagesOfLife.contains('preschool') ||
               stagesOfLife.contains('school_age')) {
      return 'Parents';
    }
    return 'Parents'; // Default
  }

  /// Initialize service and load persisted data
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load image counters first (needed by migration below)
      final countersJson = await BrowserStorage.getString(_countersKey);
      if (countersJson != null) {
        final Map<String, dynamic> decoded = json.decode(countersJson);
        decoded.forEach((k, v) => _boroughImageCounters[k] = v as int);
        _log('✓ Loaded image counters: $_boroughImageCounters');
      }

      // Load groups
      final groupsJson = await BrowserStorage.getString(_groupsKey);
      if (groupsJson != null) {
        final Map<String, dynamic> groupsMap = json.decode(groupsJson);
        _defaultGroups.clear();
        bool needsResave = false;
        groupsMap.forEach((key, value) {
          Group g = Group.fromJson(value as Map<String, dynamic>);
          // ── Lock enforcement: always ensure isImageLocked = true
          if (!g.isImageLocked) {
            g = g.copyWith(isImageLocked: true);
            needsResave = true;
            _log('🔧 Enforced isImageLocked for group: ${g.name}');
          }
          // ── Image migration: replace any old external URL with a local asset
          if (!g.imageUrl.startsWith('assets/')) {
            final migratedUrl = _migrateImageUrl(g.name, g.imageUrl);
            g = g.copyWith(imageUrl: migratedUrl, isImageLocked: true);
            needsResave = true;
            _log('🔄 Migrated image URL for group: ${g.name} → $migratedUrl');
          }
          _defaultGroups[key] = g;
        });
        _log('✓ Loaded ${_defaultGroups.length} groups from storage');
        // Persist the patched data so next load is already correct
        if (needsResave) await _saveToStorage();
      }
      
      // Load memberships
      final membershipsJson = await BrowserStorage.getString(_membershipsKey);
      if (membershipsJson != null) {
        final Map<String, dynamic> membershipsMap = json.decode(membershipsJson);
        _userGroupMemberships.clear();
        membershipsMap.forEach((key, value) {
          _userGroupMemberships[key] = List<String>.from(value as List);
        });
        _log('✓ Loaded memberships for ${_userGroupMemberships.length} users');
      }
      
      _isInitialized = true;
    } catch (e) {
      _log('❌ Error loading persisted data: $e');
    }
  }
  
  /// Save data to persistent storage
  Future<void> _saveToStorage() async {
    try {
      // Save groups
      final groupsMap = _defaultGroups.map((key, group) => MapEntry(key, group.toJson()));
      await BrowserStorage.setString(_groupsKey, json.encode(groupsMap));
      
      // Save memberships
      await BrowserStorage.setString(_membershipsKey, json.encode(_userGroupMemberships));

      // Save borough image counters
      await BrowserStorage.setString(_countersKey, json.encode(_boroughImageCounters));
      
      _log('✓ Data saved to storage');
    } catch (e) {
      _log('❌ Error saving to storage: $e');
    }
  }

  /// Get or create a default group
  Group getOrCreateDefaultGroup({
    required String parentCategory,
    required String borough,
    String? childYearOfBirth,
  }) {
    final groupName = generateGroupName(
      parentCategory: parentCategory,
      borough: borough,
      childYearOfBirth: childYearOfBirth,
    );
    
    final groupId = _generateGroupId(groupName);

    // Check if group already exists
    if (_defaultGroups.containsKey(groupId)) {
      _log('✓ Group already exists: $groupName (${_defaultGroups[groupId]!.memberCount} members)');
      return _defaultGroups[groupId]!;
    }

    // Create new group with 0 members (users will be added via joinGroup)
    // Use _getNextBoroughImage so each new group in the same borough gets
    // the next sequential photo from the pool — guaranteed unique image.
    //
    // Welcome message seeded so the Messages tab shows meaningful content
    // from the moment the user first sees the group.
    final welcomeMsg = _generateWelcomeMessage(parentCategory, borough, childYearOfBirth);

    final newGroup = Group(
      id: groupId,
      name: groupName,
      description: _generateGroupDescription(parentCategory, borough, childYearOfBirth),
      imageUrl: _getNextBoroughImage(parentCategory, borough, groupName),
      memberCount: 0, // Start with 0 members
      category: 'Default Community',
      isJoined: false, // Will be set to true when user joins
      isImageLocked: true, // Borough group images are locked — cannot be changed by members
      lastMessage: welcomeMsg['message'],
      lastSenderName: welcomeMsg['sender'],
      lastMessageTime: DateTime.now().subtract(Duration(minutes: welcomeMsg['minutesAgo'] as int)),
      unreadCount: welcomeMsg['unread'] as int,
    );

    _defaultGroups[groupId] = newGroup;
    _log('✨ Created new default group: $groupName (0 members)');
    
    // Save to storage
    _saveToStorage();
    
    return newGroup;
  }

  /// Generate group description
  String _generateGroupDescription(String category, String borough, String? birthYear) {
    if (birthYear != null) {
      if (category == 'Aspiring Parents') {
        return 'Connect with aspiring parents in $borough who are trying for a baby in $birthYear. Share your journey, get advice, and support each other.';
      } else if (category == 'Expecting Parents') {
        return 'Connect with expecting parents in $borough whose babies are due in $birthYear. Share pregnancy journey, tips, and prepare for parenthood together.';
      } else {
        return 'Connect with $category in $borough whose children were born in $birthYear. Share experiences, advice, and local recommendations.';
      }
    } else if (category == 'Expecting Parents') {
      return 'Connect with expecting parents in $borough. Share pregnancy journey, tips, and prepare for parenthood together.';
    } else if (category == 'Aspiring Parents') {
      return 'Connect with aspiring parents in $borough. Share your journey, get advice, and support each other.';
    } else {
      return 'Connect with parents in $borough. Share experiences, advice, and build lasting friendships.';
    }
  }

  /// Generate a welcome / seed message for a newly created default group.
  /// Uses a neutral system message — no fake member names.
  ///
  /// Returns a Map with keys: 'message', 'sender', 'minutesAgo', 'unread'.
  static int _welcomeCounter = 0;
  Map<String, dynamic> _generateWelcomeMessage(
      String category, String borough, String? birthYear) {
    // Single neutral system message — real member activity will follow.
    final messages = <Map<String, dynamic>>[
      {
        'message': 'Welcome to the group! Say hello to connect with other $category in $borough.',
        'sender': 'Huddl',
        'minutesAgo': 0,
        'unread': 0,
      },
    ];

    final idx = _welcomeCounter % messages.length;
    _welcomeCounter++;
    return messages[idx];
  }

  // ── Borough image pools — LOCAL ASSET PATHS (bundled with app, no CORS) ───────
  //
  // Cambridge cluster uses landmark images in assets/images/groups/.
  // All other boroughs use dedicated local photos in assets/images/groups/boroughs/.
  // Each pool entry is a distinct local landmark image for that specific place.
  // No external requests, no CORS issues, guaranteed to display on Flutter Web.
  //
  // Cambridge constants (A–I) — kept for Cambridge cluster + _migrateImageUrl
  static const _imgA = 'assets/images/groups/cambridge_kings_college.jpg';    // King's College Chapel
  static const _imgB = 'assets/images/groups/cambridge_punting.jpg';          // Punting on River Cam
  static const _imgC = 'assets/images/groups/cambridge_trinity.jpg';          // Trinity College
  static const _imgD = 'assets/images/groups/cambridge_the_backs.jpg';        // The Backs
  static const _imgE = 'assets/images/groups/east_cambs_ely_cathedral.jpg';   // Ely Cathedral
  static const _imgF = 'assets/images/groups/south_cambs_village.jpg';        // South Cambs village
  static const _imgG = 'assets/images/groups/cambridge_river_boats.jpg';      // Boats on River Cam
  static const _imgH = 'assets/images/groups/cambridge_market_square.jpg';    // Cambridge Market Square
  static const _imgI = 'assets/images/groups/cambridge_fitzwilliam.jpg';      // Fitzwilliam Museum / city view

  static const Map<String, List<String>> _boroughImagePools = {
    // ── Cambridge cluster — existing dedicated landmark assets ──────────────
    // 9 fully unique images; slot order: newest year → oldest → Expecting/Aspiring
    'cambridge':           [_imgD, _imgC, _imgB, _imgG, _imgA, _imgH, _imgI, _imgF, _imgE],
    'east cambridgeshire': [_imgE, _imgD, _imgB, _imgC, _imgA, _imgG],
    'south cambridgeshire':[_imgF, _imgD, _imgA, _imgC, _imgB, _imgG],

    // ── All other boroughs — dedicated local landmark images ─────────────────
    // Each entry is a UNIQUE photo of that specific borough.
    // Paths: assets/images/groups/boroughs/{borough}_{n}.jpg

    'barnet': [
      'assets/images/groups/boroughs/barnet_1.jpg',
      'assets/images/groups/boroughs/barnet_2.jpg',
      'assets/images/groups/boroughs/barnet_3.jpg',
      'assets/images/groups/boroughs/barnet_4.jpg',
    ],
    'birmingham': [
      'assets/images/groups/boroughs/birmingham_1.jpg',
      'assets/images/groups/boroughs/birmingham_2.jpg',
      'assets/images/groups/boroughs/birmingham_3.jpg',
      'assets/images/groups/boroughs/birmingham_4.jpg',
      'assets/images/groups/boroughs/birmingham_5.jpg',
    ],
    'brent': [
      'assets/images/groups/boroughs/brent_1.jpg',
      'assets/images/groups/boroughs/brent_2.jpg',
      'assets/images/groups/boroughs/brent_3.jpg',
      'assets/images/groups/boroughs/brent_4.jpg',
    ],
    'bristol': [
      'assets/images/groups/boroughs/bristol_1.jpg',
      'assets/images/groups/boroughs/bristol_2.jpg',
      'assets/images/groups/boroughs/bristol_3.jpg',
      'assets/images/groups/boroughs/bristol_4.jpg',
    ],
    'bromley': [
      'assets/images/groups/boroughs/bromley_1.jpg',
      'assets/images/groups/boroughs/bromley_2.jpg',
      'assets/images/groups/boroughs/bromley_3.jpg',
      'assets/images/groups/boroughs/bromley_4.jpg',
    ],
    'camden': [
      'assets/images/groups/boroughs/camden_1.jpg',
      'assets/images/groups/boroughs/camden_2.jpg',
      'assets/images/groups/boroughs/camden_3.jpg',
      'assets/images/groups/boroughs/camden_4.jpg',
    ],
    'city of london': [
      'assets/images/groups/boroughs/city_of_london_1.jpg',
      'assets/images/groups/boroughs/city_of_london_2.jpg',
      'assets/images/groups/boroughs/city_of_london_3.jpg',
      'assets/images/groups/boroughs/city_of_london_4.jpg',
      'assets/images/groups/boroughs/city_of_london_5.jpg',
    ],
    'croydon': [
      'assets/images/groups/boroughs/croydon_1.jpg',
      'assets/images/groups/boroughs/croydon_2.jpg',
      'assets/images/groups/boroughs/croydon_3.jpg',
      'assets/images/groups/boroughs/croydon_4.jpg',
    ],
    'ealing': [
      'assets/images/groups/boroughs/ealing_1.jpg',
      'assets/images/groups/boroughs/ealing_2.jpg',
      'assets/images/groups/boroughs/ealing_3.jpg',
      'assets/images/groups/boroughs/ealing_4.jpg',
    ],
    'enfield': [
      'assets/images/groups/boroughs/enfield_1.jpg',
      'assets/images/groups/boroughs/enfield_2.jpg',
      'assets/images/groups/boroughs/enfield_3.jpg',
    ],
    'greenwich': [
      'assets/images/groups/boroughs/greenwich_1.jpg',
      'assets/images/groups/boroughs/greenwich_2.jpg',
      'assets/images/groups/boroughs/greenwich_3.jpg',
      'assets/images/groups/boroughs/greenwich_4.jpg',
    ],
    'hackney': [
      'assets/images/groups/boroughs/hackney_1.jpg',
      'assets/images/groups/boroughs/hackney_2.jpg',
      'assets/images/groups/boroughs/hackney_3.jpg',
      'assets/images/groups/boroughs/hackney_4.jpg',
      'assets/images/groups/boroughs/hackney_5.jpg',
    ],
    'hammersmith and fulham': [
      'assets/images/groups/boroughs/hammersmith_1.jpg',
      'assets/images/groups/boroughs/hammersmith_2.jpg',
      'assets/images/groups/boroughs/hammersmith_3.jpg',
      'assets/images/groups/boroughs/hammersmith_4.jpg',
    ],
    'haringey': [
      'assets/images/groups/boroughs/haringey_1.jpg',
      'assets/images/groups/boroughs/haringey_2.jpg',
      'assets/images/groups/boroughs/haringey_3.jpg',
      'assets/images/groups/boroughs/haringey_4.jpg',
    ],
    'hounslow': [
      'assets/images/groups/boroughs/hounslow_1.jpg',
      'assets/images/groups/boroughs/hounslow_2.jpg',
      'assets/images/groups/boroughs/hounslow_3.jpg',
      'assets/images/groups/boroughs/hounslow_4.jpg',
    ],
    'islington': [
      'assets/images/groups/boroughs/islington_1.jpg',
      'assets/images/groups/boroughs/islington_2.jpg',
      'assets/images/groups/boroughs/islington_3.jpg',
      'assets/images/groups/boroughs/islington_4.jpg',
    ],
    'kensington and chelsea': [
      'assets/images/groups/boroughs/kensington_1.jpg',
      'assets/images/groups/boroughs/kensington_2.jpg',
      'assets/images/groups/boroughs/kensington_3.jpg',
      'assets/images/groups/boroughs/kensington_4.jpg',
      'assets/images/groups/boroughs/kensington_5.jpg',
    ],
    'lambeth': [
      'assets/images/groups/boroughs/lambeth_1.jpg',
      'assets/images/groups/boroughs/lambeth_2.jpg',
      'assets/images/groups/boroughs/lambeth_3.jpg',
      'assets/images/groups/boroughs/lambeth_4.jpg',
    ],
    'leeds': [
      'assets/images/groups/boroughs/leeds_1.jpg',
      'assets/images/groups/boroughs/leeds_2.jpg',
      'assets/images/groups/boroughs/leeds_3.jpg',
      'assets/images/groups/boroughs/leeds_4.jpg',
      'assets/images/groups/boroughs/leeds_5.jpg',
    ],
    'lewisham': [
      'assets/images/groups/boroughs/lewisham_1.jpg',
      'assets/images/groups/boroughs/lewisham_2.jpg',
      'assets/images/groups/boroughs/lewisham_3.jpg',
    ],
    'manchester': [
      'assets/images/groups/boroughs/manchester_1.jpg',
      'assets/images/groups/boroughs/manchester_2.jpg',
      'assets/images/groups/boroughs/manchester_3.jpg',
      'assets/images/groups/boroughs/manchester_4.jpg',
      'assets/images/groups/boroughs/manchester_5.jpg',
    ],
    'merton': [
      'assets/images/groups/boroughs/merton_1.jpg',
      'assets/images/groups/boroughs/merton_2.jpg',
      'assets/images/groups/boroughs/merton_3.jpg',
      'assets/images/groups/boroughs/merton_4.jpg',
    ],
    'newham': [
      'assets/images/groups/boroughs/newham_1.jpg',
      'assets/images/groups/boroughs/newham_2.jpg',
      'assets/images/groups/boroughs/newham_3.jpg',
      'assets/images/groups/boroughs/newham_4.jpg',
    ],
    'redbridge': [
      'assets/images/groups/boroughs/redbridge_1.jpg',
      'assets/images/groups/boroughs/redbridge_2.jpg',
      'assets/images/groups/boroughs/redbridge_3.jpg',
      'assets/images/groups/boroughs/redbridge_4.jpg',
    ],
    'richmond': [
      'assets/images/groups/boroughs/richmond_1.jpg',
      'assets/images/groups/boroughs/richmond_2.jpg',
      'assets/images/groups/boroughs/richmond_3.jpg',
      'assets/images/groups/boroughs/richmond_4.jpg',
    ],
    'salford': [
      'assets/images/groups/boroughs/salford_1.jpg',
      'assets/images/groups/boroughs/salford_2.jpg',
      'assets/images/groups/boroughs/salford_3.jpg',
    ],
    'southwark': [
      'assets/images/groups/boroughs/southwark_1.jpg',
      'assets/images/groups/boroughs/southwark_2.jpg',
      'assets/images/groups/boroughs/southwark_3.jpg',
      'assets/images/groups/boroughs/southwark_4.jpg',
    ],
    'tower hamlets': [
      'assets/images/groups/boroughs/tower_hamlets_1.jpg',
      'assets/images/groups/boroughs/tower_hamlets_2.jpg',
      'assets/images/groups/boroughs/tower_hamlets_3.jpg',
      'assets/images/groups/boroughs/tower_hamlets_4.jpg',
    ],
    'trafford': [
      'assets/images/groups/boroughs/trafford_1.jpg',
      'assets/images/groups/boroughs/trafford_2.jpg',
      'assets/images/groups/boroughs/trafford_3.jpg',
      'assets/images/groups/boroughs/trafford_4.jpg',
    ],
    'waltham forest': [
      'assets/images/groups/boroughs/waltham_forest_1.jpg',
      'assets/images/groups/boroughs/waltham_forest_2.jpg',
      'assets/images/groups/boroughs/waltham_forest_3.jpg',
      'assets/images/groups/boroughs/waltham_forest_4.jpg',
    ],
    'wandsworth': [
      'assets/images/groups/boroughs/wandsworth_1.jpg',
      'assets/images/groups/boroughs/wandsworth_2.jpg',
      'assets/images/groups/boroughs/wandsworth_3.jpg',
      'assets/images/groups/boroughs/wandsworth_4.jpg',
    ],
    'westminster': [
      'assets/images/groups/boroughs/westminster_1.jpg',
      'assets/images/groups/boroughs/westminster_2.jpg',
      'assets/images/groups/boroughs/westminster_3.jpg',
      'assets/images/groups/boroughs/westminster_4.jpg',
      'assets/images/groups/boroughs/westminster_5.jpg',
    ],
  };

  // ── Per-year Cambridge image map — every year 2010–2032 gets its OWN image ──
  // Rotating through all 9 assets (A–I) so no two adjacent years ever share
  // the same photo.  Years beyond the range wrap via modulo in _migrateImageUrl.
  static const Map<String, String> _cambridgeYearImages = {
    '2010': _imgA,  // King's College Chapel
    '2011': _imgB,  // Punting
    '2012': _imgC,  // Trinity College
    '2013': _imgD,  // The Backs
    '2014': _imgE,  // Ely Cathedral
    '2015': _imgF,  // South Cambs village
    '2016': _imgG,  // River Boats
    '2017': _imgH,  // Market Square
    '2018': _imgI,  // Fitzwilliam
    '2019': _imgA,  // King's College Chapel
    '2020': _imgB,  // Punting
    '2021': _imgC,  // Trinity College
    '2022': _imgD,  // The Backs
    '2023': _imgE,  // Ely Cathedral
    '2024': _imgF,  // South Cambs village
    '2025': _imgG,  // River Boats
    '2026': _imgH,  // Market Square
    '2027': _imgI,  // Fitzwilliam
    '2028': _imgA,  // King's College Chapel
    '2029': _imgB,  // Punting
    '2030': _imgC,  // Trinity College
    '2031': _imgD,  // The Backs
    '2032': _imgE,  // Ely Cathedral
  };

  /// Cambridge image pool ordered for sequential counter assignment.
  /// Same rotation as _cambridgeYearImages so new groups stay consistent.
  static const List<String> _cambridgeSequentialPool = [
    _imgA, _imgB, _imgC, _imgD, _imgE, _imgF, _imgG, _imgH, _imgI,
  ];

  /// Migrate an old external image URL to the correct local asset path.
  ///
  /// Priority order:
  ///   1. Non-Cambridge borough name match → first image from that borough's pool
  ///   2. East / South Cambridgeshire overrides
  ///   3. Cambridge year — exact per-year lookup (guaranteed unique per year)
  ///   4. Cambridge category fallback
  ///   5. Absolute default (King's College Chapel)
  static String _migrateImageUrl(String groupName, String oldUrl) {
    final n = groupName.toLowerCase();

    // ── 1. Non-Cambridge borough detection (longest match wins) ──────────
    // Iterate longest-key-first so 'kensington and chelsea' beats 'kensington'.
    final sortedKeys = _boroughImagePools.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      // Skip Cambridge cluster — handled below with per-year logic
      if (key == 'cambridge' ||
          key == 'east cambridgeshire' ||
          key == 'south cambridgeshire') { continue; }
      if (n.contains(key)) {
        return _boroughImagePools[key]!.first;
      }
    }

    // ── 2. Cambridge sub-region overrides ────────────────────────────────
    if (n.contains('east cambridgeshire') || n.contains('ely')) return _imgE;
    if (n.contains('south cambridgeshire')) return _imgF;

    // ── 3. Cambridge — exact per-year lookup (no range collisions) ───────
    // Extract the first 4-digit year found in the group name and look it up.
    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(n);
    if (yearMatch != null) {
      final year = yearMatch.group(1)!;
      // Direct lookup; fall back to cycling the pool for unmapped years
      if (_cambridgeYearImages.containsKey(year)) {
        return _cambridgeYearImages[year]!;
      }
      // Year outside the map (e.g. 2033+) — cycle through pool by year offset
      final base = int.tryParse(year) ?? 2024;
      return _cambridgeSequentialPool[(base - 2010) % _cambridgeSequentialPool.length];
    }

    // ── 4. Cambridge category fallback (no year in name) ─────────────────
    if (n.contains('aspiring'))  return _imgH;  // Market Square
    if (n.contains('expecting')) return _imgI;  // Fitzwilliam
    if (n.contains('cambridge')) return _imgB;  // Punting

    // ── 5. Absolute default ──────────────────────────────────────────────
    return _imgA;
  }

  /// Resolve the borough pool key for [borough] / [groupName] text.
  ///
  /// Longest match wins so 'east cambridgeshire' beats 'cambridge'.
  String? _resolveBoroughPoolKey(String borough, String groupName) {
    final b = '${borough.toLowerCase()} ${groupName.toLowerCase()}';
    String? poolKey;
    int bestLen = 0;
    for (final key in _boroughImagePools.keys) {
      if (b.contains(key) && key.length > bestLen) {
        poolKey = key;
        bestLen = key.length;
      }
    }
    return poolKey;
  }

  /// Assign the NEXT sequential image from the borough pool to a NEW group.
  ///
  /// Each call for the same pool key advances the counter by 1, guaranteeing
  /// that two groups created in the same borough receive DIFFERENT images
  /// (up to the pool size; wraps around after that).
  String _getNextBoroughImage(String category,
      [String borough = '', String groupName = '']) {
    final poolKey = _resolveBoroughPoolKey(borough, groupName);

    if (poolKey != null) {
      final pool = _boroughImagePools[poolKey]!;
      final nextIndex = _boroughImageCounters[poolKey] ?? 0;
      // Advance counter BEFORE returning so the next call gets a different image
      _boroughImageCounters[poolKey] = (nextIndex + 1) % pool.length;
      _log('🖼️  Borough "$poolKey" → image index $nextIndex / ${pool.length} for "$groupName"');
      return pool[nextIndex];
    }

    // ── Fallback — use King's College Chapel local asset ──────────────────
    return 'assets/images/groups/cambridge_kings_college.jpg';
  }

  /// Assign user to default groups based on onboarding data.
  ///
  /// Rules:
  ///  • **Parents with children** → one group per child, keyed by each child's
  ///    year of birth (e.g. three children born 2019, 2021, 2023 → three groups)
  ///  • **Expecting parents** → one group keyed by the expected birth year
  ///  • **Aspiring parents** → one generic group (no year)
  Future<List<Group>> assignUserToDefaultGroups(String userId) async {
    await initialize();
    // CRITICAL: ensure onboarding data is loaded from storage before reading
    await _onboardingService.initialize();
    final List<Group> assignedGroups = [];

    final stagesOfLife = _onboardingService.stagesOfLife;
    final postcode     = _onboardingService.postcode;
    final children     = _onboardingService.children; // full list

    _log('');
    _log('═══════════════════════════════════════════════════════');
    _log('🎯 ASSIGNING GROUPS FOR USER: $userId');
    _log('═══════════════════════════════════════════════════════');
    _log('📋 Onboarding Data:');
    _log('   • Postcode:       $postcode');
    _log('   • Stages of Life: $stagesOfLife');
    _log('   • Children:       ${children.length}');
    for (var i = 0; i < children.length; i++) {
      _log('     [$i] name=${children[i]['name']} birthday=${children[i]['birthday']}');
    }
    _log('   • Due Date:       ${_onboardingService.dueDate}');

    if (postcode == null || stagesOfLife.isEmpty) {
      _log('❌ INSUFFICIENT DATA — postcode or stages missing');
      _log('═══════════════════════════════════════════════════════');
      return assignedGroups;
    }

    final borough = _postcodeService.getBoroughFromPostcode(postcode);
    if (borough == null) {
      _log('❌ COULD NOT DETERMINE BOROUGH FROM POSTCODE: $postcode');
      _log('═══════════════════════════════════════════════════════');
      return assignedGroups;
    }

    final parentCategory = _determineParentCategory(stagesOfLife);
    _log('   • Borough:        $borough');
    _log('   • Parent Category: $parentCategory');
    _log('');

    // ── Build the list of (year, category) pairs to create groups for ───
    //
    // Key rule: groups for EXISTING children always use 'Parents' as the
    // category, even when the user also selected 'Expecting Parents'. The
    // word "Expecting" only appears in groups tied to an unborn/due baby.
    //
    // Examples for a user who selected BOTH expecting + parents with 3 kids:
    //   • 2019 Cambridge Parents        ← child born 2019
    //   • 2021 Cambridge Parents        ← child born 2021
    //   • 2023 Cambridge Parents        ← child born 2023
    //   • 2026 Cambridge Expecting Parents  ← due date 2026
    final List<({String? year, String category})> groupSpecs = [];

    if (children.isNotEmpty) {
      // ── One 'Parents' group per unique birth year ──────────────────
      final List<String> childYears = [];
      for (final child in children) {
        final birthday = child['birthday'];
        if (birthday != null && birthday.length >= 4) {
          final year = birthday.substring(0, 4);
          if (!childYears.contains(year)) {
            childYears.add(year);
          }
        }
      }
      if (childYears.isEmpty) {
        // Children present but no valid years — generic Parents group
        groupSpecs.add((year: null, category: 'Parents'));
      } else {
        for (final y in childYears) {
          groupSpecs.add((year: y, category: 'Parents'));
        }
      }

      // ── Also add an Expecting group if the user is also expecting ──
      if (stagesOfLife.contains('expecting')) {
        final dueDate = _onboardingService.dueDate;
        final dueYear = (dueDate != null && dueDate.length >= 4)
            ? dueDate.substring(0, 4)
            : null;
        groupSpecs.add((year: dueYear, category: 'Expecting Parents'));
        _log('   ℹ️  Also adding Expecting group (due year: ${dueYear ?? 'none'})');
      }

      // ── Also add an Aspiring group if the user is also aspiring ──
      if (stagesOfLife.contains('aspiring')) {
        final currentYear = DateTime.now().year.toString();
        groupSpecs.add((year: currentYear, category: 'Aspiring Parents'));
        _log('   ℹ️  Also adding Aspiring group (year: $currentYear)');
      }
    } else if (stagesOfLife.contains('expecting')) {
      // ── Expecting only (no existing children) ──────────────────────
      final dueDate = _onboardingService.dueDate;
      final dueYear = (dueDate != null && dueDate.length >= 4)
          ? dueDate.substring(0, 4)
          : null;
      groupSpecs.add((year: dueYear, category: 'Expecting Parents'));
    } else if (stagesOfLife.contains('aspiring')) {
      // ── Aspiring only — use current year ────────────────────────────
      final currentYear = DateTime.now().year.toString();
      groupSpecs.add((year: currentYear, category: 'Aspiring Parents'));
    } else {
      // ── Generic parents fallback ───────────────────────────────────
      groupSpecs.add((year: null, category: 'Parents'));
    }

    _log('🏘️  Groups to create/join: ${groupSpecs.length}');

    // ── Create / join one group per spec ──────────────────────────────
    for (final spec in groupSpecs) {
      final group = getOrCreateDefaultGroup(
        parentCategory: spec.category,
        borough: borough,
        childYearOfBirth: spec.year,
      );
      assignedGroups.add(group);
      joinGroup(userId, group.id);
      _log('   ✓ ${group.name}  (year: ${spec.year ?? 'none'}, category: ${spec.category})');
    }

    // Return fresh copies with updated member counts
    final updatedGroups = assignedGroups
        .map((g) => _defaultGroups[g.id]!)
        .toList();

    _log('');
    _log('✅ Assigned $userId to ${updatedGroups.length} group(s):');
    for (final g in updatedGroups) {
      _log('   • ${g.name} (${g.memberCount} member${g.memberCount != 1 ? "s" : ""})');
    }
    _log('═══════════════════════════════════════════════════════');
    _log('');

    await _saveToStorage();
    return updatedGroups;
  }

  /// Get all default groups.
  /// Returns ALL groups (unfiltered) — used internally by services like
  /// the matchmaker that need the complete set.
  List<Group> getAllDefaultGroups() {
    return _defaultGroups.values.toList();
  }

  /// Get all default groups visible to the current user.
  ///
  /// HYPERLOCAL RULE: Groups are borough-only.
  /// Only returns groups whose name contains the user's current borough.
  /// If the user's borough cannot be determined, returns all groups
  /// (graceful degradation during onboarding).
  List<Group> getVisibleGroups() {
    final borough = _guard.currentBorough;
    if (borough == null || borough.isEmpty) return getAllDefaultGroups();
    final lowerBorough = borough.toLowerCase();
    return _defaultGroups.values
        .where((g) => g.name.toLowerCase().contains(lowerBorough))
        .toList();
  }

  /// Get user's assigned groups
  Future<List<Group>> getUserGroups(String userId) async {
    // Ensure initialized
    await initialize();
    final groupIds = _userGroupMemberships[userId] ?? [];
    return groupIds
        .map((id) => _defaultGroups[id])
        .whereType<Group>()
        .toList();
  }

  /// Join a user to an existing group.
  ///
  /// HYPERLOCAL RULE: A user can only join groups that belong to their
  /// current borough. Cross-borough joins are silently blocked and logged.
  void joinGroup(String userId, String groupId) {
    if (!_defaultGroups.containsKey(groupId)) {
      _log('Group not found: $groupId');
      return;
    }

    // ── Borough gate ──────────────────────────────────────────────────
    final group = _defaultGroups[groupId]!;
    final userBorough = _guard.currentBorough;
    if (userBorough != null && userBorough.isNotEmpty) {
      if (!group.name.toLowerCase().contains(userBorough.toLowerCase())) {
        _log('BLOCKED: User $userId attempted to join cross-borough group '
            '"${group.name}" (user borough: $userBorough)');
        return;
      }
    }

    final userGroups = _userGroupMemberships[userId] ?? [];
    if (!userGroups.contains(groupId)) {
      userGroups.add(groupId);
      _userGroupMemberships[userId] = userGroups;
      
      // Increment member count — preserve all existing fields including isImageLocked
      final group = _defaultGroups[groupId]!;
      _defaultGroups[groupId] = Group(
        id: group.id,
        name: group.name,
        description: group.description,
        imageUrl: group.imageUrl,
        memberCount: group.memberCount + 1,
        category: group.category,
        isJoined: true,
        isImageLocked: true, // Always locked for default borough groups
      );
      
      _log('User $userId joined group: ${group.name}');
      
      // Save to storage
      _saveToStorage();

      // ── Sync to Firestore so other devices can see this user ──────────
      // Use the real Firebase Auth UID for cross-device visibility.
      // We upsert the group doc (create if new, update memberIds if existing)
      // so both users share the same group in Firestore.
      final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      if (firebaseUid != null) {
        _syncGroupMembershipToFirestore(group, firebaseUid);
      }
    }
  }

  /// Upsert a default group into Firestore and add [firebaseUid] to memberIds.
  /// Called fire-and-forget from joinGroup — errors are swallowed so they
  /// never block the local in-memory flow.
  void _syncGroupMembershipToFirestore(Group group, String firebaseUid) {
    final db = FirebaseFirestore.instance;
    final ref = db.collection('groups').doc(group.id);

    db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) {
        // Group already in Firestore — just add this UID to memberIds
        tx.update(ref, {
          'memberIds': FieldValue.arrayUnion([firebaseUid]),
          'memberCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create the group document in Firestore for the first time
        tx.set(ref, {
          'id': group.id,
          'name': group.name,
          'description': group.description,
          'imageUrl': group.imageUrl,
          'memberIds': [firebaseUid],
          'memberCount': 1,
          'category': group.category,
          'privacy': 'public',
          'borough': _onboardingService.postcode != null
              ? (_postcodeService.getBoroughFromPostcode(_onboardingService.postcode!) ?? '')
              : '',
          'postcode': _onboardingService.postcode ?? '',
          'creatorId': firebaseUid,
          'creatorName': _onboardingService.name ?? '',
          'isImageLocked': true,
          'invitedMemberIds': [],
          'lastMessage': group.lastMessage ?? 'Welcome to the group!',
          'lastSenderName': group.lastSenderName ?? 'Huddl',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }).catchError((e) {
      if (kDebugMode) debugPrint('[DefaultGroupService] Firestore sync error: $e');
    });
  }

  /// Leave a default group. Only allowed for groups from a previous borough
  /// (i.e. the user changed postcode/borough and wants to leave old groups).
  /// Returns true if the user was removed from the group.
  Future<bool> leaveGroup(String userId, String groupId) async {
    await initialize();
    final userGroups = _userGroupMemberships[userId] ?? [];
    if (!userGroups.contains(groupId)) return false;

    userGroups.remove(groupId);
    _userGroupMemberships[userId] = userGroups;

    // Decrement member count
    final group = _defaultGroups[groupId];
    if (group != null && group.memberCount > 0) {
      _defaultGroups[groupId] = group.copyWith(
        memberCount: group.memberCount - 1,
        isJoined: false,
      );
    }

    await _saveToStorage();
    _log('User $userId left group: ${group?.name ?? groupId}');
    return true;
  }

  /// Get default groups belonging to a specific borough for a user.
  /// Used after a borough change to show which old groups can be left.
  Future<List<Group>> getUserGroupsForBorough(
      String userId, String borough) async {
    await initialize();
    final groupIds = _userGroupMemberships[userId] ?? [];
    final boroughLower = borough.toLowerCase();
    return groupIds
        .map((id) => _defaultGroups[id])
        .whereType<Group>()
        .where((g) => g.name.toLowerCase().contains(boroughLower))
        .toList();
  }

  /// Get group statistics
  Map<String, dynamic> getGroupStatistics() {
    return {
      'total_default_groups': _defaultGroups.length,
      'total_users': _userGroupMemberships.length,
      'average_members_per_group': _defaultGroups.isEmpty 
          ? 0 
          : _defaultGroups.values.map((g) => g.memberCount).reduce((a, b) => a + b) / _defaultGroups.length,
      'groups_by_category': _groupGroupsByCategory(),
    };
  }

  Map<String, int> _groupGroupsByCategory() {
    final Map<String, int> categoryCount = {};
    for (var group in _defaultGroups.values) {
      final category = group.name.split(' - ').first;
      categoryCount[category] = (categoryCount[category] ?? 0) + 1;
    }
    return categoryCount;
  }

  /// Print group assignment summary
  void printGroupAssignmentSummary() {
    if (kDebugMode) {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('        DEFAULT GROUP ASSIGNMENT SUMMARY');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('📊 Total Default Groups: ${_defaultGroups.length}');
      debugPrint('👥 Total Users: ${_userGroupMemberships.length}');
      debugPrint('');
      debugPrint('🏘️  HYPER-LOCAL COMMUNITY GROUPS:');
      debugPrint('───────────────────────────────────────────────────────');
      
      // Sort groups by member count (descending)
      final sortedGroups = _defaultGroups.values.toList()
        ..sort((a, b) => b.memberCount.compareTo(a.memberCount));
      
      for (var group in sortedGroups) {
        final memberCountEmoji = group.memberCount == 0 ? '🆕' : 
                                 group.memberCount == 1 ? '👤' : 
                                 group.memberCount >= 5 ? '👥👥' : '👥';
        debugPrint('$memberCountEmoji  ${group.name}');
        debugPrint('    └─ ${group.memberCount} member${group.memberCount != 1 ? 's' : ''}');
        
        // Show which users are in this group
        final usersInGroup = _userGroupMemberships.entries
            .where((entry) => entry.value.contains(group.id))
            .map((entry) => entry.key)
            .toList();
        
        if (usersInGroup.isNotEmpty) {
          debugPrint('    └─ Members: ${usersInGroup.join(', ')}');
        }
        debugPrint('');
      }
      
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('💡 Hyper-local community building in action!');
      debugPrint('   Parents with same journey → Same groups → Connected');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('');
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('DefaultGroupService: $message');
    }
  }

  /// Recreate default groups when the user changes their stage of life
  /// in the profile. Removes old group memberships and creates new groups
  /// based on the updated stages.
  Future<void> recreateGroupsForStages({
    required String userId,
    required List<String> stages,
    String? postcode,
  }) async {
    await initialize();
    // Remove existing group memberships for this user
    final existing = _userGroupMemberships[userId] ?? [];
    for (final gId in existing) {
      final g = _defaultGroups[gId];
      if (g != null && g.memberCount > 0) {
        _defaultGroups[gId] = g.copyWith(memberCount: g.memberCount - 1);
      }
    }
    _userGroupMemberships[userId] = [];
    await _saveToStorage();
    _log('🔄 Cleared old memberships for $userId (had ${existing.length} groups)');

    // Re-assign using updated onboarding data (already saved by profile)
    await assignUserToDefaultGroups(userId);
  }

  /// Clear all data (for testing)
  void clear() {
    _defaultGroups.clear();
    _userGroupMemberships.clear();
    _boroughImageCounters.clear();
    _isInitialized = false;
    _log('All default group data cleared (including image counters)');
  }
}
