import 'dart:async';
import 'package:flutter/foundation.dart';
import 'browser_storage.dart';
import 'ai_knowledge_base_service.dart';
import 'ai_learning_engine_service.dart';
import 'ai_feed_service.dart';
import 'ai_event_recommender_service.dart';
import 'group_prepopulation_service.dart';
import 'meetup_prepopulation_service.dart';

// =============================================================================
// DAILY AI REFRESH CYCLE  — ENRICHED V3 (Step 13)
//
// Orchestrates periodic refresh of all AI-powered services:
//   1. Knowledge Base refresh (articles from 25+ sources, milestones, vaccinations, seasonal tips)
//   2. Learning Engine profile recalculation and signal decay
//   3. Feed nudge regeneration with fresh knowledge (including V3 enriched nudges)
//   4. Event recommendation score recomputation (UK-wide charity events)
//   5. Group prepopulation refresh for new templates (11 new community templates)
//   6. Meetup prepopulation refresh with updated venues
//
// V3 enrichment sources cycled daily:
//   Tier 1: NHS, NCT, BBC Bitesize
//   Tier 2: Coram Family Lives, Gingerbread, Contact, Parent Zone, Barnardo's,
//           Parentkind, Care for the Family, Adoption UK, Family Fund, Sibs
//   Tier 3: Netmums, Dadsnet, DaddiLife, Parent Talk Podcast, Green Parent,
//           Slummy Single Mummy, Berkshire Mummies, MummyPages, HuffPost, Bounty
//
// Runs automatically:
//   - On app launch (if > 24h since last refresh)
//   - Can be triggered manually via forceRefresh()
//   - Tracks last refresh time in BrowserStorage
// =============================================================================

/// Status of the daily refresh cycle.
enum RefreshStatus {
  idle,
  inProgress,
  completed,
  failed,
}

/// A single step in the refresh cycle with status tracking.
class RefreshStep {
  final String name;
  final String description;
  RefreshStatus status;
  String? error;
  DateTime? completedAt;

  RefreshStep({
    required this.name,
    required this.description,
    this.status = RefreshStatus.idle,
    this.error,
    this.completedAt,
  });
}

class DailyAiRefreshService {
  static final DailyAiRefreshService _instance =
      DailyAiRefreshService._internal();
  factory DailyAiRefreshService() => _instance;
  DailyAiRefreshService._internal();

  static const String _lastRefreshKey = 'daily_ai_refresh_last';
  static const Duration _refreshInterval = Duration(hours: 24);

  final AiKnowledgeBaseService _knowledgeBase = AiKnowledgeBaseService();
  final AiLearningEngineService _learningEngine = AiLearningEngineService();
  final AiFeedService _feedService = AiFeedService();
  final AiEventRecommenderService _eventRecommender =
      AiEventRecommenderService();
  final GroupPrepopulationService _groupPrepop = GroupPrepopulationService();
  final MeetupPrepopulationService _meetupPrepop =
      MeetupPrepopulationService();

  RefreshStatus _overallStatus = RefreshStatus.idle;
  DateTime? _lastRefreshTime;
  final List<RefreshStep> _steps = [];

  RefreshStatus get overallStatus => _overallStatus;
  DateTime? get lastRefreshTime => _lastRefreshTime;
  List<RefreshStep> get steps => List.unmodifiable(_steps);

  /// Whether a daily refresh is due (> 24h since last).
  bool get needsRefresh {
    if (_lastRefreshTime == null) return true;
    return DateTime.now().difference(_lastRefreshTime!) > _refreshInterval;
  }

