import 'package:flutter/foundation.dart';
import 'ai_knowledge_base_service.dart';
import 'ai_learning_engine_service.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// GEMINI SYSTEM PROMPT BUILDER  — ENRICHED V3, HYPERLOCAL EDITION
//
// The single orchestrator that assembles Gemini system prompts for EVERY
// AI service in Huddl.  It pulls together:
//   - Step 1: AiKnowledgeBaseService  (articles, milestones, community templates,
//             borough directories, hyperlocal rules, safety guardrails)
//             NOW with 40+ sources including Gingerbread, Parent Zone, Contact,
//             Adoption UK, Coram Family Lives, DaddiLife, and more
//   - Step 2: AiLearningEngineService (user signals, borough engagement stats,
//             global event preferences, topic affinities, maturity level)
//   - OnboardingDataService           (name, parent type, postcode, children,
//             stages of life, due date, family structure, support needs)
//   - PostcodeService                 (postcode \u2192 borough resolution)
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ HYPERLOCAL ARCHITECTURE — PROMPT FIRST PRINCIPLES                      │
// │                                                                        │
// │  1. EVERY prompt opens with HyperlocalRules for the user's borough.    │
// │  2. Borough-scoped features (Chat, DMs, Groups, Meetups, Marketplace,  │
// │     Matchmaker) MUST frame all suggestions within the user's borough.  │
// │  3. Events are the ONLY UK-wide feature — prompts for events include   │
// │     both the home borough AND any target borough the user explores.    │
// │  4. Borough local directory (parks, libraries, cafes, leisure centres) │
// │     is injected when the feature needs location-aware suggestions.     │
// │  5. Learning engine context is borough-partitioned: borough-only       │
// │     stats vs global event preferences.                                 │
// │  6. When a user has recently moved boroughs, a "new to borough" note   │
// │     is prepended so the AI is extra welcoming.                         │
// └──────────────────────────────────────────────────────────────────────────┘
//
// Service methods:
//   buildCopilotPrompt()        — General parenting AI assistant
//   buildMatchmakerPrompt()     — AI parent matcher (borough-only)
//   buildMarketplacePrompt()    — Listing generator / marketplace AI
//   buildGroupsMeetupsPrompt()  — Group & meetup AI suggestions
//   buildEventsPrompt()         — Event discovery / recommendation (UK-wide)
//   buildFeedNudgePrompt()      — Community feed nudge copywriter
//   buildChatSummariserPrompt() — Group/DM chat summariser
//   buildListingPrompt()        — AI marketplace listing generator
//   buildOffersPrompt()         — Deals & offers AI
//   buildEventRecommenderPrompt() — Personalised event recommendations
//   buildCustomPrompt()         — Flexible prompt for new features
//
// Each method returns a complete system prompt String ready to be passed to
// Gemini's system_instruction field.
// =============================================================================

/// The prompt scope for a feature — determines which data is injected.
enum PromptFeatureScope {
  /// Borough-restricted features: Chat, DMs, Groups, Meetups, Marketplace,
  /// Matchmaker.  All suggestions scoped to user's borough.
  boroughOnly,

  /// UK-wide features: Events only.  Suggestions can span any borough.
  ukWide,

  /// Hybrid: primarily borough-scoped but with awareness of other boroughs
  /// (e.g. Copilot which mostly talks about local things but can answer
  /// questions about events elsewhere).
  hybrid,
}

/// Configuration for what to include/exclude in a system prompt.
class PromptConfig {
  /// Which feature this prompt serves.
  final PromptFeatureScope scope;

  /// Include HyperlocalRules block.
  final bool includeHyperlocalRules;

  /// Include borough local directory (parks, libraries, etc.).
  final bool includeBoroughDirectory;

  /// Include knowledge articles relevant to user stage.
  final bool includeKnowledgeArticles;

  /// Include development milestones.
  final bool includeMilestones;

  /// Include vaccination reminders.
  final bool includeVaccinations;

  /// Include seasonal tips.
  final bool includeSeasonalTips;

  /// Include safety recalls.
  final bool includeSafetyRecalls;

  /// Include safety guardrails.
  final bool includeSafetyGuardrails;

  /// Include empathy/tone instructions.
  final bool includeEmpathy;

  /// Include learning engine behavioural context.
  final bool includeLearningProfile;

  /// Include recent activity summary from learning engine.
  final bool includeRecentActivity;

  /// Include marketplace-specific knowledge.
  final bool includeMarketplaceKnowledge;

  /// Include groups/meetups-specific knowledge.
  final bool includeGroupsMeetupsKnowledge;

  /// Include events-specific knowledge.
  final bool includeEventsKnowledge;

  /// Include community templates.
  final bool includeCommunityTemplates;

  /// Max number of knowledge articles to include.
  final int maxArticles;

  /// Knowledge category filter (null = user-stage-based).
  final KnowledgeCategory? knowledgeCategory;

  /// Target borough for cross-borough features (events).
  final String? targetBorough;

