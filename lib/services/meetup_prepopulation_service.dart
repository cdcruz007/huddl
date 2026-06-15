import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_api_helper.dart';
import 'ai_knowledge_base_service.dart';
import 'borough_scope_guard.dart';
import 'onboarding_data_service.dart';
import 'meetup_service.dart';

// =============================================================================
// MEETUP PREPOPULATION SERVICE  — PARENT CONCIERGE EDITION (Step 12)
//
// Pre-creates community meetups in each borough based on:
//   1. NCT Walk & Talk, Bumps & Babies, First Aid patterns
//   2. Netmums seasonal activity patterns
//   3. Borough-specific venue suggestions from Knowledge Base directory
//   4. Time-of-week patterns: weekday mornings for parents-at-home,
//      weekends for working parents, evenings for parents-only socials
//   5. AI-generated meetup descriptions personalised to the borough
// =============================================================================

/// A meetup template sourced from community patterns.
class MeetupTemplate {
  final String name;
  final String category;
  final String description;
  final String audience; // expecting, new_parent, dad, toddler_parent, all
  final int dayOfWeek; // DateTime.monday..sunday
  final int hour;
  final int durationMinutes;
  final bool isFree;
  final String source; // nct, netmums, dadsnet, nhs

  const MeetupTemplate({
    required this.name,
    required this.category,
    required this.description,
    required this.audience,
    required this.dayOfWeek,
    required this.hour,
    this.durationMinutes = 90,
    this.isFree = true,
    required this.source,
  });
}

class MeetupPrepopulationService {
  static final MeetupPrepopulationService _instance =
      MeetupPrepopulationService._internal();
  factory MeetupPrepopulationService() => _instance;
  MeetupPrepopulationService._internal();

  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final OnboardingDataService _onboarding = OnboardingDataService();

  bool _isInitialized = false;
  final List<Meetup> _prepopulatedMeetups = [];

