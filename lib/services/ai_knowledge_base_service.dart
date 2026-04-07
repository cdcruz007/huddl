import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'onboarding_data_service.dart';
import 'postcode_service.dart';

// =============================================================================
// AI PARENTING KNOWLEDGE BASE SERVICE  — ENRICHED HYPERLOCAL EDITION v3
//
// Centralised, structured parenting knowledge sourced from 45+ trusted UK sites:
//
//  TIER 1 — CLINICAL / AUTHORITATIVE
//   - NHS (nhs.uk)                — Clinical guidelines, vaccinations, safety
//   - NCT (nct.org.uk)            — Antenatal, postnatal, groups & workshops
//   - BBC Bitesize Parents        — Education support, teen parenting
//
//  TIER 2 — COMMUNITY / CHARITY
//   - Coram Family Lives           — Helpline, online courses, ParentChannel TV
//   - Barnardo's                   — Child safety, emotional wellbeing
//   - Gingerbread                  — Single parent support (800K+ reached/yr)
//   - Care for the Family          — Dad Cave podcast, bereavement support
//   - Parent Zone                  — Digital safety, Online Safety Act
//   - Parentkind                   — PTAs, National Parent Survey (5,866 parents)
//   - Contact                      — Families with disabled children (381K helped)
//   - Family Fund                  — Disabled/seriously ill children support
//   - Sibs                         — Sibling support for SEN families
//   - Home for Good / Adoption UK  — Fostering & adoption support
//   - OnlyMums & Dads              — Family separation & co-parenting
//   - HappySteps                   — Stepfamily / blended family coaching
//
//  TIER 3 — PARENT VOICES / BLOGS
//   - Netmums (netmums.com)        — Real-parent advice, activities, local tips
//   - Dadsnet (dadsnet.com)        — Father-focused parenting, mental health
//   - DaddiLife (daddilife.com)     — Father-specific content, sleep training
//   - Dad.info                      — Dad mental health, practical guidance
//   - Parent Talk Podcast           — Emotional intelligence, resilience
//   - Today's Parent                — Executive function, anti-racist parenting
//   - Green Parent                  — Eco-parenting, nature, parental isolation
//   - Slummy Single Mummy          — Single parent perspective, low-effort wins
//   - Berkshire Mummies             — Hyperlocal model: What's On, soft play
//   - MummyPages                    — Pregnancy tips, seasonal activities
//   - HuffPost Parents              — Raising teens, school life, health
//   - Bounty (bounty.com)           — Pregnancy stages, baby milestones
//   - Mamas & Papas                 — Product guidance, Buying for Baby
//   - MyBaba (mybaba.com)            — Luxury family lifestyle, travel, wellbeing
//   - Selmind directory              — Local mental health service referrals
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
  teens, // 10-18 years — new from HuffPost, BBC Bitesize
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
  singleParent, // new — Gingerbread, SlummySingleMummy
  digitalSafety, // new — Parent Zone, BBC Bitesize
  senDisability, // new — Contact, Family Fund, Sibs
  adoptionFostering, // new — Adoption UK, CoramBAAF, Home for Good
  stepfamily, // new — HappySteps
  separationCoParenting, // new — OnlyMums & Dads
  emotionalIntelligence, // new — Parent Talk Podcast
  ecoParenting, // new — Green Parent
  parentalWellbeing, // new — Coram Family Lives, Care for the Family
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
        '- Use inclusive language. Avoid assumptions about family structure '
        '(single parents, blended families, adoptive/foster families, co-parents '
        'are all equally valid).');
    if (isDad) {
      buffer.writeln(
          '- This user is a dad. Be mindful that dads can feel excluded from parenting '
          'conversations. Be encouraging and affirming of their role. Reference dad-specific '
          'advice when relevant (from Dadsnet, DaddiLife, Dad.info, and Care for the Family\'s '
          'Dad Cave podcast).');
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
        '- For mental health crises: PANDAS Foundation (0808 196 1776), '
        'Coram Family Lives helpline (24/7), or NHS talking therapies.');
    buffer.writeln(
        '- For single parent support: Gingerbread helpline and local groups.');
    buffer.writeln(
        '- For families with disabled children: Contact (contact.org.uk, 381K families helped).');
    buffer.writeln(
        '- For separation/co-parenting: OnlyMums & Dads, Coram Family Lives helpline.');
    buffer.writeln(
        '- Reference trusted UK sources where appropriate: "According to NHS guidelines...", '
        '"Many parents on Netmums have found...", "NCT recommends...", '
        '"Parent Talk Podcast discusses...", "Gingerbread advises..."');
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
        '- For mental health concerns: suggest NHS talking therapies, health visitor, '
        'PANDAS Foundation helpline (0808 196 1776), or Coram Family Lives helpline (24/7).');
    buffer.writeln(
        '- For family breakdown: suggest Coram Family Lives (24/7), '
        'OnlyMums & Dads, or Gingerbread for single parents.');
    buffer.writeln(
        '- For disabled children support: suggest Contact (contact.org.uk) or Family Fund.');
    buffer.writeln(
        '- For online safety concerns: suggest Parent Zone or CEOP.');
    buffer.writeln(
        '- For adoption/fostering queries: suggest Adoption UK, CoramBAAF, or Home for Good.');
    buffer.writeln(
        '- For bereavement: suggest Care for the Family bereavement support.');
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
        'Dad Meetups, Wellbeing Circle, Nearly New Sales, Activity Swaps, '
        'Single Parents Connect, Digital Families, SEN Support, Adoption & Fostering, '
        'Blended Families, Co-Parenting Support, Green Parents, School Network, '
        'Raising Teens, Emotions & Resilience Workshop.');
    buffer.writeln(
        '- Meetup types: Playdate, Coffee morning, Park walk, Swimming, '
        'Soft play, Library rhyme time, Dad & Kids outing, Bluebell walk, '
        'Nature trail, Charity event, PTA fundraiser, Nearly New Sale.');
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
        'soft play, farm visits, museum activities, festivals, NCT events, '
        'Adoption UK family walks, CoramBAAF conferences, Family Fund face-to-face support, '
        'Gingerbread virtual comedy shows, Care for the Family tours, '
        'Barnardo\'s workshops, Parentkind webinars, charity fundraising events.');
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

      // ═══════════════════════════════════════════════════════════════════════
      // ENRICHED V3: New articles from 37 additional UK parenting sources
      // ═══════════════════════════════════════════════════════════════════════

      // ─── SINGLE PARENT SUPPORT (Gingerbread, Slummy Single Mummy) ──────
      KnowledgeArticle(
        id: 'sp_001',
        title: 'Single parent support \u2014 you are not alone',
        summary:
            'Nearly 800,000 single parents access Gingerbread\'s online info each year. '
            'Over 50 volunteer-led groups operate across England and Wales.',
        body:
            'Being a single parent comes with unique challenges, but there is a huge '
            'community of support. Gingerbread (gingerbread.org.uk) is the leading charity for '
            'single parents, offering advice on benefits, housing, legal rights, employment, '
            'and emotional support. They run local volunteer-led groups in many boroughs. '
            'Key resources: 1) Benefits calculator to check your entitlements. '
            '2) Legal advice on child maintenance, custody, and co-parenting. '
            '3) Virtual comedy shows and community events for single parents. '
            '4) Policy updates (e.g. April changes to wages, sick pay, Universal Credit). '
            'Financial planning tip from Slummy Single Mummy: meal planning and growing '
            'vegetables with your kids can save money and build confidence. '
            'On Huddl, connect with other single parents in your borough for local support.',
        category: KnowledgeCategory.singleParent,
        tags: ['single parent', 'gingerbread', 'benefits', 'support', 'financial planning'],
        source: 'gingerbread',
        sourceUrl: 'https://www.gingerbread.org.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.88,
        lastUpdated: now,
      ),

      // ─── DIGITAL SAFETY (Parent Zone, BBC Bitesize) ────────────────────
      KnowledgeArticle(
        id: 'ds_001',
        title: 'Online safety for children \u2014 a parent\'s guide',
        summary:
            'Parent Zone provides resources on screen time, social media, and the Online '
            'Safety Act. BBC Bitesize helps parents support children\'s digital learning.',
        body:
            'As the government considers social media bans for under-16s, there are practical '
            'steps parents can take now. Parent Zone (parentzone.org.uk) offers: '
            '1) Everyday Digital programme \u2014 plug-and-play resources for digital family life. '
            '2) Tech Shock podcast \u2014 the latest on smartphone bans and online safety legislation. '
            '3) UK curriculum reforms on AI and Media Literacy guidance for schools. '
            'BBC Bitesize Parents (bbc.co.uk/bitesize/parents) covers: '
            '1) Life online safety tips. 2) Digital resilience building. '
            '3) Age-appropriate content recommendations. '
            'DaddiLife advises on "What is digital resilience?" with internet safety tips for kids. '
            'Key rules: Set clear screen time limits, use parental controls, watch content together, '
            'have open conversations about online experiences. '
            'For teens: know the apps they use, understand teen slang (HuffPost Parents has a guide), '
            'and create a family digital agreement.',
        category: KnowledgeCategory.digitalSafety,
        tags: ['online safety', 'screen time', 'social media', 'digital resilience', 'teens'],
        source: 'parentzone',
        sourceUrl: 'https://parentzone.org.uk/',
        ageStages: ['preschool', 'schoolAge', 'teens'],
        relevanceWeight: 0.85,
        lastUpdated: now,
      ),

      // ─── SEN & DISABILITY (Contact, Family Fund, Sibs) ────────────────
      KnowledgeArticle(
        id: 'sen_001',
        title: 'Support for families with disabled children',
        summary:
            'Contact helps 381,000 parent carers annually. 95% feel better informed after '
            'their support. Family Fund provides grants for families raising disabled children.',
        body:
            'If your child has a disability, special educational need, or long-term condition, '
            'there is significant UK-wide support: '
            '1) Contact (contact.org.uk) \u2014 advice, community, and advocacy. 381,000 parent carers '
            'helped annually; 14,735 families directly reached through programmes; 95% felt satisfied '
            'with their service. 97% would recommend. Covers education, benefits, local services. '
            '2) Family Fund (familyfund.org.uk) \u2014 grants for essentials, face-to-face events '
            'in cities across the UK. "Cost of Caring" research surveyed 2,000+ families. '
            '3) Sibs (sibs.org.uk) \u2014 support specifically for siblings. A child like Amelia, 5, '
            'who misses activities because they upset her autistic brother, can find understanding here. '
            'Supports young siblings (7-17) and adult siblings (18+). '
            '4) Barnardo\'s (barnardos.org.uk) \u2014 practical advice on preventing home accidents, '
            'supporting emotional wellbeing, addressing bullying and cyberbullying. '
            'On Huddl, our SEN Parent Support groups connect you with local families who understand.',
        category: KnowledgeCategory.senDisability,
        tags: ['SEN', 'disability', 'SEND', 'contact', 'family fund', 'sibs', 'additional needs'],
        source: 'contact',
        sourceUrl: 'https://contact.org.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.87,
        lastUpdated: now,
      ),

      // ─── ADOPTION & FOSTERING (Home for Good, Adoption UK, CoramBAAF) ──
      KnowledgeArticle(
        id: 'af_001',
        title: 'Fostering and adoption \u2014 finding loving homes',
        summary:
            'Every 15 minutes a child enters care in the UK. Adoption UK, CoramBAAF, '
            'and Home for Good help families explore fostering and adoption.',
        body:
            'Every 15 minutes a child enters care in the UK. If you are considering '
            'fostering or adoption: '
            '1) Home for Good (homeforgood.org.uk) \u2014 coordinates a national network to ensure '
            'every child finds a loving home. Supports individuals, churches, and local movements. '
            '2) Adoption UK (adoptionuk.org) \u2014 the leading UK charity for adopted and care-experienced '
            'people, founded 1971. Offers membership, community events, family walks, parent dinners, '
            'and advocacy. Recent focus on SEND reforms and forced adoption survivors. '
            '3) CoramBAAF (corambaaf.org.uk) \u2014 the UK\'s leading adoption/fostering membership body. '
            'Runs adoption conferences, effective panels courses, and publishes starter packs. '
            'New: kinship allowance pilot backed by \u00A3126 million reaching ~5,000 children. '
            '4) First4Adoption (first4adoption.org.uk) \u2014 a helpful first stop for adoption info. '
            'On Huddl, adoptive and foster families can find local support groups in their borough.',
        category: KnowledgeCategory.adoptionFostering,
        tags: ['adoption', 'fostering', 'kinship', 'care', 'Home for Good', 'CoramBAAF'],
        source: 'adoptionuk',
        sourceUrl: 'https://www.adoptionuk.org/',
        // Also: Home for Good → https://www.homeforgood.org.uk/
        ageStages: ['all'],
        relevanceWeight: 0.82,
        lastUpdated: now,
      ),

      // ─── STEPFAMILY (HappySteps) ───────────────────────────────────────
      KnowledgeArticle(
        id: 'sf_001',
        title: 'Blended families \u2014 navigating stepparenting',
        summary:
            'Dr Lisa Doodson\'s HappySteps offers workshops, coaching, and step-mum meet-ups. '
            'Stepparenting is rewarding but comes with unique challenges.',
        body:
            'Blended families are increasingly common in the UK. Dr Lisa Doodson '
            '(happysteps.co.uk) is one of the UK\'s leading stepfamily experts: '
            '1) 4-week group workshops via video call (recordings provided). '
            '2) 1-to-1 and couple coaching for specific challenges. '
            '3) Step-mum meet-ups for peer support. '
            '4) Books: "How to Be a Happy Stepmum" and "Understanding Stepfamilies" '
            '(professional guide for counsellors). '
            'Key tips: Take things slowly \u2014 building trust takes time. '
            'Don\'t try to replace the other parent. Communicate with your partner about '
            'discipline and boundaries. Celebrate the positives of your blended family. '
            'Coram Family Lives also offers leaflets on stepfamily guidance. '
            'On Huddl, stepfamilies can find understanding and local support within their borough.',
        category: KnowledgeCategory.stepfamily,
        tags: ['stepfamily', 'blended family', 'stepparent', 'happysteps'],
        source: 'happysteps',
        sourceUrl: 'https://happysteps.co.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.78,
        lastUpdated: now,
      ),

      // ─── SEPARATION & CO-PARENTING (OnlyMums & Dads) ──────────────────
      KnowledgeArticle(
        id: 'sep_001',
        title: 'Separating with children \u2014 practical support',
        summary:
            'OnlyMums & Dads is a UK social enterprise supporting families going through '
            'separation with one-to-one meetings, publications, and guidance.',
        body:
            'If you are going through a separation or divorce with children, you are not alone. '
            'OnlyMums & Dads (onlymumsanddads.org) is a social enterprise offering: '
            '1) One-to-one online meetings for parents starting their separation journey. '
            '2) "Separating With Children 101" publication for practical guidance. '
            '3) "Almost Anything But Family Court" guide to explore alternatives. '
            '4) Family Separation Support Hub with comprehensive resources. '
            'Coram Family Lives also offers: free 24/7 helpline (phone, email, WhatsApp, chat), '
            'online parenting courses, and a links directory. Their "Outsiders" booklets cover '
            'imprisonment impact on children and families. '
            'Key advice: Keep children\'s wellbeing central, maintain routines, '
            'never speak negatively about the other parent in front of children, '
            'and seek professional mediation where possible.',
        category: KnowledgeCategory.separationCoParenting,
        tags: ['separation', 'divorce', 'co-parenting', 'family court', 'mediation'],
        source: 'onlymumsanddads',
        sourceUrl: 'https://www.onlymumsanddads.org/',
        ageStages: ['all'],
        relevanceWeight: 0.80,
        lastUpdated: now,
      ),

      // ─── EMOTIONAL INTELLIGENCE (Parent Talk Podcast) ──────────────────
      KnowledgeArticle(
        id: 'ei_001',
        title: 'Emotion regulation and resilience in children',
        summary:
            'Parent Talk Podcast covers vital topics: how toddlers think, building resilience, '
            'what to do when your child says "I hate you", and emotion regulation techniques.',
        body:
            'Parent Talk Podcast (parenttalkpodcast.com) is a treasure trove of expert insights: '
            '1) "When My Child Says I Hate You" \u2014 understanding it\'s an emotional expression, not fact. '
            'Stay calm, acknowledge feelings ("I can see you\'re really upset"), give space, reconnect later. '
            '2) "How Toddlers Think" \u2014 toddlers are not being manipulative; their brains are '
            'developing and they cannot yet regulate emotions. Meltdowns are learning opportunities. '
            '3) "Resilience" \u2014 building resilience means allowing age-appropriate risk, '
            'letting children experience failure safely, and modelling problem-solving. '
            '4) "Emotion Regulation" \u2014 teach children to name their feelings. '
            'Use a feelings chart or traffic light system. DaddiLife highlights that be-calmer '
            'parenting resolutions don\'t work \u2014 try practical alternatives instead. '
            'Today\'s Parent covers executive function development \u2014 the brain\'s air traffic controller '
            'that helps children plan, focus, and manage impulses.',
        category: KnowledgeCategory.emotionalIntelligence,
        tags: ['emotion regulation', 'resilience', 'toddler behaviour', 'feelings', 'podcast'],
        source: 'parenttalk',
        sourceUrl: 'https://parenttalkpodcast.com/',
        ageStages: ['toddler', 'preschool', 'schoolAge'],
        relevanceWeight: 0.86,
        lastUpdated: now,
      ),

      // ─── ECO-PARENTING (Green Parent) ──────────────────────────────────
      KnowledgeArticle(
        id: 'eco_001',
        title: 'Green parenting \u2014 sustainable family life',
        summary:
            'The Green Parent covers eco-parenting, nature walks, and tackling parental isolation '
            'through outdoor connection. English Heritage launched "bonding benches".',
        body:
            'The Green Parent (thegreenparent.co.uk) champions sustainable family living: '
            '1) "Step Into Spring: Best Bluebell Walks Across the UK" \u2014 nature connection '
            'for families with route guides suitable for pushchairs. '
            '2) "When the Clocks Change, Kids Feel it Most" \u2014 managing sleep transitions. '
            '3) "English Heritage launches bonding benches to tackle parental isolation" \u2014 '
            'designated benches where new parents can sit and connect with others. '
            '4) "Hidden Dyslexia" \u2014 recognising signs that may be missed in young children. '
            'Practical eco tips: use cloth nappies (saves ~\u00A31,000 over potty training), '
            'buy preloved on Huddl Market, walk or cycle for short trips, '
            'grow vegetables with your kids (Slummy Single Mummy: "saves money and builds confidence"), '
            'and choose wooden toys over plastic where possible.',
        category: KnowledgeCategory.ecoParenting,
        tags: ['eco', 'sustainable', 'nature', 'green parent', 'environment'],
        source: 'greenparent',
        sourceUrl: 'https://thegreenparent.co.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.72,
        lastUpdated: now,
      ),

      // ─── PARENTAL WELLBEING (Coram Family Lives, Care for the Family) ──
      KnowledgeArticle(
        id: 'pw_001',
        title: 'Parental wellbeing \u2014 looking after yourself matters',
        summary:
            'Coram Family Lives offers free 24/7 helpline support. Care for the Family '
            'provides couple, bereavement, and parenting support across the UK.',
        body:
            'Looking after yourself is essential for looking after your children: '
            '1) Coram Family Lives (coramfamilylives.org.uk) \u2014 national helpline (phone, email, '
            'WhatsApp, chat) available 24/7. Free online parenting courses created by professionals. '
            'ParentChannel TV with 200+ expert videos. Leaflets on resilience, discipline, '
            'teen anger, school transitions, and gangs awareness. London-based Independent Support '
            'projects for SEND families at Portman Early Childhood Centre. '
            '2) Care for the Family (careforthefamily.org.uk) \u2014 since 2021 has helped 3,881 families, '
            'spending \u00A355,608 on UK-wide family support. Offers parent support, couple support, '
            'and bereavement support. Podcasts: The Dad Cave, Parentalk, Family Life, Raising Teens. '
            'Tour events: Tweens and Teens, The Mum Show. '
            '3) Selmind directory lists Family Lives Parents Helpline for local referrals. '
            '4) Perimenopause and sleep: Slummy Single Mummy addresses "the audacity of being awake at 3am" '
            '\u2014 hormone changes affect parenting energy. Speak to your GP if struggling.',
        category: KnowledgeCategory.parentalWellbeing,
        tags: ['wellbeing', 'helpline', 'self-care', 'support', 'courses', 'mental health'],
        source: 'coramfamilylives',
        sourceUrl: 'https://www.coramfamilylives.org.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.90,
        lastUpdated: now,
      ),

      // ─── TEEN PARENTING (HuffPost, BBC Bitesize) ───────────────────────
      KnowledgeArticle(
        id: 'teen_001',
        title: 'Raising teens \u2014 navigating the teenage years',
        summary:
            'HuffPost Parents and BBC Bitesize cover teen-specific topics from school life '
            'to teen slang. Care for the Family\'s "Raising Teens: Off Script" offers guidance.',
        body:
            'Parenting teenagers brings a whole new set of challenges: '
            '1) HuffPost Parents (huffingtonpost.co.uk/parents) covers: Life as a Parent, '
            'Raising Teens, Teen Slang Explained, School Life, and Children\'s Health. '
            '2) BBC Bitesize Parents has a dedicated "Parenting Teens" podcast covering '
            'education support and navigating digital life. '
            '3) Care for the Family offers "Raising Teens: Off Script" \u2014 a 3-part series, '
            'plus "Left to Their Own Devices?" on online safety events. '
            '4) Parent Zone highlights the social media ban debate for under-16s. '
            '5) Barnardo\'s addresses teenage risky behaviour, self-harm, and anxiety. '
            'Key principles: maintain open communication, choose your battles wisely, '
            'respect their growing independence, stay connected even when they push you away, '
            'and know the warning signs of mental health issues (withdrawal, self-harm, '
            'eating changes, substance use). CAMHS referral via GP if needed.',
        category: KnowledgeCategory.teens,
        tags: ['teenagers', 'teens', 'school', 'social media', 'mental health', 'independence'],
        source: 'huffpost',
        sourceUrl: 'https://www.huffingtonpost.co.uk/parents/',
        ageStages: ['teens', 'schoolAge'],
        relevanceWeight: 0.83,
        lastUpdated: now,
      ),

      // ─── DAD-SPECIFIC ENRICHMENT (DaddiLife, Dad.info) ─────────────────
      KnowledgeArticle(
        id: 'dad_003',
        title: 'DaddiLife \u2014 things to do with kids & keeping healthy',
        summary:
            'DaddiLife covers gratitude journaling, phonics activities, sleep training, '
            'parenting hacks for chores, and child development milestones.',
        body:
            'DaddiLife (daddilife.com) is a vibrant UK dad community covering: '
            '1) Things to do with kids: Pok\u00E9mon guides, gratitude journaling (7 reasons your kids '
            'should use one), 16 engaging phonics activities, 75 gratitude quotes for kids. '
            '2) Sleep training: "Cry It Out Method" review, "Baby Sleep Course from The Bedtime Champ" '
            'review, best nursery night lights guide. '
            '3) Parenting hacks: Getting chores done, home education resources, '
            '"33 Ways To Prepare For Fatherhood" from practical to emotional. '
            '4) Dad Heroes: "Three things I wish I knew before my kids were born" (Chris Ashton). '
            '5) Father\'s Day gift guides and man cave ideas. '
            'Dad.info (dad.info) provides practical information and emotional support specifically '
            'for fathers, including resources on mental health, relationships, and hands-on fatherhood. '
            'Care for the Family runs "The Dad Cave" podcast for dads.',
        category: KnowledgeCategory.dadSpecific,
        tags: ['dad', 'DaddiLife', 'activities', 'sleep training', 'fatherhood', 'dad.info'],
        source: 'daddilife',
        sourceUrl: 'https://www.daddilife.com/',
        ageStages: ['all', 'dad'],
        relevanceWeight: 0.84,
        lastUpdated: now,
      ),

      // ─── EDUCATION & SCHOOL (Parentkind, BBC Bitesize) ─────────────────
      KnowledgeArticle(
        id: 'edu_001',
        title: 'Supporting your child\'s education \u2014 the parent\'s role',
        summary:
            'The National Parent Survey (5,866 parents, 134,000+ insights) reveals what UK '
            'parents think about schools. Parentkind supports PTAs across the country.',
        body:
            'Parentkind (parentkind.org.uk) is the UK\'s leading PTA membership body: '
            '1) National Parent Survey 2025 \u2014 surveyed 5,866 parents across England, Scotland, '
            'Wales, and Northern Ireland. Over 134,000 insights on school satisfaction, funding, '
            'and parent involvement. '
            '2) "Be School Ready" guide for parents of reception-age children. '
            '3) Parent training and webinars on supporting children\'s learning at home. '
            '4) PTA resources for fundraising, community events, and school engagement. '
            'BBC Bitesize Parents provides: tips to support your child\'s education at every stage, '
            'phonics and reading resources, maths help, and homework support. '
            'Today\'s Parent highlights: executive function is the brain\'s "air traffic controller" '
            '\u2014 help develop it through board games, cooking together, and free play. '
            'Berkshire Mummies demonstrates the hyperlocal model: detailed school holiday '
            'What\'s On guides for every borough, complete with reviews and family-friendly venues.',
        category: KnowledgeCategory.education,
        tags: ['education', 'school', 'PTA', 'homework', 'reading', 'parentkind'],
        source: 'parentkind',
        sourceUrl: 'https://www.parentkind.org.uk/',
        ageStages: ['preschool', 'schoolAge', 'teens'],
        relevanceWeight: 0.84,
        lastUpdated: now,
      ),

      // ─── PREGNANCY ENRICHMENT (MummyPages, Mamas & Papas) ─────────────
      KnowledgeArticle(
        id: 'preg_005',
        title: 'First trimester survival guide \u2014 10 things that help',
        summary:
            'MummyPages shares 10 things that make life easier in the first trimester, '
            'plus calming techniques for birth anxiety.',
        body:
            'MummyPages (mummypages.co.uk) provides practical early pregnancy support: '
            '1) "10 things that will make your life SO much easier in the first trimester" '
            '\u2014 ginger biscuits, rest when you can, tell your workplace early if needed. '
            '2) "Anxious about giving birth? Try these calming techniques and tips" '
            '\u2014 breathing exercises, hypnobirthing taster sessions, birth plan discussions. '
            '3) "5 questions you need to discuss with your spouse before baby arrives" '
            '\u2014 division of responsibilities, finances, childcare, parenting values. '
            '4) "What dads can do to take an active role in labour" '
            '\u2014 addressing dads feeling "helpless, anxious & uncertain". '
            'Mamas & Papas (mamasandpapas.com) offers free "Buying for Baby" appointments '
            'with up to 40% savings, plus car seat appointments and step-by-step new parent support. '
            'Their app is available on iOS and Android for product guidance.',
        category: KnowledgeCategory.pregnancy,
        tags: ['first trimester', 'birth anxiety', 'baby essentials', 'pregnancy tips'],
        source: 'mummypages',
        sourceUrl: 'https://www.mummypages.co.uk/',
        ageStages: ['pregnancy'],
        relevanceWeight: 0.83,
        lastUpdated: now,
      ),

      // ─── ACTIVITIES ENRICHMENT (Berkshire Mummies, Netmums) ────────────
      KnowledgeArticle(
        id: 'act_002',
        title: 'Hyperlocal family activities \u2014 the borough guide model',
        summary:
            'Berkshire Mummies demonstrates the hyperlocal approach with detailed What\'s On '
            'guides for school holidays, seasonal events, walks, and soft play centres.',
        body:
            'Berkshire Mummies (berkshiremummies.co.uk) is the model for hyperlocal parenting content. '
            'Run by Shona, a stay-at-home mum, it covers Bracknell, Windsor, Maidenhead, Wokingham, '
            'Ascot, Reading, Thatcham, and Newbury. Content includes: '
            '1) Detailed "What\'s On" guides for every school holiday with dates and venues. '
            '2) Soft play centre directory with reviews and pushchair-friendliness ratings. '
            '3) "Walks with Parks" \u2014 family-friendly walking routes with playground maps. '
            '4) Summer camp listings, festival guides, and free activity roundups. '
            '5) Small business directory supporting local enterprises. '
            'Slummy Single Mummy adds "The Ultimate Guide to Rainy Day Activities" and '
            '"Low-Effort Garden Wins for Busy Parents" for time-poor families. '
            'MummyPages covers "Spring Outdoor Play: Getting Kids Moving After School" '
            'and Easter crafts. This is exactly what Huddl aims to do at scale \u2014 '
            'every borough gets its own living guide, powered by local parents sharing their finds.',
        category: KnowledgeCategory.activities,
        tags: ['hyperlocal', 'activities', 'what\'s on', 'soft play', 'family days out'],
        source: 'berkshiremummies',
        sourceUrl: 'https://berkshiremummies.co.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.80,
        lastUpdated: now,
      ),

      // ─── FOOD & NUTRITION UPDATE (Today's Parent) ──────────────────────
      KnowledgeArticle(
        id: 'feed_003',
        title: 'Ultra-processed baby food \u2014 what parents need to know',
        summary:
            'Today\'s Parent reports 71% of baby foods are ultra-processed and high in sugar. '
            'Home-made purees and whole foods are healthier alternatives.',
        body:
            'A concerning statistic from Today\'s Parent: 71% of commercially available '
            'baby foods are ultra-processed and high in sugar. What this means: '
            '1) Read labels carefully \u2014 watch for added sugars, maltodextrin, and fruit juice concentrate. '
            '2) Home-made purees using fresh vegetables are easy and much healthier. '
            '3) Baby-led weaning with soft finger foods avoids processed pouches entirely. '
            '4) NCT Baby Cafe groups can provide feeding support and recipe sharing. '
            '5) MummyPages recipe: "Crispy, salty & sweet honey-thyme fried halloumi" as '
            'a weekend family staple. '
            'Key principle: start with vegetables before fruits to develop savoury taste preferences. '
            'NHS recommends avoiding added salt and sugar for babies under 12 months. '
            'On Huddl, join your borough\'s Weaning Warriors group for local recipe ideas.',
        category: KnowledgeCategory.feeding,
        tags: ['ultra-processed', 'baby food', 'weaning', 'nutrition', 'homemade'],
        source: 'todaysparent',
        sourceUrl: 'https://www.todaysparent.com/',
        ageStages: ['baby', 'toddler'],
        relevanceWeight: 0.84,
        lastUpdated: now,
      ),

      // ─── HOME EDUCATION (DaddiLife) ────────────────────────────────────
      KnowledgeArticle(
        id: 'edu_002',
        title: 'Home education \u2014 resources and considerations',
        summary:
            'DaddiLife explores why families choose home education and the best resources '
            'available for homeschooling in the UK.',
        body:
            'DaddiLife covers home education from the parent\'s perspective: '
            '1) "Why we home educate our children" \u2014 personal accounts of the decision. '
            '2) "Help with homeschooling: the best resources available now" \u2014 curated list '
            'of UK educational platforms, workbooks, and online courses. '
            'BBC Bitesize Parents provides structured learning support aligned with the '
            'national curriculum for all ages. '
            'Key considerations: Home education is legal in the UK. You do not need permission '
            'from the local authority. However, you take full responsibility for ensuring your '
            'child receives a suitable education. Contact your local authority for guidance. '
            'Many home-educating families form local co-ops for socialisation and shared teaching. '
            'On Huddl, find other home-educating parents in your borough through groups and meetups.',
        category: KnowledgeCategory.education,
        tags: ['homeschool', 'home education', 'learning resources', 'curriculum'],
        source: 'daddilife',
        sourceUrl: 'https://www.daddilife.com/',
        ageStages: ['preschool', 'schoolAge', 'teens'],
        relevanceWeight: 0.72,
        lastUpdated: now,
      ),

      // ─── NCT FIRST 1,000 DAYS (nct.org.uk) ─────────────────────────────
      KnowledgeArticle(
        id: 'nct_002',
        title: 'NCT First 1,000 Days \u2014 critical early development',
        summary:
            'The first 1,000 days (conception to age 2) are the most critical window for brain '
            'development, attachment, and lifelong health outcomes.',
        body:
            'NCT\u2019s First 1,000 Days programme (nct.org.uk/first-1000-days) highlights: '
            '1) 80% of brain development occurs in the first 1,000 days of life. '
            '2) Secure attachment in this period predicts emotional resilience for life. '
            '3) Nutrition: breast milk or formula \u2192 weaning at 6 months \u2192 family food by 12 months. '
            '4) Language: babies exposed to rich talk and reading develop 30% larger vocabularies by age 3. '
            '5) NCT offers antenatal courses, postnatal groups, Baby Caf\u00E9, and Walk & Talk \u2014 '
            'all designed to support parents during this critical period. '
            '6) NHS Start for Life reinforces: skin-to-skin, responsive feeding, and tummy time '
            'are the foundation blocks. '
            'On Huddl, your borough\u2019s Bumps & Babies and Walk & Talk groups provide peer support '
            'throughout the first 1,000 days.',
        category: KnowledgeCategory.development,
        tags: ['first 1000 days', 'brain development', 'attachment', 'NCT', 'early years'],
        source: 'nct',
        sourceUrl: 'https://www.nct.org.uk/first-1000-days',
        ageStages: ['pregnancy', 'newborn', 'baby'],
        relevanceWeight: 0.95,
        lastUpdated: now,
      ),

      // ─── HOME FOR GOOD \u2014 FOSTERING & ADOPTION (homeforgood.org.uk) ──────
      KnowledgeArticle(
        id: 'af_002',
        title: 'Home for Good \u2014 every child deserves a loving home',
        summary:
            'Home for Good coordinates a national movement ensuring every child who needs '
            'a family finds one. Works with churches, individuals, and local authorities.',
        body:
            'Home for Good (homeforgood.org.uk) is a UK charity dedicated to finding loving '
            'homes for children in the care system: '
            '1) National network of foster carers, adopters, and supported lodgings hosts. '
            '2) Advocacy for children in care \u2014 every 15 minutes a child enters care in the UK. '
            '3) Church mobilisation \u2014 helps congregations become fostering-friendly communities. '
            '4) Resources for prospective foster carers and adopters at every stage of the journey. '
            '5) Regional events and information sessions across England, Scotland, Wales, and NI. '
            '6) Partnership with First4Adoption (first4adoption.org.uk) for initial guidance. '
            'Key: Many children in care have experienced trauma. Therapeutic parenting training '
            'from Adoption UK and CoramBAAF helps families understand and respond to challenging behaviour. '
            'On Huddl, our Adoptive & Foster Families groups in your borough connect you '
            'with families who understand the unique rewards and challenges.',
        category: KnowledgeCategory.adoptionFostering,
        tags: ['fostering', 'adoption', 'Home for Good', 'care system', 'church', 'kinship'],
        source: 'homeforgood',
        sourceUrl: 'https://www.homeforgood.org.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.83,
        lastUpdated: now,
      ),

      // ─── DAD.INFO \u2014 DEDICATED FATHERHOOD RESOURCE ─────────────────────
      KnowledgeArticle(
        id: 'dad_004',
        title: 'Dad.info \u2014 practical support for fathers',
        summary:
            'Dad.info provides practical guidance, emotional support, and a community for fathers '
            'navigating all stages of parenting.',
        body:
            'Dad.info (dad.info) is a dedicated UK fatherhood resource: '
            '1) Mental health support \u2014 1 in 10 new fathers experience postnatal depression; '
            'Dad.info provides guidance on recognising symptoms and seeking help. '
            '2) Practical fatherhood \u2014 step-by-step guides on nappy changing, bottle feeding, '
            'bath time, and night routines from a dad\u2019s perspective. '
            '3) Relationships \u2014 maintaining a strong partnership after baby arrives, co-parenting '
            'after separation, and managing blended family dynamics. '
            '4) Legal rights \u2014 paternity leave (1\u20132 weeks at \u00A3184.03/week), shared parental leave, '
            'and flexible working requests. '
            '5) Community \u2014 forums where dads share experiences without judgement. '
            'Care for the Family\u2019s "The Dad Cave" podcast complements with real-dad stories. '
            'On Huddl, borough-specific Dad & Kids Saturday Club and Dad Brunch Club meetups '
            'connect fathers locally.',
        category: KnowledgeCategory.dadSpecific,
        tags: ['dad.info', 'fatherhood', 'mental health', 'paternity', 'dad support'],
        source: 'dadinfo',
        sourceUrl: 'https://www.dad.info/',
        ageStages: ['all', 'dad'],
        relevanceWeight: 0.84,
        lastUpdated: now,
      ),

      // ─── BBC BITESIZE PARENTS \u2014 EDUCATION & TEEN SUPPORT ────────────────
      KnowledgeArticle(
        id: 'edu_003',
        title: 'BBC Bitesize Parents \u2014 supporting learning at every stage',
        summary:
            'BBC Bitesize Parents provides curriculum-aligned resources, teen parenting guides, '
            'and online safety advice trusted by millions of UK families.',
        body:
            'BBC Bitesize Parents (bbc.co.uk/bitesize/parents) offers: '
            '1) Curriculum-aligned learning \u2014 maths, English, science activities for KS1\u2013KS4. '
            '2) "Parenting Teens" podcast \u2014 expert guidance on education, digital life, and wellbeing. '
            '3) Online safety advice \u2014 age-appropriate conversations about social media, gaming, '
            'and screen time. Complemented by Parent Zone\u2019s digital safety resources. '
            '4) Exam support \u2014 revision guides, mental health during exams, and managing expectations. '
            '5) SEN/SEND support \u2014 resources for parents of children with additional needs, '
            'supporting learning differences at home. '
            '6) Film and video content making complex topics accessible for parents. '
            'Key fact: children who receive parental support with homework show measurably '
            'better academic outcomes (Parentkind National Parent Survey 2025, 5,866 parents).',
        category: KnowledgeCategory.education,
        tags: ['BBC Bitesize', 'education', 'curriculum', 'teens', 'online safety', 'exams'],
        source: 'bbcbitesize',
        sourceUrl: 'https://www.bbc.co.uk/bitesize/parents',
        ageStages: ['schoolAge', 'teens'],
        relevanceWeight: 0.88,
        lastUpdated: now,
      ),

      // ─── BARNARDO\u2019S \u2014 CHILD SAFETY & WELLBEING ─────────────────────────
      KnowledgeArticle(
        id: 'safe_003',
        title: 'Barnardo\u2019s \u2014 protecting children, supporting families',
        summary:
            'Barnardo\u2019s is the UK\u2019s largest children\u2019s charity, providing child safety advice, '
            'emotional wellbeing resources, and local family services.',
        body:
            'Barnardo\u2019s (barnardos.org.uk) supports children and families across the UK: '
            '1) Child safety \u2014 accident prevention guides for every room in the home. '
            '2) Emotional wellbeing \u2014 helping children manage anxiety, anger, and transitions. '
            '3) Anti-bullying \u2014 resources for parents dealing with bullying and cyberbullying. '
            '4) Young carers \u2014 support for children caring for family members. '
            '5) Child sexual exploitation (CSE) awareness \u2014 signs to look for and how to report. '
            '6) Local services \u2014 children\u2019s centres, family hubs, and youth programmes in many boroughs. '
            'Key stat: Barnardo\u2019s reaches over 300,000 children, young people, and families annually. '
            'On Huddl, safety tips from Barnardo\u2019s inform our AI safety guardrails and product '
            'recall checking in the marketplace.',
        category: KnowledgeCategory.safety,
        tags: ['barnardos', 'child safety', 'wellbeing', 'bullying', 'young carers'],
        source: 'barnardos',
        sourceUrl: 'https://www.barnardos.org.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.88,
        lastUpdated: now,
      ),

      // ─── CARE FOR THE FAMILY \u2014 FAMILY SUPPORT ─────────────────────────
      KnowledgeArticle(
        id: 'pw_002',
        title: 'Care for the Family \u2014 strengthening family life',
        summary:
            'Since 2021 Care for the Family has helped 3,881 families with UK-wide events, '
            'podcasts (The Dad Cave, Parentalk), and bereavement support.',
        body:
            'Care for the Family (careforthefamily.org.uk) is a UK charity focused on '
            'strengthening family life: '
            '1) Tour events: "Tweens and Teens" live events, "The Mum Show", and couple support evenings. '
            '2) Podcasts: The Dad Cave (for fathers), Parentalk (general), Family Life, Raising Teens. '
            '3) Bereavement support \u2014 for families who have lost a child or partner. '
            '4) Single parent support \u2014 alongside Gingerbread, provides networks and events. '
            '5) Couple support \u2014 date night ideas, communication tools, and relationship courses. '
            '6) "Left to Their Own Devices?" \u2014 events on managing children\u2019s screen time. '
            'Since 2021: 3,881 families supported, \u00A355,608 spent on UK-wide family support. '
            'On Huddl, Care for the Family tour events appear in our UK-wide events calendar.',
        category: KnowledgeCategory.parentalWellbeing,
        tags: ['Care for the Family', 'bereavement', 'couple support', 'tour events', 'podcasts'],
        source: 'careforthefamily',
        sourceUrl: 'https://www.careforthefamily.org.uk/',
        ageStages: ['all'],
        relevanceWeight: 0.82,
        lastUpdated: now,
      ),

      // ─── SLUMMY SINGLE MUMMY \u2014 SINGLE PARENT VOICE ───────────────────
      KnowledgeArticle(
        id: 'sp_002',
        title: 'Slummy Single Mummy \u2014 real talk for single parents',
        summary:
            'Jo Middleton\u2019s Slummy Single Mummy blog offers financial tips, rainy day activities, '
            'and honest perspectives on solo parenting.',
        body:
            'Slummy Single Mummy (slummysinglemummy.com) provides: '
            '1) Finance \u2014 "How to cope with Christmas on a budget" and money-saving hacks '
            'for single-income households. '
            '2) Activities \u2014 "The Ultimate Guide to Rainy Day Activities" and '
            '"Low-Effort Garden Wins for Busy Parents" for time-poor families. '
            '3) Wellbeing \u2014 "The Audacity of Being Awake at 3am" on perimenopause and '
            'parenting exhaustion. '
            '4) Real talk \u2014 honest, witty perspectives on dating as a single parent, '
            'co-parenting challenges, and self-care without guilt. '
            'Gingerbread (gingerbread.org.uk) complements with policy advocacy, reaching '
            '\u007E800,000 single parents annually with advice, volunteer support groups, and campaigns. '
            'On Huddl, Single Parents Connect groups in your borough offer local solidarity.',
        category: KnowledgeCategory.singleParent,
        tags: ['single parent', 'Slummy Single Mummy', 'budget', 'activities', 'real talk'],
        source: 'slummysinglemummy',
        sourceUrl: 'https://www.slummysinglemummy.com/',
        ageStages: ['all'],
        relevanceWeight: 0.78,
        lastUpdated: now,
      ),

      // ─── MAMAS & PAPAS \u2014 PRODUCT GUIDANCE ─────────────────────────────
      KnowledgeArticle(
        id: 'market_002',
        title: 'Mamas & Papas \u2014 Buying for Baby guidance',
        summary:
            'Free "Buying for Baby" appointments with up to 40% savings. Expert car seat fittings '
            'and new parent support from the UK\u2019s leading baby retailer.',
        body:
            'Mamas & Papas (mamasandpapas.com) offers: '
            '1) Free "Buying for Baby" appointment \u2014 personal shopping with up to 40% off. '
            '2) Car seat appointments \u2014 expert fitting to ensure safety compliance. '
            '3) Nursery planning \u2014 room layouts, essential lists, and budget guidance. '
            '4) New parent support \u2014 step-by-step guides from pregnancy through first year. '
            '5) Mamas & Papas app (iOS/Android) with product reviews and wishlists. '
            '6) Trade-in scheme \u2014 bring in old pushchairs for money off new ones. '
            'Key marketplace advice: always check product recalls before buying second-hand. '
            'On Huddl, our AI marketplace checks every listed item against known safety recalls '
            'and suggests fair pricing based on your borough\u2019s local market.',
        category: KnowledgeCategory.marketplace,
        tags: ['Mamas & Papas', 'baby products', 'car seats', 'nursery', 'shopping'],
        source: 'mamasandpapas',
        sourceUrl: 'https://www.mamasandpapas.com/',
        ageStages: ['pregnancy', 'newborn', 'baby'],
        relevanceWeight: 0.80,
        lastUpdated: now,
      ),

      // ─── MYBABA — FAMILY LIFESTYLE & WELLBEING ────────────────────────
      KnowledgeArticle(
        id: 'lifestyle_001',
        title: 'MyBaba \u2014 family lifestyle, travel, and wellbeing',
        summary:
            'MyBaba is a curated UK family lifestyle platform covering luxury travel, '
            'nursery design, pregnancy wellbeing, and quality children\u2019s products.',
        body:
            'MyBaba (mybaba.com) is a trusted UK family lifestyle resource: '
            '1) Family travel guides \u2014 curated villa holidays, beach clubs with cr\u00E8che, '
            'family-friendly destinations with childcare and babysitting options. '
            '2) Nursery design \u2014 expert-led nursery inspiration, interior trends, and '
            'storage solutions for compact UK homes. '
            '3) Pregnancy wellbeing \u2014 antenatal fitness, nutrition guides, birth plans, '
            'and postnatal recovery tips. '
            '4) Product reviews \u2014 in-depth reviews of pushchairs, car seats, baby monitors '
            'and other essentials, with comparisons to help parents choose wisely. '
            '5) Children\u2019s activities \u2014 age-appropriate crafts, learning activities, '
            'and seasonal event guides across the UK. '
            'On Huddl, share travel tips and product reviews with other parents in your borough.',
        category: KnowledgeCategory.activities,
        tags: ['MyBaba', 'lifestyle', 'family travel', 'nursery', 'wellbeing', 'product reviews'],
        source: 'mybaba',
        sourceUrl: 'https://www.mybaba.com/',
        ageStages: ['pregnancy', 'newborn', 'baby', 'toddler'],
        relevanceWeight: 0.72,
        lastUpdated: now,
      ),

      // ─── SELMIND — LOCAL MENTAL HEALTH DIRECTORY ──────────────────────
      KnowledgeArticle(
        id: 'mh_001',
        title: 'Finding local family mental health support via Selmind',
        summary:
            'Selmind is a UK directory connecting families to local mental health services, '
            'including the Family Lives Parents Helpline.',
        body:
            'Selmind (selmind.org.uk) is a UK-wide directory of mental health resources: '
            '1) Family Lives Parents Helpline \u2014 free, confidential phone and email '
            'support for any parenting issue, listed prominently in the Selmind directory. '
            '2) Local service finder \u2014 search by postcode to find counselling, '
            'therapy, and support groups near you. '
            '3) Covers anxiety, depression, postnatal mental health, relationship issues, '
            'bereavement, and children\u2019s emotional wellbeing. '
            '4) Referral pathway: start with GP or self-refer via Selmind directory entries. '
            'Key: Coram Family Lives offers a free 24/7 helpline (phone, email, WhatsApp, '
            'live chat) and free online parenting courses for immediate support. '
            'On Huddl, your borough\u2019s AI copilot can help find local services near you.',
        category: KnowledgeCategory.mentalHealth,
        tags: ['Selmind', 'mental health', 'helpline', 'local services', 'counselling', 'Family Lives'],
        source: 'selmind',
        sourceUrl: 'https://selmind.org.uk/directory/family-lives-parents-helpline/',
        ageStages: ['all'],
        relevanceWeight: 0.82,
        lastUpdated: now,
      ),

      // ─── NATIONAL PARENT SURVEY — UK'S LARGEST PARENT POLL ────────────
      KnowledgeArticle(
        id: 'edu_004',
        title: 'National Parent Survey 2025 \u2014 what 5,866 parents really think',
        summary:
            'The National Parent Survey is the UK\u2019s largest annual parent poll, run by '
            'Parentkind with YouGov, generating 134,000+ insights into family life.',
        body:
            'The National Parent Survey 2025 (nationalparentsurvey.com) key findings: '
            '1) 5,866 parents surveyed across England (3,391), Scotland (1,309), '
            'Wales (865), and Northern Ireland (301), commissioned by Parentkind with YouGov. '
            '2) 134,000+ data points covering school happiness, homework, digital '
            'device usage, financial pressures, and parental mental health. '
            '3) Supported by The Times and The Sunday Times \u2014 bringing parent voices '
            'into the national conversation on education policy. '
            '4) Free webinars for parents \u2014 Parentkind provides expert-led sessions '
            'on PTA fundraising, Be School Ready guides, and parent engagement. '
            '5) Margin of error: 0.5\u20132.5 percentage points for the sample. '
            'Key insight: parental engagement in education directly correlates with '
            'better child outcomes. Parentkind\u2019s PTA network of 13,500+ PTAs '
            'connects schools with families across the UK. '
            'On Huddl, share your school experience with other parents in your borough.',
        category: KnowledgeCategory.education,
        tags: ['National Parent Survey', 'Parentkind', 'YouGov', 'education', 'school', 'PTA'],
        source: 'parentkind',
        sourceUrl: 'https://nationalparentsurvey.com/',
        ageStages: ['schoolAge', 'teens'],
        relevanceWeight: 0.86,
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

      // ═══════════════════════════════════════════════════════════════════════
      // ENRICHED V3: New community templates from 37 additional sources
      // ═══════════════════════════════════════════════════════════════════════

      // ── SINGLE PARENT groups (Gingerbread) ──
      CommunityTemplate(
        name: 'Single Parents Connect',
        description:
            'A welcoming space for single parents in {borough}. Share tips on financial planning, '
            'co-parenting, and building confidence. Inspired by Gingerbread\'s 800K-strong community.',
        category: 'single_parent',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'weekly',
        source: 'gingerbread',
        scope: ContentScope.boroughOnly,
      ),

      // ── DIGITAL SAFETY group (Parent Zone) ──
      CommunityTemplate(
        name: 'Digital Families Circle',
        description:
            'Navigating screen time, online safety, and digital resilience for families in {borough}. '
            'Share tips on parental controls, age-appropriate apps, and digital agreements.',
        category: 'digital_safety',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'monthly',
        source: 'parentzone',
        scope: ContentScope.boroughOnly,
      ),

      // ── SEN / ADDITIONAL NEEDS groups (Contact, Sibs) ──
      CommunityTemplate(
        name: 'SEN Siblings Support',
        description:
            'For brothers and sisters of children with disabilities or additional needs in {borough}. '
            'A safe space inspired by Sibs \u2014 because siblings need support too.',
        category: 'sen_support',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'fortnightly',
        source: 'sibs',
        scope: ContentScope.boroughOnly,
      ),

      // ── ADOPTION & FOSTERING group (Adoption UK) ──
      CommunityTemplate(
        name: 'Adoptive & Foster Families',
        description:
            'A supportive group for adoptive and foster families in {borough}. Share experiences, '
            'celebrate milestones, and find understanding. Inspired by Adoption UK\'s community.',
        category: 'adoption_fostering',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'monthly',
        source: 'adoptionuk',
        scope: ContentScope.boroughOnly,
      ),

      // ── STEPFAMILY group (HappySteps) ──
      CommunityTemplate(
        name: 'Blended Families Hub',
        description:
            'For stepparents and blended families in {borough}. Navigate the joys and challenges '
            'of stepparenting together. Inspired by Dr Lisa Doodson\'s HappySteps approach.',
        category: 'stepfamily',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'monthly',
        source: 'happysteps',
        scope: ContentScope.boroughOnly,
      ),

      // ── SEPARATION SUPPORT group (OnlyMums & Dads) ──
      CommunityTemplate(
        name: 'Co-Parenting Support',
        description:
            'For separated parents in {borough} navigating co-parenting. Practical tips, '
            'emotional support, and shared experiences. Inspired by OnlyMums & Dads.',
        category: 'separation_support',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'fortnightly',
        source: 'onlymumsanddads',
        scope: ContentScope.boroughOnly,
      ),

      // ── ECO-PARENTING group (Green Parent) ──
      CommunityTemplate(
        name: 'Green Parents Circle',
        description:
            'Eco-conscious families in {borough} sharing sustainable tips: cloth nappies, '
            'preloved shopping, nature walks, and growing veg with kids. Inspired by The Green Parent.',
        category: 'eco_parenting',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'fortnightly',
        source: 'greenparent',
        scope: ContentScope.boroughOnly,
      ),

      // ── SCHOOL PTA group (Parentkind) ──
      CommunityTemplate(
        name: 'School Parents Network',
        description:
            'For school parents in {borough} to share PTA ideas, fundraising tips, '
            'homework support strategies, and school readiness advice. Inspired by Parentkind.',
        category: 'school_network',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'fortnightly',
        source: 'parentkind',
        scope: ContentScope.boroughOnly,
      ),

      // ── TEEN PARENTS group (HuffPost, BBC Bitesize) ──
      CommunityTemplate(
        name: 'Raising Teens Together',
        description:
            'For parents of teenagers in {borough}. Navigate school, social media, independence, '
            'and emotional wellbeing. No topic is off-limits.',
        category: 'teen_parents',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'fortnightly',
        source: 'huffpost',
        scope: ContentScope.boroughOnly,
      ),

      // ── EMOTIONAL INTELLIGENCE group (Parent Talk Podcast) ──
      CommunityTemplate(
        name: 'Emotions & Resilience Workshop',
        description:
            'For {borough} parents interested in building emotional intelligence in their children. '
            'Discuss emotion regulation, resilience, and positive discipline. Inspired by Parent Talk Podcast.',
        category: 'emotional_intelligence',
        audience: 'all',
        format: 'hybrid',
        suggestedFrequency: 'monthly',
        source: 'parenttalk',
        scope: ContentScope.boroughOnly,
      ),

      // ── UK-WIDE: Charity events and workshops ──
      CommunityTemplate(
        name: 'UK Charity Family Events',
        description:
            'Browse UK-wide charity events: NCT Nearly New Sales, Barnardo\'s workshops, '
            'Adoption UK family walks, CoramBAAF conferences, and Family Fund face-to-face support.',
        category: 'events',
        audience: 'all',
        format: 'in_person',
        suggestedFrequency: 'weekly',
        source: 'nct',
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
      case 'daddilife':
        return 'DaddiLife';
      case 'dadinfo':
        return 'Dad.info';
      case 'parenttalk':
        return 'Parent Talk Podcast';
      case 'bbcbitesize':
        return 'BBC Bitesize Parents';
      case 'parentkind':
        return 'Parentkind';
      case 'greenparent':
        return 'The Green Parent';
      case 'huffpost':
        return 'HuffPost Parents';
      case 'slummysinglemummy':
        return 'Slummy Single Mummy';
      case 'mummypages':
        return 'MummyPages';
      case 'berkshiremummies':
        return 'Berkshire Mummies';
      case 'coramfamilylives':
        return 'Coram Family Lives';
      case 'parentzone':
        return 'Parent Zone';
      case 'careforthefamily':
        return 'Care for the Family';
      case 'barnardos':
        return 'Barnardo\'s';
      case 'gingerbread':
        return 'Gingerbread';
      case 'onlymumsanddads':
        return 'OnlyMums & Dads';
      case 'contact':
        return 'Contact (Disabled Children)';
      case 'familyfund':
        return 'Family Fund';
      case 'sibs':
        return 'Sibs';
      case 'homeforgood':
        return 'Home for Good';
      case 'adoptionuk':
        return 'Adoption UK';
      case 'corambaaf':
        return 'CoramBAAF';
      case 'happysteps':
        return 'HappySteps';
      case 'mamasandpapas':
        return 'Mamas & Papas';
      case 'todaysparent':
        return 'Today\'s Parent';
      case 'mybaba':
        return 'MyBaba';
      case 'selmind':
        return 'Selmind';
      case 'familylives':
        return 'Family Lives';
      case 'nationalparentsurvey':
        return 'National Parent Survey 2025';
      case 'spurgeons':
        return 'Spurgeons';
      default:
        return source;
    }
  }

  /// Public accessor for source display name (used by nudge generators).
  String getSourceDisplayName(String source) => _sourceDisplayName(source);

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('\u{1F9E0} KnowledgeBase: $message');
    }
  }
}