  const PromptConfig({
    this.scope = PromptFeatureScope.boroughOnly,
    this.includeHyperlocalRules = true,
    this.includeBoroughDirectory = true,
    this.includeKnowledgeArticles = true,
    this.includeMilestones = true,
    this.includeVaccinations = false,
    this.includeSeasonalTips = true,
    this.includeSafetyRecalls = false,
    this.includeSafetyGuardrails = true,
    this.includeEmpathy = true,
    this.includeLearningProfile = true,
    this.includeRecentActivity = false,
    this.includeMarketplaceKnowledge = false,
    this.includeGroupsMeetupsKnowledge = false,
    this.includeEventsKnowledge = false,
    this.includeCommunityTemplates = false,
    this.maxArticles = 5,
    this.knowledgeCategory,
    this.targetBorough,
  });
}

// =============================================================================
// MAIN BUILDER
// =============================================================================

class GeminiSystemPromptBuilder {
  static final GeminiSystemPromptBuilder _instance =
      GeminiSystemPromptBuilder._internal();
  factory GeminiSystemPromptBuilder() => _instance;
  GeminiSystemPromptBuilder._internal();

  // ── Dependencies ─────────────────────────────────────────────────────────
  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final AiLearningEngineService _learningEngine = AiLearningEngineService();
  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  // ── Cached user context (refreshed each build) ───────────────────────────
  String? _currentBorough;
  String? _userName;
  String? _parentType;
  List<String> _stagesOfLife = [];
  String? _dueDate;
  List<Map<String, String>> _children = [];
  bool _isInitialized = false;

