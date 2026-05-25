import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'meetup_service.dart';
import 'browser_storage.dart';

// =============================================================================
// MEETUP AI SERVICE — "Invisible AI" for the Meetups Tab
//
// Two responsibilities:
//   B) Smart Sort — silently reorder meetups by personal relevance
//   E) Smart Nudges — contextual one-line prompts that appear only when useful
//
// Design philosophy: No new buttons, no "AI Matchmaker" language, no
// dating-app vibes. The AI works in the background to reduce cognitive load.
// =============================================================================

/// A scored meetup with an optional sparkle reason (shown subtly on the card).
class ScoredMeetup {
  final Meetup meetup;
  final double score; // 0–100
  final String? boostReason; // e.g. "Friends going" — shown as a chip

  const ScoredMeetup({
    required this.meetup,
    required this.score,
    this.boostReason,
  });
}

/// A contextual nudge — one-line insight shown at the top of the list.
class SmartNudge {
  final String text;
  final String icon; // emoji
  final String? actionLabel; // e.g. "Create one" or null for info-only
  final NudgeType type;

  const SmartNudge({
    required this.text,
    required this.icon,
    this.actionLabel,
    required this.type,
  });
}

enum NudgeType {
  weatherSuggestion,
  inactivityReminder,
  popularCategory,
  weekendPrompt,
  friendActivity,
}

class MeetupAiService {
  // ── User behaviour state (persisted) ──────────────────────────────
  Map<String, int> _categoryClickCount = {};
  List<String> _attendedMeetupIds = [];
  final Set<String> _dismissedNudgeKeys = {};
  DateTime? _lastAttendedDate;

  bool _initialized = false;