  /// Time until next refresh.
  Duration get timeUntilNextRefresh {
    if (_lastRefreshTime == null) return Duration.zero;
    final next = _lastRefreshTime!.add(_refreshInterval);
    final diff = next.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Initialize and check if refresh is needed.
  Future<void> initialize() async {
    await _loadLastRefreshTime();
  }

  /// Run the full daily refresh cycle.
  /// Only runs if > 24h since last, unless [force] is true.
  Future<bool> runRefreshCycle({bool force = false}) async {
    if (!force && !needsRefresh) {
      _log('Refresh not needed (last: $_lastRefreshTime)');
      return false;
    }

    if (_overallStatus == RefreshStatus.inProgress) {
      _log('Refresh already in progress');
      return false;
    }

    _overallStatus = RefreshStatus.inProgress;
    _buildSteps();
    _log('Starting daily AI refresh cycle...');

    int successCount = 0;

    // Step 1: Refresh Knowledge Base
    await _runStep(0, () async {
      await _knowledgeBase.initialize();
      await _knowledgeBase.refresh();
    });
    if (_steps[0].status == RefreshStatus.completed) successCount++;

    // Step 2: Recalculate Learning Engine
    await _runStep(1, () async {
      await _learningEngine.initialize();
      // The learning engine persists and decays signals automatically
    });
    if (_steps[1].status == RefreshStatus.completed) successCount++;

    // Step 3: Regenerate Feed Nudges
    await _runStep(2, () async {
      await _feedService.initialize();
      await _feedService.refresh();
    });
    if (_steps[2].status == RefreshStatus.completed) successCount++;

    // Step 4: Recompute Event Recommendations
    await _runStep(3, () async {
      await _eventRecommender.initialize();
    });
    if (_steps[3].status == RefreshStatus.completed) successCount++;

    // Step 5: Refresh Group Prepopulation
    await _runStep(4, () async {
      await _groupPrepop.initialize();
      await _groupPrepop.generateGroupsForBorough();
    });
    if (_steps[4].status == RefreshStatus.completed) successCount++;

    // Step 6: Refresh Meetup Prepopulation
    await _runStep(5, () async {
      await _meetupPrepop.initialize();
      await _meetupPrepop.generateMeetupsForBorough();
    });
    if (_steps[5].status == RefreshStatus.completed) successCount++;

    // Record completion
    _lastRefreshTime = DateTime.now();
    await _saveLastRefreshTime();

    if (successCount == _steps.length) {
      _overallStatus = RefreshStatus.completed;
      _log('Daily refresh completed successfully ($successCount/${_steps.length} steps)');
    } else {
      _overallStatus = RefreshStatus.completed; // Partial success is still completion
      _log('Daily refresh completed with $successCount/${_steps.length} successful steps');
    }

    return true;
  }

  /// Force an immediate refresh regardless of timing.
  Future<bool> forceRefresh() => runRefreshCycle(force: true);

  // ── Internal ──────────────────────────────────────────────────────────

  void _buildSteps() {
    _steps.clear();
    _steps.addAll([
      RefreshStep(
        name: 'Knowledge Base',
        description: 'Refreshing parenting articles, milestones, vaccinations, seasonal tips',
      ),
      RefreshStep(
        name: 'Learning Engine',
        description: 'Recalculating user behaviour profile and signal decay',
      ),
      RefreshStep(
        name: 'Feed Nudges',
        description: 'Regenerating personalised nudge cards',
      ),
      RefreshStep(
        name: 'Event Recommendations',
        description: 'Recomputing event relevance scores',
      ),
      RefreshStep(
        name: 'Group Prepopulation',
        description: 'Refreshing community group templates',
      ),
      RefreshStep(
        name: 'Meetup Prepopulation',
        description: 'Refreshing borough meetup suggestions',
      ),
    ]);
  }

  Future<void> _runStep(int index, Future<void> Function() action) async {
    _steps[index].status = RefreshStatus.inProgress;
    try {
      await action();
      _steps[index].status = RefreshStatus.completed;
      _steps[index].completedAt = DateTime.now();
      _log('\u2705 ${_steps[index].name} refreshed');
    } catch (e) {
      _steps[index].status = RefreshStatus.failed;
      _steps[index].error = e.toString();
      _log('\u274C ${_steps[index].name} failed: $e');
    }
  }

  Future<void> _loadLastRefreshTime() async {
    try {
      final stored = await BrowserStorage.getString(_lastRefreshKey);
      if (stored != null) {
        _lastRefreshTime = DateTime.tryParse(stored);
      }
    } catch (e) {
      _log('Error loading last refresh time: $e');
    }
  }

  Future<void> _saveLastRefreshTime() async {
    try {
      if (_lastRefreshTime != null) {
        await BrowserStorage.setString(
            _lastRefreshKey, _lastRefreshTime!.toIso8601String());
      }
    } catch (e) {
      _log('Error saving last refresh time: $e');
    }
  }

  /// Build a debug summary of the refresh state.
  String debugSummary() {
    final buf = StringBuffer();
    buf.writeln('=== Daily AI Refresh Status ===');
    buf.writeln('Overall: ${_overallStatus.name}');
    buf.writeln('Last refresh: ${_lastRefreshTime ?? "never"}');
    buf.writeln('Needs refresh: $needsRefresh');
    buf.writeln('Time until next: ${timeUntilNextRefresh.inMinutes} minutes');
    buf.writeln('');
    buf.writeln('Steps:');
    for (final step in _steps) {
      final status = step.status == RefreshStatus.completed
          ? '\u2705'
          : step.status == RefreshStatus.failed
              ? '\u274C'
              : step.status == RefreshStatus.inProgress
                  ? '\u23F3'
                  : '\u2B1C';
      buf.writeln('  $status ${step.name}: ${step.status.name}');
      if (step.error != null) {
        buf.writeln('     Error: ${step.error}');
      }
    }
    return buf.toString();
  }

  /// Export refresh data for GDPR compliance.
  Map<String, dynamic> exportRefreshData() {
    return {
      'lastRefreshTime': _lastRefreshTime?.toIso8601String(),
      'overallStatus': _overallStatus.name,
      'stepsCompleted': _steps.where((s) => s.status == RefreshStatus.completed).length,
      'totalSteps': _steps.length,
    };
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('\u{1F504} DailyRefresh: $message');
    }
  }
}