  // ═════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _knowledgeBase.initialize();
    await _learningEngine.initialize();
    _refreshUserContext();
    _isInitialized = true;
    _log('Initialised with borough: $_currentBorough');
  }

  void _refreshUserContext() {
    _userName = _onboarding.name;
    _parentType = _onboarding.parentType;
    _stagesOfLife = _onboarding.stagesOfLife;
    _dueDate = _onboarding.dueDate;
    _children = _onboarding.children;

    final pc = _onboarding.postcode;
    if (pc != null) {
      _currentBorough = _postcode.getBoroughFromPostcode(pc);
    }
  }

  /// Call before building any prompt to ensure user context is fresh.
  void refresh() => _refreshUserContext();

  /// The user's resolved borough name (or null if unknown).
  String? get userBorough => _currentBorough;

  // ═════════════════════════════════════════════════════════════════════════
  // ──── FEATURE-SPECIFIC PROMPT BUILDERS ────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  // ────────────────────────────────────────────────────────────────────────
  // 1. COPILOT — General parenting AI assistant (hybrid scope)
  // ────────────────────────────────────────────────────────────────────────

  String buildCopilotPrompt() {
    _refreshUserContext();
    final buf = StringBuffer();

    // ── Identity & role ──────────────────────────────────────────────────
    buf.writeln(
        'You are the huddl AI Parenting Copilot \u2014 a warm, knowledgeable, '
        'and supportive AI assistant built into the huddl app. huddl is a '
        'HYPERLOCAL community platform for parents in the UK.\n');

    buf.writeln('YOUR PERSONALITY:');
    buf.writeln(
        '- Warm, friendly, and empathetic \u2014 like talking to a knowledgeable friend');
    buf.writeln(
        '- Supportive and non-judgmental \u2014 every parenting style is valid');
    buf.writeln('- Concise but thorough \u2014 give actionable advice');
    buf.writeln(
        '- Use a casual British English tone (e.g. "nursery" not "daycare", '
        '"pushchair" not "stroller", "nappy" not "diaper")');
    buf.writeln(
        '- Use bullet points and bold text (**text**) to structure responses');
    buf.writeln(
        '- Keep responses focused and helpful, typically 3-6 paragraphs');
    buf.writeln();

    // ── Hyperlocal rules (ALWAYS first) ──────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Borough local directory ──────────────────────────────────────────
    if (_currentBorough != null) {
      final dir = _knowledgeBase.getBoroughDirectory(_currentBorough!);
      if (dir != null) {
        buf.writeln(dir.toPromptContext());
        buf.writeln();
      }
    }

    // ── Knowledge context ────────────────────────────────────────────────
    final childAge = _getFirstChildAgeMonths();
    buf.writeln(_knowledgeBase.buildKnowledgeContext(
      childAgeMonths: childAge,
      maxArticles: 5,
      includeHyperlocalRules: false, // already included above
    ));

    // ── Learning engine context ──────────────────────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    // ── Empathy & tone ───────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildEmpathyInstructions());

    // ── Safety guardrails ────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildSafetyGuardrails());

    // ── Huddl features (hyperlocal-aware) ────────────────────────────────
    buf.writeln(_buildHuddlFeaturesBlock());

    // ── Borough change context ───────────────────────────────────────────
    buf.writeln(_buildBoroughChangeBlock());

    // ── Response guidelines ──────────────────────────────────────────────
    buf.writeln('RESPONSE GUIDELINES:');
    if (_currentBorough != null) {
      buf.writeln(
          '- Reference the user\'s borough ($_currentBorough) when relevant.');
      buf.writeln(
          '- For groups, meetups, marketplace, chat: ONLY suggest $_currentBorough options.');
      buf.writeln(
          '- For events: Can suggest events in $_currentBorough AND other boroughs.');
    }
    buf.writeln(
        '- Suggest relevant huddl app features naturally when they fit the conversation.');
    buf.writeln(
        '- Keep responses grounded and practical, avoiding overly generic advice.');
    buf.writeln(
        '- If you do not know something specific, say so honestly rather than making up data.');
    buf.writeln();

    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 2. MATCHMAKER — AI parent matcher (BOROUGH-ONLY)
  // ────────────────────────────────────────────────────────────────────────

  String buildMatchmakerPrompt({
    required String matchProfileSummary,
    String? matchBorough,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    buf.writeln(
        'You are the huddl AI Matchmaker for a UK parents\' HYPERLOCAL '
        'community app. You help parents in the SAME BOROUGH connect with '
        'each other based on compatibility.\n');

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    buf.writeln('MATCHMAKER RULES (CRITICAL):');
    buf.writeln(
        '- You can ONLY match parents who are BOTH in $borough.');
    buf.writeln(
        '- NEVER suggest meeting parents from a different borough.');
    buf.writeln(
        '- All suggested meeting locations MUST be within $borough.');
    buf.writeln(
        '- Frame all meetup ideas around $borough venues and amenities.');
    buf.writeln();

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Match profile ────────────────────────────────────────────────────
    buf.writeln('MATCH PROFILE:');
    buf.writeln(matchProfileSummary);
    if (matchBorough != null) {
      buf.writeln('Match\'s borough: $matchBorough');
      if (matchBorough != _currentBorough) {
        buf.writeln(
            'WARNING: This match is in a DIFFERENT borough ($matchBorough). '
            'Cross-borough matching is NOT allowed. Suggest the user look '
            'for matches within $borough instead.');
      }
    }
    buf.writeln();

    // ── Borough directory ────────────────────────────────────────────────
    if (_currentBorough != null) {
      final dir = _knowledgeBase.getBoroughDirectory(_currentBorough!);
      if (dir != null) {
        buf.writeln('MEETING VENUES IN $borough:');
        buf.writeln(dir.toPromptContext());
        buf.writeln();
      }
    }

    // ── Learning context ─────────────────────────────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    // ── Empathy ──────────────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildEmpathyInstructions());

    // ── Output instructions ──────────────────────────────────────────────
    buf.writeln('OUTPUT INSTRUCTIONS:');
    buf.writeln(
        '- Generate a warm, personalised meetup suggestion for these two parents in $borough.');
    buf.writeln(
        '- Suggest a specific venue or location WITHIN $borough.');
    buf.writeln(
        '- Include a suggested activity appropriate for their children\'s ages.');
    buf.writeln(
        '- Explain in 2-3 sentences why they might get along well.');
    buf.writeln(
        '- Keep the tone warm, encouraging, and casual British English.');
    buf.writeln();

    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 3. MARKETPLACE / LISTING GENERATOR — (BOROUGH-ONLY)
  // ────────────────────────────────────────────────────────────────────────

  String buildMarketplacePrompt({
    String? itemDescription,
    bool isListingGeneration = false,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    if (isListingGeneration) {
      buf.writeln(
          'You are a marketplace listing expert for huddl Market, a HYPERLOCAL '
          'buy & sell platform for parents in $borough.\n');
    } else {
      buf.writeln(
          'You are a marketplace assistant for huddl Market, a HYPERLOCAL '
          'buy & sell platform for parents in $borough.\n');
    }

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    // ── Marketplace knowledge (borough-scoped) ───────────────────────────
    buf.writeln(_knowledgeBase.buildMarketplaceContext());

    // ── Safety recalls ───────────────────────────────────────────────────
    final recalls = _knowledgeBase.safetyRecalls;
    if (recalls.isNotEmpty) {
      buf.writeln('KNOWN SAFETY RECALLS (warn seller/buyer if relevant):');
      for (final r in recalls) {
        buf.writeln('- ${r.productName}: ${r.reason} (${r.dateIssued})');
      }
      buf.writeln();
    }

    // ── Borough directory for meetup/collection suggestions ──────────────
    if (_currentBorough != null) {
      final dir = _knowledgeBase.getBoroughDirectory(_currentBorough!);
      if (dir != null) {
        buf.writeln('SAFE COLLECTION POINTS IN $borough:');
        for (final cafe in dir.localCafes) {
          buf.writeln('- $cafe');
        }
        for (final hall in dir.localCommunityHalls) {
          buf.writeln('- $hall');
        }
        buf.writeln();
      }
    }

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Learning context ─────────────────────────────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    if (isListingGeneration && itemDescription != null) {
      buf.writeln('ITEM TO LIST:');
      buf.writeln(itemDescription);
      buf.writeln();
      buf.writeln('OUTPUT INSTRUCTIONS:');
      buf.writeln('Return a JSON object with:');
      buf.writeln('  "title": catchy title (max 60 chars)');
      buf.writeln('  "description": detailed description (3-5 sentences)');
      buf.writeln('  "suggestedPrice": price in GBP (number)');
      buf.writeln('  "category": one of [clothing, toys, equipment, books, feeding, bathing, nursery, travel, other]');
      buf.writeln('  "condition": one of [brand_new, like_new, good, fair]');
      buf.writeln('  "ageRange": suggested age range (e.g. "0-6 months")');
      buf.writeln(
          '  "safetyNote": any safety warnings or null if safe');
      buf.writeln();
      buf.writeln(
          'IMPORTANT: Frame everything for $borough parents. '
          'Mention that collection is easy because buyer and seller are both in $borough.');
    }

    // ── Safety guardrails ────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildSafetyGuardrails());

    return buf.toString();
  }

  /// Convenience alias for listing generation.
  String buildListingPrompt({required String itemDescription}) =>
      buildMarketplacePrompt(
        itemDescription: itemDescription,
        isListingGeneration: true,
      );

  // ────────────────────────────────────────────────────────────────────────
  // 4. GROUPS & MEETUPS — (BOROUGH-ONLY)
  // ────────────────────────────────────────────────────────────────────────

  String buildGroupsMeetupsPrompt({
    String? context,
    bool isMeetupPlanning = false,
    bool isGroupSuggestion = false,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    if (isMeetupPlanning) {
      buf.writeln(
          'You are a meetup planning assistant for huddl, a HYPERLOCAL '
          'parents\' community in $borough.\n');
    } else if (isGroupSuggestion) {
      buf.writeln(
          'You are a group recommendation engine for huddl, a HYPERLOCAL '
          'parents\' community in $borough.\n');
    } else {
      buf.writeln(
          'You are a community assistant for huddl, a HYPERLOCAL '
          'parents\' community in $borough.\n');
    }

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    // ── Groups/meetups knowledge ─────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildGroupsMeetupsContext());

    // ── Community templates (for group suggestions) ──────────────────────
    if (isGroupSuggestion && _currentBorough != null) {
      final templates = _knowledgeBase.getTemplatesForUserBorough(
        audience: _getAudienceFromStage(),
      );
      final boroughTemplates =
          templates.where((t) => t.scope == ContentScope.boroughOnly).toList();
      if (boroughTemplates.isNotEmpty) {
        buf.writeln('SUGGESTED GROUP TEMPLATES FOR $borough:');
        for (final t in boroughTemplates) {
          final desc = t.description.replaceAll('{borough}', borough);
          buf.writeln('- ${t.name}: $desc');
          buf.writeln(
              '  Format: ${t.format} | Frequency: ${t.suggestedFrequency}');
        }
        buf.writeln();
      }
    }

    // ── Borough directory ────────────────────────────────────────────────
    if (_currentBorough != null) {
      final dir = _knowledgeBase.getBoroughDirectory(_currentBorough!);
      if (dir != null) {
        buf.writeln('VENUES IN $borough FOR GROUPS & MEETUPS:');
        buf.writeln(dir.toPromptContext());
        buf.writeln();
      }
    }

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Learning context ─────────────────────────────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    // ── Seasonal context ─────────────────────────────────────────────────
    final seasonal = _knowledgeBase.getCurrentSeasonalTips();
    if (seasonal.isNotEmpty && _currentBorough != null) {
      buf.writeln('SEASONAL IDEAS FOR $borough:');
      for (final tip in seasonal) {
        buf.writeln(
            '- ${tip.title}: ${tip.renderForBorough(borough)}');
      }
      buf.writeln();
    }

    // ── Empathy ──────────────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildEmpathyInstructions());

    if (context != null) {
      buf.writeln('ADDITIONAL CONTEXT:');
      buf.writeln(context);
      buf.writeln();
    }

    // ── Borough change ───────────────────────────────────────────────────
    buf.writeln(_buildBoroughChangeBlock());

    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 5. EVENTS — (UK-WIDE, the ONLY cross-borough feature)
  // ────────────────────────────────────────────────────────────────────────

  String buildEventsPrompt({
    String? targetBorough,
    bool isEventCreation = false,
    bool isEventDiscovery = false,
    String? additionalContext,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final homeBorough = _currentBorough ?? 'your area';
    final viewingBorough = targetBorough ?? homeBorough;

    if (isEventCreation) {
      buf.writeln(
          'You are a community event copywriter for huddl, a UK parents\' '
          'community app. You are helping create an event.\n');
    } else if (isEventDiscovery) {
      buf.writeln(
          'You are a family event discovery assistant for huddl, a UK parents\' '
          'community app. You help parents find great family events.\n');
    } else {
      buf.writeln(
          'You are an events assistant for huddl, a UK parents\' '
          'community app.\n');
    }

    // ── Hyperlocal rules (even for events, so the AI understands context) ─
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    // ── Events-specific knowledge ────────────────────────────────────────
    buf.writeln(
        _knowledgeBase.buildEventsContext(targetBorough: targetBorough));

    // ── Cross-borough awareness ──────────────────────────────────────────
    buf.writeln('EVENT BROWSING CONTEXT:');
    buf.writeln('- User\'s HOME borough: $homeBorough');
    if (targetBorough != null && targetBorough != _currentBorough) {
      buf.writeln(
          '- User is BROWSING events in: $targetBorough (different from home)');
      buf.writeln(
          '- This is perfectly normal \u2014 events are UK-wide. The user may '
          'be travelling to $targetBorough or planning a day out.');
    } else {
      buf.writeln('- Currently viewing events in their home borough.');
    }
    buf.writeln(
        '- REMINDER: Events are the ONLY feature that crosses borough boundaries.');
    buf.writeln(
        '- All OTHER features (groups, meetups, marketplace, chat, matchmaker) '
        'are STRICTLY $homeBorough only.');
    buf.writeln();

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Learning engine: global event preferences ────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    // ── Seasonal context ─────────────────────────────────────────────────
    final seasonal = _knowledgeBase.getCurrentSeasonalTips();
    if (seasonal.isNotEmpty) {
      buf.writeln('SEASONAL EVENT IDEAS:');
      for (final tip in seasonal) {
        final body = tip.renderForBorough(viewingBorough);
        buf.writeln('- ${tip.title}: $body');
      }
      buf.writeln();
    }

    // ── Empathy ──────────────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildEmpathyInstructions());

    if (additionalContext != null) {
      buf.writeln('ADDITIONAL CONTEXT:');
      buf.writeln(additionalContext);
      buf.writeln();
    }

    if (isEventCreation) {
      buf.writeln('OUTPUT INSTRUCTIONS:');
      buf.writeln('Return a JSON object with:');
      buf.writeln('  "title": engaging event title');
      buf.writeln('  "description": warm, detailed description (4-6 sentences)');
      buf.writeln('  "suggestedTags": list of relevant tags');
      buf.writeln(
          '  "ageRangeNote": which ages this event suits');
      buf.writeln(
          '  "whatToBring": practical list of items parents should bring');
      buf.writeln(
          'Use British English. Frame the event for families and parents.');
      buf.writeln();
    }

    return buf.toString();
  }

  /// Convenience for event recommender AI.
  String buildEventRecommenderPrompt({
    String? targetBorough,
    String? eventsSummary,
  }) {
    final base = buildEventsPrompt(
      targetBorough: targetBorough,
      isEventDiscovery: true,
    );
    final buf = StringBuffer(base);
    if (eventsSummary != null) {
      buf.writeln('AVAILABLE EVENTS:');
      buf.writeln(eventsSummary);
      buf.writeln();
      buf.writeln(
          'Rank the above events by relevance for this parent. Consider '
          'their children\'s ages, interests from the learning profile, '
          'and borough proximity.');
    }
    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 6. FEED NUDGE — Community feed nudge copywriter (BOROUGH-ONLY context)
  // ────────────────────────────────────────────────────────────────────────

  String buildFeedNudgePrompt({
    required String nudgeType,
    String? feedContext,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    buf.writeln(
        'You are a notification copywriter for huddl, a UK parents\' '
        'HYPERLOCAL community app. Generate short, warm, personalised nudge '
        'card text.\n');

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    buf.writeln('NUDGE CONTEXT:');
    buf.writeln('- Nudge type: $nudgeType');
    buf.writeln('- Borough: $borough');
    if (feedContext != null) {
      buf.writeln('- Additional context: $feedContext');
    }
    buf.writeln();

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Learning context ─────────────────────────────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    // ── Empathy ──────────────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildEmpathyInstructions());

    buf.writeln('OUTPUT RULES:');
    buf.writeln('- Max 2 sentences, warm and encouraging.');
    buf.writeln('- Use British English. Mention $borough by name if natural.');
    buf.writeln(
        '- For borough-scoped features (groups, meetups, market, chat): '
        'frame within $borough.');
    buf.writeln(
        '- For events: can reference other boroughs if the nudge is about travel.');
    buf.writeln(
        '- Include a clear call-to-action (e.g. "Join the meetup", "Check it out").');
    buf.writeln();

    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 7. CHAT SUMMARISER — Group/DM chat summary (BOROUGH-ONLY context)
  // ────────────────────────────────────────────────────────────────────────

  String buildChatSummariserPrompt({
    required String chatType,
    String? groupName,
    int messageCount = 0,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    buf.writeln(
        'You are a chat summariser for huddl, a UK parents\' HYPERLOCAL '
        'community app based in $borough.\n');

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    buf.writeln('CHAT CONTEXT:');
    buf.writeln('- Type: $chatType');
    buf.writeln('- Borough: $borough');
    if (groupName != null) {
      buf.writeln('- Group: $groupName');
    }
    if (messageCount > 0) {
      buf.writeln('- Messages to summarise: $messageCount');
    }
    buf.writeln(
        '- All participants are parents in $borough (same-borough requirement).');
    buf.writeln();

    buf.writeln('SUMMARISATION RULES:');
    buf.writeln('- Create a concise, warm summary of the conversation.');
    buf.writeln('- Highlight key topics, decisions, and action items.');
    buf.writeln(
        '- Note any safety concerns (direct to NHS/GP/999 where relevant).');
    buf.writeln(
        '- If any meetups or marketplace items were mentioned, note the '
        'borough context ($borough).');
    buf.writeln('- Use British English. Be warm and supportive in tone.');
    buf.writeln(
        '- Output 3-5 bullet points, then a 1-sentence overall summary.');
    buf.writeln();

    // ── Safety guardrails ────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildSafetyGuardrails());

    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 8. OFFERS — Deals & offers AI (BOROUGH-AWARE)
  // ────────────────────────────────────────────────────────────────────────

  String buildOffersPrompt({
    required String offerContext,
    bool isPersonalisation = false,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    if (isPersonalisation) {
      buf.writeln(
          'You are a deals personalisation engine for huddl, a UK parents\' '
          'HYPERLOCAL community app. Rank and personalise offers for a parent '
          'in $borough.\n');
    } else {
      buf.writeln(
          'You are a deals content writer for huddl, a UK parents\' '
          'HYPERLOCAL community app in $borough.\n');
    }

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (_currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    buf.writeln('OFFER CONTEXT:');
    buf.writeln(offerContext);
    buf.writeln();

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Learning context ─────────────────────────────────────────────────
    buf.writeln(_learningEngine.buildPromptContext());

    // ── Empathy ──────────────────────────────────────────────────────────
    buf.writeln(_knowledgeBase.buildEmpathyInstructions());

    buf.writeln('OUTPUT RULES:');
    buf.writeln(
        '- Prioritise offers relevant to parents with children at the user\'s '
        'stage.');
    buf.writeln(
        '- Local offers (stores/services in $borough) should be ranked higher.');
    buf.writeln(
        '- National/online offers are acceptable but local > national.');
    buf.writeln('- Use warm, concise British English.');
    buf.writeln();

    return buf.toString();
  }

  // ────────────────────────────────────────────────────────────────────────
  // 9. CUSTOM PROMPT — Flexible builder for new/experimental features
  // ────────────────────────────────────────────────────────────────────────

  /// Build a fully customisable prompt with granular control over sections.
  String buildCustomPrompt({
    required String role,
    required String featureName,
    required PromptConfig config,
    String? additionalInstructions,
  }) {
    _refreshUserContext();
    final buf = StringBuffer();
    final borough = _currentBorough ?? 'your area';

    // ── Role declaration ─────────────────────────────────────────────────
    buf.writeln(role);
    buf.writeln();

    // ── Hyperlocal rules ─────────────────────────────────────────────────
    if (config.includeHyperlocalRules && _currentBorough != null) {
      buf.writeln(HyperlocalRules.toPromptContext(_currentBorough!));
      buf.writeln();
    }

    // ── User identity ────────────────────────────────────────────────────
    buf.writeln(_buildUserIdentityBlock());

    // ── Borough directory ────────────────────────────────────────────────
    if (config.includeBoroughDirectory && _currentBorough != null) {
      final dir = _knowledgeBase.getBoroughDirectory(_currentBorough!);
      if (dir != null) {
        buf.writeln(dir.toPromptContext());
        buf.writeln();
      }
    }

    // ── Knowledge articles ───────────────────────────────────────────────
    if (config.includeKnowledgeArticles) {
      buf.writeln(_knowledgeBase.buildKnowledgeContext(
        category: config.knowledgeCategory,
        childAgeMonths:
            config.includeMilestones ? _getFirstChildAgeMonths() : null,
        maxArticles: config.maxArticles,
        includeHyperlocalRules: false,
        overrideBorough: config.targetBorough,
      ));
    }

    // ── Feature-specific knowledge blocks ────────────────────────────────
    if (config.includeMarketplaceKnowledge) {
      buf.writeln(_knowledgeBase.buildMarketplaceContext());
    }
    if (config.includeGroupsMeetupsKnowledge) {
      buf.writeln(_knowledgeBase.buildGroupsMeetupsContext());
    }
    if (config.includeEventsKnowledge) {
      buf.writeln(
          _knowledgeBase.buildEventsContext(targetBorough: config.targetBorough));
    }

    // ── Community templates ──────────────────────────────────────────────
    if (config.includeCommunityTemplates) {
      final templates = _knowledgeBase.getTemplatesForUserBorough(
        audience: _getAudienceFromStage(),
      );
      if (templates.isNotEmpty) {
        buf.writeln('COMMUNITY TEMPLATES:');
        for (final t in templates) {
          final desc = t.description.replaceAll('{borough}', borough);
          buf.writeln('- ${t.name}: $desc (scope: ${t.scope.name})');
        }
        buf.writeln();
      }
    }

    // ── Safety recalls ───────────────────────────────────────────────────
    if (config.includeSafetyRecalls) {
      final recalls = _knowledgeBase.safetyRecalls;
      if (recalls.isNotEmpty) {
        buf.writeln('SAFETY RECALLS:');
        for (final r in recalls) {
          buf.writeln('- ${r.productName}: ${r.reason}');
        }
        buf.writeln();
      }
    }

    // ── Seasonal tips ────────────────────────────────────────────────────
    if (config.includeSeasonalTips) {
      final seasonal = _knowledgeBase.getCurrentSeasonalTips();
      if (seasonal.isNotEmpty) {
        buf.writeln('SEASONAL TIPS:');
        for (final tip in seasonal) {
          buf.writeln(
              '- ${tip.title}: ${tip.renderForBorough(borough)}');
        }
        buf.writeln();
      }
    }

    // ── Learning profile ─────────────────────────────────────────────────
    if (config.includeLearningProfile) {
      buf.writeln(_learningEngine.buildPromptContext());
    }

    // ── Recent activity ──────────────────────────────────────────────────
    if (config.includeRecentActivity) {
      buf.writeln(_learningEngine.recentActivitySummary());
      buf.writeln();
    }

    // ── Empathy ──────────────────────────────────────────────────────────
    if (config.includeEmpathy) {
      buf.writeln(_knowledgeBase.buildEmpathyInstructions());
    }

    // ── Safety guardrails ────────────────────────────────────────────────
    if (config.includeSafetyGuardrails) {
      buf.writeln(_knowledgeBase.buildSafetyGuardrails());
    }

    // ── Borough change ───────────────────────────────────────────────────
    buf.writeln(_buildBoroughChangeBlock());

    // ── Additional instructions ──────────────────────────────────────────
    if (additionalInstructions != null) {
      buf.writeln(additionalInstructions);
      buf.writeln();
    }

    return buf.toString();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ──── SHARED PROMPT BUILDING BLOCKS ────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  /// Build the user identity block (name, parent type, borough, children, family structure).
  String _buildUserIdentityBlock() {
    final buf = StringBuffer();
    buf.writeln('USER CONTEXT:');
    if (_userName != null) {
      buf.writeln('- Name: $_userName');
    }
    if (_parentType != null) {
      buf.writeln('- Parent type: $_parentType');
    }
    if (_currentBorough != null) {
      buf.writeln('- Borough: $_currentBorough, UK');
    }
    if (_stagesOfLife.isNotEmpty) {
      buf.writeln('- Life stage: ${_stagesOfLife.join(", ")}');
    }
    if (_dueDate != null) {
      buf.writeln('- Due date: $_dueDate');
    }
    for (int i = 0; i < _children.length; i++) {
      final child = _children[i];
      final name = child['name'] ?? 'Child ${i + 1}';
      final birthday = child['birthday'];
      if (birthday != null) {
        final months = _parseAgeMonths(birthday);
        if (months < 12) {
          buf.writeln('- Child: $name, $months months old');
        } else {
          buf.writeln(
              '- Child: $name, ${months ~/ 12} year(s) old');
        }
      } else {
        buf.writeln('- Child: $name');
      }
    }

    // ── Enriched V3: Family structure & support context ──────────────────
    final familyStructure = _onboarding.familyStructure;
    if (familyStructure != null) {
      final structureLabels = {
        'two_parent': 'Two-parent household',
        'single_parent': 'Single parent',
        'blended': 'Blended/stepfamily',
        'adoptive': 'Adoptive family',
        'foster': 'Foster family',
        'kinship': 'Kinship carer',
        'co_parenting': 'Co-parenting arrangement',
      };
      buf.writeln('- Family structure: ${structureLabels[familyStructure] ?? familyStructure}');
    }
    if (_onboarding.isSingleParent) {
      buf.writeln('- NOTE: Single parent \u2014 be mindful of financial and time pressures. '
          'Reference Gingerbread and single-parent-specific advice.');
    }
    if (_onboarding.isBlendedFamily) {
      buf.writeln('- NOTE: Blended family \u2014 be sensitive to stepparenting dynamics. '
          'Reference HappySteps blended family advice.');
    }
    if (_onboarding.isAdoptiveFoster) {
      buf.writeln('- NOTE: Adoptive/foster family \u2014 be aware of attachment and identity needs. '
          'Reference Adoption UK, CoramBAAF, and Home for Good (homeforgood.org.uk) support.');
    }
    if (_onboarding.hasSENChild) {
      buf.writeln('- NOTE: Family has a child with SEN/disability \u2014 reference Contact '
          '(381K families helped, 14,735 directly reached, 95% satisfied) '
          'and Family Fund. Be mindful of additional care responsibilities.');
    }
    if (_onboarding.isSeparating) {
      buf.writeln('- NOTE: Parent is separating/separated \u2014 be supportive and non-judgmental. '
          'Reference Coram Family Lives helpline and OnlyMums & Dads.');
    }
    if (_onboarding.hasTeens) {
      buf.writeln('- NOTE: Parent has teenagers \u2014 include teen-relevant advice from '
          'HuffPost Parents, BBC Bitesize, and Care for the Family\'s Raising Teens resources.');
    }
    final supportNeeds = _onboarding.supportNeeds;
    if (supportNeeds.isNotEmpty) {
      buf.writeln('- Support interests: ${supportNeeds.join(", ")}');
    }

    buf.writeln();
    return buf.toString();
  }

  /// Build huddl features block with hyperlocal framing.
  String _buildHuddlFeaturesBlock() {
    final borough = _currentBorough ?? 'your area';
    final buf = StringBuffer();
    buf.writeln(
        'HUDDL APP FEATURES (hyperlocal-aware \u2014 mention when relevant):');
    buf.writeln(
        '- **Groups**: Local community groups ONLY for parents in $borough');
    buf.writeln(
        '  \u2192 Includes: Bumps & Babies, Walk & Talk, Single Parents Connect, '
        'SEN Support, Blended Families, Digital Families, Green Parents, and more');
    buf.writeln(
        '- **Meetups**: Organise and join meetups ONLY with parents in $borough');
    buf.writeln(
        '- **Market**: Buy & sell baby/children items ONLY with parents in $borough');
    buf.writeln(
        '- **AI Matchmaker**: Matches compatible parents ONLY within $borough');
    buf.writeln(
        '- **DMs & Chat**: Message other parents ONLY within $borough');
    buf.writeln(
        '- **Events**: Browse family events across the WHOLE UK (the only cross-borough feature)');
    buf.writeln(
        '  \u2192 Includes: NCT sales, Adoption UK walks, CoramBAAF conferences, '
        'Family Fund events, Gingerbread comedy shows, Care for the Family tours');
    buf.writeln(
        '  \u2192 Parents travelling can see events at their destination');
    buf.writeln(
        '- **Tutorials**: Parenting resources from 40+ trusted UK sources');
    buf.writeln(
        '  \u2192 Includes: NHS, NCT, Coram Family Lives courses, BBC Bitesize, '
        'Parent Talk Podcast, DaddiLife, Parentkind webinars');
    buf.writeln();
    return buf.toString();
  }

  /// Build a contextual note if the user has recently changed borough.
  String _buildBoroughChangeBlock() {
    final profile = _learningEngine.profile;
    if (profile.hasRecentlyChangedBorough &&
        profile.previousBorough != null) {
      final prev = profile.previousBorough;
      final curr = _currentBorough ?? 'their new area';
      return 'BOROUGH CHANGE NOTE:\n'
          'This parent recently moved from $prev to $curr. They may be '
          'rebuilding their local network. Be extra welcoming and suggest '
          'ways to connect with $curr parents.\n\n';
    }
    return '';
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ──── QUERY HELPERS ────────────────────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  /// Get a map of all prompt sections for debugging.
  Map<String, String> debugPromptSections() {
    _refreshUserContext();
    return {
      'borough': _currentBorough ?? 'unknown',
      'hyperlocalRules': _currentBorough != null
          ? HyperlocalRules.toPromptContext(_currentBorough!)
          : 'No borough set',
      'userIdentity': _buildUserIdentityBlock(),
      'features': _buildHuddlFeaturesBlock(),
      'knowledgeContext': _knowledgeBase.buildKnowledgeContext(
        childAgeMonths: _getFirstChildAgeMonths(),
        includeHyperlocalRules: false,
      ),
      'learningContext': _learningEngine.buildPromptContext(),
      'empathy': _knowledgeBase.buildEmpathyInstructions(),
      'safetyGuardrails': _knowledgeBase.buildSafetyGuardrails(),
      'marketplaceContext': _knowledgeBase.buildMarketplaceContext(),
      'groupsMeetupsContext': _knowledgeBase.buildGroupsMeetupsContext(),
      'eventsContext': _knowledgeBase.buildEventsContext(),
      'boroughChange': _buildBoroughChangeBlock(),
    };
  }

  /// Estimate total token count for a prompt (rough: 1 token ~ 4 chars).
  int estimateTokens(String prompt) => (prompt.length / 4).ceil();

  /// Whether the user's borough is resolved.
  bool get hasBoroughContext => _currentBorough != null;

  /// Get the learning engine's maturity for the current borough.
  LearningMaturity get currentMaturity => _learningEngine.maturity;

  // ═════════════════════════════════════════════════════════════════════════
  // ──── PRIVATE HELPERS ──────────────────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  int? _getFirstChildAgeMonths() {
    if (_children.isEmpty) return null;
    final birthday = _children.first['birthday'];
    if (birthday == null) return null;
    return _parseAgeMonths(birthday);
  }

  String? _getAudienceFromStage() {
    if (_stagesOfLife.contains('expecting')) return 'expecting';
    if (_stagesOfLife.contains('newborn')) return 'new_parent';
    if (_stagesOfLife.contains('baby')) return 'new_parent';
    return 'all';
  }

  int _parseAgeMonths(String birthday) {
    try {
      final parts = birthday.split('/');
      if (parts.length >= 2) {
        final month = int.parse(parts[0]);
        final year = int.parse(parts.last);
        final now = DateTime.now();
        return ((now.difference(DateTime(year, month)).inDays) / 30.44)
            .round();
      }
    } catch (_) {}
    return 12;
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('\u{1F4DD} PromptBuilder: $message');
    }
  }
}
