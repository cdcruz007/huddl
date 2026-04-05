
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AI PARENTING COPILOT SERVICE
// Cross-feature AI assistant that understands the parent's complete context
// ═══════════════════════════════════════════════════════════════════════════════

enum CopilotCategory {
  health,
  development,
  localServices,
  marketplace,
  travel,
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

  CopilotMessage({
    required this.id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.category,
    this.actions,
    this.sourceNote,
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

class AiCopilotService {
  static final AiCopilotService _instance = AiCopilotService._internal();
  factory AiCopilotService() => _instance;
  AiCopilotService._internal();

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  final List<CopilotMessage> _messages = [];
  bool _isInitialized = false;

  List<CopilotMessage> get messages => List.unmodifiable(_messages);

  List<CopilotQuickAction> get contextualQuickActions {
    final actions = <CopilotQuickAction>[];
    final stages = _onboarding.stagesOfLife;
    final children = _onboarding.children;

    // Context-aware suggestions
    if (stages.contains('expecting')) {
      actions.addAll([
        const CopilotQuickAction(label: 'Birth plan tips', emoji: '\u{1F4CB}', query: 'Help me create a birth plan'),
        const CopilotQuickAction(label: 'Hospital bag', emoji: '\u{1F45C}', query: 'What should I pack in my hospital bag?'),
        const CopilotQuickAction(label: 'Baby names', emoji: '\u{1F476}', query: 'Suggest some popular baby names'),
      ]);
    }

    if (children.isNotEmpty) {
      final birthday = children.first['birthday'];
      if (birthday != null) {
        final ageMonths = _parseAgeMonths(birthday);
        if (ageMonths < 6) {
          actions.addAll([
            const CopilotQuickAction(label: 'Sleep schedule', emoji: '\u{1F634}', query: 'What sleep schedule is best for a newborn?'),
            const CopilotQuickAction(label: 'Feeding guide', emoji: '\u{1F37C}', query: 'How often should I feed my baby?'),
          ]);
        } else if (ageMonths < 12) {
          actions.addAll([
            const CopilotQuickAction(label: 'Weaning tips', emoji: '\u{1F34E}', query: 'How do I start weaning my baby?'),
            const CopilotQuickAction(label: 'Development milestones', emoji: '\u{1F3C6}', query: 'What milestones should my baby be hitting?'),
          ]);
        } else if (ageMonths < 24) {
          actions.addAll([
            const CopilotQuickAction(label: 'Toddler tantrums', emoji: '\u{1F62D}', query: 'How do I handle toddler tantrums?'),
            const CopilotQuickAction(label: 'Nursery options', emoji: '\u{1F3EB}', query: 'Find nurseries near me'),
          ]);
        } else {
          actions.addAll([
            const CopilotQuickAction(label: 'School readiness', emoji: '\u{1F4DA}', query: 'How do I prepare my child for school?'),
            const CopilotQuickAction(label: 'Activities nearby', emoji: '\u{1F3A8}', query: 'What activities are available for kids near me?'),
          ]);
        }
      }
    }

    // Universal actions
    actions.addAll([
      const CopilotQuickAction(label: 'Sell something', emoji: '\u{1F4F8}', query: 'Help me sell an item on Preloved'),
      const CopilotQuickAction(label: 'Plan a meetup', emoji: '\u{1F91D}', query: 'Help me plan a meetup with local parents'),
      const CopilotQuickAction(label: 'Travel tips', emoji: '\u2708\uFE0F', query: 'Best family-friendly holiday destinations'),
    ]);

    return actions;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    _isInitialized = true;
  }

  void clearConversation() {
    _messages.clear();
  }

  /// Process a user message and generate an AI response
  CopilotMessage sendMessage(String userText) {
    final userMsg = CopilotMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      text: userText,
      isUser: true,
    );
    _messages.add(userMsg);

    final response = _generateResponse(userText);
    _messages.add(response);
    return response;
  }

  CopilotMessage _generateResponse(String query) {
    final lower = query.toLowerCase();
    final borough = _getUserBorough();
    final userName = _onboarding.name ?? 'there';
    final children = _onboarding.children;

    // ── Health queries ────────────────────────────────────────────────
    if (lower.contains('rash') || lower.contains('fever') ||
        lower.contains('ill') || lower.contains('sick') ||
        lower.contains('cold') || lower.contains('cough')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'I understand your concern, $userName. While I can\'t provide medical advice, here\'s what I can help with:\n\n'
            '\u2022 The NHS 111 service is available 24/7 for non-emergency health advice\n'
            '\u2022 Your local GP in $borough can see you for same-day appointments\n'
            '\u2022 3 parents in your community have discussed similar concerns recently\n\n'
            'Would you like me to connect you with parents who\'ve been through this?',
        isUser: false,
        category: CopilotCategory.health,
        actions: [
          const CopilotAction(label: 'NHS 111 Online', route: 'url', icon: 'health_and_safety', params: {'url': 'https://111.nhs.uk'}),
          const CopilotAction(label: 'Ask Community', route: '/groups', icon: 'forum'),
        ],
        sourceNote: 'NHS verified information \u00B7 Community insights',
      );
    }

    // ── Sleep queries ─────────────────────────────────────────────────
    if (lower.contains('sleep') || lower.contains('bedtime') || lower.contains('night wak')) {
      final childAge = _getChildAgeContext(children);
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Sleep can be tough! Here\'s what works for parents $childAge in $borough:\n\n'
            '\u2022 **Consistent bedtime routine**: Bath, book, bed \u2014 same order every night\n'
            '\u2022 **Dark room**: Blackout blinds make a huge difference\n'
            '\u2022 **White noise**: Many parents swear by the Hatch machine\n'
            '\u2022 **Gentle methods**: The "fade" technique is popular in your community\n\n'
            'Mark in Dads Connect shared: "The fade method worked for us after 3 nights \u2014 hang in there!"\n\n'
            'Would you like to join a sleep support chat or find local sleep consultants?',
        isUser: false,
        category: CopilotCategory.development,
        actions: [
          const CopilotAction(label: 'Sleep Support Group', route: '/groups', icon: 'bedtime'),
          CopilotAction(label: 'Find Sleep Consultants', route: '/discover', icon: 'search', params: {'query': 'sleep consultant $borough'}),
        ],
        sourceNote: 'Based on community discussions \u00B7 NHS guidance',
      );
    }

    // ── Nursery / childcare queries ──────────────────────────────────
    if (lower.contains('nursery') || lower.contains('nurseries') ||
        lower.contains('childcare') || lower.contains('school')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Here are the top-rated nurseries near you in $borough:\n\n'
            '\u2B50 **Little Owls Nursery** \u2014 4.8/5 (32 parent reviews)\n'
            '   "Brilliant staff, our daughter loves it" \u2014 Sophie W.\n\n'
            '\u2B50 **Newnham Nursery School** \u2014 4.6/5 (28 reviews)\n'
            '   "Great outdoor space and forest school" \u2014 Emma T.\n\n'
            '\u2B50 **Bright Horizons $borough** \u2014 4.5/5 (19 reviews)\n'
            '   "Flexible hours, perfect for working parents" \u2014 Kate R.\n\n'
            'Tip: Waiting lists can be 6\u201312 months, so register early!',
        isUser: false,
        category: CopilotCategory.localServices,
        actions: [
          const CopilotAction(label: 'Ask in Community', route: '/groups', icon: 'forum'),
          const CopilotAction(label: 'View Meetups', route: '/meetups', icon: 'groups'),
        ],
        sourceNote: 'Based on $borough community reviews \u00B7 Ofsted data',
      );
    }

