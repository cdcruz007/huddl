
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
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
  bool _isApiOnline = false;

  // Gemini API configuration (centralised in GeminiConfig)
  /// Whether the Gemini API responded successfully at least once.
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
    // Validate the Gemini key in the background so the UI can reflect status
    _isApiOnline = await GeminiConfig.validateKey();
    _isInitialized = true;
  }

  void clearConversation() {
    _messages.clear();
    _conversationHistory.clear();
  }

  /// Process a user message and generate an AI response
  Future<CopilotMessage> sendMessage(String userText) async {
    final userMsg = CopilotMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      text: userText,
      isUser: true,
    );
    _messages.add(userMsg);

    // Add to conversation history
    _conversationHistory.add({
      'role': 'user',
      'parts': [
        {'text': userText}
      ],
    });

    try {
      final response = await _callGeminiApi(userText);
      _messages.add(response);
      _isApiOnline = true;

      // Add AI response to conversation history
      _conversationHistory.add({
        'role': 'model',
        'parts': [
          {'text': response.text}
        ],
      });

      return response;
    } catch (e) {
      _isApiOnline = false;
      if (kDebugMode) {
        debugPrint('Gemini API error: $e');
      }
      // Fall back to smart local response
      final fallback = _generateLocalResponse(userText);
      _messages.add(fallback);
      _conversationHistory.add({
        'role': 'model',
        'parts': [
          {'text': fallback.text}
        ],
      });
      return fallback;
    }
  }

  /// Call Gemini API with full conversation context
  Future<CopilotMessage> _callGeminiApi(String query) async {
    // ── System prompt from centralised builder (hyperlocal-aware) ─────
    final systemPrompt = _promptBuilder.buildCopilotPrompt();

    // Build contents with system instruction + conversation history
    final contents = <Map<String, dynamic>>[];

    // Add conversation history (Gemini uses alternating user/model roles)
    for (final msg in _conversationHistory) {
      contents.add(msg);
    }

    final requestBody = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.8,
        'topP': 0.95,
        'topK': 40,
        'maxOutputTokens': 1024,
      },
      'safetySettings': [
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_ONLY_HIGH'
        },
        {
          'category': 'HARM_CATEGORY_HARASSMENT',
          'threshold': 'BLOCK_ONLY_HIGH'
        },
        {
          'category': 'HARM_CATEGORY_HATE_SPEECH',
          'threshold': 'BLOCK_ONLY_HIGH'
        },
        {
          'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'threshold': 'BLOCK_ONLY_HIGH'
        },
      ],
    };

    final url = Uri.parse(GeminiConfig.generateContentUrl);

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = parts[0]['text'] as String? ?? '';
          final category = _detectCategory(query);
          final actions = _suggestActions(query, category);

          return CopilotMessage(
            id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
            text: text.trim(),
            isUser: false,
            category: category,
            actions: actions,
            sourceNote: 'Powered by huddl AI',
          );
        }
      }
      // If no valid content, throw to trigger fallback
      throw Exception('No content in Gemini response');
    } else if (response.statusCode == 429) {
      // Quota exceeded — key is valid but rate-limited
      _isApiOnline = false;
      final userName = _onboarding.name ?? 'there';
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text:
            'I\'m taking a short breather, $userName! Our AI quota has been '
            'reached for the moment.\n\n'
            'This usually resets within **a few minutes**. In the meantime '
            'I can still help with the topics below, or try again shortly!',
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
        sourceNote: 'Quota limit reached \u00B7 Resets shortly',
      );
    } else {
      throw Exception(
          'Gemini API error: ${response.statusCode} - ${response.body}');
    }
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

    // -- Default general --
    return CopilotMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      text:
          'That\'s a great question, $userName! I\'m having trouble connecting '
          'to my full AI brain right now, but I can still help with the basics.\n\n'
          'Try asking me about:\n'
          '\u2022 **Sleep**, **feeding**, or **development milestones**\n'
          '\u2022 **Nurseries** or **local services** near $borough\n'
          '\u2022 **Selling items** on Market\n'
          '\u2022 **Planning meetups** with local parents\n\n'
          'Or try again in a moment \u2014 I\'ll be fully connected shortly!',
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
      sourceNote: 'Offline mode \u00B7 Full AI available when connected',
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
