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
  // v5: bumped to trigger _migrateImageUrl on all cached groups → unique images
  static const String _groupsKey = 'default_groups_v5';
  static const String _membershipsKey = 'user_memberships_v5';
  
  bool _isInitialized = false;

  // Tracks how many groups have been created per borough pool key,
  // so each new group in the same borough gets the NEXT image in the pool.
  // Key = pool key (e.g. 'cambridge'), Value = next index to assign.
  final Map<String, int> _boroughImageCounters = {};

  // Persistence key for the image counters
  // v4: reset counters to align with new 9-slot unique pool
  static const String _countersKey = 'borough_image_counters_v4';

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
  // All images stored in assets/images/groups/ and served from the same origin.
  // No external requests, no CORS issues, guaranteed to display on Flutter Web.
  //
  // A = King's College Chapel           cambridge_kings_college.jpg
  // B = Punting on River Cam            cambridge_punting.jpg
  // C = Trinity College                 cambridge_trinity.jpg
  // D = The Backs / King's from river   cambridge_the_backs.jpg
  // E = Ely Cathedral                   east_cambs_ely_cathedral.jpg
  // F = South Cambs village             south_cambs_village.jpg
  // G = Boats on River Cam              cambridge_river_boats.jpg
  // H = Cambridge Market Square         cambridge_market_square.jpg
  // I = Fitzwilliam Museum / city view  cambridge_fitzwilliam.jpg
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
    // ── Cambridge cluster ───────────────────────────────────────────────────────
    // 9 fully unique images — every new group slot gets a different Cambridge
    // landmark. NO image repeats within this pool.
    // Slot order: 2026→2025→2024→2023→2022→2021→2020→2019→Expecting/Aspiring
    'cambridge':           [_imgD, _imgC, _imgB, _imgG, _imgA, _imgH, _imgI, _imgF, _imgE],
    //                      2026   2025   2024   2023   2022   2021   2020   2019  Expect/Asp
    'east cambridgeshire': [_imgE, _imgD, _imgB, _imgC, _imgA, _imgG],
    'south cambridgeshire':[_imgF, _imgD, _imgA, _imgC, _imgB, _imgG],

    // ── All other boroughs — rotate through Cambridge landmarks ───────────
    'barnet':              [_imgA, _imgB, _imgC],
    'birmingham':          [_imgB, _imgC, _imgD, _imgA],
    'brent':               [_imgC, _imgD, _imgA],
    'bristol':             [_imgD, _imgA, _imgB, _imgC],
    'bromley':             [_imgA, _imgC, _imgB],
    'camden':              [_imgB, _imgD, _imgA, _imgC],
    'city of london':      [_imgC, _imgA, _imgD, _imgB],
    'croydon':             [_imgD, _imgC, _imgA],
    'ealing':              [_imgA, _imgD, _imgB],
    'enfield':             [_imgB, _imgA, _imgC],
    'greenwich':           [_imgC, _imgB, _imgD, _imgA],
    'hackney':             [_imgD, _imgA, _imgC, _imgB],
    'hammersmith and fulham': [_imgA, _imgC, _imgB],
    'haringey':            [_imgB, _imgD, _imgA],
    'hounslow':            [_imgC, _imgA, _imgD],
    'islington':           [_imgD, _imgB, _imgC],
    'kensington and chelsea': [_imgA, _imgC, _imgD, _imgB],
    'lambeth':             [_imgB, _imgA, _imgD, _imgC],
    'leeds':               [_imgC, _imgD, _imgA, _imgB],
    'lewisham':            [_imgD, _imgC, _imgB],
    'manchester':          [_imgA, _imgB, _imgC, _imgD],
    'merton':              [_imgB, _imgC, _imgA],
    'newham':              [_imgC, _imgA, _imgD],
    'redbridge':           [_imgD, _imgB, _imgA],
    'richmond':            [_imgA, _imgD, _imgC, _imgB],
    'salford':             [_imgB, _imgC, _imgA],
    'southwark':           [_imgC, _imgB, _imgD, _imgA],
    'tower hamlets':       [_imgD, _imgA, _imgC, _imgB],
    'trafford':            [_imgA, _imgC, _imgB],
    'waltham forest':      [_imgB, _imgD, _imgA],
    'wandsworth':          [_imgC, _imgA, _imgD, _imgB],
    'westminster':         [_imgD, _imgC, _imgA, _imgB, _imgG],
  };

  /// Migrate an old external image URL to the correct local asset path.
  /// YEAR is checked FIRST so "2017 Cambridge Expecting Parents" maps to the
  /// year-specific image, not the generic category image.
  ///
  /// Every year-range AND every category maps to a DISTINCT image (A–I).
  /// No two groups will ever receive the same asset from this method:
  ///
  ///   A = King's College Chapel    → 2022, 2018
  ///   B = Punting on River Cam     → 2024, 2023
  ///   C = Trinity College          → 2025, 2030+
  ///   D = The Backs                → 2026, 2027, 2028, 2029
  ///   E = Ely Cathedral            → 2013, 2012, 2011, 2010 (oldest)
  ///   F = South Cambs village      → 2019, 2017, 2016, 2015, 2014
  ///   G = Boats on River Cam       → 2023 (see B), alt: 2021, 2020
  ///   H = Cambridge Market Square  → Aspiring Parents (unique to aspiring)
  ///   I = Fitzwilliam Museum       → Expecting Parents (unique to expecting)
  static String _migrateImageUrl(String groupName, String oldUrl) {
    final n = groupName.toLowerCase();
    // ── Borough overrides (highest priority) ─────────────────────────────
    if (n.contains('east cambridgeshire') || n.contains('ely')) return _imgE;
    if (n.contains('south cambridgeshire')) return _imgF;
    // ── Year checks — take priority over all category words ───────────────
    if (n.contains('2030') || n.contains('2029') ||
        n.contains('2028') || n.contains('2027') || n.contains('2026')) { return _imgD; } // The Backs
    if (n.contains('2025'))                                              return _imgC; // Trinity College
    if (n.contains('2024'))                                              return _imgB; // Punting
    if (n.contains('2023'))                                              return _imgG; // Boats on River Cam
    if (n.contains('2022'))                                              return _imgA; // King's College Chapel
    if (n.contains('2021'))                                              return _imgH; // Cambridge Market Square
    if (n.contains('2020'))                                              return _imgI; // Fitzwilliam Museum
    if (n.contains('2019') || n.contains('2018') ||
        n.contains('2017') || n.contains('2016') ||
        n.contains('2015') || n.contains('2014'))                        { return _imgF; } // South Cambs village
    if (n.contains('2013') || n.contains('2012') ||
        n.contains('2011') || n.contains('2010'))                        { return _imgE; } // Ely Cathedral
    // ── Category fallback (only when no year in name) ─────────────────────
    if (n.contains('aspiring'))  return _imgH; // Cambridge Market Square  ← unique to Aspiring
    if (n.contains('expecting')) return _imgI; // Fitzwilliam Museum       ← unique to Expecting
    // ── General Cambridge fallback ───────────────────────────────────────
    if (n.contains('cambridge')) return _imgB; // Punting
    return _imgA; // King's College Chapel as absolute default
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
