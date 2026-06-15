import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import '../models/group.dart';
import 'ai_knowledge_base_service.dart';
import 'borough_scope_guard.dart';
import 'onboarding_data_service.dart';

// =============================================================================
// GROUP PREPOPULATION SERVICE  — PARENT CONCIERGE EDITION (Step 11)
//
// Pre-creates community groups in each borough based on:
//   1. NCT community templates from Knowledge Base (Bumps & Babies, Walk & Talk, etc.)
//   2. Netmums local activity patterns (weaning groups, nearly new sales)
//   3. Dadsnet dad-specific group templates
//   4. AI-generated descriptions personalised to the borough
//   5. Interest-based groups seeded from common UK parenting topics
//
// Source patterns:
//   - NCT (nct.org.uk) — Bumps & Babies, Walk & Talk, First Aid, Baby Cafe
//   - Netmums (netmums.com) — Local activity swaps, weaning groups, SEN support
//   - Dadsnet (dadsnet.com) — Dad & Kids Saturday Club, Expecting Dads Chat
//   - NHS/Bounty — Milestone groups, Sleep Support, Wellbeing circles
// =============================================================================

/// A single prepopulated group suggestion sourced from community templates.
class PrepopulatedGroup {
  final String templateName;
  final String generatedName;
  final String description;
  final String category;
  final String audience;
  final String source;
  final String suggestedFrequency;
  final String borough;

  const PrepopulatedGroup({
    required this.templateName,
    required this.generatedName,
    required this.description,
    required this.category,
    required this.audience,
    required this.source,
    required this.suggestedFrequency,
    required this.borough,
  });
}

class GroupPrepopulationService {
  static final GroupPrepopulationService _instance =
      GroupPrepopulationService._internal();
  factory GroupPrepopulationService() => _instance;
  GroupPrepopulationService._internal();

  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final OnboardingDataService _onboarding = OnboardingDataService();

  bool _isInitialized = false;
  final List<PrepopulatedGroup> _prepopulatedGroups = [];

