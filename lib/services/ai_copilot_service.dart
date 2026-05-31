
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'ai_api_helper.dart';
import 'gemini_system_prompt_builder.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';
import 'borough_ai_context.dart';

// =============================================================================
// AI PARENTING COPILOT SERVICE  — HYPERLOCAL EDITION
// Real conversational AI using Google Gemini API
// Cross-feature assistant that understands the parent's complete context
//
// System prompt is now assembled by GeminiSystemPromptBuilder (Step 3),
// which injects HyperlocalRules, borough directory, knowledge base,
// learning engine context, empathy & safety guardrails.
// =============================================================================

enum CopilotCategory {
  health,
  development,
  localServices,
  marketplace,
  social,
  general,
}

class CopilotMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final CopilotCategory? category;
  final List<CopilotAction>? actions;
  final String? sourceNote;
  final bool isError;

  CopilotMessage({
    required this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.category,
    this.actions,
    this.sourceNote,
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class CopilotAction {
  final String label;
  final String route;
  final String icon;
  final Map<String, dynamic> params;

  const CopilotAction({
    required this.label,
    required this.route,
    required this.icon,
    this.params = const {},
  });
}

class CopilotQuickAction {
  final String label;
  final String emoji;
  final String query;

  const CopilotQuickAction({
    required this.label,
    required this.emoji,
    required this.query,
  });
}

class AiCopilotService with BoroughAiContext {
  static final AiCopilotService _instance = AiCopilotService._internal();
  factory AiCopilotService() => _instance;
  AiCopilotService._internal();

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();
  final GeminiSystemPromptBuilder _promptBuilder =
      GeminiSystemPromptBuilder();

  final List<CopilotMessage> _messages = [];
  bool _isInitialized = false;
  // Starts true — assume online until a real API call proves otherwise.
  // This prevents the "Offline mode" badge flickering on screen open.
  bool _isApiOnline = true;

  // AI configuration — fine-tuned model via Vertex AI (primary),
  // Gemini AI Studio (fallback if Vertex AI credentials fail).
  /// Whether the last AI API call succeeded.
  bool get isOnline => _isApiOnline;

  // Conversation history for multi-turn chat
  final List<Map<String, dynamic>> _conversationHistory = [];

  List<CopilotMessage> get messages => List.unmodifiable(_messages);

  List<CopilotQuickAction> get contextualQuickActions {
    final actions = <CopilotQuickAction>[];
    final stages = _onboarding.stagesOfLife;
    final children = _onboarding.children;

    // Context-aware suggestions
    if (stages.contains('expecting')) {
      actions.addAll(const [
        CopilotQuickAction(
            label: 'Birth plan tips',
            emoji: '\u{1F4CB}',
            query: 'Help me create a birth plan'),
        CopilotQuickAction(
            label: 'Hospital bag',
            emoji: '\u{1F45C}',
            query: 'What should I pack in my hospital bag?'),
        CopilotQuickAction(
            label: 'Baby names',
            emoji: '\u{1F476}',
            query: 'Suggest some popular baby names'),
      ]);
    }

    if (children.isNotEmpty) {
      final birthday = children.first['birthday'];
      if (birthday != null) {
        final ageMonths = _parseAgeMonths(birthday);
        if (ageMonths < 6) {
          actions.addAll(const [
            CopilotQuickAction(
                label: 'Sleep schedule',
                emoji: '\u{1F634}',
                query: 'What sleep schedule is best for a newborn?'),
            CopilotQuickAction(
                label: 'Feeding guide',
                emoji: '\u{1F37C}',
                query: 'How often should I feed my baby?'),
          ]);
        } else if (ageMonths < 12) {
          actions.addAll(const [
            CopilotQuickAction(
                label: 'Weaning tips',
                emoji: '\u{1F34E}',
                query: 'How do I start weaning my baby?'),
            CopilotQuickAction(
                label: 'Development milestones',
                emoji: '\u{1F3C6}',
                query:
                    'What milestones should my baby be hitting?'),
          ]);
        } else if (ageMonths < 24) {
          actions.addAll(const [
            CopilotQuickAction(
                label: 'Toddler tantrums',
                emoji: '\u{1F62D}',
                query: 'How do I handle toddler tantrums?'),
            CopilotQuickAction(
                label: 'Nursery options',
                emoji: '\u{1F3EB}',
                query: 'Find nurseries near me'),
          ]);
        } else {
          actions.addAll(const [
            CopilotQuickAction(
                label: 'School readiness',
                emoji: '\u{1F4DA}',
                query: 'How do I prepare my child for school?'),
            CopilotQuickAction(
                label: 'Activities nearby',
                emoji: '\u{1F3A8}',
                query:
                    'What activities are available for kids near me?'),
          ]);
        }
      }
    }

    // Universal actions
    actions.addAll(const [
      CopilotQuickAction(
          label: 'Sell something',
          emoji: '\u{1F4F8}',
          query: 'Help me sell an item on Market'),
      CopilotQuickAction(
          label: 'Plan a meetup',
          emoji: '\u{1F91D}',
          query: 'Help me plan a meetup with local parents'),
    ]);

    return actions;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _promptBuilder.initialize();
    // Do NOT pre-validate credentials here — doing so makes a network round-
    // trip that (a) slows startup and (b) can poison _isApiOnline=false before
    // the user sends any message, showing a permanent "Offline" badge even
    // when the AI APIs are reachable.
    // Instead, _isApiOnline is updated by the result of each real sendMessage
    // call so it reflects actual live status.
    _isInitialized = true;
    if (kDebugMode) {
      if (kDebugMode) debugPrint('AiCopilot: initialized (online assumed until first call)');
    }
  }

  void clearConversation() {
    _messages.clear();
    _conversationHistory.clear();
  }

  /// Process a user message and generate an AI response.
  ///
  /// §2C: Primary path → `huddlCopilotChat` Cloud Function (Claude Sonnet).
  /// Fallback → Gemini (AiApiHelper) if Cloud Function call fails.
  /// Offline fallback → local pattern-matched response.
  Future<CopilotMessage> sendMessage(String userText) async {
    final userMsg = CopilotMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      text: userText,
      isUser: true,
    );
    _messages.add(userMsg);

    // Add to conversation history (Anthropic format: role/content)
    _conversationHistory.add({
      'role': 'user',
      'content': userText,
    });

    try {
      // ── §2C Primary: Claude API via huddlCopilotChat Cloud Function ──────
      final replyText = await _callCopilotCloudFunction(userText);
      final category = _detectCategory(userText);
      final actions = _suggestActions(userText, category);
      final response = CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: replyText.trim(),
        isUser: false,
        category: category,
        actions: actions,
        sourceNote: 'Powered by huddl AI',
      );
      _messages.add(response);
      _isApiOnline = true;
      _conversationHistory.add({
        'role': 'assistant',
        'content': response.text,
      });
      return response;
    } catch (cloudError) {
      if (kDebugMode) {
        if (kDebugMode) {
          debugPrint('AiCopilot: Cloud Function failed ($cloudError), trying Gemini fallback');
        }
      }
      // ── Fallback: Gemini via AiApiHelper ─────────────────────────────────
      try {
        // Re-build Gemini-format history from _conversationHistory
        final geminiHistory = _conversationHistory.map((m) => {
          'role': m['role'] == 'assistant' ? 'model' : m['role'],
          'parts': [{'text': m['content'] ?? ''}],
        }).toList();
        final systemPrompt = _promptBuilder.buildCopilotPrompt();
        final requestBody = {
          'system_instruction': {
            'parts': [{'text': systemPrompt}]
          },
          'contents': <Map<String, dynamic>>[...geminiHistory],
          'generationConfig': {
            'temperature': 0.75,
            'topP': 0.95,
            'topK': 40,
            'maxOutputTokens': 1024,
          },
          'safetySettings': [
            {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',  'threshold': 'BLOCK_ONLY_HIGH'},
            {'category': 'HARM_CATEGORY_HARASSMENT',         'threshold': 'BLOCK_ONLY_HIGH'},
            {'category': 'HARM_CATEGORY_HATE_SPEECH',        'threshold': 'BLOCK_ONLY_HIGH'},
            {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',  'threshold': 'BLOCK_ONLY_HIGH'},
          ],
        };
        final text = await AiApiHelper.generateText(requestBody) ?? '';
        final category = _detectCategory(userText);
        final actions = _suggestActions(userText, category);
        final response = CopilotMessage(
          id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
          text: text.trim(),
          isUser: false,
          category: category,
          actions: actions,
          sourceNote: 'Powered by huddl AI',
        );
        _messages.add(response);
        _isApiOnline = true;
        _conversationHistory.add({
          'role': 'assistant',
          'content': response.text,
        });
        return response;
      } catch (geminiError) {
        // API_KEY_SERVICE_BLOCKED = permanent config issue, not a network outage.
        // Do NOT set _isApiOnline=false in that case — the Cloud Function primary
        // path is unaffected, and the "Offline" badge would be misleading.
        final isConfigError = geminiError.toString().contains('GEMINI_API_NOT_ENABLED');
        _isApiOnline = !isConfigError;
        if (kDebugMode) {
          if (kDebugMode) {
            debugPrint('AiCopilot: all AI APIs failed: $geminiError');
          }
        }
        // ── Offline fallback: local pattern-matched response ──────────────
        final fallback = _generateLocalResponse(userText);
        _messages.add(fallback);
        _conversationHistory.add({
          'role': 'assistant',
          'content': fallback.text,
        });
        return fallback;
      }
    }
  }

  /// Build user context map for the Cloud Function call.
  Map<String, String> _buildUserContextForFunction() {
    final name = _onboarding.name ?? '';
    final pc = _onboarding.postcode ?? '';
    final borough = _postcode.getBoroughFromPostcode(pc) ?? _onboarding.borough ?? '';
    final children = _onboarding.children;
    String childrenSummary;
    if (children.isEmpty) {
      childrenSummary = 'not specified';
    } else {
      childrenSummary = children.map((c) {
        final n = c['name'] ?? 'child';
        final bday = c['birthday'] ?? '';
        if (bday.isEmpty) return n;
        try {
          final dob = DateTime.parse(bday);
          final ageMonths = DateTime.now().difference(dob).inDays ~/ 30;
          final ageLabel = ageMonths < 12 ? '$ageMonths months' : '${ageMonths ~/ 12} years';
          return '$n ($ageLabel)';
        } catch (_) {
          return n;
        }
      }).join(', ');
    }
    final stages = _onboarding.stagesOfLife;
    final stage = stages.isNotEmpty ? stages.first : 'not specified';
    return {
      'userName': name,
      'borough': borough,
      'childrenSummary': childrenSummary,
      'parentingStage': stage,
    };
  }

  /// Call the `huddlCopilotChat` Firebase Cloud Function.
  /// Passes last 10 messages and user context.
  /// Throws on failure so the caller can try Gemini fallback.
  ///
  /// REGION NOTE: Uses the default `us-central1` region.
  /// If the function is deployed to a different region (e.g. `europe-west1`),
  /// change `FirebaseFunctions.instance` to:
  ///   FirebaseFunctions.instanceFor(region: 'europe-west1')
  /// Check deployed region with: firebase functions:list --project huddl-connect
  Future<String> _callCopilotCloudFunction(String userText) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'huddlCopilotChat',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );

    // §2C: Pass last 10 messages in Anthropic format (role/content)
    final last10 = _conversationHistory.length > 10
        ? _conversationHistory.sublist(_conversationHistory.length - 10)
        : List<Map<String, dynamic>>.from(_conversationHistory);

    final result = await callable.call(<String, dynamic>{
      'messages': last10,
      'userContext': _buildUserContextForFunction(),
    });

    final reply = (result.data as Map<dynamic, dynamic>?)?['reply'] as String?;
    if (reply == null || reply.isEmpty) {
      throw Exception('Empty reply from Cloud Function');
    }
    return reply;
  }

  // NOTE: _buildSystemPrompt() has been replaced by
  // GeminiSystemPromptBuilder.buildCopilotPrompt() which includes:
  //   - HyperlocalRules (borough-scoped feature enforcement)
  //   - Borough local directory (parks, libraries, cafes)
  //   - Knowledge base articles, milestones, vaccinations, seasonal tips
  //   - Learning engine context (borough engagement stats, event prefs)
  //   - Empathy & safety guardrails
  //   - Huddl features block (hyperlocal-aware)
  //   - Borough change detection for recently-moved parents

  /// Detect the category of a user query
  CopilotCategory _detectCategory(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('rash') ||
        lower.contains('fever') ||
        lower.contains('ill') ||
        lower.contains('sick') ||
        lower.contains('cold') ||
        lower.contains('cough') ||
        lower.contains('health') ||
        lower.contains('doctor') ||
        lower.contains('gp') ||
        lower.contains('nhs')) {
      return CopilotCategory.health;
    }
    if (lower.contains('milestone') ||
        lower.contains('development') ||
        lower.contains('crawl') ||
        lower.contains('walk') ||
        lower.contains('talk') ||
        lower.contains('sleep') ||
        lower.contains('wean') ||
        lower.contains('feed')) {
      return CopilotCategory.development;
    }
    if (lower.contains('nursery') ||
        lower.contains('childcare') ||
        lower.contains('school') ||
        lower.contains('class')) {
      return CopilotCategory.localServices;
    }
    if (lower.contains('sell') ||
        lower.contains('buy') ||
        lower.contains('preloved') ||
        lower.contains('market')) {
      return CopilotCategory.marketplace;
    }
    if (lower.contains('meetup') ||
        lower.contains('meet') ||
        lower.contains('social') ||
        lower.contains('friend') ||
        lower.contains('lonely') ||
        lower.contains('connect')) {
      return CopilotCategory.social;
    }
    return CopilotCategory.general;
  }

  /// Suggest relevant app actions based on category
  List<CopilotAction> _suggestActions(
      String query, CopilotCategory category) {
    switch (category) {
      case CopilotCategory.health:
        return const [
          CopilotAction(
              label: 'NHS 111 Online',
              route: 'url',
              icon: 'health_and_safety',
              params: {'url': 'https://111.nhs.uk'}),
          CopilotAction(
              label: 'Ask Community', route: '/groups', icon: 'forum'),
        ];
      case CopilotCategory.development:
        return const [
          CopilotAction(
              label: 'Track Milestones',
              route: '/profile',
              icon: 'timeline'),
          CopilotAction(
              label: 'Ask Community', route: '/groups', icon: 'forum'),
        ];
      case CopilotCategory.localServices:
        return const [
          CopilotAction(
              label: 'Ask in Community',
              route: '/groups',
              icon: 'forum'),
          CopilotAction(
              label: 'View Meetups', route: '/meetups', icon: 'groups'),
        ];
      case CopilotCategory.marketplace:
        return const [
          CopilotAction(
              label: 'Create AI Listing',
              route: '/create_listing',
              icon: 'add_a_photo'),
          CopilotAction(
              label: 'Browse Market',
              route: '/marketplace',
              icon: 'storefront'),
        ];
      case CopilotCategory.social:
        return const [
          CopilotAction(
              label: 'AI Matchmaker',
              route: '/meetups',
              icon: 'auto_awesome'),
          CopilotAction(
              label: 'Browse Meetups',
              route: '/meetups',
              icon: 'groups'),
        ];
      case CopilotCategory.general:
        return const [
          CopilotAction(
              label: 'Browse Meetups',
              route: '/meetups',
              icon: 'groups'),
          CopilotAction(
              label: 'Market',
              route: '/marketplace',
              icon: 'storefront'),
        ];
    }
  }

  /// Smart local fallback when API is unavailable
  CopilotMessage _generateLocalResponse(String query) {
    final lower = query.toLowerCase();
    final borough = _getUserBorough();
    final userName = _onboarding.name ?? 'there';
    final children = _onboarding.children;

    // -- Health queries --
    if (lower.contains('rash') ||
        lower.contains('fever') ||
        lower.contains('ill') ||
        lower.contains('sick') ||
        lower.contains('cold') ||
        lower.contains('cough') ||
        lower.contains('health') ||
        lower.contains('doctor')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'I understand your concern, $userName. While I can\'t provide '
            'medical advice, here are some helpful steps:\n\n'
            '\u2022 **NHS 111** is available 24/7 for non-emergency health advice\n'
            '\u2022 Your local **GP in $borough** can see you for urgent appointments\n'
            '\u2022 For emergencies, always call **999**\n\n'
            'You could also ask parents in your local huddl community '
            '\u2014 they may have been through something similar.',
        isUser: false,
        category: CopilotCategory.health,
        actions: const [
          CopilotAction(
              label: 'NHS 111 Online',
              route: 'url',
              icon: 'health_and_safety',
              params: {'url': 'https://111.nhs.uk'}),
          CopilotAction(
              label: 'Ask Community', route: '/groups', icon: 'forum'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Sleep queries --
    if (lower.contains('sleep') ||
        lower.contains('bedtime') ||
        lower.contains('night wak') ||
        lower.contains('nap')) {
      final childAge = _getChildAgeContext(children);
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'Sleep can be challenging! Here are some tips $childAge:\n\n'
            '\u2022 **Consistent routine**: Bath, book, bed \u2014 same order every night\n'
            '\u2022 **Dark room**: Blackout blinds can help enormously\n'
            '\u2022 **White noise**: Steady background sound often soothes babies\n'
            '\u2022 **Patience**: Most sleep regressions pass within 2\u20134 weeks\n\n'
            'Many parents in $borough have shared their sleep tips in the community groups.',
        isUser: false,
        category: CopilotCategory.development,
        actions: const [
          CopilotAction(
              label: 'Sleep Support Group',
              route: '/groups',
              icon: 'bedtime'),
          CopilotAction(
              label: 'Ask Community', route: '/groups', icon: 'forum'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Nursery / childcare --
    if (lower.contains('nursery') ||
        lower.contains('nurseries') ||
        lower.contains('childcare') ||
        lower.contains('school')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Finding the right nursery in $borough is so important! '
            'Here are some tips:\n\n'
            '\u2022 **Start early** \u2014 waiting lists can be 6\u201312 months\n'
            '\u2022 **Check Ofsted ratings** for quality assurance\n'
            '\u2022 **Visit in person** during a normal day to see the staff in action\n'
            '\u2022 **Ask other parents** \u2014 word of mouth is invaluable\n\n'
            'Your huddl community groups are a great place to get local recommendations!',
        isUser: false,
        category: CopilotCategory.localServices,
        actions: const [
          CopilotAction(
              label: 'Ask in Community',
              route: '/groups',
              icon: 'forum'),
          CopilotAction(
              label: 'View Meetups', route: '/meetups', icon: 'groups'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Sell something --
    if (lower.contains('sell') ||
        lower.contains('list') ||
        lower.contains('preloved') ||
        lower.contains('market')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'Great idea! Selling on huddl Market is super easy:\n\n'
            '1. **Take a photo** \u2014 our AI identifies the product\n'
            '2. **Auto-generates** title, description & smart pricing\n'
            '3. **One tap** to publish \u2014 ready in seconds!\n\n'
            'Items in $borough typically sell quickly. Give it a go!',
        isUser: false,
        category: CopilotCategory.marketplace,
        actions: const [
          CopilotAction(
              label: 'Create AI Listing',
              route: '/create_listing',
              icon: 'add_a_photo'),
          CopilotAction(
              label: 'Browse Market',
              route: '/marketplace',
              icon: 'storefront'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Meetup / social --
    if (lower.contains('meetup') ||
        lower.contains('meet') ||
        lower.contains('social') ||
        lower.contains('lonely') ||
        lower.contains('friend')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'Let\'s get you connected, $userName! Here\'s what you can do:\n\n'
            '\u2022 **Browse meetups** happening near you in $borough\n'
            '\u2022 **Create your own meetup** \u2014 coffee mornings are very popular\n'
            '\u2022 **Try AI Matchmaker** to find compatible parents nearby\n\n'
            'Making parent friends is one of the best things you can do. '
            'The huddl community is here for you!',
        isUser: false,
        category: CopilotCategory.social,
        actions: const [
          CopilotAction(
              label: 'AI Matchmaker',
              route: '/meetups',
              icon: 'auto_awesome'),
          CopilotAction(
              label: 'Browse Meetups',
              route: '/meetups',
              icon: 'groups'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Travel --
    if (lower.contains('travel') ||
        lower.contains('holiday') ||
        lower.contains('vacation') ||
        lower.contains('trip') ||
        lower.contains('destination')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'Family travel is so rewarding! Here are some popular picks:\n\n'
            '\u2022 **Short haul**: Mallorca, Tenerife, Algarve \u2014 great for little ones\n'
            '\u2022 **UK staycation**: Center Parcs, Bluestone, Haven \u2014 rain or shine\n'
            '\u2022 **City breaks**: Barcelona, Amsterdam \u2014 surprisingly family-friendly\n\n'
            'Check out the **Travel Tribe** group in Connect for tips '
            'from parents who\'ve been there and done it!',
        isUser: false,
        category: CopilotCategory.social,
        actions: const [
          CopilotAction(
              label: 'Go to Connect',
              route: '/groups',
              icon: 'people'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Feeding / weaning --
    if (lower.contains('wean') ||
        lower.contains('food') ||
        lower.contains('feed') ||
        lower.contains('solids') ||
        lower.contains('formula') ||
        lower.contains('breastfe')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'Great question about feeding! Here are the basics:\n\n'
            '\u2022 **NHS recommends** starting solids around 6 months\n'
            '\u2022 **First foods**: Sweet potato, banana, avocado, porridge\n'
            '\u2022 **Baby-led weaning** is popular \u2014 start with soft finger foods\n'
            '\u2022 **Go at your baby\'s pace** \u2014 every child is different\n\n'
            'Parents in $borough have great tips in the community groups!',
        isUser: false,
        category: CopilotCategory.health,
        actions: const [
          CopilotAction(
              label: 'NHS Weaning Guide',
              route: 'url',
              icon: 'restaurant',
              params: {
                'url': 'https://www.nhs.uk/start4life/weaning'
              }),
          CopilotAction(
              label: 'Join Weaning Group',
              route: '/groups',
              icon: 'group_add'),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Work, leave & legal rights (paternity, maternity, parental leave etc.) --
    if (lower.contains('paternity') ||
        lower.contains('maternity') ||
        lower.contains('parental leave') ||
        lower.contains('shared parental') ||
        lower.contains('adoption leave') ||
        lower.contains('statutory pay') ||
        lower.contains('smp') ||
        lower.contains('spp') ||
        lower.contains('shpp') ||
        lower.contains('leave entitle') ||
        lower.contains('weeks leave') ||
        lower.contains('weeks off') ||
        lower.contains('work rights') ||
        lower.contains('employment rights') ||
        lower.contains('redundan') ||
        lower.contains('flexible working') ||
        lower.contains('return to work') ||
        lower.contains('keeping in touch day') ||
        lower.contains('kit day') ||
        lower.contains('childcare voucher') ||
        lower.contains('tax-free childcare') ||
        lower.contains('universal credit') ||
        lower.contains('child benefit') ||
        lower.contains('child tax credit')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'Great question about parental rights, $userName! Here are the key UK entitlements:\n\n'
            '\u2022 **Paternity leave**: 1 or 2 consecutive weeks within 56 days of birth\n'
            '\u2022 **Statutory Paternity Pay (SPP)**: £184.03/week (or 90% of earnings if lower) — 2025 rate\n'
            '\u2022 **Maternity leave**: up to 52 weeks (26 ordinary + 26 additional)\n'
            '\u2022 **Shared Parental Leave**: split the remaining leave after week 2 between both parents\n'
            '\u2022 **Child Benefit**: £25.60/week for first child (2025 rate)\n'
            '\u2022 **Tax-Free Childcare**: up to £2,000/year per child via gov.uk\n\n'
            'For your specific situation — especially if you\'re employed vs self-employed — '
            'the GOV.UK pages have the most up-to-date figures. My full AI can give you '
            'personalised guidance when connected!',
        isUser: false,
        category: CopilotCategory.general,
        actions: const [
          CopilotAction(
              label: 'GOV.UK Paternity Leave',
              route: 'url',
              icon: 'work',
              params: {'url': 'https://www.gov.uk/paternity-leave'}),
          CopilotAction(
              label: 'GOV.UK Parental Leave',
              route: 'url',
              icon: 'family_restroom',
              params: {'url': 'https://www.gov.uk/parental-leave'}),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Financial / benefits --
    if (lower.contains('benefit') ||
        lower.contains('grant') ||
        lower.contains('allowance') ||
        lower.contains('sure start') ||
        lower.contains('healthy start') ||
        lower.contains('free hours') ||
        lower.contains('15 hours') ||
        lower.contains('30 hours') ||
        lower.contains('funded') ||
        lower.contains('voucher') ||
        lower.contains('pip') ||
        lower.contains('dla') ||
        lower.contains('council tax')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'There are several financial supports available to families, $userName:\n\n'
            '\u2022 **Child Benefit**: £25.60/week (first child), £16.95 (subsequent) — 2025 rates\n'
            '\u2022 **Free childcare**: 15–30 funded hours/week for eligible children 9 months–4 years\n'
            '\u2022 **Tax-Free Childcare**: save up to £2,000/year via gov.uk/tax-free-childcare\n'
            '\u2022 **Sure Start Maternity Grant**: £500 one-off for first child if on qualifying benefits\n'
            '\u2022 **Healthy Start**: free vouchers for fruit/veg/milk if pregnant or have <4yr-olds\n\n'
            'Use the **GOV.UK benefits checker** to see exactly what you\'re entitled to.',
        isUser: false,
        category: CopilotCategory.general,
        actions: const [
          CopilotAction(
              label: 'Benefits Calculator',
              route: 'url',
              icon: 'calculate',
              params: {'url': 'https://www.gov.uk/benefits-calculators'}),
          CopilotAction(
              label: 'Free Childcare Hours',
              route: 'url',
              icon: 'child_care',
              params: {'url': 'https://www.gov.uk/check-eligible-free-childcare-if-youre-working'}),
        ],
        sourceNote: 'Offline response \u00B7 Connect to internet for full AI',
      );
    }

    // -- Default general --
    // This fires only when no keyword matches — show a helpful connecting message
    // rather than implying the AI is broken.
    return CopilotMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      text:
          'I\'m connecting to my full AI brain to answer that properly, $userName!\n\n'
          'While I load up, here are some things I can always help with:\n'
          '\u2022 **Sleep**, **feeding**, or **development milestones**\n'
          '\u2022 **Paternity / maternity leave** and parental rights\n'
          '\u2022 **Nurseries** or **local services** near $borough\n'
          '\u2022 **Selling items** on Market\n'
          '\u2022 **Planning meetups** with local parents\n\n'
          'Try sending your message again in a moment \u2014 the AI is warming up!',
      isUser: false,
      category: CopilotCategory.general,
      actions: const [
        CopilotAction(
            label: 'Browse Meetups',
            route: '/meetups',
            icon: 'groups'),
        CopilotAction(
            label: 'Market',
            route: '/marketplace',
            icon: 'storefront'),
      ],
      sourceNote: 'Connecting to AI \u00B7 Try again in a moment',
    );
  }

  // -- Helpers --
  String _getUserBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) {
      return _postcode.getBoroughFromPostcode(pc) ?? 'your area';
    }
    return 'your area';
  }

  String _getChildAgeContext(List<Map<String, String>> children) {
    if (children.isEmpty) return '';
    final birthday = children.first['birthday'];
    if (birthday == null) return '';
    final months = _parseAgeMonths(birthday);
    if (months < 12) return 'for a $months-month-old';
    final years = months ~/ 12;
    return 'for a $years-year-old';
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
}