  List<Meetup> get prepopulatedMeetups =>
      List.unmodifiable(_prepopulatedMeetups);

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _onboarding.initialize();
    await _knowledgeBase.initialize();
    _isInitialized = true;
  }

  /// Single source of truth — delegates to BoroughScopeGuard.
  /// Returns '' when borough is unresolved (never a hardcoded fallback).
  String _getUserBorough() => BoroughScopeGuard().currentBorough ?? '';

  /// Generate prepopulated meetups for the user's borough.
  Future<List<Meetup>> generateMeetupsForBorough({String? borough}) async {
    await initialize();
    final targetBorough = borough ?? _getUserBorough();
    final now = DateTime.now();

    _prepopulatedMeetups.clear();

    // Get borough directory for venue names
    final boroughDir = _knowledgeBase.getBoroughDirectory(targetBorough);
    final venues = _buildVenueList(boroughDir, targetBorough);

    // Get meetup templates
    final templates = _getMeetupTemplates();

    // Try AI-enhanced descriptions
    Map<String, String>? aiDescriptions;
    try {
      aiDescriptions = await _getAiMeetupDescriptions(targetBorough, templates);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AI meetup description generation error: $e');
      }
    }

    for (int i = 0; i < templates.length; i++) {
      final template = templates[i];
      final nextDate = _nextOccurrence(now, template.dayOfWeek);
      final venue = venues[i % venues.length];
      final endHour = template.hour + (template.durationMinutes ~/ 60);
      final endMin = template.durationMinutes % 60;

      final description = aiDescriptions?[template.name] ??
          template.description.replaceAll('{borough}', targetBorough);

      final meetup = Meetup(
        id: 'prepop_${template.category}_${i}_${targetBorough.toLowerCase().replaceAll(' ', '_')}',
        title: '${template.name} \u2014 $targetBorough',
        description: description,
        category: template.category,
        dateDisplay: _formatDate(nextDate),
        timeDisplay:
            '${_fmtTime(template.hour, 0)} \u2013 ${_fmtTime(endHour, endMin)}',
        dateTime: DateTime(
            nextDate.year, nextDate.month, nextDate.day, template.hour),
        location: '$venue, $targetBorough',
        organiserName: _sourceOrgName(template.source),
        organiserId: 'system_${template.source}',
        attendeeCount: 0,
        isGoing: false,
        attendeeNames: const [],
        isFree: template.isFree,
        borough: targetBorough,
        privacy: MeetupPrivacy.public,
      );

      _prepopulatedMeetups.add(meetup);
    }

    _log('Generated ${_prepopulatedMeetups.length} meetups for $targetBorough');
    return List.unmodifiable(_prepopulatedMeetups);
  }

  // ── Meetup Templates ──────────────────────────────────────────────────

  List<MeetupTemplate> _getMeetupTemplates() {
    return const [
      // NCT-sourced patterns
      MeetupTemplate(
        name: 'Walk & Talk',
        category: 'Walk',
        description:
            'Gentle buggy walk around {borough} with other local parents. Fresh air, '
            'light exercise, and friendly conversation. All welcome!',
        audience: 'all',
        dayOfWeek: DateTime.tuesday,
        hour: 10,
        durationMinutes: 90,
        source: 'nct',
      ),
      MeetupTemplate(
        name: 'Bumps & Babies',
        category: 'Social',
        description:
            'Drop-in for expecting parents and those with babies in {borough}. '
            'Tea, biscuits, and a warm welcome. Share stories and make friends.',
        audience: 'expecting',
        dayOfWeek: DateTime.wednesday,
        hour: 10,
        durationMinutes: 120,
        source: 'nct',
      ),
      MeetupTemplate(
        name: 'Baby Sensory Play',
        category: 'Activity',
        description:
            'Sensory play session for babies 0-12 months in {borough}. '
            'Lights, textures, sounds, and gentle music. Great for development!',
        audience: 'new_parent',
        dayOfWeek: DateTime.thursday,
        hour: 10,
        durationMinutes: 60,
        source: 'netmums',
      ),
      MeetupTemplate(
        name: 'Toddler Park Playdate',
        category: 'Playdate',
        description:
            'Meet other toddler parents at the park in {borough}. Bring snacks, '
            'let the little ones run free, and enjoy some grown-up chat.',
        audience: 'toddler_parent',
        dayOfWeek: DateTime.friday,
        hour: 10,
        durationMinutes: 90,
        source: 'netmums',
      ),
      MeetupTemplate(
        name: 'Dad & Kids Saturday Club',
        category: 'Social',
        description:
            'Saturday morning meetup for dads and their kids in {borough}. '
            'Parks, soft play, or a cafe. Meet other hands-on local dads!',
        audience: 'dad',
        dayOfWeek: DateTime.saturday,
        hour: 10,
        durationMinutes: 120,
        source: 'dadsnet',
      ),
      MeetupTemplate(
        name: 'Coffee & Chat',
        category: 'Coffee',
        description:
            'Relaxed coffee morning for parents in {borough}. '
            'Bring the little ones and enjoy a hot drink while it is still warm.',
        audience: 'all',
        dayOfWeek: DateTime.monday,
        hour: 10,
        durationMinutes: 90,
        source: 'nct',
      ),
      MeetupTemplate(
        name: 'Library Rhyme Time',
        category: 'Activity',
        description:
            'Free rhyme time session at {borough} library. Songs, stories, and action '
            'rhymes for babies and toddlers. Stay for a coffee afterwards!',
        audience: 'all',
        dayOfWeek: DateTime.wednesday,
        hour: 11,
        durationMinutes: 45,
        source: 'nhs',
      ),
      MeetupTemplate(
        name: 'Parents Evening Social',
        category: 'Social',
        description:
            'Leave the kids with a babysitter and enjoy a child-free evening in {borough}! '
            'Dinner, drinks, or just good conversation with other local parents.',
        audience: 'all',
        dayOfWeek: DateTime.friday,
        hour: 19,
        durationMinutes: 180,
        isFree: false,
        source: 'netmums',
      ),
      MeetupTemplate(
        name: 'Nearly New Sale',
        category: 'Marketplace',
        description:
            'Buy and sell quality preloved baby items at bargain prices in {borough}. '
            'Pushchairs, clothes, toys, books. Cash and card accepted.',
        audience: 'all',
        dayOfWeek: DateTime.saturday,
        hour: 10,
        durationMinutes: 180,
        source: 'nct',
      ),
      MeetupTemplate(
        name: 'Swimming for Tots',
        category: 'Activity',
        description:
            'Baby and toddler swimming session at {borough} leisure centre. '
            'From 3 months. Build water confidence in a warm, shallow pool.',
        audience: 'all',
        dayOfWeek: DateTime.thursday,
        hour: 9,
        durationMinutes: 45,
        isFree: false,
        source: 'netmums',
      ),
    ];
  }

  // ── Venue list from borough directory ────────────────────────────────

  List<String> _buildVenueList(
      BoroughLocalDirectory? dir, String borough) {
    if (dir == null) {
      return [
        '$borough Community Centre',
        '$borough Central Park',
        '$borough Library',
        '$borough Family Cafe',
        '$borough Leisure Centre',
      ];
    }

    final venues = <String>[];
    if (dir.localParks.isNotEmpty) venues.add(dir.localParks.first);
    if (dir.localCommunityHalls.isNotEmpty) {
      venues.add(dir.localCommunityHalls.first);
    }
    if (dir.localLibraries.isNotEmpty) venues.add(dir.localLibraries.first);
    if (dir.localCafes.isNotEmpty) venues.add(dir.localCafes.first);
    if (dir.localLeisureCentres.isNotEmpty) {
      venues.add(dir.localLeisureCentres.first);
    }
    if (venues.isEmpty) venues.add('$borough Community Centre');
    return venues;
  }

  // ── AI Description Generation ────────────────────────────────────────

  Future<Map<String, String>> _getAiMeetupDescriptions(
    String borough,
    List<MeetupTemplate> templates,
  ) async {
    final templateList = templates
        .map((t) => '"${t.name}": "${t.category}"')
        .join(', ');

    final systemPrompt =
        'You are writing meetup descriptions for Huddl, a UK parenting community app.\n'
        'Borough: $borough\n\n'
        'For each meetup, write a warm 2-sentence description in British English.\n'
        'Mention $borough. Sound friendly. Make new parents feel welcome.\n\n'
        'Meetups: {$templateList}\n\n'
        'RESPOND IN EXACT JSON (no markdown):\n'
        '{"Walk & Talk": "description...", "Bumps & Babies": "description...", ...}';

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
            {'text': 'Generate meetup descriptions for $borough.'}
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
          final parsed = jsonDecode(text) as Map<String, dynamic>;
          return parsed.map((k, v) => MapEntry(k, v.toString()));
        }
      }
    } catch (_) {}

    return {};
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  DateTime _nextOccurrence(DateTime from, int weekday) {
    var d = from.add(const Duration(days: 1));
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  String _formatDate(DateTime d) {
    const dayAbbr = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const monthAbbr = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    return '${dayAbbr[d.weekday - 1]}, ${monthAbbr[d.month - 1]} ${d.day}';
  }

  String _fmtTime(int hour, int min) {
    final h = hour > 12 ? hour - 12 : hour;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final m = min > 0 ? ':${min.toString().padLeft(2, '0')}' : ':00';
    return '$h$m $ampm';
  }

  String _sourceOrgName(String source) {
    switch (source) {
      case 'nct':
        return 'NCT Local';
      case 'netmums':
        return 'Huddl Community';
      case 'dadsnet':
        return 'Dads Connect';
      case 'nhs':
        return 'Local Library';
      default:
        return 'Community Organiser';
    }
  }

  // _generateAttendeeNames removed — no fake attendee names in production.

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('\u{1F4C5} MeetupPrepopulation: $message');
    }
  }
}