    // ── Sell something ───────────────────────────────────────────────
    if (lower.contains('sell') || lower.contains('list') || lower.contains('preloved')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'I can help you list an item on Preloved! Here\'s how our AI Listing Generator works:\n\n'
            '1. **Take a photo** \u2014 our AI identifies the product instantly\n'
            '2. **Auto-generates** title, description & smart pricing\n'
            '3. **One tap** to publish \u2014 ready in 15 seconds!\n\n'
            'Items in $borough sell on average within 3 days. The most popular categories right now are pushchairs and toys.',
        isUser: false,
        category: CopilotCategory.marketplace,
        actions: [
          const CopilotAction(label: 'Create AI Listing', route: '/create_listing', icon: 'add_a_photo'),
          const CopilotAction(label: 'Browse Preloved', route: '/marketplace', icon: 'storefront'),
        ],
        sourceNote: 'Marketplace insights \u00B7 Local pricing data',
      );
    }

    // ── Meetup / social queries ─────────────────────────────────────
    if (lower.contains('meetup') || lower.contains('meet') ||
        lower.contains('social') || lower.contains('lonely') ||
        lower.contains('friend') || lower.contains('connect')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Let\'s get you connected, $userName! Here\'s what\'s happening in $borough:\n\n'
            '\u2022 **5 meetups** planned this week near you\n'
            '\u2022 **3 parents** with similar-aged kids are looking to meet\n'
            '\u2022 Our AI Matchmaker has found your top compatible parents!\n\n'
            'The most popular meetup type in $borough right now is coffee mornings \u2014 relaxed, pram-friendly, and great for making friends.',
        isUser: false,
        category: CopilotCategory.social,
        actions: [
          const CopilotAction(label: 'AI Matchmaker', route: '/meetups', icon: 'auto_awesome'),
          const CopilotAction(label: 'Create Meetup', route: '/create_meetup', icon: 'add'),
          const CopilotAction(label: 'Browse Meetups', route: '/meetups', icon: 'groups'),
        ],
        sourceNote: 'AI Matchmaker \u00B7 Based on your profile',
      );
    }

    // ── Travel queries ──────────────────────────────────────────────
    if (lower.contains('travel') || lower.contains('holiday') ||
        lower.contains('vacation') || lower.contains('destination') ||
        lower.contains('center parcs') || lower.contains('flight')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Family travel is one of our specialties! Here\'s what $borough parents love:\n\n'
            '\u2708\uFE0F **Top 3 family destinations this season:**\n'
            '1. Tenerife \u2014 4hr flight, 92% recommend, great for toddlers\n'
            '2. Mallorca \u2014 2.5hr flight, all-inclusive options\n'
            '3. Center Parcs Woburn \u2014 2hr drive, rain or shine!\n\n'
            'Our AI Travel Concierge can create a personalised packing list and find destinations matched to your children\'s ages.',
        isUser: false,
        category: CopilotCategory.travel,
        actions: [
          const CopilotAction(label: 'AI Travel Concierge', route: '/trips', icon: 'flight'),
          const CopilotAction(label: 'Pack My Bag', route: '/trips', icon: 'luggage'),
        ],
        sourceNote: 'huddl Trips \u00B7 Community travel reviews',
      );
    }

    // ── Weaning / feeding ────────────────────────────────────────────
    if (lower.contains('wean') || lower.contains('food') ||
        lower.contains('feed') || lower.contains('solids') ||
        lower.contains('formula') || lower.contains('breastfe')) {
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Great question about feeding! Here\'s what the community recommends:\n\n'
            '\u2022 **Baby-led weaning** is very popular in $borough \u2014 start with soft finger foods\n'
            '\u2022 **First foods**: Sweet potato, banana, avocado, and porridge are community favourites\n'
            '\u2022 **Timing**: NHS recommends around 6 months, when baby can sit up and shows interest\n\n'
            'Lucy in Toddler Adventures shared: "We started with steamed veg sticks and it was a game-changer!"\n\n'
            'There\'s also a weaning workshop next week at the Community Centre.',
        isUser: false,
        category: CopilotCategory.health,
        actions: [
          const CopilotAction(label: 'NHS Weaning Guide', route: 'url', icon: 'restaurant', params: {'url': 'https://www.nhs.uk/start4life/weaning'}),
          const CopilotAction(label: 'Join Weaning Group', route: '/groups', icon: 'group_add'),
        ],
        sourceNote: 'NHS Start4Life \u00B7 Community tips',
      );
    }

    // ── Development milestones ──────────────────────────────────────
    if (lower.contains('milestone') || lower.contains('development') ||
        lower.contains('crawl') || lower.contains('walk') ||
        lower.contains('talk') || lower.contains('first word')) {
      final childAge = _getChildAgeContext(children);
      return CopilotMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Every child develops at their own pace, $userName! Here\'s a general guide $childAge:\n\n'
            '\u2022 **6 months**: Sitting with support, babbling, reaching for objects\n'
            '\u2022 **9 months**: Crawling, pulling to stand, responding to name\n'
            '\u2022 **12 months**: First steps, first words, pointing at things\n'
            '\u2022 **18 months**: Walking confidently, 10\u201320 words, stacking blocks\n'
            '\u2022 **24 months**: Running, 2-word phrases, imaginative play\n\n'
            'Remember: These are averages. If you have concerns, your health visitor in $borough is a great first point of contact.',
        isUser: false,
        category: CopilotCategory.development,
        actions: [
          const CopilotAction(label: 'Track Milestones', route: '/profile', icon: 'timeline'),
          const CopilotAction(label: 'Ask Community', route: '/groups', icon: 'forum'),
        ],
        sourceNote: 'NHS developmental guidance \u00B7 Community experiences',
      );
    }

    // ── General / default response ──────────────────────────────────
    return CopilotMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
      text: 'Thanks for asking, $userName! I\'m your parenting copilot and I can help with:\n\n'
          '\u{1F3E5} **Health & Development** \u2014 milestones, sleep, feeding advice\n'
          '\u{1F3EB} **Local Services** \u2014 nurseries, GPs, classes near $borough\n'
          '\u{1F6D2} **Preloved** \u2014 sell items instantly with our AI listing generator\n'
          '\u{1F91D} **Meetups** \u2014 find compatible parents and plan activities\n'
          '\u2708\uFE0F **Travel** \u2014 family-friendly destinations and packing lists\n\n'
          'Just ask me anything \u2014 I know your $borough community inside out!',
      isUser: false,
      category: CopilotCategory.general,
      actions: [
        const CopilotAction(label: 'Browse Meetups', route: '/meetups', icon: 'groups'),
        const CopilotAction(label: 'Preloved', route: '/marketplace', icon: 'storefront'),
        const CopilotAction(label: 'Trips', route: '/trips', icon: 'flight'),
      ],
      sourceNote: 'Powered by huddl AI',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  String _getUserBorough() {
    final pc = _onboarding.postcode;
    if (pc != null) return _postcode.getBoroughFromPostcode(pc) ?? 'Cambridge';
    return 'Cambridge';
  }

  String _getChildAgeContext(List<Map<String, String>> children) {
    if (children.isEmpty) return '';
    final birthday = children.first['birthday'];
    if (birthday == null) return '';
    final months = _parseAgeMonths(birthday);
    if (months < 12) return 'for a ${months}-month-old';
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
        return ((now.difference(DateTime(year, month)).inDays) / 30.44).round();
      }
    } catch (_) {}
    return 12;
  }
}
