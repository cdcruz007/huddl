import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// AI PARENTING KNOWLEDGE BASE SERVICE  — HYPERLOCAL EDITION
//
// Centralised, structured parenting knowledge sourced from trusted UK websites:
//   - NHS (nhs.uk)           — Clinical guidelines, vaccinations, safety
//   - NCT (nct.org.uk)       — Antenatal, postnatal, groups & workshops
//   - Bounty (bounty.com)    — Pregnancy stages, baby milestones, vouchers
//   - Netmums (netmums.com)  — Real-parent advice, activities, local tips
//   - Dadsnet (dadsnet.com)  — Father-focused parenting, mental health, play
//
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ HYPERLOCAL ARCHITECTURE                                                 │
// │                                                                         │
// │  Borough is the PRIMARY scope for all social features:                  │
// │    • Groups       — same-borough parents ONLY                           │
// │    • Meetups      — same-borough parents ONLY                           │
// │    • Chat / DMs   — same-borough parents ONLY                           │
// │    • Marketplace  — same-borough parents ONLY (buy/sell locally)        │
// │                                                                         │
// │  The ONLY UK-wide feature is Events:                                    │
// │    • Events can be browsed across ANY borough / the whole UK            │
// │    • Parents travelling can see events at their destination             │
// │                                                                         │
// │  This Knowledge Base now:                                               │
// │    1. Stores a BoroughLocalDirectory per borough (venues, parks, etc.)  │
// │    2. Scopes CommunityTemplates to the user's borough                   │
// │    3. Builds all Gemini prompt context with borough-first framing       │
// │    4. Provides marketplace safety knowledge per borough                 │
// │    5. Surfaces seasonal tips with borough-local activity suggestions    │
// └──────────────────────────────────────────────────────────────────────────┘
// =============================================================================

/// Top-level categories the knowledge base is organised into.
enum KnowledgeCategory {
  pregnancy,
  newborn, // 0-12 weeks
  baby, // 3-12 months
  toddler, // 1-3 years
  preschool, // 3-5 years
  schoolAge, // 5+
  feeding,
  sleep,
  health,
  mentalHealth,
  development,
  safety,
  finance,
  education,
  activities,
  dadSpecific,
  marketplace,
  socialConnection,
}

/// Scope of a piece of content — hyperlocal vs UK-wide.
enum ContentScope {
  boroughOnly, // Chat, Groups, Meetups, Marketplace
  ukWide, // Events, general articles
}

/// A single knowledge article — the atomic unit of the knowledge base.
class KnowledgeArticle {
  final String id;
  final String title;
  final String summary; // 1-3 sentence overview
  final String body; // Full knowledge text
  final KnowledgeCategory category;
  final List<String> tags;
  final String source; // nhs | nct | bounty | netmums | dadsnet
  final String? sourceUrl;
  final List<String> ageStages; // e.g. ['newborn','baby'] or ['all']
  final double relevanceWeight; // 0.0 - 1.0 — how universally useful
  final DateTime lastUpdated;

  const KnowledgeArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.body,
    required this.category,
    this.tags = const [],
    required this.source,
    this.sourceUrl,
    this.ageStages = const ['all'],
    this.relevanceWeight = 0.5,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'body': body,
        'category': category.name,
        'tags': tags,
        'source': source,
        'sourceUrl': sourceUrl,
        'ageStages': ageStages,
        'relevanceWeight': relevanceWeight,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory KnowledgeArticle.fromJson(Map<String, dynamic> json) {
    return KnowledgeArticle(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      body: json['body'] as String,
      category: KnowledgeCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => KnowledgeCategory.health,
      ),
      tags: List<String>.from(json['tags'] ?? []),
      source: json['source'] as String,
      sourceUrl: json['sourceUrl'] as String?,
      ageStages: List<String>.from(json['ageStages'] ?? ['all']),
      relevanceWeight: (json['relevanceWeight'] as num?)?.toDouble() ?? 0.5,
      lastUpdated:
          DateTime.tryParse(json['lastUpdated'] ?? '') ?? DateTime.now(),
    );
  }
}

/// Baby development milestone — month-keyed.
class DevelopmentMilestone {
  final int ageMonths;
  final String label; // e.g. "First smile"
  final String description;
  final String nhsGuidance;
  final String parentTip;
  final List<String> warningSignsToWatch;

  const DevelopmentMilestone({
    required this.ageMonths,
    required this.label,
    required this.description,
    required this.nhsGuidance,
    required this.parentTip,
    this.warningSignsToWatch = const [],
  });
}

/// UK vaccination schedule item.
class VaccinationItem {
  final int ageWeeks; // age in weeks when due
  final String name;
  final String protectsAgainst;
  final String nhsNote;

  const VaccinationItem({
    required this.ageWeeks,
    required this.name,
    required this.protectsAgainst,
    required this.nhsNote,
  });
}

/// Safety recall item for marketplace awareness.
class SafetyRecall {
  final String productName;
  final String manufacturer;
  final String reason;
  final String dateIssued;
  final String source;

  const SafetyRecall({
    required this.productName,
    required this.manufacturer,
    required this.reason,
    required this.dateIssued,
    required this.source,
  });
}

/// Seasonal parenting tip — rotated monthly, now with borough placeholders.
class SeasonalTip {
  final int month; // 1-12
  final String title;
  final String body;
  final List<String> suggestedActivities;
  final String source;

  const SeasonalTip({
    required this.month,
    required this.title,
    required this.body,
    this.suggestedActivities = const [],
    required this.source,
  });

  /// Render the tip body with the user's borough name inserted.
  String renderForBorough(String borough) {
    return body.replaceAll('{borough}', borough);
  }
}

// =============================================================================
// BOROUGH LOCAL DIRECTORY
//
// A lightweight model describing the local resources, venues, and facilities
// that exist within a specific borough. When Gemini generates suggestions
// for groups, meetups, marketplace listings, or copilot advice, it can ground
// its output in real-world local context.
//
// On first use, this is populated with a set of generic UK-typical venues.
// In production, it would be enriched via council APIs, Google Places, etc.
// =============================================================================

/// A single local venue / resource within a borough.
class LocalVenue {
  final String name;
  final String type; // park, library, leisure_centre, cafe, church_hall, etc.
  final String? address;
  final bool freeEntry;
  final List<String> suitableFor; // e.g. ['baby', 'toddler', 'pushchair_friendly']

  const LocalVenue({
    required this.name,
    required this.type,
    this.address,
    this.freeEntry = true,
    this.suitableFor = const ['all'],
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'address': address,
        'freeEntry': freeEntry,
        'suitableFor': suitableFor,
      };
}

/// The full local directory for a single borough.
class BoroughLocalDirectory {
  final String borough;
  final List<LocalVenue> venues;
  final List<String> localParks;
  final List<String> localLibraries;
  final List<String> localLeisureCentres;
  final List<String> localCafes; // family-friendly cafes
  final List<String> localCommunityHalls;
  final String? councilWebsite;
  final String? nhsTrustName; // local NHS trust
  final String? childrensCentreInfo;

  const BoroughLocalDirectory({
    required this.borough,
    this.venues = const [],
    this.localParks = const [],
    this.localLibraries = const [],
    this.localLeisureCentres = const [],
    this.localCafes = const [],
    this.localCommunityHalls = const [],
    this.councilWebsite,
    this.nhsTrustName,
    this.childrensCentreInfo,
  });

  /// Build a prompt-friendly summary of the borough's local resources.
  String toPromptContext() {
    final buf = StringBuffer();
    buf.writeln('LOCAL RESOURCES IN $borough:');
    if (localParks.isNotEmpty) {
      buf.writeln('  Parks: ${localParks.join(", ")}');
    }
    if (localLibraries.isNotEmpty) {
      buf.writeln('  Libraries: ${localLibraries.join(", ")}');
    }
    if (localLeisureCentres.isNotEmpty) {
      buf.writeln('  Leisure centres: ${localLeisureCentres.join(", ")}');
    }
    if (localCafes.isNotEmpty) {
      buf.writeln('  Family-friendly cafes: ${localCafes.join(", ")}');
    }
    if (localCommunityHalls.isNotEmpty) {
      buf.writeln('  Community halls: ${localCommunityHalls.join(", ")}');
    }
    if (nhsTrustName != null) {
      buf.writeln('  Local NHS Trust: $nhsTrustName');
    }
    if (childrensCentreInfo != null) {
      buf.writeln('  Children\'s Centre: $childrensCentreInfo');
    }
    if (councilWebsite != null) {
      buf.writeln('  Council: $councilWebsite');
    }
    return buf.toString();
  }
}

// =============================================================================
// COMMUNITY TEMPLATES  — BOROUGH-SCOPED
// =============================================================================

/// NCT/community-style group template for prepopulation.
/// These are borough-scoped: a "Walk & Talk" in Camden is a different
/// group from "Walk & Talk" in Cambridge.
class CommunityTemplate {
  final String name;
  final String description;
  final String category; // bumps_and_babies, walk_and_talk, first_aid, etc.
  final String audience; // expecting, new_parent, dad, toddler_parent, all
  final String format; // in_person, online, hybrid
  final String suggestedFrequency; // weekly, fortnightly, monthly
  final String source;
  final ContentScope scope; // boroughOnly or ukWide

  const CommunityTemplate({
    required this.name,
    required this.description,
    required this.category,
    required this.audience,
    this.format = 'in_person',
    this.suggestedFrequency = 'weekly',
    required this.source,
    this.scope = ContentScope.boroughOnly,
  });

  /// Render the template name with borough prefix for display.
  String renderName(String borough) => '$borough $name';

  /// Render the template description with borough context.
  String renderDescription(String borough) =>
      description.replaceAll('{borough}', borough);
}

// =============================================================================
// HYPERLOCAL SCOPE RULES — encoded as constants
// =============================================================================

/// The definitive list of features that are BOROUGH-ONLY.
/// Everything else defaults to boroughOnly unless explicitly listed as ukWide.
class HyperlocalRules {
  /// Features restricted to SAME BOROUGH only.
  static const List<String> boroughOnlyFeatures = [
    'chat',
    'direct_messages',
    'groups',
    'meetups',
    'marketplace',
    'matchmaker',
  ];

  /// Features that are open UK-wide (or location-aware but not restricted).
  static const List<String> ukWideFeatures = [
    'events',
  ];

  /// Check if a feature is borough-scoped.
  static bool isBoroughScoped(String feature) =>
      boroughOnlyFeatures.contains(feature.toLowerCase());

