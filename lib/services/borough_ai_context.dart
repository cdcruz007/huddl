import 'borough_scope_guard.dart';
import 'gemini_system_prompt_builder.dart';

// =============================================================================
// BOROUGH AI CONTEXT MIXIN  — STEP 10
//
// Provides a consistent borough-aware context injection for ALL AI services.
// Any AI service can use this mixin to:
//   1. Access the user's current borough from BoroughScopeGuard
//   2. Verify the prompt builder is borough-aware
//   3. Build a borough-context preamble for any Gemini request
//   4. Classify feature scope consistently
//
// HYPERLOCAL RULE:
//   Borough-only AI services (Matchmaker, Feed, Chat Summariser, Listing,
//   Discover, Messages AI) MUST call boroughPreamble() and reject any
//   cross-borough data before sending to Gemini.
//   UK-wide AI services (Event Recommender, Event Discovery, Invisible AI)
//   MUST still include the home borough for scoring/ranking.
// =============================================================================

/// Mixin providing borough context to any AI service.
mixin BoroughAiContext {
  final BoroughScopeGuard _boroughGuard = BoroughScopeGuard();

  /// The user's current borough (resolved from postcode).
  String get aiBoroughContext =>
      _boroughGuard.currentBoroughOr('Unknown Borough');

  /// True if the user has a valid borough set.
  bool get hasBoroughContext =>
      _boroughGuard.currentBorough != null &&
      _boroughGuard.currentBorough!.isNotEmpty;

  /// Returns a brief preamble string to prepend to any AI prompt
  /// so that Gemini is always aware of the user's home borough.
  String boroughPreamble({
    HuddlFeature? feature,
    String? targetBorough,
  }) {
    final home = aiBoroughContext;
    final scope = feature != null
        ? BoroughScopeGuard.scopeOf(feature)
        : FeatureScope.boroughOnly;

    final buffer = StringBuffer();
    buffer.writeln('[Borough Context]');
    buffer.writeln('Home borough: $home');

    switch (scope) {
      case FeatureScope.boroughOnly:
        buffer.writeln(
          'Scope: BOROUGH-ONLY. All suggestions, data, and recommendations '
          'MUST be restricted to $home. Do NOT reference other boroughs.',
        );
        break;
      case FeatureScope.ukWide:
        buffer.writeln(
          'Scope: UK-WIDE. Show events from all UK boroughs, '
          'but highlight $home events with priority.',
        );
        if (targetBorough != null && targetBorough != home) {
          buffer.writeln('Target borough being explored: $targetBorough');
        }
        break;
      case FeatureScope.boroughAware:
        buffer.writeln(
          'Scope: BOROUGH-AWARE. Prioritise $home content but allow '
          'cross-borough content when relevant.',
        );
        break;
    }

    return buffer.toString();
  }

  /// Validates that data belongs to the user's borough for borough-only services.
  /// Returns true if the data is allowed, false if it should be excluded.
  bool isDataBoroughAllowed(String? dataBorough, HuddlFeature feature) {
    return _boroughGuard.isAccessAllowed(
      feature: feature,
      dataBorough: dataBorough,
    );
  }

  /// Filter a list of items by borough for AI processing.
  List<T> filterForAi<T>(
    List<T> items,
    String? Function(T) boroughExtractor,
    HuddlFeature feature,
  ) {
    if (BoroughScopeGuard.isUkWide(feature)) return items;
    return _boroughGuard.filterByUserBorough(items, boroughExtractor);
  }
}

/// Extension on GeminiSystemPromptBuilder to ensure borough is always fresh.
extension BoroughPromptExtension on GeminiSystemPromptBuilder {
  /// Returns the current borough that the builder will inject into prompts.
  String get boroughForPrompt {
    final guard = BoroughScopeGuard();
    return guard.currentBoroughOr('Unknown Borough');
  }
}