  // ── Public API ────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadBehaviourData();
    _initialized = true;
  }

  /// Track that the user tapped on a category filter (learns preferences).
  void trackCategoryTap(String category) {
    _categoryClickCount[category] =
        (_categoryClickCount[category] ?? 0) + 1;
    _persistBehaviourData();
  }

  /// Track that the user opened/attended a meetup.
  void trackMeetupView(String meetupId, String category) {
    if (!_attendedMeetupIds.contains(meetupId)) {
      _attendedMeetupIds.add(meetupId);
    }
    _categoryClickCount[category] =
        (_categoryClickCount[category] ?? 0) + 2; // heavier signal
    _lastAttendedDate = DateTime.now();
    _persistBehaviourData();
  }

  /// Dismiss a nudge so it doesn't appear again this session.
  void dismissNudge(String nudgeKey) {
    _dismissedNudgeKeys.add(nudgeKey);
  }

  // ── B) Smart Sort ─────────────────────────────────────────────────

  /// Returns meetups sorted by personal relevance. Higher-scored meetups
  /// appear first. The scoring is invisible — the list just "feels right".
  List<ScoredMeetup> smartSort(List<Meetup> meetups) {
    final scored = meetups.map((m) => _scoreMeetup(m)).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  ScoredMeetup _scoreMeetup(Meetup m) {
    double score = 50; // baseline
    String? boostReason;

    // 1. Category affinity — most important signal
    final catScore = _categoryClickCount[m.category] ?? 0;
    if (catScore > 0) {
      score += (catScore * 3).clamp(0, 20).toDouble();
    }

    // 2. Temporal proximity — sooner is better (within reason)
    final daysUntil = m.dateTime.difference(DateTime.now()).inDays;
    if (daysUntil <= 2) {
      score += 15;
      boostReason ??= 'Happening soon';
    } else if (daysUntil <= 5) {
      score += 10;
    } else if (daysUntil <= 14) {
      score += 5;
    }

    // 3. Social proof — more attendees = more interesting
    if (m.attendeeCount >= 5) {
      score += 8;
      boostReason ??= 'Popular';
    } else if (m.attendeeCount >= 3) {
      score += 4;
    }

    // 4. Weekend bias — on weekdays, boost weekend meetups slightly
    final now = DateTime.now();
    final isWeekday = now.weekday <= 5;
    final meetupIsWeekend = m.dateTime.weekday >= 6;
    if (isWeekday && meetupIsWeekend && daysUntil <= 7) {
      score += 6;
      boostReason ??= 'This weekend';
    }

    // 5. Free meetups get a small nudge
    if (m.isFree) {
      score += 3;
    }

    // 6. User is already going — pin to top
    if (m.isGoing) {
      score += 30;
      boostReason = "You're going";
    }

    // 7. Organiser is current user — their own meetups always surface
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? 'current_user';
    if (m.organiserId == myUid || m.organiserId == 'current_user') {
      score += 25;
      boostReason = 'Your meetup';
    }

    // 8. Spots filling up creates urgency
    if (m.maxAttendees != null) {
      final remaining = m.maxAttendees! - m.attendeeCount;
      if (remaining <= 2 && remaining > 0) {
        score += 12;
        boostReason ??= '$remaining spots left';
      } else if (remaining <= 5) {
        score += 5;
      }
    }

    return ScoredMeetup(
      meetup: m,
      score: score.clamp(0, 100),
      boostReason: boostReason,
    );
  }

  /// Returns the user's top 3 preferred categories (for adaptive filter order).
  List<String> get preferredCategories {
    if (_categoryClickCount.isEmpty) return [];
    final sorted = _categoryClickCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).map((e) => e.key).toList();
  }

  // ── E) Smart Nudges ───────────────────────────────────────────────

  /// Returns 0–1 contextual nudges for the current moment.
  /// Only shows if genuinely relevant — "less is more".
  SmartNudge? getSmartNudge(List<Meetup> meetups) {
    final now = DateTime.now();

    // Priority 1: Inactivity reminder (hasn't attended in 2+ weeks)
    if (_lastAttendedDate != null) {
      final daysSince = now.difference(_lastAttendedDate!).inDays;
      if (daysSince >= 14 && !_dismissedNudgeKeys.contains('inactivity')) {
        // Find a meetup happening soon to suggest
        final soon = meetups
            .where((m) =>
                !m.isGoing &&
                m.dateTime.isAfter(now) &&
                m.dateTime.difference(now).inDays <= 5)
            .toList();
        if (soon.isNotEmpty) {
          return SmartNudge(
            text: "It's been a while \u2014 ${soon.first.title} is ${soon.first.isFree ? 'free' : 'happening'} ${_friendlyDate(soon.first.dateTime)}",
            icon: '\u{1F44B}',
            type: NudgeType.inactivityReminder,
          );
        }
      }
    } else if (_attendedMeetupIds.isEmpty &&
        !_dismissedNudgeKeys.contains('first_time')) {
      // First-time user nudge
      return const SmartNudge(
        text: 'Meetups are sorted by what\u2019s most relevant to you',
        icon: '\u2728',
        type: NudgeType.friendActivity,
      );
    }

    // Priority 2: Weekend prompt (Thursday/Friday → suggest weekend meetups)
    if ((now.weekday == 4 || now.weekday == 5) &&
        !_dismissedNudgeKeys.contains('weekend_${now.weekOfYear}')) {
      final weekendMeetups = meetups.where((m) {
        final d = m.dateTime;
        return d.weekday >= 6 &&
            d.difference(now).inDays <= 3 &&
            d.isAfter(now);
      }).toList();
      if (weekendMeetups.isNotEmpty) {
        final count = weekendMeetups.length;
        return SmartNudge(
          text: '$count meetup${count > 1 ? 's' : ''} happening this weekend near you',
          icon: '\u2600\uFE0F',
          type: NudgeType.weekendPrompt,
        );
      }
    }

    // Priority 3: Popular category insight
    if (meetups.length >= 4 &&
        !_dismissedNudgeKeys.contains('popular_${now.day}')) {
      final catCounts = <String, int>{};
      for (final m in meetups) {
        catCounts[m.category] = (catCounts[m.category] ?? 0) + 1;
      }
      final topCat = catCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (topCat.isNotEmpty && topCat.first.value >= 3) {
        final cat = topCat.first.key;
        final catLabel = _categoryDisplayName(cat);
        return SmartNudge(
          text: '$catLabel is trending \u2014 ${topCat.first.value} meetups coming up',
          icon: '\u{1F525}',
          type: NudgeType.popularCategory,
        );
      }
    }

    return null; // No nudge needed — keep the UI clean
  }

  // ── Private helpers ───────────────────────────────────────────────

  String _friendlyDate(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    if (diff <= 2) return 'in $diff days';
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return 'this ${weekdays[dt.weekday - 1]}';
  }

  String _categoryDisplayName(String code) {
    const names = {
      'Coffee': 'Coffee & tea',
      'Playdate': 'Playdates',
      'Sport': 'Sports',
      'Walk': 'Parks & walks',
      'Social': 'Social hangouts',
      'Food': 'Food meetups',
      'Other': 'Other meetups',
    };
    return names[code] ?? code;
  }

  // ── Persistence ───────────────────────────────────────────────────

  Future<void> _loadBehaviourData() async {
    try {
      final raw = await BrowserStorage.getString('meetup_ai_behaviour_v1');
      if (raw != null) {
        final data = json.decode(raw) as Map<String, dynamic>;
        _categoryClickCount = (data['catClicks'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as int)) ??
            {};
        _attendedMeetupIds =
            (data['attended'] as List<dynamic>?)?.cast<String>() ?? [];
        if (data['lastAttended'] != null) {
          _lastAttendedDate = DateTime.tryParse(data['lastAttended']);
        }
      }
    } catch (_) {}
  }

  Future<void> _persistBehaviourData() async {
    try {
      await BrowserStorage.setString(
        'meetup_ai_behaviour_v1',
        json.encode({
          'catClicks': _categoryClickCount,
          'attended': _attendedMeetupIds.take(50).toList(),
          'lastAttended': _lastAttendedDate?.toIso8601String(),
        }),
      );
    } catch (_) {}
  }
}

// ── Week-of-year extension ──────────────────────────────────────────────────
extension _DateWeek on DateTime {
  int get weekOfYear {
    final jan1 = DateTime(year, 1, 1);
    return ((difference(jan1).inDays + jan1.weekday) / 7).ceil();
  }
}
