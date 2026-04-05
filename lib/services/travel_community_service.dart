import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/gemini_config.dart';
import 'onboarding_data_service.dart';
import 'travel_service.dart';

// =============================================================================
// HUDDL TRIPS — COMMUNITY Q&A SERVICE
// "Ask Parents Who Know" — Parent-to-parent knowledge sharing with AI synthesis
// =============================================================================

// ─── Data Models ─────────────────────────────────────────────────────────────

/// Age group tags for filtering
enum ChildAgeGroup {
  newborn('0-6 months', '0-6m'),
  baby('6-12 months', '6-12m'),
  toddler('1-2 years', '1-2yr'),
  preschool('2-4 years', '2-4yr'),
  schoolAge('4-10 years', '4-10yr');

  final String label;
  final String shortLabel;
  const ChildAgeGroup(this.label, this.shortLabel);
}

/// Question category tags
enum QuestionCategory {
  accommodation('Accommodation', 'Where to stay', Icons: '🏨'),
  transport('Transport', 'Getting around', Icons: '✈️'),
  gear('Gear & Packing', 'What to bring', Icons: '🎒'),
  health('Health & Safety', 'Staying safe', Icons: '🏥'),
  food('Food & Feeding', 'Eating out', Icons: '🍽️'),
  activities('Activities', 'Things to do', Icons: '🎯'),
  general('General', 'Everything else', Icons: '💬');

  final String label;
  final String description;
  // ignore the Icons field — it's just for documentation
  final String Icons;
  const QuestionCategory(this.label, this.description, {required this.Icons});
}

/// A "Been There" badge earned by answering questions about a destination
class BeenThereBadge {
  final String destinationId;
  final String destinationName;
  final DateTime earnedDate;
  final int answersGiven;
  final int upvotesReceived;

  BeenThereBadge({
    required this.destinationId,
    required this.destinationName,
    required this.earnedDate,
    required this.answersGiven,
    required this.upvotesReceived,
  });

  /// Badge level based on answers
  String get level {
    if (upvotesReceived >= 25) return 'expert';
    if (upvotesReceived >= 10) return 'trusted';
    return 'visited';
  }

  String get levelLabel {
    switch (level) {
      case 'expert':
        return 'Destination Expert';
      case 'trusted':
        return 'Trusted Voice';
      default:
        return 'Been There';
    }
  }
}

/// A parent's community expert profile
class ParentExpertProfile {
  final String id;
  final String name;
  final String avatarColor;
  final String location;
  final List<BeenThereBadge> badges;
  final int totalAnswers;
  final int totalUpvotes;
  final List<String> childAges;
  final String bio;
  final DateTime joinedDate;
  final List<String> specialities; // e.g. "newborn travel", "budget holidays"

  ParentExpertProfile({
    required this.id,
    required this.name,
    required this.avatarColor,
    required this.location,
    required this.badges,
    required this.totalAnswers,
    required this.totalUpvotes,
    required this.childAges,
    required this.bio,
    required this.joinedDate,
    required this.specialities,
  });

  String get rank {
    if (totalUpvotes >= 50) return 'Community Legend';
    if (totalUpvotes >= 25) return 'Destination Expert';
    if (totalUpvotes >= 10) return 'Trusted Voice';
    if (totalAnswers >= 5) return 'Active Contributor';
    return 'New Member';
  }

  int get rankLevel {
    if (totalUpvotes >= 50) return 4;
    if (totalUpvotes >= 25) return 3;
    if (totalUpvotes >= 10) return 2;
    if (totalAnswers >= 5) return 1;
    return 0;
  }
}

/// An answer to a community travel question
class TravelAnswer {
  final String id;
  final String questionId;
  final String authorId;
  final String authorName;
  final String authorAvatarColor;
  final String content;
  final DateTime createdAt;
  int upvotes;
  final List<String> upvotedBy;
  final String? visitDate;
  final String? childAgesAtVisit;
  final List<String> attachedLinks;
  final bool isAiGenerated;
  final List<String> authorBadges;

  TravelAnswer({
    required this.id,
    required this.questionId,
    required this.authorId,
    required this.authorName,
    required this.authorAvatarColor,
    required this.content,
    required this.createdAt,
    this.upvotes = 0,
    List<String>? upvotedBy,
    this.visitDate,
    this.childAgesAtVisit,
    List<String>? attachedLinks,
    this.isAiGenerated = false,
    List<String>? authorBadges,
  })  : upvotedBy = upvotedBy ?? [],
        attachedLinks = attachedLinks ?? [],
        authorBadges = authorBadges ?? [];

  bool get hasBeenThereBadge => authorBadges.contains('been_there');
}

/// AI-generated synthesis of parent answers
class AiSynthesis {
  final String questionId;
  final String summary;
  final List<String> recommendations;
  final List<String> warnings;
  final List<String> mentionedPlaces;
  final int parentResponseCount;
  final DateTime generatedAt;

  AiSynthesis({
    required this.questionId,
    required this.summary,
    required this.recommendations,
    required this.warnings,
    required this.mentionedPlaces,
    required this.parentResponseCount,
    required this.generatedAt,
  });
}

/// A community travel question
class TravelQuestion {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatarColor;
  final String question;
  final String? destination;
  final String? childAge;
  final String? travelDates;
  final QuestionCategory category;
  final List<String> tags;
  final DateTime createdAt;
  final List<TravelAnswer> answers;
  AiSynthesis? aiSynthesis;
  int views;
  bool isBookmarked;
  bool isSolved;

  TravelQuestion({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatarColor,
    required this.question,
    this.destination,
    this.childAge,
    this.travelDates,
    required this.category,
    List<String>? tags,
    required this.createdAt,
    List<TravelAnswer>? answers,
    this.aiSynthesis,
    this.views = 0,
    this.isBookmarked = false,
    this.isSolved = false,
  })  : tags = tags ?? [],
        answers = answers ?? [];

  int get totalUpvotes => answers.fold(0, (sum, a) => sum + a.upvotes);
  bool get hasAiSynthesis => aiSynthesis != null;
}

