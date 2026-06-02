import 'package:flutter/material.dart';
import '../../theme/huddl_icons.dart';
import '../../theme/huddl_colors.dart';
import '../../models/user_journey_map.dart';
import '../../constants/app_text_styles.dart';

/// An in-app visual user-journey-map screen.
///
/// Accessible from Profile > Design System > Journey Maps (or dev menu).
/// Turns the previously code-comment-only documentation into a browseable,
/// interactive artefact that designers & QA engineers can reference at any time.
class JourneyMapScreen extends StatefulWidget {
  const JourneyMapScreen({super.key});

  @override
  State<JourneyMapScreen> createState() => _JourneyMapScreenState();
}

class _JourneyMapScreenState extends State<JourneyMapScreen> {
  int _selectedPersona = 0;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final journey = HuddlJourneyMaps.all[_selectedPersona];

    return Scaffold(
      backgroundColor: hc.scaffold,
      appBar: AppBar(
        backgroundColor: hc.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(HuddlIcons.arrowBack, color: hc.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: Text(
          'User Journey Maps',
          style: HuddlText.heading(),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Persona selector chips ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: List.generate(HuddlJourneyMaps.all.length, (i) {
                    final j = HuddlJourneyMaps.all[i];
                    final selected = i == _selectedPersona;
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                      child: Semantics(
                        label: 'View ${j.personaLabel} journey',
                        selected: selected,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedPersona = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? HuddlColors.primary
                                  : hc.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: selected
                                  ? null
                                  : Border.all(color: hc.divider),
                            ),
                            child: Text(
                              j.personaName,
                              style: HuddlText.body(weight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            // ── Persona card ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HuddlColors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: HuddlColors.primary,
                      child: Text(
                        journey.personaName[0],
                        style: HuddlText.display(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            journey.personaLabel,
                            style: HuddlText.body(weight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Age ${journey.ageRange}',
                            style: HuddlText.caption(),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            journey.bio,
                            style: HuddlText.caption(color: context.hc.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Emotional arc ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emotional arc',
                      style: HuddlText.body(weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < journey.emotionalArc.length; i++) ...[
                          _emotionChip(journey.emotionalArc[i], i, journey.emotionalArc.length),
                          if (i < journey.emotionalArc.length - 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Icon(HuddlIcons.arrowForward,
                                  size: 14, color: hc.textTertiary),
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Journey stages timeline ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Journey stages',
                  style: HuddlText.body(weight: FontWeight.w600),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) => _StageCard(
                  stage: journey.stages[idx],
                  index: idx,
                  isLast: idx == journey.stages.length - 1,
                ),
                childCount: journey.stages.length,
              ),
            ),

            // ── Pain points ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Pain points mitigated',
                  style: HuddlText.body(weight: FontWeight.w600),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) => _PainPointTile(point: journey.painPoints[idx]),
                childCount: journey.painPoints.length,
              ),
            ),

            // ── Competitor analysis ───────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Competitor analysis',
                  style: HuddlText.body(weight: FontWeight.w600),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, idx) => _CompetitorTile(
                    entry: HuddlJourneyMaps.competitors[idx]),
                childCount: HuddlJourneyMaps.competitors.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _emotionChip(String emotion, int i, int total) {
    // Gradient from warm to cool as emotional state improves
    final t = total > 1 ? i / (total - 1) : 0.0;
    final color = Color.lerp(
      HuddlColors.primary,
      HuddlColors.nearBlack,
      t,
    )!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        emotion,
        style: HuddlText.caption(weight: FontWeight.w600),
      ),
    );
  }
}

// ── Stage timeline card ─────────────────────────────────────────────────
class _StageCard extends StatelessWidget {
  final JourneyStage stage;
  final int index;
  final bool isLast;

  const _StageCard({
    required this.stage,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline dot + line
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HuddlColors.divider,
                      border: Border.all(
                          color: HuddlColors.divider, width: 2),
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: HuddlColors.divider,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Content
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: hc.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: HuddlColors.neutral50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${index + 1}. ${stage.name}',
                            style: HuddlText.caption(weight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        if (stage.emotionalState != null)
                          Text(
                            stage.emotionalState!,
                            style: HuddlText.label().copyWith(fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stage.description,
                      style: HuddlText.body(color: hc.textPrimary),
                    ),
                    if (stage.touchpoints.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...stage.touchpoints.map((tp) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: context.hc.textTertiary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tp,
                                    style: HuddlText.caption(color: hc.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pain-point tile ──────────────────────────────────────────────────────
class _PainPointTile extends StatelessWidget {
  final PainPoint point;
  const _PainPointTile({required this.point});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: HuddlColors.error.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(HuddlIcons.warning,
              size: 18, color: HuddlColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.issue,
                  style: HuddlText.caption(weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(HuddlIcons.checkCircle,
                        size: 14, color: HuddlColors.nearBlack),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        point.mitigation,
                        style: HuddlText.caption(color: HuddlColors.nearBlack),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Competitor tile ──────────────────────────────────────────────────────
class _CompetitorTile extends StatelessWidget {
  final CompetitorEntry entry;
  const _CompetitorTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isHuddl = entry.name == 'Huddl';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHuddl
            ? HuddlColors.primary.withValues(alpha: 0.06)
            : hc.surface,
        borderRadius: BorderRadius.circular(12),
        border: isHuddl
            ? Border.all(color: HuddlColors.primary.withValues(alpha: 0.3))
            : null,
        boxShadow: isHuddl
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isHuddl)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(HuddlIcons.star, size: 16, color: HuddlColors.primary),
                ),
              Text(
                entry.name,
                style: HuddlText.body(weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(HuddlIcons.addCircle,
                  size: 14, color: HuddlColors.nearBlack),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  entry.strength,
                  style: HuddlText.caption(color: hc.textSecondary),
                ),
              ),
            ],
          ),
          if (!isHuddl) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(HuddlIcons.removeCircle,
                    size: 14, color: HuddlColors.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.weakness,
                    style: HuddlText.caption(color: hc.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