  /// Check if a feature is UK-wide.
  static bool isUkWide(String feature) =>
      ukWideFeatures.contains(feature.toLowerCase());

  /// Build a Gemini-ready summary of the hyperlocal rules.
  static String toPromptContext(String borough) {
    final buf = StringBuffer();
    buf.writeln('HYPERLOCAL RULES FOR HUDDL (CRITICAL - MUST FOLLOW):');
    buf.writeln('The user\'s borough is: $borough');
    buf.writeln('');
    buf.writeln('BOROUGH-ONLY features (same-borough parents ONLY):');
    buf.writeln('  - Chat & DMs: Parents can ONLY message other parents in $borough');
    buf.writeln('  - Groups: Parents can ONLY join/create groups within $borough');
    buf.writeln('  - Meetups: Parents can ONLY create/join meetups within $borough');
    buf.writeln('  - Marketplace: Parents can ONLY buy/sell with other parents in $borough');
    buf.writeln('  - Matchmaker: AI matches parents ONLY within $borough');
    buf.writeln('');
    buf.writeln('UK-WIDE features (open to all locations):');
    buf.writeln('  - Events: Parents can browse events in ANY borough across the UK');
    buf.writeln('    (useful when travelling or planning days out)');
    buf.writeln('');
    buf.writeln('When making suggestions, ALWAYS frame them within $borough context.');
    buf.writeln('For groups, meetups, marketplace, chat: ONLY suggest $borough options.');
    buf.writeln('For events: Can suggest events in $borough AND nearby areas.');
    return buf.toString();
  }
}

// =============================================================================
// MAIN SERVICE
// =============================================================================

class AiKnowledgeBaseService {
  static final AiKnowledgeBaseService _instance =
      AiKnowledgeBaseService._internal();
  factory AiKnowledgeBaseService() => _instance;
  AiKnowledgeBaseService._internal();

  static const String _storageKey = 'ai_knowledge_base_v2';
  static const String _lastRefreshKey = 'ai_kb_last_refresh_v2';

  final OnboardingDataService _onboarding = OnboardingDataService();
  final PostcodeService _postcode = PostcodeService();

  bool _isInitialized = false;
  DateTime? _lastRefresh;

  // ── Core knowledge stores ──────────────────────────────────────────────
  final List<KnowledgeArticle> _articles = [];
  final List<DevelopmentMilestone> _milestones = [];
  final List<VaccinationItem> _vaccinations = [];
  final List<SafetyRecall> _safetyRecalls = [];
  final List<SeasonalTip> _seasonalTips = [];
  final List<CommunityTemplate> _communityTemplates = [];

  // ── Hyperlocal stores ──────────────────────────────────────────────────
  final Map<String, BoroughLocalDirectory> _boroughDirectories = {};

  // ── Public getters ─────────────────────────────────────────────────────
  List<KnowledgeArticle> get allArticles => List.unmodifiable(_articles);
  List<DevelopmentMilestone> get milestones => List.unmodifiable(_milestones);
  List<VaccinationItem> get vaccinations => List.unmodifiable(_vaccinations);
  List<SafetyRecall> get safetyRecalls => List.unmodifiable(_safetyRecalls);
  List<SeasonalTip> get seasonalTips => List.unmodifiable(_seasonalTips);
  List<CommunityTemplate> get communityTemplates =>
      List.unmodifiable(_communityTemplates);
  bool get isInitialized => _isInitialized;
  DateTime? get lastRefresh => _lastRefresh;

  /// The user's current borough (derived from postcode).
  String? get userBorough {
    final pc = _onboarding.postcode;
    if (pc == null || pc.isEmpty) return null;
    return _postcode.getBoroughFromPostcode(pc);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_isInitialized) return;

    await _onboarding.initialize();

    // Load any cached data
    await _loadFromStorage();

    // Always ensure we have the built-in knowledge
    if (_articles.isEmpty) {
      _seedCoreKnowledge();
    }

    // Ensure borough directory exists for user's borough
    final borough = userBorough;
    if (borough != null && !_boroughDirectories.containsKey(borough)) {
      _boroughDirectories[borough] = _buildGenericBoroughDirectory(borough);
    }

    _isInitialized = true;
    _log('Knowledge base initialised (hyperlocal) with '
        '${_articles.length} articles, '
        '${_milestones.length} milestones, ${_vaccinations.length} vaccinations, '
        '${_safetyRecalls.length} recalls, ${_seasonalTips.length} seasonal tips, '
        '${_communityTemplates.length} community templates, '
        '${_boroughDirectories.length} borough directories');
  }

  /// Force a full refresh of the knowledge base (e.g. on daily check).
  Future<void> refresh() async {
    _seedCoreKnowledge();
    _lastRefresh = DateTime.now();
    await _saveToStorage();
    _log('Knowledge base refreshed');
  }