/// A curated community tip (short-form, max 3 sentences)
class CommunityTip {
  final String id;
  final String authorName;
  final String authorAvatarColor;
  final String destination;
  final String childAge;
  final String tip;
  final int upvotes;
  final DateTime createdAt;
  final String? sourceQuestionId;
  final List<String> authorBadges;

  CommunityTip({
    required this.id,
    required this.authorName,
    required this.authorAvatarColor,
    required this.destination,
    required this.childAge,
    required this.tip,
    required this.upvotes,
    required this.createdAt,
    this.sourceQuestionId,
    List<String>? authorBadges,
  }) : authorBadges = authorBadges ?? [];
}

/// A saved/bookmarked answer for personal trip research
class SavedAnswer {
  final String answerId;
  final String questionId;
  final String questionText;
  final String answerText;
  final String authorName;
  final String destination;
  final DateTime savedAt;

  SavedAnswer({
    required this.answerId,
    required this.questionId,
    required this.questionText,
    required this.answerText,
    required this.authorName,
    required this.destination,
    required this.savedAt,
  });
}

// =============================================================================
// TRAVEL COMMUNITY SERVICE — Singleton
// =============================================================================

class TravelCommunityService extends ChangeNotifier {
  static final TravelCommunityService _instance =
      TravelCommunityService._internal();
  factory TravelCommunityService() => _instance;
  TravelCommunityService._internal();

  final TravelService _travelService = TravelService();

  final List<TravelQuestion> _questions = [];
  final List<ParentExpertProfile> _experts = [];
  final List<CommunityTip> _tips = [];
  final List<SavedAnswer> _savedAnswers = [];
  bool _isInitialized = false;

  // ── Public getters ────────────────────────────────────────────────────
  List<TravelQuestion> get questions => List.unmodifiable(_questions);
  List<ParentExpertProfile> get experts => List.unmodifiable(_experts);
  List<CommunityTip> get tips => List.unmodifiable(_tips);
  List<SavedAnswer> get savedAnswers => List.unmodifiable(_savedAnswers);

  List<TravelQuestion> get recentQuestions {
    final sorted = List<TravelQuestion>.from(_questions)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  List<TravelQuestion> get hotQuestions {
    final sorted = List<TravelQuestion>.from(_questions)
      ..sort((a, b) => b.totalUpvotes.compareTo(a.totalUpvotes));
    return sorted;
  }

  List<TravelQuestion> get unansweredQuestions =>
      _questions.where((q) => q.answers.isEmpty).toList();

  List<ParentExpertProfile> get topExperts {
    final sorted = List<ParentExpertProfile>.from(_experts)
      ..sort((a, b) => b.totalUpvotes.compareTo(a.totalUpvotes));
    return sorted;
  }

  List<CommunityTip> get trendingTips {
    final sorted = List<CommunityTip>.from(_tips)
      ..sort((a, b) => b.upvotes.compareTo(a.upvotes));
    return sorted;
  }

  // ── Initialization ────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _travelService.initialize();
    _loadSampleData();
    _isInitialized = true;
    notifyListeners();
  }

  // ── Filtering ─────────────────────────────────────────────────────────
  List<TravelQuestion> filterQuestions({
    String? destination,
    String? childAge,
    QuestionCategory? category,
    String? searchQuery,
  }) {
    var results = List<TravelQuestion>.from(_questions);

    if (destination != null && destination.isNotEmpty) {
      results = results
          .where((q) =>
              q.destination?.toLowerCase().contains(destination.toLowerCase()) ??
              false)
          .toList();
    }
    if (childAge != null && childAge.isNotEmpty) {
      results = results
          .where((q) =>
              q.childAge?.toLowerCase().contains(childAge.toLowerCase()) ??
              false)
          .toList();
    }
    if (category != null) {
      results = results.where((q) => q.category == category).toList();
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      results = results
          .where((q) =>
              q.question.toLowerCase().contains(query) ||
              (q.destination?.toLowerCase().contains(query) ?? false) ||
              q.answers.any((a) => a.content.toLowerCase().contains(query)))
          .toList();
    }

    return results..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<ParentExpertProfile> getExpertsForDestination(String destination) {
    return _experts
        .where((e) => e.badges
            .any((b) => b.destinationName.toLowerCase() == destination.toLowerCase()))
        .toList()
      ..sort((a, b) => b.totalUpvotes.compareTo(a.totalUpvotes));
  }

  List<CommunityTip> getTipsForDestination(String destination) {
    return _tips
        .where(
            (t) => t.destination.toLowerCase().contains(destination.toLowerCase()))
        .toList()
      ..sort((a, b) => b.upvotes.compareTo(a.upvotes));
  }

  // ── Posting a question ────────────────────────────────────────────────
  Future<TravelQuestion> postQuestion({
    required String question,
    String? destination,
    String? childAge,
    String? travelDates,
    QuestionCategory category = QuestionCategory.general,
  }) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();

    final autoCategory = _autoDetectCategory(question);
    final autoDestination = destination ?? _autoDetectDestination(question);
    final autoAge = childAge ?? _autoDetectChildAge(question);

    final newQuestion = TravelQuestion(
      id: 'q_${DateTime.now().millisecondsSinceEpoch}',
      authorId: 'current_user',
      authorName: onboarding.name ?? 'You',
      authorAvatarColor: '#FF975C',
      question: question,
      destination: autoDestination,
      childAge: autoAge,
      travelDates: travelDates,
      category: autoCategory ?? category,
      tags: _generateTags(question, autoDestination, autoAge),
      createdAt: DateTime.now(),
    );

    _questions.insert(0, newQuestion);
    notifyListeners();

    // Generate an AI starter answer from existing community data
    _generateAiStarterAnswer(newQuestion);

    return newQuestion;
  }

