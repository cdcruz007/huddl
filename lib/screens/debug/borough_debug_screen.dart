import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/huddl_colors.dart';
import '../../services/borough_scope_guard.dart';
import '../../services/borough_cache_service.dart';
import '../../services/borough_analytics_service.dart';
import '../../constants/app_text_styles.dart';

// =============================================================================
// BOROUGH DEBUG PANEL  — STEP 12
//
// Developer-only screen accessible from Profile → Settings → Borough Debug.
// Shows:
//   1. Current borough context (guard state)
//   2. Cache status (BoroughCacheService)
//   3. Analytics counters & recent events (BoroughAnalyticsService)
//   4. Feature scope map
//   5. Guard debug summary
// =============================================================================

class BoroughDebugScreen extends StatefulWidget {
  const BoroughDebugScreen({super.key});

  @override
  State<BoroughDebugScreen> createState() => _BoroughDebugScreenState();
}

class _BoroughDebugScreenState extends State<BoroughDebugScreen> {
  final BoroughScopeGuard _guard = BoroughScopeGuard();
  final BoroughCacheService _cache = BoroughCacheService();
  final BoroughAnalyticsService _analytics = BoroughAnalyticsService();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _cache.initialize();
    await _analytics.initialize();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Production guard — this screen must never render in a release build.
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Not available in release builds')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? HuddlColors.darkBackground : HuddlColors.neutral50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Borough Debug',
          style: HuddlText.body(weight: FontWeight.w600),
        ),
        iconTheme: IconThemeData(
          color: isDark ? HuddlColors.white : HuddlColors.textDark,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear analytics',
            onPressed: () async {
              await _analytics.clearAll();
              await _analytics.initialize();
              if (mounted) setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Analytics cleared')),
                );
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Guard State', _guardInfo()),
                  const SizedBox(height: 16),
                  _buildSection('Cache Status', _cacheInfo()),
                  const SizedBox(height: 16),
                  _buildSection('Feature Scope Map', _featureScopeInfo()),
                  const SizedBox(height: 16),
                  _buildSection('Analytics Counters', _analyticsCounters()),
                  const SizedBox(height: 16),
                  _buildSection('Recent Events', _recentEvents()),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? HuddlColors.darkSurface : HuddlColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: HuddlText.body(weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? valueColor}) {

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: HuddlText.caption(),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: HuddlText.caption(color: HuddlColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _guardInfo() => [
        _buildRow('Current borough', _guard.currentBorough ?? 'Not set'),
        _buildRow(
            'Borough set', _guard.currentBorough != null ? 'Yes' : 'No',
            valueColor: _guard.currentBorough != null
                ? HuddlColors.nearBlack
                : HuddlColors.accentCoral),
      ];

  List<Widget> _cacheInfo() => [
        _buildRow('Cached borough', _cache.cachedBorough ?? 'None'),
        _buildRow('Cached postcode', _cache.cachedPostcode ?? 'None'),
        _buildRow('Previous borough', _cache.previousBorough ?? 'None'),
        _buildRow('Member count', _cache.memberCount.toString()),
        _buildRow(
            'Resolved at',
            _cache.resolvedAt?.toIso8601String().substring(0, 19) ??
                'Never'),
        _buildRow(
            'Has directory', _cache.directory != null ? 'Yes' : 'No'),
      ];

  List<Widget> _featureScopeInfo() {
    return HuddlFeature.values.map((f) {
      final scope = BoroughScopeGuard.scopeOf(f);
      final scopeLabel = scope == FeatureScope.boroughOnly
          ? 'Borough-only'
          : scope == FeatureScope.ukWide
              ? 'UK-wide'
              : 'Borough-aware';
      final color = scope == FeatureScope.boroughOnly
          ? HuddlColors.nearBlack
          : scope == FeatureScope.ukWide
              ? HuddlColors.nearBlack
              : HuddlColors.primary;
      return _buildRow(f.name, scopeLabel, valueColor: color);
    }).toList();
  }

  List<Widget> _analyticsCounters() {
    final counters = _analytics.counters;
    if (counters.isEmpty) {
      return [
        _buildRow('No counters', 'No analytics data yet'),
      ];
    }
    final keys = counters.keys.toList()..sort();
    return keys.map((k) => _buildRow(k, counters[k].toString())).toList();
  }

  List<Widget> _recentEvents() {
    final events = _analytics.events;
    if (events.isEmpty) {
      return [
        _buildRow('No events', 'No analytics events recorded'),
      ];
    }
    final recent =
        events.length > 10 ? events.sublist(events.length - 10) : events;
    return recent.reversed.map((e) {
      final ts = e.timestamp.toIso8601String().substring(11, 19);
      return _buildRow(
        '[$ts] ${e.type}',
        '${e.feature ?? "—"} (${e.userBorough ?? "?"} → ${e.targetBorough ?? "?"})',
      );
    }).toList();
  }
}
