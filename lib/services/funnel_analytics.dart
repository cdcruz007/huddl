import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper for conversion-funnel analytics events.
///
/// LAYER-16-NO-FUNNEL-1: tracks onboarding drop-off at 5 steps so silent
/// abandonment is visible in Firebase Analytics → Funnels.
///
/// Opt-out: collection is gated by [FirebaseAnalytics.setAnalyticsCollectionEnabled],
/// which is toggled from the user's analytics_enabled pref in main.dart.
/// These events therefore automatically respect the user's analytics toggle —
/// no extra guard needed here.
///
/// Best-effort: every call is wrapped in a try/catch so a transient Analytics
/// failure NEVER blocks the user flow.
class FunnelAnalytics {
  FunnelAnalytics._(); // static-only — no instances

  static Future<void> log(String name, [Map<String, Object>? params]) async {
    try {
      await FirebaseAnalytics.instance
          .logEvent(name: name, parameters: params);
    } catch (e) {
      if (kDebugMode) debugPrint('[FunnelAnalytics] $name failed: $e');
      // best-effort — never block the user flow on an analytics call
    }
  }
}