  /// Whether a daily refresh is due.
  bool get needsRefresh {
    if (_lastRefresh == null) return true;
    return DateTime.now().difference(_lastRefresh!).inHours >= 24;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BOROUGH-SCOPED QUERY METHODS
  // ═════════════════════════════════════════════════════════════════════════

  /// Get the local directory for the user's borough.
  BoroughLocalDirectory? getUserBoroughDirectory() {
    final borough = userBorough;
    if (borough == null) return null;
    return _boroughDirectories[borough];
  }

  /// Get the local directory for a specific borough (e.g. for events).
  BoroughLocalDirectory? getBoroughDirectory(String borough) {
    if (!_boroughDirectories.containsKey(borough)) {
      _boroughDirectories[borough] = _buildGenericBoroughDirectory(borough);
    }
    return _boroughDirectories[borough];
  }

  /// Get community templates appropriate for the user's borough and audience.
  /// These templates are ALWAYS borough-scoped (except events).
  List<CommunityTemplate> getTemplatesForUserBorough({
    String? audience,
  }) {
    final templates = audience != null
        ? _communityTemplates
            .where((t) => t.audience == audience || t.audience == 'all')
            .toList()
        : _communityTemplates.toList();

    // All group/meetup templates are inherently borough-scoped.
    return templates
        .where((t) => t.scope == ContentScope.boroughOnly)
        .toList();
  }

  /// Get community templates for UK-wide features (events only).
  List<CommunityTemplate> getUkWideTemplates() {
    return _communityTemplates
        .where((t) => t.scope == ContentScope.ukWide)
        .toList();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // GENERAL QUERY METHODS — used by all AI services
  // ═════════════════════════════════════════════════════════════════════════

  /// Get articles relevant to a user's current life stage.
  List<KnowledgeArticle> getArticlesForUser() {
    final stages = _onboarding.stagesOfLife;
    final children = _onboarding.children;
    final parentType = _onboarding.parentType;

    final userAgeStages = <String>{'all'};

    if (stages.contains('expecting')) userAgeStages.add('pregnancy');
    if (stages.contains('new_parent') || stages.contains('newParent')) {
      userAgeStages.addAll(['newborn', 'baby']);
    }

    // Derive from children's ages
    for (final child in children) {
      final birthday = child['birthday'];
      if (birthday != null) {
        final months = _parseAgeMonths(birthday);
        if (months <= 3) userAgeStages.add('newborn');
        if (months <= 12) userAgeStages.add('baby');
        if (months > 12 && months <= 36) userAgeStages.add('toddler');
        if (months > 36 && months <= 60) userAgeStages.add('preschool');
        if (months > 60) userAgeStages.add('schoolAge');
      }
    }

    // If dad, include dad-specific content
    if (parentType == 'dad') {
      userAgeStages.add('dad');
    }

    return _articles.where((a) {
      return a.ageStages.any((s) => userAgeStages.contains(s));
    }).toList()
      ..sort((a, b) => b.relevanceWeight.compareTo(a.relevanceWeight));
  }

  /// Query articles by category.
  List<KnowledgeArticle> getArticlesByCategory(KnowledgeCategory category) {
    return _articles.where((a) => a.category == category).toList();
  }

  /// Query articles by keyword search.
  List<KnowledgeArticle> searchArticles(String query) {
    final lower = query.toLowerCase();
    final terms =
        lower.split(RegExp(r'\s+')).where((t) => t.length > 2).toList();

    if (terms.isEmpty) return [];

    return _articles.where((a) {
      final searchable =
          '${a.title} ${a.summary} ${a.body} ${a.tags.join(' ')}'.toLowerCase();
      return terms.any((term) => searchable.contains(term));
    }).toList()
      ..sort((a, b) {
        final searchableA =
            '${a.title} ${a.summary} ${a.tags.join(' ')}'.toLowerCase();
        final searchableB =
            '${b.title} ${b.summary} ${b.tags.join(' ')}'.toLowerCase();
        final scoreA = terms.where((t) => searchableA.contains(t)).length;
        final scoreB = terms.where((t) => searchableB.contains(t)).length;
        return scoreB.compareTo(scoreA);
      });
  }

  /// Get milestones relevant to a child's current age.
  List<DevelopmentMilestone> getMilestonesForChild(int ageMonths) {
    return _milestones.where((m) {
      final diff = m.ageMonths - ageMonths;
      return diff >= -1 && diff <= 3;
    }).toList()
      ..sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
  }

  /// Get next upcoming milestone for a child.
  DevelopmentMilestone? getNextMilestone(int ageMonths) {
    final upcoming =
        _milestones.where((m) => m.ageMonths > ageMonths).toList();
    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
    return upcoming.first;
  }

  /// Get vaccinations due for a child's age.
  List<VaccinationItem> getVaccinationsDue(int ageWeeks) {
    return _vaccinations.where((v) {
      final diff = v.ageWeeks - ageWeeks;
      return diff >= -2 && diff <= 4;
    }).toList();
  }

  /// Get seasonal tips for the current month, rendered with borough name.
  List<SeasonalTip> getCurrentSeasonalTips() {
    final month = DateTime.now().month;
    return _seasonalTips.where((t) => t.month == month).toList();
  }

  /// Get community templates for an audience type.
  List<CommunityTemplate> getTemplatesForAudience(String audience) {
    return _communityTemplates
        .where((t) => t.audience == audience || t.audience == 'all')
        .toList();
  }

  /// Check if a product name matches any safety recall.
  SafetyRecall? checkSafetyRecall(String productName) {
    final lower = productName.toLowerCase();
    for (final recall in _safetyRecalls) {
      if (lower.contains(recall.productName.toLowerCase()) ||
          lower.contains(recall.manufacturer.toLowerCase())) {
        return recall;
      }
    }
    return null;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CONTEXTUAL PROMPT GENERATION — for Gemini system prompts
  // ═════════════════════════════════════════════════════════════════════════

  /// Build a knowledge context string for Gemini system prompts.
  /// This is the key method all Gemini services call.
  /// Now includes HYPERLOCAL rules and borough context.
  String buildKnowledgeContext({
    KnowledgeCategory? category,
    int? childAgeMonths,
    int maxArticles = 5,
    bool includeSource = true,
    bool includeHyperlocalRules = true,
    String? overrideBorough, // e.g. for events in another borough
  }) {
    final borough = overrideBorough ?? userBorough;
    final buffer = StringBuffer();

    // ── 0. HYPERLOCAL RULES (top of every prompt) ────────────────────────
    if (includeHyperlocalRules && borough != null) {
      buffer.writeln(HyperlocalRules.toPromptContext(borough));
      buffer.writeln();
    }

    // ── 0b. Borough local directory ──────────────────────────────────────
    if (borough != null) {
      final dir = getBoroughDirectory(borough);
      if (dir != null) {
        buffer.writeln(dir.toPromptContext());
        buffer.writeln();
      }
    }

    // ── 1. Stage-relevant articles ───────────────────────────────────────
    List<KnowledgeArticle> relevant;
    if (category != null) {
      relevant = getArticlesByCategory(category);
    } else {
      relevant = getArticlesForUser();
    }
    if (relevant.length > maxArticles) {
      relevant = relevant.sublist(0, maxArticles);
    }

    if (relevant.isNotEmpty) {
      buffer.writeln('TRUSTED PARENTING KNOWLEDGE (from UK sources):');
      for (final article in relevant) {
        buffer.writeln('- ${article.title}: ${article.summary}');
        if (includeSource) {
          buffer.writeln(
              '  Source: ${_sourceDisplayName(article.source)}');
        }
      }
      buffer.writeln();
    }

    // ── 2. Milestone context ─────────────────────────────────────────────
    if (childAgeMonths != null) {
      final milestoneList = getMilestonesForChild(childAgeMonths);
      if (milestoneList.isNotEmpty) {
        buffer.writeln('CHILD DEVELOPMENT MILESTONES (NHS-backed):');
        for (final m in milestoneList) {
          final status =
              m.ageMonths <= childAgeMonths ? 'Recently' : 'Upcoming';
          buffer.writeln(
              '- $status (${m.ageMonths}mo): ${m.label} - ${m.description}');
          buffer.writeln('  Tip: ${m.parentTip}');
        }
        buffer.writeln();
      }

      // ── 3. Vaccination awareness ───────────────────────────────────────
      final ageWeeks = (childAgeMonths * 4.34).round();
      final vacc = getVaccinationsDue(ageWeeks);
      if (vacc.isNotEmpty) {
        buffer.writeln('VACCINATION REMINDERS (NHS schedule):');
        for (final v in vacc) {
          buffer.writeln(
              '- ${v.name}: Protects against ${v.protectsAgainst} (due ~${v.ageWeeks} weeks)');
        }
        buffer.writeln();
      }
    }

    // ── 4. Seasonal context with borough localisation ────────────────────
    final seasonal = getCurrentSeasonalTips();
    if (seasonal.isNotEmpty) {
      buffer.writeln('SEASONAL TIPS${borough != null ? " FOR $borough" : ""}:');
      for (final s in seasonal) {
        final body =
            borough != null ? s.renderForBorough(borough) : s.body;
        buffer.writeln('- ${s.title}: $body');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Build the empathy and tone instructions that all services use.
  String buildEmpathyInstructions() {
    final parentType = _onboarding.parentType ?? 'parent';
    final isDad = parentType == 'dad';
    final borough = userBorough;

    final buffer = StringBuffer();
    buffer.writeln('EMPATHY & TONE GUIDELINES:');
    buffer.writeln(
        '- Be warm, supportive, and never judgmental. Every parenting journey is unique.');
    buffer.writeln(
        '- Acknowledge that parenting is hard work. Celebrate small wins.');
    buffer.writeln(
        '- Use inclusive language. Avoid assumptions about family structure.');
    if (isDad) {
      buffer.writeln(
          '- This user is a dad. Be mindful that dads can feel excluded from parenting '
          'conversations. Be encouraging and affirming of their role. Reference dad-specific '
          'advice when relevant (from Dadsnet and similar communities).');
    }
    if (borough != null) {
      buffer.writeln(
          '- This parent lives in $borough. Whenever possible, frame advice '
          'and suggestions within the $borough local context. Mention local '
          'parks, libraries, and community resources in $borough.');
    }
    buffer.writeln(
        '- Never be prescriptive. Use phrases like "many parents find..." or '
        '"you might consider..." instead of "you should" or "you must".');
    buffer.writeln(
        '- For medical topics: ALWAYS recommend consulting NHS 111, their GP, or '
        'health visitor. Never diagnose or prescribe.');
    buffer.writeln(
        '- For safety emergencies: Direct to 999 immediately.');
    buffer.writeln(
        '- Reference trusted UK sources where appropriate: "According to NHS guidelines...", '
        '"Many parents on Netmums have found...", "NCT recommends..."');
    buffer.writeln(
        '- Use British English (nappy, pushchair, nursery, dummy, cot, mum/dad).');
    buffer.writeln();

    return buffer.toString();
  }

  /// Build safety guardrails for all AI prompts.
  String buildSafetyGuardrails() {
    final buffer = StringBuffer();
    buffer.writeln('SAFETY GUARDRAILS (MUST FOLLOW):');
    buffer.writeln(
        '- NEVER provide specific medical diagnoses or prescribe medication.');
    buffer.writeln(
        '- NEVER advise against seeing a healthcare professional.');
    buffer.writeln(
        '- For ANY medical concern, direct to: NHS 111, GP, or health visitor.');
    buffer.writeln(
        '- For EMERGENCIES: Direct to 999 or A&E immediately.');
    buffer.writeln(
        '- NEVER recommend specific sleeping arrangements that go against NHS safe sleep guidelines.');
    buffer.writeln(
        '- NHS safe sleep: baby on their back, in their own cot/moses basket, in the same room as parent for first 6 months.');
    buffer.writeln(
        '- Flag any product that appears on known safety recall lists.');
    buffer.writeln(
        '- Be cautious with advice about infant feeding — support the parent\'s choice (breast/bottle/combo) without judgment.');
    buffer.writeln(
        '- NEVER recommend leaving a child unattended.');
    buffer.writeln(
        '- For mental health concerns: suggest NHS talking therapies, health visitor, or PANDAS Foundation helpline.');
    buffer.writeln();

    return buffer.toString();
  }

  /// Build a marketplace-specific knowledge block for the user's borough.
  String buildMarketplaceContext() {
    final borough = userBorough;
    final buffer = StringBuffer();

    buffer.writeln('MARKETPLACE KNOWLEDGE (HYPERLOCAL):');
    if (borough != null) {
      buffer.writeln(
          '- All marketplace listings are visible ONLY to parents in $borough.');
      buffer.writeln(
          '- Buyers and sellers are all local to $borough — easy collection/drop-off.');
      buffer.writeln(
          '- Suggest meeting in safe public places in $borough for exchanges.');
    }
    buffer.writeln(
        '- Always check safety recalls before buying second-hand baby items.');
    buffer.writeln(
        '- Avoid buying used: car seats (unless history known), mattresses, drop-side cots.');
    buffer.writeln(
        '- Safe to buy preloved: clothes, toys, pushchairs, books, high chairs.');
    buffer.writeln(
        '- Pricing guide: brand new 60-70% retail, like new 45-55%, good 30-45%, well-used 15-30%.');
    buffer.writeln();

    return buffer.toString();
  }

  /// Build a groups/meetups context block that enforces borough scoping.
  String buildGroupsMeetupsContext() {
    final borough = userBorough;
    final buffer = StringBuffer();

    buffer.writeln('GROUPS & MEETUPS KNOWLEDGE (HYPERLOCAL):');
    if (borough != null) {
      buffer.writeln(
          '- All groups and meetups are EXCLUSIVELY for parents in $borough.');
      buffer.writeln(
          '- When suggesting groups, frame them as "$borough [Group Name]".');
      buffer.writeln(
          '- When suggesting meetup locations, use venues within $borough.');
      buffer.writeln(
          '- Parents CANNOT join groups or attend meetups outside $borough.');
    }
    buffer.writeln(
        '- Group types: Bumps & Babies, Walk & Talk, First Aid, Feeding Support, '
        'Dad Meetups, Wellbeing Circle, Nearly New Sales, Activity Swaps.');
    buffer.writeln(
        '- Meetup types: Playdate, Coffee morning, Park walk, Swimming, '
        'Soft play, Library rhyme time, Dad & Kids outing.');
    buffer.writeln();

    return buffer.toString();
  }

  /// Build an events context block (UK-wide, the ONLY cross-borough feature).
  String buildEventsContext({String? targetBorough}) {
    final borough = targetBorough ?? userBorough;
    final buffer = StringBuffer();

    buffer.writeln('EVENTS KNOWLEDGE (UK-WIDE):');
    buffer.writeln(
        '- Events are the ONLY feature that is NOT borough-restricted.');
    buffer.writeln(
        '- Parents can browse events in ANY borough across the UK.');
    buffer.writeln(
        '- This is useful when parents are travelling or planning a day out.');
    if (borough != null) {
      buffer.writeln(
          '- Default view shows events in $borough, but user can search other areas.');
    }
    buffer.writeln(
        '- Event types: Library sessions, baby classes, swimming, music, '
        'soft play, farm visits, museum activities, festivals, NCT events.');
    buffer.writeln();

    return buffer.toString();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // BOROUGH DIRECTORY BUILDER
  // ═════════════════════════════════════════════════════════════════════════

  /// Build a generic borough directory with typical UK amenities.
  /// In production, this would be replaced with real data from council APIs.
  BoroughLocalDirectory _buildGenericBoroughDirectory(String borough) {
    return BoroughLocalDirectory(
      borough: borough,
      localParks: [
        '$borough Central Park',
        '$borough Recreation Ground',
        '$borough Community Garden',
      ],
      localLibraries: [
        '$borough Central Library',
        '$borough Community Library',
      ],
      localLeisureCentres: [
        '$borough Leisure Centre',
        '$borough Swimming Pool',
      ],
      localCafes: [
        '$borough Family Cafe',
        '$borough Community Coffee Shop',
      ],
      localCommunityHalls: [
        '$borough Community Centre',
        '$borough Village Hall',
      ],
      childrensCentreInfo: '$borough Children\'s Centre',
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CORE KNOWLEDGE DATA
  // Sourced from NHS, NCT, Bounty, Netmums, Dadsnet
  // ═════════════════════════════════════════════════════════════════════════

  void _seedCoreKnowledge() {
    _articles.clear();
    _milestones.clear();
    _vaccinations.clear();
    _safetyRecalls.clear();
    _seasonalTips.clear();
    _communityTemplates.clear();

    _seedArticles();
    _seedMilestones();
    _seedVaccinations();
    _seedSafetyRecalls();
    _seedSeasonalTips();
    _seedCommunityTemplates();
  }

  // ── ARTICLES ───────────────────────────────────────────────────────────

  void _seedArticles() {
    final now = DateTime.now();

    _articles.addAll([
      // ─── PREGNANCY (Source: NHS, NCT, Bounty) ─────────────────────────
      KnowledgeArticle(
        id: 'preg_001',
        title: 'Preparing for birth — NHS guidance',
        summary:
            'NHS recommends attending antenatal classes, creating a birth plan, '
            'and knowing the signs of labour. Pack your hospital bag by 36 weeks.',
        body:
            'Key preparation steps: 1) Attend antenatal classes (NHS or NCT). '
            '2) Create a birth plan discussing pain relief preferences, birthing position, '
            'and who you want as your birth partner. 3) Pack hospital bag by 36 weeks: '
            'nightwear, breast pads, maternity pads, nappies, baby clothes, car seat. '
            '4) Know the signs of labour: regular contractions, waters breaking, '
            'backache, urge to go to the toilet. Call your midwife when contractions are '
            '5 minutes apart, lasting 60 seconds, for 1 hour (5-1-1 rule).',
        category: KnowledgeCategory.pregnancy,
        tags: ['birth plan', 'hospital bag', 'labour signs', 'antenatal'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/pregnancy/labour-and-birth/',
        ageStages: ['pregnancy'],
        relevanceWeight: 0.95,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'preg_002',
        title: 'NCT antenatal courses — what to expect',
        summary:
            'NCT courses cover pregnancy, birth, and early parenthood over 15-18 hours. '
            'They help you build a support network of other expecting parents.',
        body:
            'NCT antenatal courses are the UK\'s most popular birthing classes. '
            'They cover: stages of labour, pain relief options, feeding your baby, '
            'adjusting to parenthood, and partner support. A key benefit is the '
            'social network — your NCT group often becomes a lifeline of parent friends. '
            'Courses are available in-person and online. Bursary places available '
            'for those on lower incomes.',
        category: KnowledgeCategory.pregnancy,
        tags: ['nct', 'antenatal', 'birth class', 'support network'],
        source: 'nct',
        sourceUrl: 'https://www.nct.org.uk/courses-workshops/nct-antenatal-course',
        ageStages: ['pregnancy'],
        relevanceWeight: 0.90,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'preg_003',
        title: 'Pregnancy week by week — Bounty guide',
        summary:
            'Bounty provides week-by-week pregnancy updates covering baby\'s development, '
            'your body changes, and what to expect at each stage.',
        body:
            'First trimester (weeks 1-12): Morning sickness, fatigue, first scan at 12 weeks. '
            'Second trimester (weeks 13-27): Energy returns, baby bump shows, anomaly scan at 20 weeks, '
            'you may feel baby\'s first kicks. Third trimester (weeks 28-40): Baby grows rapidly, '
            'Braxton Hicks contractions, nesting instinct, prepare for birth. Important: take folic acid '
            'daily, attend all midwife appointments, report any concerns promptly.',
        category: KnowledgeCategory.pregnancy,
        tags: ['week by week', 'trimester', 'pregnancy stages', 'scans'],
        source: 'bounty',
        sourceUrl:
            'https://www.bounty.com/pregnancy-and-birth/pregnancy/pregnancy-week-by-week',
        ageStages: ['pregnancy'],
        relevanceWeight: 0.85,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'preg_004',
        title: 'Paternity leave in the UK — what dads need to know',
        summary:
            'UK dads are entitled to 1-2 weeks paternity leave. Recent changes allow '
            'leave to be taken earlier. Shared parental leave offers more flexibility.',
        body:
            'Statutory paternity leave: 1 or 2 consecutive weeks, paid at the lower of '
            '\u00A3184.03/week or 90% of average weekly earnings. Must give 15 weeks\' notice. '
            'Shared parental leave: up to 50 weeks shared between both parents. '
            'Recent updates: dads can now take paternity leave from day 1 of employment '
            '(no 26-week qualifying period for births from April 2024). '
            'Self-employed dads: not eligible for statutory paternity pay but may claim '
            'Maternity Allowance through shared parental arrangement.',
        category: KnowledgeCategory.dadSpecific,
        tags: [
          'paternity leave',
          'dad rights',
          'shared parental leave',
          'employment'
        ],
        source: 'netmums',
        sourceUrl:
            'https://www.netmums.com/life/work/maternity-and-paternity-leave/',
        ageStages: ['pregnancy', 'newborn'],
        relevanceWeight: 0.88,
        lastUpdated: now,
      ),

      // ─── NEWBORN & BABY (Source: NHS, Bounty) ─────────────────────────
      KnowledgeArticle(
        id: 'nb_001',
        title: 'Caring for a newborn — first 12 weeks',
        summary:
            'NHS guidance on newborn care covering feeding, sleeping, bathing, '
            'umbilical cord care, and when to seek medical help.',
        body:
            'Feeding: feed on demand, roughly every 2-3 hours. Breast or formula are both fine. '
            'Sleep: place baby on their back in a clear cot, same room as you for 6 months. '
            'Aim for 14-17 hours of sleep in 24 hours. Bathing: 2-3 times per week is enough, '
            'use plain water for the first month. Umbilical cord: keep clean and dry, falls off '
            'in 1-3 weeks. Nappies: expect 6+ wet nappies per day by day 5. '
            'Red flags \u2014 seek help immediately: difficulty breathing, persistent vomiting, '
            'fever over 38\u00B0C (under 3 months), rash that doesn\'t fade under glass, '
            'not feeding for 8+ hours, floppy or unresponsive.',
        category: KnowledgeCategory.newborn,
        tags: ['newborn care', 'feeding', 'sleeping', 'bathing', 'red flags'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/caring-for-a-newborn/',
        ageStages: ['newborn'],
        relevanceWeight: 0.98,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'nb_002',
        title: 'Safe sleep guidelines — NHS Lullaby Trust',
        summary:
            'Always place baby on their back, use a firm flat mattress, keep room '
            '16-20\u00B0C, and never sleep with baby on a sofa or armchair.',
        body:
            'The ABCs of safe sleep: Alone (own sleep space), on their Back, in a Cot/moses basket. '
            'Keep head uncovered. Feet to foot of the cot. Room temperature 16-20\u00B0C. '
            'No pillows, duvets, bumpers, or soft toys in the cot. Use a baby sleeping bag '
            'appropriate for the room temperature. Co-sleeping increases risk, especially if '
            'parent has been drinking, smoking, or taking medication that causes drowsiness. '
            'NEVER sleep with baby on a sofa or armchair \u2014 this is the highest risk factor. '
            'Place in same room as parent for all sleeps for first 6 months.',
        category: KnowledgeCategory.sleep,
        tags: [
          'safe sleep',
          'SIDS',
          'cot',
          'sleeping bag',
          'room temperature'
        ],
        source: 'nhs',
        sourceUrl:
            'https://www.nhs.uk/baby/caring-for-a-newborn/reducing-the-risk-of-sudden-infant-death-syndrome/',
        ageStages: ['newborn', 'baby'],
        relevanceWeight: 0.99,
        lastUpdated: now,
      ),

      // ─── FEEDING & WEANING ────────────────────────────────────────────
      KnowledgeArticle(
        id: 'feed_001',
        title: 'Breastfeeding — getting started',
        summary:
            'NHS recommends exclusive breastfeeding for about the first 6 months. '
            'Support is available from midwives, health visitors, and NCT breastfeeding counsellors.',
        body:
            'First feeds: colostrum (thick yellow milk) is all baby needs in the first few days. '
            'Mature milk comes in around day 3-5. Feed on demand \u2014 look for feeding cues: '
            'rooting, sucking fingers, turning head. Latch: baby\'s mouth should cover the areola, '
            'not just the nipple. Pain is common initially but should improve. Seek help if: '
            'persistent pain, baby not gaining weight, mastitis symptoms (red, hot, painful area). '
            'Support: NCT breastfeeding helpline 0300 330 0700. NHS Start4Life app. '
            'It\'s OK to combination feed or use formula \u2014 fed is best.',
        category: KnowledgeCategory.feeding,
        tags: [
          'breastfeeding',
          'latch',
          'colostrum',
          'support',
          'NCT helpline'
        ],
        source: 'nhs',
        sourceUrl:
            'https://www.nhs.uk/baby/breastfeeding-and-bottle-feeding/',
        ageStages: ['newborn', 'baby'],
        relevanceWeight: 0.92,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'feed_002',
        title: 'Weaning your baby — NHS guidance',
        summary:
            'Start introducing solid foods at around 6 months. Begin with soft finger '
            'foods or smooth purees alongside continued milk feeds.',
        body:
            'Signs of readiness (all three needed): 1) Can stay in a sitting position and hold '
            'head steady. 2) Can coordinate eyes, hands, and mouth to pick up food and eat it. '
            '3) Can swallow food (rather than pushing it back out). '
            'Good first foods: cooked vegetables (broccoli, carrot, sweet potato), soft fruits '
            '(banana, avocado, mango), baby rice, porridge. Baby-led weaning (finger foods from '
            'the start) and spoon-feeding are both fine approaches. '
            'Avoid: honey (until 12 months), whole nuts, added salt/sugar, low-fat dairy, '
            'shark/swordfish/marlin. Cow\'s milk as a main drink only after 12 months.',
        category: KnowledgeCategory.feeding,
        tags: [
          'weaning',
          'solid foods',
          'baby led weaning',
          'first foods',
          '6 months'
        ],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/weaning-and-feeding/',
        ageStages: ['baby'],
        relevanceWeight: 0.93,
        lastUpdated: now,
      ),

      // ─── HEALTH & SAFETY ──────────────────────────────────────────────
      KnowledgeArticle(
        id: 'health_001',
        title: 'When to take your baby to A&E',
        summary:
            'Go to A&E or call 999 if baby has: difficulty breathing, blue/grey skin, '
            'seizure, unresponsive/floppy, rash that doesn\'t fade.',
        body:
            'EMERGENCY (call 999/A&E): Difficulty breathing, blue/grey/pale skin, seizure or fit, '
            'very floppy/unresponsive, rash that doesn\'t fade when pressed with a glass. '
            'URGENT (call 111/GP): Fever over 38\u00B0C (under 3 months), fever over 39\u00B0C '
            '(3-6 months), not feeding for 8+ hours, fewer than 6 wet nappies in 24 hours, '
            'persistent vomiting, unusual drowsiness, high-pitched/continuous cry. '
            'ROUTINE (book GP): Mild rashes, minor coughs/colds lasting over 10 days, '
            'mild constipation, cradle cap, mild nappy rash.',
        category: KnowledgeCategory.health,
        tags: ['emergency', 'A&E', '999', 'NHS 111', 'fever', 'breathing'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/health/',
        ageStages: ['newborn', 'baby', 'toddler', 'preschool'],
        relevanceWeight: 0.99,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'health_002',
        title: 'Baby first aid — essential skills',
        summary:
            'Every parent should know CPR, choking response, and how to treat '
            'burns and febrile convulsions. NCT offers first aid courses.',
        body:
            'CHOKING (under 1): 5 back blows (between shoulder blades, face down on your thigh), '
            'then 5 chest thrusts. Repeat. Call 999 if not cleared. '
            'BABY CPR: 5 rescue breaths, then 30 compressions (2 fingers, centre of chest), '
            'then 2 breaths. Repeat 30:2. Call 999. '
            'BURNS: Cool under running water for 20 minutes. Remove clothing unless stuck. '
            'Cover loosely with cling film. Do NOT use ice, butter, or creams. '
            'FEBRILE CONVULSION: Place on side. Clear area. Note the time. Call 999 if first '
            'seizure or lasts over 5 minutes. '
            'NCT Baby & Child First Aid course teaches all these skills \u2014 check local events.',
        category: KnowledgeCategory.safety,
        tags: ['first aid', 'CPR', 'choking', 'burns', 'NCT course'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/first-aid-and-safety/',
        ageStages: ['all'],
        relevanceWeight: 0.97,
        lastUpdated: now,
      ),

      // ─── MENTAL HEALTH ────────────────────────────────────────────────
      KnowledgeArticle(
        id: 'mh_001',
        title: 'Postnatal depression — recognising the signs',
        summary:
            'Postnatal depression affects 1 in 10 mothers and 1 in 10 fathers within '
            'a year of birth. Help is available and recovery is possible.',
        body:
            'Baby blues (first 2 weeks): tearfulness, mood swings, anxiety \u2014 this is normal and '
            'usually passes. Postnatal depression: persistent low mood, loss of enjoyment, '
            'excessive tiredness, difficulty bonding with baby, frightening thoughts, '
            'withdrawing from contact. It can start any time in the first year. '
            'DADS TOO: 1 in 10 new dads experience postnatal depression. Signs may include '
            'irritability, withdrawing, working excessively, or increased drinking. '
            'Help: talk to your health visitor or GP (they screen for this). '
            'Talking therapies (CBT) available free on NHS. PANDAS Foundation: 0808 196 1776. '
            'Netmums has an anonymous peer support chat for parents struggling with PND.',
        category: KnowledgeCategory.mentalHealth,
        tags: [
          'postnatal depression',
          'PND',
          'mental health',
          'baby blues',
          'dad depression',
          'PANDAS'
        ],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/support-and-services/',
        ageStages: ['newborn', 'baby'],
        relevanceWeight: 0.96,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'mh_002',
        title: 'Loneliness in new parenthood — you\'re not alone',
        summary:
            'Over 50% of new parents experience loneliness. Joining local groups, '
            'attending meetups, and online communities can make a huge difference.',
        body:
            'Loneliness is one of the most common experiences in new parenthood, yet rarely '
            'talked about. NCT groups, Netmums local forums, and community organisations offer '
            'vital social connection. Tips: 1) Attend a Bumps & Babies or Walk & Talk group '
            'in your borough \u2014 Huddl connects you ONLY with parents in your local area. '
            '2) Say yes to invitations even when tired. 3) Use Huddl to connect '
            'with parents right in your borough \u2014 everyone is local! '
            '4) Be honest with friends/family about how you\'re feeling. '
            '5) Remember: building a new social network takes time. The NCT found that parents '
            'who attend local groups report 60% less loneliness in the first year.',
        category: KnowledgeCategory.socialConnection,
        tags: ['loneliness', 'isolation', 'social', 'NCT groups', 'community'],
        source: 'nct',
        sourceUrl: 'https://www.nct.org.uk/local-activities-meet-ups',
        ageStages: ['all'],
        relevanceWeight: 0.90,
        lastUpdated: now,
      ),

      // ─── DEVELOPMENT ──────────────────────────────────────────────────
      KnowledgeArticle(
        id: 'dev_001',
        title: 'Baby development — month by month overview',
        summary:
            'Every baby develops at their own pace. Key milestones include social smiling '
            '(6-8 weeks), rolling (4-6 months), sitting (6-9 months), first words (12 months).',
        body:
            '2 months: Social smile, tracks objects, lifts head during tummy time. '
            '4 months: Laughs, grasps toys, rolls front to back. '
            '6 months: Sits with support, passes objects hand to hand, recognises familiar faces, '
            'ready for weaning. 9 months: Sits unaided, crawling/shuffling, pincer grip, '
            'separation anxiety. 12 months: Pulls to stand, first steps (some babies), '
            '1-3 words, waves bye-bye. 18 months: Walks confidently, 10-20 words, '
            'simple pretend play. Remember: wide variation is normal. If concerned, '
            'speak to your health visitor at the routine developmental reviews.',
        category: KnowledgeCategory.development,
        tags: ['milestones', 'development', 'month by month', 'health visitor'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/babys-development/',
        ageStages: ['baby', 'toddler'],
        relevanceWeight: 0.91,
        lastUpdated: now,
      ),

      // ─── TODDLER & PRESCHOOL ──────────────────────────────────────────
      KnowledgeArticle(
        id: 'tod_001',
        title: 'Handling toddler tantrums — practical strategies',
        summary:
            'Tantrums peak between ages 1-3 and are a normal part of emotional development. '
            'Stay calm, acknowledge feelings, and offer comfort.',
        body:
            'Tantrums are normal \u2014 they happen because toddlers have big emotions but limited '
            'ability to express them. Strategies: 1) Stay calm \u2014 your calm is contagious. '
            '2) Acknowledge feelings: "I can see you\'re really frustrated." '
            '3) Distraction works brilliantly under 2. 4) Offer choices: "Would you like the '
            'red cup or the blue cup?" 5) After the storm, offer a cuddle. Never punish tantrums \u2014 '
            'they\'re not manipulation. 6) Consistent boundaries help \u2014 say what you mean, '
            'mean what you say. Netmums parents report that naming emotions ("You\'re angry '
            'because...") dramatically reduces tantrum frequency over time.',
        category: KnowledgeCategory.development,
        tags: ['tantrums', 'toddler', 'behaviour', 'emotions', 'strategies'],
        source: 'netmums',
        sourceUrl: 'https://www.netmums.com/parenting/',
        ageStages: ['toddler'],
        relevanceWeight: 0.89,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'tod_002',
        title: 'Potty training — when and how to start',
        summary:
            'Most children are ready for potty training between 18 months and 3 years. '
            'Signs of readiness include awareness of wet nappies and interest in the toilet.',
        body:
            'Signs of readiness: 1) Knows when they have a wet or dirty nappy. '
            '2) Can tell you before they wee/poo (or tell you as it happens). '
            '3) Stays dry for at least 2 hours. 4) Can pull trousers up and down. '
            '5) Shows interest in others using the toilet. '
            'Tips: Let them choose their potty. Put the potty where they can see it. '
            'Use loose, easy-to-pull-down clothing. Praise success, never punish accidents. '
            'Expect setbacks \u2014 they\'re completely normal. Boys and girls often train at different '
            'rates (girls sometimes earlier). Night dryness often comes later \u2014 average age 3.5-4.',
        category: KnowledgeCategory.development,
        tags: [
          'potty training',
          'toilet training',
          'readiness signs',
          'toddler'
        ],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/babys-development/',
        ageStages: ['toddler', 'preschool'],
        relevanceWeight: 0.85,
        lastUpdated: now,
      ),

      // ─── SCHOOL READINESS ─────────────────────────────────────────────
      KnowledgeArticle(
        id: 'sch_001',
        title: 'Getting your child ready for school reception',
        summary:
            'School readiness isn\'t just about ABCs \u2014 it\'s about independence, social skills, '
            'and emotional resilience. Focus on play-based learning.',
        body:
            'Key skills for school readiness: 1) Using the toilet independently. '
            '2) Putting on and taking off coat and shoes. 3) Eating lunch with a knife and fork. '
            '4) Recognising their own name. 5) Sharing and taking turns. 6) Following simple '
            'instructions. 7) Separating from parent without excessive distress. '
            'How to prepare at home: read together daily, count during everyday activities, '
            'practise using scissors and holding a pencil, play board games for turn-taking, '
            'arrange playdates for social skills. The NHS Best Start in Life programme emphasises '
            'that 90% of brain growth happens before age 5.',
        category: KnowledgeCategory.education,
        tags: [
          'school readiness',
          'reception',
          'independence',
          'learning',
          'social skills'
        ],
        source: 'nhs',
        sourceUrl:
            'https://www.nhs.uk/best-start-in-life/early-learning-development/',
        ageStages: ['preschool'],
        relevanceWeight: 0.82,
        lastUpdated: now,
      ),

      // ─── DAD-SPECIFIC ─────────────────────────────────────────────────
      KnowledgeArticle(
        id: 'dad_001',
        title: 'The modern dad — embracing hands-on fatherhood',
        summary:
            'Research shows that actively involved dads have children with better educational '
            'outcomes, higher self-esteem, and fewer behavioural problems.',
        body:
            'Being a hands-on dad makes a measurable difference. Children with involved fathers '
            'perform better at school, have stronger emotional regulation, and report higher '
            'self-esteem. Tips from the Dadsnet community: 1) Take on bedtime routine \u2014 it\'s '
            'great bonding time. 2) Skin-to-skin contact is not just for mums \u2014 do it from day 1. '
            '3) Join dad-specific groups in your borough \u2014 Huddl connects you with other local dads. '
            '4) Don\'t wait to be asked to help \u2014 just do it. 5) It\'s OK to feel overwhelmed. '
            '6) Your partner is not the gatekeeper \u2014 you\'re equally capable of caring for your child. '
            'Dadsnet runs the UK\'s largest dad community with regular events and articles.',
        category: KnowledgeCategory.dadSpecific,
        tags: ['dad', 'fatherhood', 'bonding', 'involved dad', 'Dadsnet'],
        source: 'dadsnet',
        sourceUrl: 'https://dadsnet.com/category/fatherhood/',
        ageStages: ['all', 'dad'],
        relevanceWeight: 0.87,
        lastUpdated: now,
      ),
      KnowledgeArticle(
        id: 'dad_002',
        title: 'Dad mental health — it matters too',
        summary:
            '38% of new dads worry about their mental health. It\'s OK to not be OK. '
            'Talking about it is the first step.',
        body:
            'Postnatal depression in dads is real but underdiagnosed. Warning signs: '
            'persistent irritability, withdrawing from baby/partner, drinking more, '
            'working excessively, loss of interest in things you enjoyed, difficulty sleeping '
            'even when baby is sleeping. What helps: 1) Talk to your partner, a friend, or your GP. '
            '2) Join a dad group in your borough where honesty is welcomed. '
            '3) Exercise \u2014 even a 20-minute walk with the pushchair helps. '
            '4) Reduce alcohol. 5) Accept that adjusting to fatherhood takes time. '
            'Resources: Dadsnet community support, Andy\'s Man Club (free groups), '
            'PANDAS Foundation dad line, NHS talking therapies (self-refer).',
        category: KnowledgeCategory.dadSpecific,
        tags: [
          'dad mental health',
          'postnatal depression',
          'support',
          'Andy\'s Man Club'
        ],
        source: 'dadsnet',
        sourceUrl: 'https://dadsnet.com/',
        ageStages: ['all', 'dad'],
        relevanceWeight: 0.90,
        lastUpdated: now,
      ),

      // ─── FINANCE & BENEFITS ───────────────────────────────────────────
      KnowledgeArticle(
        id: 'fin_001',
        title: 'Child Benefit and financial support for parents',
        summary:
            'All parents can claim Child Benefit regardless of income. Additional support '
            'includes free childcare hours, Tax-Free Childcare, and Sure Start grants.',
        body:
            'Child Benefit: \u00A326.05/week for first child, \u00A317.25 for each additional child '
            '(2025 rates). Claim within 3 months of birth. Higher earners (over \u00A360,000) '
            'may pay High Income Charge \u2014 but still worth claiming for NI credits. '
            'Sure Start Maternity Grant: \u00A3500 for first baby if on certain benefits. '
            'Free childcare: 15 hours/week from age 2 (disadvantaged), 15 hours from age 3 '
            '(universal), 30 hours from age 3 (working parents). Tax-Free Childcare: government '
            'pays \u00A32 for every \u00A38 you pay, up to \u00A32,000/year per child. '
            'Healthy Start vouchers: free milk, fruit, veg for low-income families. '
            'Bounty also provides exclusive vouchers and offers for new parents.',
        category: KnowledgeCategory.finance,
        tags: [
          'child benefit',
          'financial help',
          'free childcare',
          'tax-free childcare',
          'Sure Start',
          'Healthy Start'
        ],
        source: 'netmums',
        sourceUrl:
            'https://www.netmums.com/life/money-and-debt/benefits-and-entitlements/',
        ageStages: ['all'],
        relevanceWeight: 0.86,
        lastUpdated: now,
      ),

      // ─── ACTIVITIES & PLAY ────────────────────────────────────────────
      KnowledgeArticle(
        id: 'act_001',
        title: 'Free and low-cost activities for families in the UK',
        summary:
            'From library rhyme time to park playdates, there are plenty of free activities. '
            'Netmums lists where kids eat free at UK restaurants.',
        body:
            'Free activities: Library rhyme time and story sessions, playground visits, '
            'nature walks and bug hunts, soft play (some offer free sessions), '
            'NCT Walk & Talk groups (free), museum and gallery visits (many free for under 5s), '
            'sensory play at home (water play, pasta/rice tray, playdough). '
            'Low-cost: Swimming (many pools offer baby swim from 3 months), '
            'baby music classes, messy play groups, city farms. '
            'Kids eat free: Many UK restaurants offer free kids\' meals \u2014 check Netmums '
            'for the latest list. Tip: use Huddl to find activities '
            'in your borough \u2014 other local parents share the best spots!',
        category: KnowledgeCategory.activities,
        tags: [
          'free activities',
          'kids eat free',
          'play',
          'family days out',
          'library'
        ],
        source: 'netmums',
        sourceUrl: 'https://www.netmums.com/activities/',
        ageStages: ['all'],
        relevanceWeight: 0.80,
        lastUpdated: now,
      ),

      // ─── MARKETPLACE ──────────────────────────────────────────────────
      KnowledgeArticle(
        id: 'mkt_001',
        title: 'Buying and selling preloved baby items safely',
        summary:
            'The UK second-hand baby market saves families thousands. Always check safety '
            'recalls, inspect car seats for damage, and avoid used mattresses.',
        body:
            'What\'s safe to buy preloved: Clothes, toys (check age warnings), pushchairs '
            '(check model isn\'t recalled), books, high chairs, baby carriers. '
            'What to avoid buying second-hand: Car seats (unless you know full history \u2014 no accidents), '
            'mattresses (SIDS risk), cribs older than 10 years, drop-side cots (banned). '
            'Safety checks: Look up product recalls on the government website. Check for sharp edges, '
            'loose parts, missing screws. Ensure items meet current BS (British Standard) marks. '
            'Pricing guide: Brand new items sell for 60-70% of retail, like new 45-55%, '
            'good condition 30-45%, well-used 15-30%. '
            'On Huddl, the marketplace is hyperlocal \u2014 every buyer and seller is in your borough, '
            'making collection easy and safe. Arrange to meet at a local cafe or community centre.',
        category: KnowledgeCategory.marketplace,
        tags: ['preloved', 'second-hand', 'safety', 'car seat', 'pricing'],
        source: 'netmums',
        ageStages: ['all'],
        relevanceWeight: 0.78,
        lastUpdated: now,
      ),

      // ─── SOCIAL CONNECTION ────────────────────────────────────────────
      KnowledgeArticle(
        id: 'soc_001',
        title: 'NCT local groups — your parenting lifeline',
        summary:
            'NCT runs Bumps & Babies, Walk & Talk, Nearly New Sales, and Baby & Child '
            'First Aid courses across the UK. Most are free or low-cost.',
        body:
            'NCT local activities: 1) Bumps & Babies: drop-in groups for pregnant parents '
            'and those with babies. Chat, tea, support. Free. 2) Walk & Talk: gentle walks '
            'with buggies/slings. Fresh air + conversation. Free. 3) Nearly New Sales: '
            'buy and sell quality baby equipment, clothes, and toys at bargain prices. '
            '4) Baby & Child First Aid: learn CPR, choking response, burns treatment. '
            'Usually \u00A320-30. 5) Baby Cafes: breastfeeding support in a social setting. Free. '
            'All events can be found at nct.org.uk/local-activities-meet-ups. '
            'Benefits: 60% of parents who attend NCT groups report reduced loneliness. '
            'Huddl brings this hyper-local connection to your phone \u2014 '
            'every group and meetup is with parents right in your borough.',
        category: KnowledgeCategory.socialConnection,
        tags: [
          'NCT',
          'bumps and babies',
          'walk and talk',
          'nearly new sale',
          'first aid'
        ],
        source: 'nct',
        sourceUrl: 'https://www.nct.org.uk/local-activities-meet-ups',
        ageStages: ['all'],
        relevanceWeight: 0.88,
        lastUpdated: now,
      ),

      // ─── SCREEN TIME ──────────────────────────────────────────────────
      KnowledgeArticle(
        id: 'scr_001',
        title: 'Managing screen time for young children',
        summary:
            'NHS Best Start in Life recommends limiting screen time for under 5s. '
            'No screens before 18 months (video calls excepted). Quality over quantity.',
        body:
            'NHS/WHO guidelines: Under 2: avoid screen time (except video calls with family). '
            '2-5 years: limit to 1 hour per day of high-quality content. '
            'Over 5: set consistent limits, ensure it doesn\'t replace physical activity or sleep. '
            'Tips: 1) Watch WITH your child \u2014 talk about what you see. '
            '2) Choose educational content (CBeebies, Hey Duggee, Numberblocks). '
            '3) No screens during meals. 4) Switch off 1 hour before bedtime. '
            '5) Model good screen habits yourself. Netmums reports that parents who set '
            'consistent screen rules early find it much easier to maintain them as children grow.',
        category: KnowledgeCategory.development,
        tags: ['screen time', 'technology', 'digital', 'CBeebies', 'limits'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/best-start-in-life/',
        ageStages: ['baby', 'toddler', 'preschool'],
        relevanceWeight: 0.80,
        lastUpdated: now,
      ),

      // ─── TEETHING ─────────────────────────────────────────────────────
      KnowledgeArticle(
        id: 'teeth_001',
        title: 'Teething — symptoms and relief',
        summary:
            'First teeth usually appear at 6 months. Signs include drooling, flushed cheeks, '
            'chewing on things, and irritability. Teething rings and paracetamol can help.',
        body:
            'Teething typically starts around 6 months (some babies earlier, some later). '
            'Symptoms: red/sore gums, flushed cheek, dribbling more than usual, gnawing/chewing, '
            'irritability, slight temperature (not high fever). '
            'What helps: chilled (not frozen) teething ring, teething gel (sugar-free, from 4 months), '
            'gently rubbing gums with a clean finger, infant paracetamol if in pain (from 2 months), '
            'infant ibuprofen (from 3 months). '
            'Teething does NOT cause: high fever, diarrhoea, rashes, or ear infections \u2014 '
            'if you see these, consult your GP. First dental visit recommended around first birthday.',
        category: KnowledgeCategory.health,
        tags: ['teething', 'teeth', 'teething ring', 'gums', 'paracetamol'],
        source: 'nhs',
        sourceUrl: 'https://www.nhs.uk/baby/babys-development/teething/',
        ageStages: ['baby', 'toddler'],
        relevanceWeight: 0.82,
        lastUpdated: now,
      ),
    ]);
  }

  // ── DEVELOPMENT MILESTONES ─────────────────────────────────────────────

  void _seedMilestones() {
    _milestones.addAll(const [
      DevelopmentMilestone(
        ageMonths: 1,
        label: 'First social smile',
        description:
            'Baby begins to smile in response to faces and voices.',
        nhsGuidance:
            'Talk and sing to your baby \u2014 they learn from your face and voice.',
        parentTip:
            'Get up close and talk gently. Your baby will start responding with smiles.',
        warningSignsToWatch: ['No eye contact', 'Very quiet, no cooing sounds'],
      ),
      DevelopmentMilestone(
        ageMonths: 3,
        label: 'Head control improves',
        description:
            'Baby can hold head steady when supported in sitting position. '
            'Starts to bat at objects.',
        nhsGuidance:
            'Tummy time helps strengthen neck and back muscles.',
        parentTip:
            'Give 3-5 minutes of tummy time several times a day. Use a play mat with toys.',
      ),
      DevelopmentMilestone(
        ageMonths: 4,
        label: 'Laughs and grasps',
        description:
            'Baby laughs out loud, grasps toys, and starts to roll from front to back.',
        nhsGuidance:
            'Offer a variety of textures and sounds to explore.',
        parentTip:
            'Rattles and crinkly toys are brilliant right now. Play peek-a-boo!',
      ),
      DevelopmentMilestone(
        ageMonths: 6,
        label: 'Sits with support & ready for weaning',
        description:
            'Baby sits with support, passes objects between hands, recognises familiar faces. '
            'Ready to start solid foods.',
        nhsGuidance:
            'NHS recommends starting solids around 6 months alongside continued milk feeds.',
        parentTip:
            'This is an exciting time! Try soft finger foods like banana or cooked sweet potato.',
        warningSignsToWatch: [
          'Cannot hold head steady',
          'No interest in objects',
          'No social smiling'
        ],
      ),
      DevelopmentMilestone(
        ageMonths: 9,
        label: 'Crawling and separation anxiety',
        description:
            'Baby sits unaided, crawls or shuffles, uses pincer grip, '
            'may show separation anxiety.',
        nhsGuidance:
            'Separation anxiety is normal. Short, confident goodbyes help.',
        parentTip:
            'Baby-proof everything! They\'re mobile now. Expect some clinginess \u2014 it\'s healthy attachment.',
      ),
      DevelopmentMilestone(
        ageMonths: 12,
        label: 'First birthday \u2014 first words & steps',
        description:
            'Baby may say 1-3 words, pull to stand, possibly take first steps. '
            'Waves bye-bye, responds to name.',
        nhsGuidance:
            'Walking typically starts between 9-18 months. Wide variation is normal.',
        parentTip:
            'Don\'t worry if they\'re not walking yet. Some babies are early walkers, some are early talkers!',
        warningSignsToWatch: [
          'No babbling at all',
          'Doesn\'t respond to name',
          'Cannot bear weight on legs'
        ],
      ),
      DevelopmentMilestone(
        ageMonths: 18,
        label: 'Walking confidently & vocabulary explosion',
        description:
            'Walks well, starts to run, 10-20 words, simple pretend play, '
            'can follow basic instructions.',
        nhsGuidance:
            'Encourage independence \u2014 let them feed themselves, help with dressing.',
        parentTip:
            'Read together every day. Point at things and name them. Their vocabulary is growing fast!',
      ),
      DevelopmentMilestone(
        ageMonths: 24,
        label: 'Two-word sentences & growing independence',
        description:
            'Combines two words ("more milk"), runs, kicks a ball, '
            'starts to show defiance (the "terrible twos").',
        nhsGuidance:
            'This is a normal stage of asserting independence. Set clear, consistent boundaries.',
        parentTip:
            'Tantrums are normal! Stay calm, acknowledge their feelings. This phase passes.',
        warningSignsToWatch: [
          'No words at all',
          'Not walking',
          'Doesn\'t play with others'
        ],
      ),
      DevelopmentMilestone(
        ageMonths: 36,
        label: 'Nursery readiness',
        description:
            'Full sentences, imaginative play, toilet training, can dress with help, '
            'plays alongside other children.',
        nhsGuidance:
            'Free 15-hour childcare available for all 3-year-olds in England.',
        parentTip:
            'If starting nursery, do settling-in visits. It\'s normal for both of you to find it emotional!',
      ),
      DevelopmentMilestone(
        ageMonths: 48,
        label: 'Pre-school skills developing',
        description:
            'Recognises some letters and numbers, draws recognisable shapes, '
            'has friends, tells stories.',
        nhsGuidance:
            'Focus on social skills, independence, and a love of learning through play.',
        parentTip:
            'Don\'t stress about academic skills \u2014 play IS learning at this age.',
      ),
    ]);
  }

  // ── UK VACCINATION SCHEDULE ────────────────────────────────────────────

  void _seedVaccinations() {
    _vaccinations.addAll(const [
      VaccinationItem(
        ageWeeks: 8,
        name: '6-in-1 vaccine (1st dose)',
        protectsAgainst:
            'Diphtheria, hepatitis B, Hib, polio, tetanus, whooping cough',
        nhsNote: 'Given at 8 weeks. Baby may be fussy for 24-48 hours after.',
      ),
      VaccinationItem(
        ageWeeks: 8,
        name: 'Rotavirus vaccine (1st dose)',
        protectsAgainst: 'Rotavirus gastroenteritis',
        nhsNote: 'Oral drops. Given at 8 weeks alongside 6-in-1.',
      ),
      VaccinationItem(
        ageWeeks: 8,
        name: 'MenB vaccine (1st dose)',
        protectsAgainst: 'Meningococcal group B disease',
        nhsNote:
            'May cause fever \u2014 give infant paracetamol as advised by nurse.',
      ),
      VaccinationItem(
        ageWeeks: 12,
        name: '6-in-1 vaccine (2nd dose)',
        protectsAgainst:
            'Diphtheria, hepatitis B, Hib, polio, tetanus, whooping cough',
        nhsNote: 'Second dose at 12 weeks.',
      ),
      VaccinationItem(
        ageWeeks: 12,
        name: 'Pneumococcal vaccine (1st dose)',
        protectsAgainst: 'Pneumococcal infections',
        nhsNote: 'Given at 12 weeks.',
      ),
      VaccinationItem(
        ageWeeks: 12,
        name: 'Rotavirus vaccine (2nd dose)',
        protectsAgainst: 'Rotavirus gastroenteritis',
        nhsNote: 'Second and final dose at 12 weeks.',
      ),
      VaccinationItem(
        ageWeeks: 16,
        name: '6-in-1 vaccine (3rd dose)',
        protectsAgainst:
            'Diphtheria, hepatitis B, Hib, polio, tetanus, whooping cough',
        nhsNote: 'Third dose at 16 weeks.',
      ),
      VaccinationItem(
        ageWeeks: 16,
        name: 'MenB vaccine (2nd dose)',
        protectsAgainst: 'Meningococcal group B disease',
        nhsNote: 'Second dose at 16 weeks.',
      ),
      VaccinationItem(
        ageWeeks: 52,
        name: 'Hib/MenC booster',
        protectsAgainst:
            'Haemophilus influenzae type b and meningococcal C',
        nhsNote: 'Given at 1 year as a booster.',
      ),
      VaccinationItem(
        ageWeeks: 52,
        name: 'MMR vaccine (1st dose)',
        protectsAgainst: 'Measles, mumps, rubella',
        nhsNote:
            'First dose at 1 year. Very important \u2014 measles can be serious.',
      ),
      VaccinationItem(
        ageWeeks: 52,
        name: 'Pneumococcal booster',
        protectsAgainst: 'Pneumococcal infections',
        nhsNote: 'Booster at 1 year.',
      ),
      VaccinationItem(
        ageWeeks: 52,
        name: 'MenB booster',
        protectsAgainst: 'Meningococcal group B disease',
        nhsNote: 'Booster at 1 year.',
      ),
    ]);
  }

  // ── SAFETY RECALLS ─────────────────────────────────────────────────────

  void _seedSafetyRecalls() {
    _safetyRecalls.addAll(const [
      SafetyRecall(
        productName: 'Fisher-Price Rock \'n Play Sleeper',
        manufacturer: 'Fisher-Price',
        reason:
            'Linked to infant fatalities. Recalled due to risk of suffocation when babies roll.',
        dateIssued: '2019',
        source: 'US CPSC / UK Trading Standards',
      ),
      SafetyRecall(
        productName: 'Kids2 Rocking Sleeper',
        manufacturer: 'Kids2',
        reason:
            'Similar risk to Rock \'n Play \u2014 inclined sleepers not safe for unsupervised sleep.',
        dateIssued: '2019',
        source: 'US CPSC / UK Trading Standards',
      ),
      SafetyRecall(
        productName: 'Boppy Lounger',
        manufacturer: 'Boppy',
        reason: 'Linked to infant suffocation. Not designed for sleep.',
        dateIssued: '2021',
        source: 'US CPSC',
      ),
      SafetyRecall(
        productName: 'Bumbo Floor Seat',
        manufacturer: 'Bumbo',
        reason:
            'Risk of falling when placed on elevated surfaces. Must only be used on the floor.',
        dateIssued: '2012',
        source: 'UK Trading Standards',
      ),
      SafetyRecall(
        productName: 'Drop-side cots',
        manufacturer: 'Various',
        reason:
            'Banned in the UK since 2013 due to risk of entrapment and suffocation.',
        dateIssued: '2013',
        source: 'UK Government',
      ),
      SafetyRecall(
        productName: 'Inclined sleepers (all brands)',
        manufacturer: 'Various',
        reason:
            'Any inclined sleeper over 10 degrees is considered unsafe. '
            'Babies should sleep on a flat, firm surface.',
        dateIssued: '2020',
        source: 'NHS / Lullaby Trust',
      ),
    ]);
  }

  // ── SEASONAL TIPS (with {borough} placeholder) ─────────────────────────

  void _seedSeasonalTips() {
    _seasonalTips.addAll(const [
      SeasonalTip(
        month: 1,
        title: 'January \u2014 new year, new routines',
        body:
            'A great time to establish healthy routines after the festive season. '
            'Try a new baby class or join a local group in {borough} to beat the January blues.',
        suggestedActivities: [
          'Join a new baby/toddler group in your borough',
          'Library rhyme time',
          'Indoor soft play',
          'Messy play at home'
        ],
        source: 'netmums',
      ),
      SeasonalTip(
        month: 2,
        title: 'February \u2014 half-term activities',
        body:
            'Half-term is a great opportunity for family outings in {borough}. '
            'Museums often run free workshops for children.',
        suggestedActivities: [
          'Museum visit',
          'Science centre',
          'Indoor play centre',
          'Baking together'
        ],
        source: 'netmums',
      ),
      SeasonalTip(
        month: 3,
        title: 'March \u2014 spring is coming',
        body:
            'Days are getting longer. Perfect time to start outdoor meetups in {borough}. '
            'NCT Walk & Talk groups are brilliant this time of year.',
        suggestedActivities: [
          'NCT Walk & Talk in your borough',
          'Park playdate',
          'Spring nature walk',
          'Plant seeds together'
        ],
        source: 'nct',
      ),
      SeasonalTip(
        month: 4,
        title: 'April \u2014 Easter fun',
        body:
            'Easter activities are everywhere in {borough}! Many venues do egg hunts. '
            'Check the Huddl events page for what\'s on locally.',
        suggestedActivities: [
          'Easter egg hunt',
          'Farm visit',
          'Easter crafts',
          'Outdoor picnic'
        ],
        source: 'netmums',
      ),
      SeasonalTip(
        month: 5,
        title: 'May \u2014 outdoor play season begins',
        body:
            'The weather is warming up. Great time for park meetups in {borough}, '
            'outdoor swimming, and nature walks.',
        suggestedActivities: [
          'Park meetup with borough parents',
          'Paddling pool day',
          'Nature walk',
          'Garden play'
        ],
        source: 'nct',
      ),
      SeasonalTip(
        month: 6,
        title: 'June \u2014 summer socialising',
        body:
            'School summer fetes, family festivals, and long evenings in {borough}. '
            'Perfect for organising neighbourhood parent meetups.',
        suggestedActivities: [
          'Summer fete',
          'Outdoor family picnic',
          'Beach day',
          'Evening park play'
        ],
        source: 'netmums',
      ),
      SeasonalTip(
        month: 7,
        title: 'July \u2014 summer holidays',
        body:
            'Six weeks of summer holidays! Plan a mix of free outdoor activities '
            'in {borough} and rainy-day indoor options.',
        suggestedActivities: [
          'Water play at home',
          'City farm visit',
          'Library summer reading challenge',
          'Camping in the garden'
        ],
        source: 'netmums',
      ),
      SeasonalTip(
        month: 8,
        title: 'August \u2014 keeping cool and entertained',
        body:
            'August can be hot! Paddling pools, water tables, and shaded park play in {borough}. '
            'Don\'t forget sun protection \u2014 factor 50 and a hat.',
        suggestedActivities: [
          'Paddling pool playdate',
          'Shaded park picnic',
          'Ice lolly making',
          'Story time at the library'
        ],
        source: 'nhs',
      ),
      SeasonalTip(
        month: 9,
        title: 'September \u2014 back to school/nursery',
        body:
            'If your child is starting nursery or school, prepare with settling-in visits. '
            'Join a {borough} parent group on Huddl for tips from parents who\'ve been through it.',
        suggestedActivities: [
          'School/nursery settling visits',
          'Back-to-school shopping',
          'Autumn nature walk',
          'Join a new parent group'
        ],
        source: 'nhs',
      ),
      SeasonalTip(
        month: 10,
        title: 'October \u2014 half-term & Halloween',
        body:
            'Halloween crafts and pumpkin picking are big hits in {borough}. '
            'Check Huddl marketplace for costumes \u2014 buy local, save money!',
        suggestedActivities: [
          'Pumpkin picking',
          'Halloween crafts',
          'Nearly New Sale',
          'Conker collecting'
        ],
        source: 'nct',
      ),
      SeasonalTip(
        month: 11,
        title: 'November \u2014 fireworks and cosy indoor play',
        body:
            'Bonfire night in {borough}! Protect little ears with ear defenders. '
            'As it gets colder, indoor play centres are your friend.',
        suggestedActivities: [
          'Fireworks display',
          'Indoor soft play',
          'Sensory play at home',
          'Baking session'
        ],
        source: 'netmums',
      ),
      SeasonalTip(
        month: 12,
        title: 'December \u2014 festive family fun',
        body:
            'Christmas can be magical but also overwhelming with a baby/toddler. '
            'Keep routines as normal as possible. Check {borough} events for Santa visits and pantos.',
        suggestedActivities: [
          'Santa\'s grotto visit',
          'Christmas crafts',
          'Carol singing',
          'Borough Christmas meetup'
        ],
        source: 'netmums',
      ),
    ]);
  }

  // ── COMMUNITY TEMPLATES (Borough-Scoped) ───────────────────────────────

  void _seedCommunityTemplates() {
    _communityTemplates.addAll(const [
      // ── BOROUGH-ONLY groups (chat, meetups, marketplace scoped) ──
      CommunityTemplate(
        name: 'Bumps & Babies',
        description:
            'A friendly drop-in group for pregnant parents and those with babies '
            'in {borough}. Share stories, get support, and make friends over tea and biscuits.',
        category: 'bumps_and_babies',
        audience: 'expecting',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'nct',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Walk & Talk',
        description:
            'Gentle walks with buggies and slings around {borough}. Fresh air, '
            'light exercise, and great conversation. All local parents welcome.',
        category: 'walk_and_talk',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'nct',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Baby & Child First Aid',
        description:
            'Learn essential first aid skills: CPR, choking response, burns treatment. '
            'Held locally in {borough} \u2014 every parent should feel confident to act in an emergency.',
        category: 'first_aid',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'monthly',
        source: 'nct',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Baby Cafe',
        description:
            'Breastfeeding and feeding support in a relaxed, social setting in {borough}. '
            'Trained volunteers and peer supporters available. All feeding methods welcome.',
        category: 'feeding_support',
        audience: 'new_parent',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'nct',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Nearly New Sale',
        description:
            'Quality preloved baby and children\'s items at bargain prices \u2014 '
            'exclusively for {borough} parents. Sell your outgrown gear locally.',
        category: 'nearly_new_sale',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'monthly',
        source: 'nct',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Local Activity Swap',
        description:
            'Share recommendations for local classes, soft play centres, parks, '
            'and family-friendly venues in {borough}. Your local knowledge helps everyone!',
        category: 'local_tips',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'fortnightly',
        source: 'netmums',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Weaning Warriors',
        description:
            'Starting solids? Join other {borough} parents navigating weaning. Share recipes, '
            'tips, and stories. Baby-led or spoon-fed \u2014 all approaches welcome.',
        category: 'feeding_support',
        audience: 'new_parent',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'netmums',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'SEN Parent Support',
        description:
            'A safe space for {borough} parents of children with additional needs. '
            'Share experiences, resources, and emotional support. You are not alone.',
        category: 'sen_support',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'fortnightly',
        source: 'netmums',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'School-Gate Coffee',
        description:
            'Weekly coffee catch-up for school parents in {borough}. Swap tips on homework, '
            'school events, and kids\' activities.',
        category: 'social',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'netmums',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Dad & Kids Saturday Club',
        description:
            'Weekend meetup for dads and their kids in {borough}. Parks, soft play, or just a brew. '
            'Meet other hands-on local dads.',
        category: 'dad_meetup',
        audience: 'dad',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'dadsnet',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Dad Brunch Club',
        description:
            'Monthly brunch for dads in {borough}. Bring the kids, grab some food, and talk about '
            'the real stuff \u2014 sleep deprivation, work-life balance, and dad jokes.',
        category: 'dad_meetup',
        audience: 'dad',
        format: 'in_person',
        suggestedFrequency: 'monthly',
        source: 'dadsnet',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Expecting Dads Chat',
        description:
            'For dads-to-be in {borough}. Ask questions, share worries, and get advice '
            'from experienced local dads. No question is too silly.',
        category: 'dad_meetup',
        audience: 'expecting',
        format: 'hybrid',
        suggestedFrequency: 'fortnightly',
        source: 'dadsnet',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'New Parent Wellbeing Circle',
        description:
            'A supportive group for new parents in {borough} to talk openly about '
            'how they\'re really feeling. Mental health matters. You\'re not alone.',
        category: 'wellbeing',
        audience: 'new_parent',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'nhs',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Sleep Support Group',
        description:
            'Struggling with sleep? Join other {borough} parents to share what works '
            '(and what doesn\'t). Evidence-based tips and moral support.',
        category: 'sleep_support',
        audience: 'new_parent',
        format: 'hybrid',
        suggestedFrequency: 'fortnightly',
        source: 'nhs',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Milestone Mums & Dads',
        description:
            'Celebrating baby milestones together in {borough}! Share photos, stories, and tips. '
            'From first smile to first steps.',
        category: 'milestones',
        audience: 'new_parent',
        format: 'in_person',
        suggestedFrequency: 'monthly',
        source: 'bounty',
        scope: ContentScope.boroughOnly,
      ),
      CommunityTemplate(
        name: 'Borough Marketplace Chat',
        description:
            'The go-to group for buying and selling preloved baby items in {borough}. '
            'Everything from buggies to baby clothes \u2014 all local, all easy to collect.',
        category: 'marketplace',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'netmums',
        scope: ContentScope.boroughOnly,
      ),

      // ── UK-WIDE templates (events only) ──
      CommunityTemplate(
        name: 'Family Day Out Planner',
        description:
            'Discover family events and days out across the UK. Browse events in any borough '
            '\u2014 great for when you\'re travelling or planning an adventure.',
        category: 'events',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'netmums',
        scope: ContentScope.ukWide,
      ),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _saveToStorage() async {
    try {
      final data = {
        'articles': _articles.map((a) => a.toJson()).toList(),
        'lastRefresh': _lastRefresh?.toIso8601String(),
      };
      await BrowserStorage.setString(_storageKey, jsonEncode(data));
      _log('Saved knowledge base to storage');
    } catch (e) {
      _log('Error saving knowledge base: $e');
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final json = await BrowserStorage.getString(_storageKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final refreshStr = data['lastRefresh'] as String?;
        if (refreshStr != null) {
          _lastRefresh = DateTime.tryParse(refreshStr);
        }
        _log('Loaded knowledge base metadata from storage');
      }

      final refreshJson = await BrowserStorage.getString(_lastRefreshKey);
      if (refreshJson != null) {
        _lastRefresh = DateTime.tryParse(refreshJson);
      }
    } catch (e) {
      _log('Error loading knowledge base from storage: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

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

  String _sourceDisplayName(String source) {
    switch (source) {
      case 'nhs':
        return 'NHS';
      case 'nct':
        return 'NCT';
      case 'bounty':
        return 'Bounty';
      case 'netmums':
        return 'Netmums';
      case 'dadsnet':
        return 'Dadsnet';
      default:
        return source;
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('\u{1F9E0} KnowledgeBase: $message');
    }
  }
}