  List<PrepopulatedGroup> get prepopulatedGroups =>
      List.unmodifiable(_prepopulatedGroups);

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _knowledgeBase.initialize();
    _isInitialized = true;
  }

  /// Single source of truth — delegates to BoroughScopeGuard.
  /// Returns '' when borough is unresolved (never a hardcoded fallback).
  String _getUserBorough() => BoroughScopeGuard().currentBorough ?? '';

  /// Generate prepopulated groups for a specific borough using community
  /// templates from the Knowledge Base.
  Future<List<PrepopulatedGroup>> generateGroupsForBorough(
      {String? borough}) async {
    await initialize();
    final targetBorough = borough ?? _getUserBorough();

    _prepopulatedGroups.clear();

    // 1. Get borough-scoped community templates from Knowledge Base
    final templates = _knowledgeBase.communityTemplates
        .where((t) => t.scope == ContentScope.boroughOnly)
        .toList();

    // 2. Generate groups from each template with borough context
    for (final template in templates) {
      final groupName = template.renderName(targetBorough);
      final description = template.renderDescription(targetBorough);

      _prepopulatedGroups.add(PrepopulatedGroup(
        templateName: template.name,
        generatedName: groupName,
        description: description,
        category: template.category,
        audience: template.audience,
        source: template.source,
        suggestedFrequency: template.suggestedFrequency,
        borough: targetBorough,
      ));
    }

    // 3. Try to generate AI-enhanced descriptions for top groups
    try {
      final aiDescriptions =
          await _getAiGroupDescriptions(targetBorough, templates.take(8).toList());
      if (aiDescriptions.isNotEmpty) {
        for (int i = 0;
            i < aiDescriptions.length && i < _prepopulatedGroups.length;
            i++) {
          final aiDesc = aiDescriptions[i];
          if (aiDesc.isNotEmpty) {
            _prepopulatedGroups[i] = PrepopulatedGroup(
              templateName: _prepopulatedGroups[i].templateName,
              generatedName: _prepopulatedGroups[i].generatedName,
              description: aiDesc,
              category: _prepopulatedGroups[i].category,
              audience: _prepopulatedGroups[i].audience,
              source: _prepopulatedGroups[i].source,
              suggestedFrequency: _prepopulatedGroups[i].suggestedFrequency,
              borough: targetBorough,
            );
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI group description generation error: $e');
      }
      // Fallback: use template descriptions (already set above)
    }

    _log('Generated ${_prepopulatedGroups.length} groups for $targetBorough');
    return List.unmodifiable(_prepopulatedGroups);
  }

  /// Create actual Group objects from prepopulated groups for the discover screen.
  List<Group> createDiscoverableGroups({String? borough}) {
    final targetBorough = borough ?? _getUserBorough();
    final rng = Random(targetBorough.hashCode);

    // Image pool for community groups
    const groupImages = [
      'https://images.pexels.com/photos/3807517/pexels-photo-3807517.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3933261/pexels-photo-3933261.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3807398/pexels-photo-3807398.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3807397/pexels-photo-3807397.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3662630/pexels-photo-3662630.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3807541/pexels-photo-3807541.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3807571/pexels-photo-3807571.jpeg?auto=compress&cs=tinysrgb&w=600',
      'https://images.pexels.com/photos/3807621/pexels-photo-3807621.jpeg?auto=compress&cs=tinysrgb&w=600',
    ];

    return _prepopulatedGroups.map((pg) {
      final id = 'disc_${pg.category}_${pg.borough.toLowerCase().replaceAll(' ', '_')}';
      return Group(
        id: id,
        name: pg.generatedName,
        description: pg.description,
        imageUrl: groupImages[rng.nextInt(groupImages.length)],
        memberCount: 0, // real count loaded from Firestore via FirestoreService.getMyGroups()
        category: pg.category,
        isJoined: false,
        targetAudience: [pg.audience],
        privacy: GroupPrivacy.public,
        creatorBorough: pg.borough,
      );
    }).toList();
  }

  /// Get the number of groups available for the user's borough.
  int get availableGroupCount => _prepopulatedGroups.length;

  /// Get groups filtered by audience type.
  List<PrepopulatedGroup> getGroupsForAudience(String audience) {
    return _prepopulatedGroups
        .where((g) => g.audience == audience || g.audience == 'all')
        .toList();
  }

  /// Get groups from a specific source (nct, netmums, dadsnet, nhs).
  List<PrepopulatedGroup> getGroupsBySource(String source) {
    return _prepopulatedGroups.where((g) => g.source == source).toList();
  }

  // ── AI Description Generation ──────────────────────────────────────────

  Future<List<String>> _getAiGroupDescriptions(
    String borough,
    List<CommunityTemplate> templates,
  ) async {
    final templateList = templates
        .map((t) => '{"name":"${t.name}","category":"${t.category}","audience":"${t.audience}"}')
        .join(',\n');

    final systemPrompt =
        'You are a UK community group copywriter for Huddl, a hyperlocal parenting app.\n'
        'Borough: $borough\n\n'
        'For each group template below, write a warm, inviting description (2-3 sentences) '
        'that:\n'
        '- Mentions $borough by name\n'
        '- Uses British English (mum, dad, nappy, nursery, etc.)\n'
        '- Sounds friendly and inclusive\n'
        '- Mentions the group frequency if relevant\n'
        '- Makes a new parent feel welcome\n\n'
        'Templates:\n[$templateList]\n\n'
        'RESPOND IN EXACT JSON FORMAT (no markdown, no backticks):\n'
        '["description for group 1", "description for group 2", ...]';

    final requestBody = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text':
                  'Generate descriptions for ${templates.length} community groups in $borough.'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.8,
        'topP': 0.9,
        'maxOutputTokens': 1024,
      },
    };

    try {
      final data = await AiApiHelper.generateContent(
          requestBody, timeout: const Duration(seconds: 15));
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          var text = (parts[0]['text'] as String? ?? '').trim();
          text = text.replaceAll(RegExp(r'^```json\s*'), '');
          text = text.replaceAll(RegExp(r'\s*```$'), '');
          text = text.trim();
          final parsed = jsonDecode(text) as List;
          return parsed.map((d) => d.toString()).toList();
        }
      }
    } catch (_) {}

    return [];
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('\u{1F4E6} GroupPrepopulation: $message');
    }
  }
}