  // ── Posting an answer ─────────────────────────────────────────────────
  Future<TravelAnswer> postAnswer({
    required String questionId,
    required String content,
    String? visitDate,
    String? childAgesAtVisit,
    List<String>? attachedLinks,
  }) async {
    final onboarding = OnboardingDataService();
    await onboarding.initialize();

    final answer = TravelAnswer(
      id: 'a_${DateTime.now().millisecondsSinceEpoch}',
      questionId: questionId,
      authorId: 'current_user',
      authorName: onboarding.name ?? 'You',
      authorAvatarColor: '#FF975C',
      content: content,
      createdAt: DateTime.now(),
      visitDate: visitDate,
      childAgesAtVisit: childAgesAtVisit,
      attachedLinks: attachedLinks,
      authorBadges: ['been_there'],
    );

    final question = _questions.firstWhere((q) => q.id == questionId);
    question.answers.add(answer);
    notifyListeners();

    // Re-generate AI synthesis if we have 2+ answers
    if (question.answers.where((a) => !a.isAiGenerated).length >= 2) {
      _generateAiSynthesis(question);
    }

    return answer;
  }

  // ── Upvoting ──────────────────────────────────────────────────────────
  void upvoteAnswer(String questionId, String answerId) {
    final question = _questions.firstWhere((q) => q.id == questionId);
    final answer = question.answers.firstWhere((a) => a.id == answerId);

    if (!answer.upvotedBy.contains('current_user')) {
      answer.upvotes++;
      answer.upvotedBy.add('current_user');
      notifyListeners();
    }
  }

  // ── Bookmarking ───────────────────────────────────────────────────────
  void toggleBookmark(String questionId) {
    final question = _questions.firstWhere((q) => q.id == questionId);
    question.isBookmarked = !question.isBookmarked;
    notifyListeners();
  }

  void saveAnswer(TravelAnswer answer, TravelQuestion question) {
    if (_savedAnswers.any((s) => s.answerId == answer.id)) return;
    _savedAnswers.add(SavedAnswer(
      answerId: answer.id,
      questionId: question.id,
      questionText: question.question,
      answerText: answer.content,
      authorName: answer.authorName,
      destination: question.destination ?? 'General',
      savedAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void removeSavedAnswer(String answerId) {
    _savedAnswers.removeWhere((s) => s.answerId == answerId);
    notifyListeners();
  }

  // ── Mark solved ───────────────────────────────────────────────────────
  void markAsSolved(String questionId) {
    final question = _questions.firstWhere((q) => q.id == questionId);
    question.isSolved = true;
    notifyListeners();
  }

  // ── AI Features ───────────────────────────────────────────────────────

  /// Generate an instant AI starter answer from existing community data
  Future<void> _generateAiStarterAnswer(TravelQuestion question) async {
    try {
      // Gather community context
      final relatedTips = _tips
          .where((t) =>
              question.destination != null &&
              t.destination
                  .toLowerCase()
                  .contains(question.destination!.toLowerCase()))
          .take(5)
          .map((t) => '- ${t.authorName}: "${t.tip}"')
          .join('\n');

      final relatedReviews = _travelService.reviews
          .where((r) {
            final dest = _travelService.destinations.firstWhere(
              (d) => d.id == r.destinationId,
              orElse: () => _travelService.destinations.first,
            );
            return question.destination != null &&
                dest.name
                    .toLowerCase()
                    .contains(question.destination!.toLowerCase());
          })
          .take(3)
          .map((r) =>
              '- ${r.parentName} (visited with ${r.childAgesAtVisit}): "${r.review}"')
          .join('\n');

      final prompt =
          '''You are the huddl community AI assistant. A parent has asked a question about family travel. 
Generate a helpful starter answer based on existing community knowledge while we wait for parent responses.

QUESTION: "${question.question}"
${question.destination != null ? 'DESTINATION: ${question.destination}' : ''}
${question.childAge != null ? 'CHILD AGE: ${question.childAge}' : ''}

COMMUNITY DATA:
${relatedTips.isNotEmpty ? 'Parent Tips:\n$relatedTips' : 'No specific tips yet for this destination.'}

${relatedReviews.isNotEmpty ? 'Parent Reviews:\n$relatedReviews' : ''}

GUIDELINES:
- Be helpful but note this is AI-generated while we find parents who can answer from experience
- Use British English (nappy, pushchair, Calpol etc.)
- Give practical, actionable advice
- Reference community data when available
- Keep it concise (3-4 paragraphs max)
- End by encouraging other parents to share their experience
- Start with "While we find parents who've been there..."''';

      final response = await _callGemini(prompt);

      if (response.isNotEmpty) {
        final aiAnswer = TravelAnswer(
          id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
          questionId: question.id,
          authorId: 'ai_concierge',
          authorName: 'AI Travel Assistant',
          authorAvatarColor: '#3580F0',
          content: response,
          createdAt: DateTime.now(),
          isAiGenerated: true,
          authorBadges: ['ai'],
        );

        question.answers.insert(0, aiAnswer);
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI starter answer error: $e');
      }
    }
  }

  /// Generate AI synthesis from multiple parent answers
  Future<void> _generateAiSynthesis(TravelQuestion question) async {
    try {
      final parentAnswers = question.answers
          .where((a) => !a.isAiGenerated)
          .map((a) =>
              '${a.authorName}${a.childAgesAtVisit != null ? " (visited with ${a.childAgesAtVisit})" : ""}: "${a.content}"')
          .join('\n\n');

      final prompt =
          '''Synthesise these parent responses into a concise summary for a UK parent asking about family travel.

QUESTION: "${question.question}"
${question.destination != null ? 'DESTINATION: ${question.destination}' : ''}

PARENT RESPONSES:
$parentAnswers

FORMAT YOUR RESPONSE AS JSON (no markdown, no backticks):
{
  "summary": "2-3 sentence synthesis of key advice",
  "recommendations": ["specific recommendation 1", "specific recommendation 2"],
  "warnings": ["things to avoid or be careful about"],
  "mentioned_places": ["specific places, hotels, restaurants mentioned"]
}

RULES:
- Use British English
- Distil actionable points only
- Credit parent experiences naturally
- Keep it practical and concise''';

      final response = await _callGemini(prompt);

      if (response.isNotEmpty) {
        try {
          var text = response.trim();
          text = text.replaceAll(RegExp(r'^```json\s*'), '');
          text = text.replaceAll(RegExp(r'\s*```$'), '');
          text = text.trim();

          final json = jsonDecode(text) as Map<String, dynamic>;

          question.aiSynthesis = AiSynthesis(
            questionId: question.id,
            summary: json['summary'] as String? ?? '',
            recommendations:
                List<String>.from(json['recommendations'] as List? ?? []),
            warnings: List<String>.from(json['warnings'] as List? ?? []),
            mentionedPlaces:
                List<String>.from(json['mentioned_places'] as List? ?? []),
            parentResponseCount:
                question.answers.where((a) => !a.isAiGenerated).length,
            generatedAt: DateTime.now(),
          );
          notifyListeners();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('AI synthesis JSON parse error: $e');
          }
          // Fallback: use raw text as summary
          question.aiSynthesis = AiSynthesis(
            questionId: question.id,
            summary: response,
            recommendations: [],
            warnings: [],
            mentionedPlaces: [],
            parentResponseCount:
                question.answers.where((a) => !a.isAiGenerated).length,
            generatedAt: DateTime.now(),
          );
          notifyListeners();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI synthesis error: $e');
      }
    }
  }

  /// Generate community-informed AI concierge answer
  Future<String> askCommunityAI(String question) async {
    // Gather relevant community context
    final relatedQuestions = filterQuestions(searchQuery: question).take(3);
    final context = StringBuffer();

    for (final q in relatedQuestions) {
      context.writeln('Q: ${q.question}');
      for (final a in q.answers.where((a) => !a.isAiGenerated).take(2)) {
        context.writeln(
            'A (${a.authorName}): ${a.content.length > 200 ? a.content.substring(0, 200) : a.content}');
      }
      context.writeln('');
    }

    final relatedTips = _tips
        .where((t) => t.tip.toLowerCase().contains(question.toLowerCase().split(' ').take(3).join(' ')))
        .take(5)
        .map((t) => '- ${t.authorName} (${t.destination}): "${t.tip}"')
        .join('\n');

    final prompt =
        '''You are the huddl AI Travel Concierge. Answer this parent's travel question using community knowledge.

QUESTION: "$question"

COMMUNITY CONTEXT:
${context.isNotEmpty ? context.toString() : 'No directly related questions yet.'}

${relatedTips.isNotEmpty ? 'COMMUNITY TIPS:\n$relatedTips' : ''}

GUIDELINES:
- Reference community data: "Based on X parents' experiences..."
- British English
- Practical, actionable advice
- 3-4 paragraphs max
- Suggest posting in "Ask Parents" for more personal answers''';

    return _callGemini(prompt);
  }

  // ── Gemini API call ───────────────────────────────────────────────────
  Future<String> _callGemini(String prompt) async {
    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topP': 0.9,
        'maxOutputTokens': 1024,
      },
    };

    final url = Uri.parse(GeminiConfig.generateContentUrl);

    final httpResponse = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 20));

