import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/ai_learning_engine_service.dart';
import '../../services/daily_ai_refresh_service.dart';

// =============================================================================
// LEARNING MATURITY UI INDICATOR  — PARENT CONCIERGE EDITION (Step 14)
//
// Visual indicator showing how well Huddl's AI knows the user.
// Appears on the Home screen and Profile screen.
//
// Maturity stages:
//   1. Cold Start (< 10 signals)   — "Getting to know you" + seedling icon
//   2. Warming (10-50 signals)     — "Learning your preferences" + growing plant
//   3. Personalised (50-200)       — "Personalised for you" + flower
//   4. Mature (> 200 signals)      — "Deeply personalised" + tree
// =============================================================================

class LearningMaturityIndicator extends StatelessWidget {
  final bool showLabel;
  final bool compact;

  const LearningMaturityIndicator({
    super.key,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final engine = AiLearningEngineService();
    final profile = engine.profile;
    final maturity = profile.currentBoroughMaturity;
    final progress = profile.maturityProgress;
    final label = profile.maturityLabel;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (compact) {
      return _buildCompactIndicator(context, maturity, progress, isDark);
    }

    return _buildFullIndicator(context, maturity, progress, label, isDark);
  }

  Widget _buildCompactIndicator(
    BuildContext context,
    LearningMaturity maturity,
    double progress,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _maturityColor(maturity).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _maturityEmoji(maturity),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor:
                    isDark ? Colors.white12 : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(_maturityColor(maturity)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullIndicator(
    BuildContext context,
    LearningMaturity maturity,
    double progress,
    String label,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _maturityColor(maturity).withValues(alpha: 0.12),
            _maturityColor(maturity).withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _maturityColor(maturity).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                _maturityEmoji(maturity),
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maturityTitle(maturity),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey.shade800,
                      ),
                    ),
                    if (showLabel)
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white70
                              : Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _maturityColor(maturity),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor:
                  isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(_maturityColor(maturity)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _maturityHint(maturity),
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: isDark ? Colors.white54 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  String _maturityEmoji(LearningMaturity maturity) {
    switch (maturity) {
      case LearningMaturity.coldStart:
        return '\u{1F331}';
      case LearningMaturity.warming:
        return '\u{1F33F}';
      case LearningMaturity.personalised:
        return '\u{1F33B}';
      case LearningMaturity.mature:
        return '\u{1F333}';
    }
  }

  String _maturityTitle(LearningMaturity maturity) {
    switch (maturity) {
      case LearningMaturity.coldStart:
        return 'AI Active';
      case LearningMaturity.warming:
        return 'AI Adapting';
      case LearningMaturity.personalised:
        return 'AI Personalised';
      case LearningMaturity.mature:
        return 'AI Deeply Personalised';
    }
  }

  String _maturityHint(LearningMaturity maturity) {
    switch (maturity) {
      case LearningMaturity.coldStart:
        return 'Already personalising based on your profile \u2014 the more you use Huddl, the smarter it gets';
      case LearningMaturity.warming:
        return 'Getting better every day \u2014 your suggestions are already tailored to you';
      case LearningMaturity.personalised:
        return 'Your feed and recommendations are now personalised to you';
      case LearningMaturity.mature:
        return 'Your AI knows you well. Enjoy deeply personalised content';
    }
  }

  Color _maturityColor(LearningMaturity maturity) {
    switch (maturity) {
      case LearningMaturity.coldStart:
        return Colors.teal;
      case LearningMaturity.warming:
        return Colors.amber.shade700;
      case LearningMaturity.personalised:
        return Colors.green;
      case LearningMaturity.mature:
        return Colors.purple;
    }
  }
}

// =============================================================================
// DAILY REFRESH STATUS WIDGET — shows last refresh and next refresh time
// =============================================================================

class DailyRefreshStatusWidget extends StatelessWidget {
  const DailyRefreshStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final refreshService = DailyAiRefreshService();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final lastRefresh = refreshService.lastRefreshTime;
    final needsRefresh = refreshService.needsRefresh;
    final timeUntil = refreshService.timeUntilNextRefresh;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            needsRefresh ? Icons.refresh : Icons.check_circle_outline,
            size: 20,
            color: needsRefresh ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Knowledge Refresh',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                ),
                Text(
                  lastRefresh != null
                      ? needsRefresh
                          ? 'Refresh available now'
                          : 'Next refresh in ${timeUntil.inHours}h ${timeUntil.inMinutes % 60}m'
                      : 'Not yet refreshed',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