    if (httpResponse.statusCode == 200) {
      final data = jsonDecode(httpResponse.body);
      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return (parts[0]['text'] as String? ?? '').trim();
        }
      }
    }
    throw Exception('Gemini API error: ${httpResponse.statusCode}');
  }

  // ── Auto-detection helpers ────────────────────────────────────────────
  QuestionCategory? _autoDetectCategory(String question) {
    final q = question.toLowerCase();
    if (q.contains('hotel') || q.contains('stay') || q.contains('airbnb') || q.contains('resort') || q.contains('villa')) {
      return QuestionCategory.accommodation;
    }
    if (q.contains('fly') || q.contains('flight') || q.contains('car hire') || q.contains('drive') || q.contains('airport') || q.contains('airline')) {
      return QuestionCategory.transport;
    }
    if (q.contains('pack') || q.contains('bring') || q.contains('gear') || q.contains('pushchair') || q.contains('sling') || q.contains('carrier')) {
      return QuestionCategory.gear;
    }
    if (q.contains('safe') || q.contains('health') || q.contains('vaccine') || q.contains('hospital') || q.contains('medicine') || q.contains('insurance')) {
      return QuestionCategory.health;
    }
    if (q.contains('food') || q.contains('eat') || q.contains('restaurant') || q.contains('formula') || q.contains('highchair') || q.contains('feeding')) {
      return QuestionCategory.food;
    }
    if (q.contains('do') || q.contains('activity') || q.contains('beach') || q.contains('play') || q.contains('zoo') || q.contains('park')) {
      return QuestionCategory.activities;
    }
    return null;
  }

  String? _autoDetectDestination(String question) {
    final q = question.toLowerCase();
    for (final dest in _travelService.destinations) {
      if (q.contains(dest.name.toLowerCase()) ||
          q.contains(dest.country.toLowerCase())) {
        return dest.name;
      }
    }
    // Common destination keywords
    final destMap = {
      'tenerife': 'Tenerife', 'mallorca': 'Mallorca', 'majorca': 'Mallorca',
      'algarve': 'Algarve', 'portugal': 'Algarve', 'costa del sol': 'Costa del Sol',
      'malaga': 'Costa del Sol', 'cornwall': 'Cornwall', 'cotswolds': 'Cotswolds',
      'crete': 'Crete', 'greece': 'Crete', 'lake garda': 'Lake Garda',
      'italy': 'Lake Garda', 'spain': 'Mallorca', 'france': 'France',
      'dubai': 'Dubai', 'turkey': 'Turkey', 'lanzarote': 'Lanzarote',
      'madeira': 'Madeira', 'florida': 'Florida', 'copenhagen': 'Copenhagen',
    };
    for (final entry in destMap.entries) {
      if (q.contains(entry.key)) return entry.value;
    }
    return null;
  }

  String? _autoDetectChildAge(String question) {
    final q = question.toLowerCase();
    final agePatterns = {
      RegExp(r'(\d+)\s*month'): (Match m) => '${m.group(1)} months',
      RegExp(r'(\d+)\s*mo\b'): (Match m) => '${m.group(1)} months',
      RegExp(r'(\d+)\s*year'): (Match m) => '${m.group(1)} years',
      RegExp(r'(\d+)\s*yr'): (Match m) => '${m.group(1)} years',
      RegExp(r'newborn'): (_) => '0-6 months',
      RegExp(r'baby'): (_) => '6-12 months',
      RegExp(r'toddler'): (_) => '1-2 years',
      RegExp(r'infant'): (_) => '0-12 months',
    };
    for (final entry in agePatterns.entries) {
      final match = entry.key.firstMatch(q);
      if (match != null) return entry.value(match);
    }
    return null;
  }

  List<String> _generateTags(String question, String? destination, String? age) {
    final tags = <String>[];
    if (destination != null) tags.add(destination);
    if (age != null) tags.add(age);
    final q = question.toLowerCase();
    if (q.contains('beach')) tags.add('beach');
    if (q.contains('pushchair') || q.contains('buggy')) tags.add('pushchairs');
    if (q.contains('flight') || q.contains('flying')) tags.add('flights');
    if (q.contains('hotel') || q.contains('resort')) tags.add('hotels');
    if (q.contains('food') || q.contains('eat')) tags.add('dining');
    return tags;
  }

  // ── Sample Data ───────────────────────────────────────────────────────
  void _loadSampleData() {
    // Sample data initialization

    // ── Parent Expert Profiles ──────────────────────────────────────────
    _experts.addAll([
      ParentExpertProfile(
        id: 'expert_1', name: 'Sarah M.', avatarColor: '#FF975C',
        location: 'Cambridge', childAges: ['14 months'],
        bio: 'Mum to Lily. Travelled to 8 countries since she was born. Beach holidays specialist.',
        joinedDate: DateTime(2024, 3, 1), totalAnswers: 28, totalUpvotes: 47,
        specialities: ['Beach holidays', 'Baby travel', 'Spain'],
        badges: [
          BeenThereBadge(destinationId: 'tenerife', destinationName: 'Tenerife', earnedDate: DateTime(2024, 9, 1), answersGiven: 12, upvotesReceived: 22),
          BeenThereBadge(destinationId: 'mallorca', destinationName: 'Mallorca', earnedDate: DateTime(2024, 11, 1), answersGiven: 8, upvotesReceived: 15),
          BeenThereBadge(destinationId: 'malaga', destinationName: 'Costa del Sol', earnedDate: DateTime(2025, 1, 1), answersGiven: 5, upvotesReceived: 10),
        ],
      ),
      ParentExpertProfile(
        id: 'expert_2', name: 'Tom & Emma', avatarColor: '#3580F0',
        location: 'Cambridge', childAges: ['2 years', '4 years'],
        bio: 'Parents to Archie (2) and Mia (4). Tenerife regulars — 3rd year running! Budget travel pros.',
        joinedDate: DateTime(2024, 1, 15), totalAnswers: 35, totalUpvotes: 62,
        specialities: ['Tenerife', 'Budget holidays', 'Toddler travel'],
        badges: [
          BeenThereBadge(destinationId: 'tenerife', destinationName: 'Tenerife', earnedDate: DateTime(2024, 7, 1), answersGiven: 18, upvotesReceived: 30),
          BeenThereBadge(destinationId: 'cornwall', destinationName: 'Cornwall', earnedDate: DateTime(2024, 8, 1), answersGiven: 10, upvotesReceived: 18),
        ],
      ),
      ParentExpertProfile(
        id: 'expert_3', name: 'Priya K.', avatarColor: '#199A85',
        location: 'Cambridge', childAges: ['18 months'],
        bio: 'Solo-travelling mum to Aarav. Short-flight destinations are my thing!',
        joinedDate: DateTime(2024, 5, 10), totalAnswers: 19, totalUpvotes: 31,
        specialities: ['Short-haul flights', 'Solo parent travel', 'Mallorca'],
        badges: [
          BeenThereBadge(destinationId: 'mallorca', destinationName: 'Mallorca', earnedDate: DateTime(2025, 5, 1), answersGiven: 9, upvotesReceived: 16),
          BeenThereBadge(destinationId: 'algarve', destinationName: 'Algarve', earnedDate: DateTime(2024, 10, 1), answersGiven: 6, upvotesReceived: 10),
        ],
      ),
      ParentExpertProfile(
        id: 'expert_4', name: 'James & Lisa', avatarColor: '#F3C54F',
        location: 'Ely', childAges: ['3 years', '5 years'],
        bio: 'Budget-conscious parents. We prove family holidays don\'t have to cost a fortune!',
        joinedDate: DateTime(2024, 4, 20), totalAnswers: 22, totalUpvotes: 38,
        specialities: ['Budget holidays', 'Costa del Sol', 'Self-catering'],
        badges: [
          BeenThereBadge(destinationId: 'malaga', destinationName: 'Costa del Sol', earnedDate: DateTime(2024, 8, 1), answersGiven: 14, upvotesReceived: 24),
        ],
      ),
      ParentExpertProfile(
        id: 'expert_5', name: 'Meg C.', avatarColor: '#FF975C',
        location: 'Newmarket', childAges: ['8 months', '3 years'],
        bio: 'Two kids under 4. Staycation queen — Cornwall is my happy place!',
        joinedDate: DateTime(2024, 6, 1), totalAnswers: 15, totalUpvotes: 24,
        specialities: ['Staycations', 'Cornwall', 'UK breaks'],
        badges: [
          BeenThereBadge(destinationId: 'cornwall', destinationName: 'Cornwall', earnedDate: DateTime(2025, 7, 1), answersGiven: 10, upvotesReceived: 16),
          BeenThereBadge(destinationId: 'cotswolds', destinationName: 'Cotswolds', earnedDate: DateTime(2024, 10, 1), answersGiven: 5, upvotesReceived: 8),
        ],
      ),
      ParentExpertProfile(
        id: 'expert_6', name: 'Rachel W.', avatarColor: '#3580F0',
        location: 'Cambridge', childAges: ['2 years'],
        bio: 'Italian travel enthusiast. Lake Garda is our second home!',
        joinedDate: DateTime(2024, 2, 1), totalAnswers: 12, totalUpvotes: 28,
        specialities: ['Italy', 'Lake Garda', 'Culture holidays'],
        badges: [
          BeenThereBadge(destinationId: 'lakegarda', destinationName: 'Lake Garda', earnedDate: DateTime(2024, 6, 1), answersGiven: 9, upvotesReceived: 20),
        ],
      ),
    ]);

    // ── Community Questions ──────────────────────────────────────────────
    _questions.addAll([
      TravelQuestion(
        id: 'q1',
        authorId: 'user_10', authorName: 'Hannah B.', authorAvatarColor: '#78B0FF',
        question: 'Going to Lisbon with a 7-month-old in September. Best area to stay? Is it pushchair-friendly?',
        destination: 'Lisbon', childAge: '7 months', travelDates: 'September 2025',
        category: QuestionCategory.accommodation,
        tags: ['Lisbon', '7 months', 'pushchairs', 'hotels'],
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        views: 42,
        answers: [
          TravelAnswer(
            id: 'a1_1', questionId: 'q1', authorId: 'expert_3',
            authorName: 'Priya K.', authorAvatarColor: '#199A85',
            content: 'We stayed in Parque das Nacoes — avoid Alfama! The cobblestones are a nightmare with a pushchair. Parque das Nacoes is flat, modern, and has a brilliant aquarium (Oceanario) that\'s fully buggy-accessible with baby-change rooms. Hotel Myriad by SANA was excellent for families.',
            createdAt: DateTime.now().subtract(const Duration(hours: 2)),
            upvotes: 8, upvotedBy: ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8'],
            visitDate: 'October 2024', childAgesAtVisit: '15 months',
            authorBadges: ['been_there', 'trusted'],
          ),
          TravelAnswer(
            id: 'a1_2', questionId: 'q1', authorId: 'expert_1',
            authorName: 'Sarah M.', authorAvatarColor: '#FF975C',
            content: 'Agree with Priya on Parque das Nacoes! We went in September too — weather was still warm (25-28°C). The Oceanario is honestly one of the best aquariums we\'ve ever visited. Also, the cable car is pushchair-friendly and the kids loved it. Belem is also doable with a buggy along the waterfront. The pasteis de nata from Pasteis de Belem are a must but go before 11am to avoid the queue!',
            createdAt: DateTime.now().subtract(const Duration(hours: 1)),
            upvotes: 5, upvotedBy: ['u2', 'u4', 'u6', 'u8', 'u10'],
            visitDate: 'September 2024', childAgesAtVisit: '10 months',
            authorBadges: ['been_there'],
          ),
        ],
        aiSynthesis: AiSynthesis(
          questionId: 'q1',
          summary: 'Based on 2 parent experiences in Lisbon with babies aged 10-15 months, Parque das Nacoes is the clear recommendation for pushchair accessibility. Both parents advise against Alfama due to cobblestones.',
          recommendations: ['Stay in Parque das Nacoes (flat, modern, family-friendly)', 'Visit Oceanario — buggy-accessible with baby-change rooms', 'Hotel Myriad by SANA recommended for families', 'Belem waterfront is also pushchair-friendly', 'Visit Pasteis de Belem before 11am'],
          warnings: ['Avoid Alfama — cobblestones are very difficult with a pushchair'],
          mentionedPlaces: ['Parque das Nacoes', 'Oceanario', 'Hotel Myriad by SANA', 'Belem', 'Pasteis de Belem'],
          parentResponseCount: 2,
          generatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        ),
      ),
      TravelQuestion(
        id: 'q2',
        authorId: 'user_11', authorName: 'David R.', authorAvatarColor: '#199A85',
        question: 'First time flying with a 10-month-old to Tenerife. Any tips for the flight and what to pack in hand luggage?',
        destination: 'Tenerife', childAge: '10 months',
        category: QuestionCategory.transport,
        tags: ['Tenerife', '10 months', 'flights', 'packing'],
        createdAt: DateTime.now().subtract(const Duration(hours: 8)),
        views: 67,
        answers: [
          TravelAnswer(
            id: 'a2_1', questionId: 'q2', authorId: 'expert_2',
            authorName: 'Tom & Emma', authorAvatarColor: '#3580F0',
            content: 'We\'ve done this flight 3 times now! Key tips:\n\n• **Book a seat near the back** — closer to toilets and more space for standing/bouncing a fussy baby\n• **Feed on takeoff and landing** — bottle or breastfeed to help their ears\n• **Calpol sachets in hand luggage** — liquid is under 100ml so it\'s fine\n• **New small toy** — something they haven\'t seen before buys you 30 mins\n• **Snack pouches** — Ella\'s Kitchen or similar, the cabin crew don\'t count them as liquids\n• **Change of clothes for baby AND you** — trust us on this one\n• **Pushchair to the gate** — they\'ll gate-check it and return it when you land\n\nThe flight is 4h 30m which is perfectly nap-able. Our youngest slept most of it at that age!',
            createdAt: DateTime.now().subtract(const Duration(hours: 6)),
            upvotes: 14, upvotedBy: List.generate(14, (i) => 'u$i'),
            visitDate: 'July 2025', childAgesAtVisit: '2yr, 4yr',
            authorBadges: ['been_there', 'expert'],
          ),
          TravelAnswer(
            id: 'a2_2', questionId: 'q2', authorId: 'expert_5',
            authorName: 'Meg C.', authorAvatarColor: '#FF975C',
            content: 'Adding to Tom & Emma\'s brilliant list — ask for a **bassinet** when booking if your airline offers them (usually for under-1s). BA and easyJet both do them on Canary Islands flights. Also, baby wearing through security is SO much easier than trying to fold a pushchair while holding a baby. I always wear the sling through the airport and gate-check the buggy.',
            createdAt: DateTime.now().subtract(const Duration(hours: 4)),
            upvotes: 9, upvotedBy: List.generate(9, (i) => 'u${i + 20}'),
            childAgesAtVisit: '8 months',
            authorBadges: ['been_there'],
          ),
        ],
        aiSynthesis: AiSynthesis(
          questionId: 'q2',
          summary: 'Based on experienced parents who\'ve flown to Tenerife with babies multiple times: feed during takeoff/landing for ear pressure, pack Calpol sachets and snack pouches in hand luggage, and bring a change of clothes for everyone.',
          recommendations: ['Book seats near the back for toilet access', 'Gate-check pushchair, wear sling through security', 'Pack new toys for distraction', 'Ask about bassinet seats for under-1s', 'Ella\'s Kitchen pouches don\'t count as liquids'],
          warnings: ['Pack spare clothes for parent too — not just baby'],
          mentionedPlaces: ['Tenerife'],
          parentResponseCount: 2,
          generatedAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      ),
      TravelQuestion(
        id: 'q3',
        authorId: 'user_12', authorName: 'Laura S.', authorAvatarColor: '#F3C54F',
        question: 'Can anyone recommend a baby-friendly hotel in Mallorca? Need a cot, shallow pool, and ideally near a calm beach. Travelling with a 12-month-old.',
        destination: 'Mallorca', childAge: '12 months',
        category: QuestionCategory.accommodation,
        tags: ['Mallorca', '12 months', 'hotels', 'beach'],
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        views: 89,
        isSolved: true,
        answers: [
          TravelAnswer(
            id: 'a3_1', questionId: 'q3', authorId: 'expert_3',
            authorName: 'Priya K.', authorAvatarColor: '#199A85',
            content: 'We stayed at Zafiro Palace Alcudia and it was PERFECT for this exact brief. They had cots available (free), a dedicated toddler pool (maybe 10cm deep, warm, shaded), and Alcudia Beach is literally a 5 minute walk — the water is incredibly shallow for ages. Our 18-month-old could wade out for what felt like forever!\n\nThe hotel also had a baby club (limited hours) and a really good buffet with baby food options. Staff were lovely with little ones. Can\'t recommend it enough!',
            createdAt: DateTime.now().subtract(const Duration(hours: 20)),
            upvotes: 12, upvotedBy: List.generate(12, (i) => 'u$i'),
            visitDate: 'May 2025', childAgesAtVisit: '18 months',
            authorBadges: ['been_there', 'trusted'],
          ),
        ],
      ),
      TravelQuestion(
        id: 'q4',
        authorId: 'user_13', authorName: 'Kirsty W.', authorAvatarColor: '#78B0FF',
        question: 'Planning a ski holiday with a 2-year-old and 4-year-old. Is it even worth it? Where in Europe is best for toddler-friendly skiing?',
        destination: null, childAge: '2 years, 4 years',
        category: QuestionCategory.activities,
        tags: ['skiing', 'winter', 'toddler'],
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        views: 45,
        answers: [
          TravelAnswer(
            id: 'a4_1', questionId: 'q4', authorId: 'expert_4',
            authorName: 'James & Lisa', authorAvatarColor: '#F3C54F',
            content: 'Yes, absolutely worth it! We took ours at 3 and 5, and our only regret is not going sooner. Key tips:\n\n• **Austria** is the best for families — try Serfaus-Fiss-Ladis. It literally has an underground train for kids and a massive play area on the mountain\n• A **Decathlon baby sled** (about £15) was the best purchase we made. The 2-year-old loved being pulled around in the snow\n• Most resorts have **ski kindergarten** from age 3, some from age 2.5\n• Book a **chalet or apartment** rather than hotel — you need space for drying gear and early bedtimes\n• Don\'t ski every day — alternate with snow play, sledging, and hot chocolate stops\n\nThe 4-year-old will probably be ready for actual ski lessons. The 2-year-old will love the snow but lessons at that age are more like supervised play.',
            createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 12)),
            upvotes: 11, upvotedBy: List.generate(11, (i) => 'u$i'),
            authorBadges: ['been_there'],
          ),
        ],
      ),
      TravelQuestion(
        id: 'q5',
        authorId: 'user_14', authorName: 'Amy T.', authorAvatarColor: '#199A85',
        question: 'Is it safe to take formula through customs in Spain? Flying with a 6-month-old and worried about getting it confiscated at security.',
        destination: 'Spain', childAge: '6 months',
        category: QuestionCategory.health,
        tags: ['Spain', '6 months', 'formula', 'flights', 'health'],
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        views: 112,
        isSolved: true,
        answers: [
          TravelAnswer(
            id: 'a5_1', questionId: 'q5', authorId: 'expert_1',
            authorName: 'Sarah M.', authorAvatarColor: '#FF975C',
            content: 'Don\'t worry at all! I\'ve taken formula through UK and Spanish security dozens of times. The rules are:\n\n• **Formula, breast milk, and baby food are EXEMPT from the 100ml liquid rule**\n• You DO need to declare it at security — just show it to the officer\n• They may test it (they just open and sniff or use a strip test)\n• **Tip: pre-measure powder into individual portions** in small ziplock bags and just add water on the plane. This avoids carrying heavy liquid formula entirely\n• Most airlines will heat bottles for you if you ask — cabin crew are usually brilliant\n\nFor Spain specifically, Mercadona and Lidl both stock UK-compatible formula. We found Aptamil in Mercadona in Tenerife. But bring enough for the whole trip plus 2 extra days just in case!',
            createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 18)),
            upvotes: 19, upvotedBy: List.generate(19, (i) => 'u$i'),
            visitDate: 'Multiple trips', childAgesAtVisit: '6-14 months',
            authorBadges: ['been_there', 'expert'],
          ),
        ],
      ),
      TravelQuestion(
        id: 'q6',
        authorId: 'user_15', authorName: 'Nadia H.', authorAvatarColor: '#FF975C',
        question: 'Cornwall or Devon for a week with a toddler in July? Both look great but can only pick one!',
        destination: 'Cornwall', childAge: 'Toddler',
        category: QuestionCategory.general,
        tags: ['Cornwall', 'Devon', 'staycation', 'toddler'],
        createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
        views: 53,
        answers: [
          TravelAnswer(
            id: 'a6_1', questionId: 'q6', authorId: 'expert_5',
            authorName: 'Meg C.', authorAvatarColor: '#FF975C',
            content: 'Cornwall every time for me! Here\'s why:\n\n• **Beaches** — St Ives and Sennen Cove have the softest sand and warmest water in the UK\n• **Eden Project** — rainy day gold with under-5s activities (and there WILL be a rainy day!)\n• **Padstow** — fish and chips on the harbour wall is a core memory waiting to happen\n• **Rock pooling** — anywhere on the north coast is brilliant. Little ones are fascinated\n• **The Minack Theatre** — even if your toddler can\'t sit through a show, the cliff-top views are worth the drive\n\nDevon is lovely too (Woolacombe beach is stunning) but Cornwall just edges it for variety. Only downside: it\'s a long drive from Cambridge (5-6 hours). Leave at 5am while they sleep!',
            createdAt: DateTime.now().subtract(const Duration(hours: 22)),
            upvotes: 7, upvotedBy: List.generate(7, (i) => 'u$i'),
            visitDate: 'July 2025', childAgesAtVisit: '8 months, 3 years',
            authorBadges: ['been_there', 'trusted'],
          ),
        ],
      ),
    ]);

    // ── Community Tips ──────────────────────────────────────────────────
    _tips.addAll([
      CommunityTip(id: 't1', authorName: 'Tom & Emma', authorAvatarColor: '#3580F0', destination: 'Tenerife', childAge: '1-3yr', tip: 'Lidl in Los Cristianos stocks Ella\'s Kitchen pouches, Sudocrem, and Pampers. Don\'t fill your suitcase with supplies — buy them there for half the price!', upvotes: 24, createdAt: DateTime.now().subtract(const Duration(days: 5)), authorBadges: ['expert']),
      CommunityTip(id: 't2', authorName: 'Priya K.', authorAvatarColor: '#199A85', destination: 'Mallorca', childAge: '6-12m', tip: 'Alcudia Beach is the shallowest beach I\'ve ever seen — your baby can literally sit in ankle-deep warm water for 20 metres out. Perfect for first beach holiday.', upvotes: 19, createdAt: DateTime.now().subtract(const Duration(days: 3)), authorBadges: ['trusted']),
      CommunityTip(id: 't3', authorName: 'Sarah M.', authorAvatarColor: '#FF975C', destination: 'Tenerife', childAge: '0-12m', tip: 'Book the Siam Park baby area early (before 10am). By midday it\'s packed. Also, they don\'t allow swim nappies in the wave pool — only the baby/toddler section.', upvotes: 16, createdAt: DateTime.now().subtract(const Duration(days: 7)), authorBadges: ['trusted']),
      CommunityTip(id: 't4', authorName: 'Meg C.', authorAvatarColor: '#FF975C', destination: 'Cornwall', childAge: '0-3yr', tip: 'Pack waterproofs for Cornwall even in August! We\'ve been caught out every single year. Eden Project is the perfect rainy-day backup — their under-5s area is brilliant.', upvotes: 15, createdAt: DateTime.now().subtract(const Duration(days: 4)), authorBadges: ['trusted']),
      CommunityTip(id: 't5', authorName: 'James & Lisa', authorAvatarColor: '#F3C54F', destination: 'Costa del Sol', childAge: '2-5yr', tip: 'Fuengirola > Malaga city with toddlers. The beach has a playground right on the promenade, chiringuitos serve kids\' meals, and you can eat out as a family of 4 for about £30.', upvotes: 13, createdAt: DateTime.now().subtract(const Duration(days: 6)), authorBadges: ['been_there']),
      CommunityTip(id: 't6', authorName: 'Rachel W.', authorAvatarColor: '#3580F0', destination: 'Lake Garda', childAge: '1-3yr', tip: 'Italians absolutely adore children. Every restaurant brought colouring sheets and bread the moment we sat down. Sirmione thermal baths have a toddler section — blissful!', upvotes: 11, createdAt: DateTime.now().subtract(const Duration(days: 8)), authorBadges: ['been_there']),
      CommunityTip(id: 't7', authorName: 'Sarah M.', authorAvatarColor: '#FF975C', destination: 'General', childAge: '0-12m', tip: 'Pre-measure formula powder into ziplock bags for the flight. Just ask cabin crew for warm water — they\'re always happy to help. Avoids carrying heavy liquid formula through security.', upvotes: 21, createdAt: DateTime.now().subtract(const Duration(days: 2)), authorBadges: ['expert']),
      CommunityTip(id: 't8', authorName: 'Tom & Emma', authorAvatarColor: '#3580F0', destination: 'General', childAge: '0-5yr', tip: 'Always take a photo of your hotel room number and address in the local language. Saved us when our toddler had a fever and we needed to tell the taxi driver where to go.', upvotes: 18, createdAt: DateTime.now().subtract(const Duration(days: 9)), authorBadges: ['expert']),
      CommunityTip(id: 't9', authorName: 'Priya K.', authorAvatarColor: '#199A85', destination: 'Mallorca', childAge: '1-2yr', tip: 'The 2.5-hour flight to Mallorca is the perfect length for a baby nap. We timed our flight for nap time and she slept the entire way. Game changer!', upvotes: 14, createdAt: DateTime.now().subtract(const Duration(days: 1)), authorBadges: ['trusted']),
      CommunityTip(id: 't10', authorName: 'Meg C.', authorAvatarColor: '#FF975C', destination: 'Cotswolds', childAge: '0-5yr', tip: 'Cotswold Farm Park is worth the drive even for under-1s. The animal petting area is low enough for little hands and the outdoor play area is fenced. Bourton-on-the-Water is postcard-perfect but go early — it\'s heaving by midday.', upvotes: 10, createdAt: DateTime.now().subtract(const Duration(days: 10)), authorBadges: ['been_there']),
    ]);
  }
}
