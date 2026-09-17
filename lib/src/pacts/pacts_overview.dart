import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../home/home_backend.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'pact_icons.dart';
import '../widgets/app_icon.dart';
import 'pacts_backend.dart';

class YourWeekCard extends StatelessWidget {
  const YourWeekCard({super.key, required this.week, required this.userId});

  final CrewWeek week;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final completed = week.completed(userId);
    final target = week.target;
    final remaining = target - completed;
    final today = DateTime.parse('${week.today}T00:00:00Z');
    final start = DateTime.parse('${week.weekStart}T00:00:00Z');
    final daysLeft = (7 - today.difference(start).inDays).clamp(1, 7);
    return AppSurface(
      fillColor: WeekPactColors.stone,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your week so far',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (target == 0)
              Text(
                'Add a pact to start your week.',
                style: TextStyle(color: context.muted),
              )
            else ...[
              Text(
                '$completed of $target check-ins done',
                key: const ValueKey('weekly-progress-total'),
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: completed / target,
                minHeight: 10,
                borderRadius: WeekPactMetrics.pill,
                color: context.ink,
                backgroundColor: context.ink.withValues(alpha: .12),
                semanticsLabel:
                    'Your weekly check-ins: $completed of $target completed',
              ),
              const SizedBox(height: 10),
              Text(
                remaining == 0
                    ? 'All weekly targets met. Nice work!'
                    : '$remaining left · ${daysLeft == 1 ? 'Today is the last day' : '$daysLeft days remaining, including today'}',
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: context.border),
              const SizedBox(height: 6),
              for (final pact in week.pacts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      AppIcon(
                        icon: PactIcon.find(pact.iconKey).data,
                        color: context.ink,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pact.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${week.days(pact.id, userId).clamp(0, pact.daysPerWeek)} / ${pact.daysPerWeek}',
                        key: ValueKey('weekly-progress-${pact.id}'),
                        semanticsLabel:
                            '${pact.title}: ${week.days(pact.id, userId).clamp(0, pact.daysPerWeek)} of ${pact.daysPerWeek} check-ins',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The pact list as a week-load chart: every pact is a full-width track whose
/// tinted fill spans the share of the week it claims, so the list reads as one
/// picture of the week rather than a grid of separate tiles.
class PactBarList extends StatelessWidget {
  const PactBarList({super.key, required this.pacts, this.onEdit});
  final List<CrewPact> pacts;
  final ValueChanged<CrewPact>? onEdit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, pact) in pacts.indexed) ...[
        if (index > 0) const SizedBox(height: 8),
        PactBar(
          key: ValueKey('pact-management-${pact.id}'),
          pact: pact,
          tint: WeekPactColors.pactTint(index),
          onEdit: onEdit == null ? null : () => onEdit!(pact),
        ),
      ],
    ],
  );
}

/// One pact track. The fill is the pact's own tint, measured against a seven
/// day week; the ink stays the card ink on both the fill and the bare track, so
/// a title that crosses the edge does not change colour halfway through.
class PactBar extends StatelessWidget {
  const PactBar({super.key, required this.pact, this.tint, this.onEdit});
  final CrewPact pact;
  final Color? tint;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final share = (pact.daysPerWeek / 7).clamp(0.0, 1.0);
    return AppSurface(
      borderRadius: WeekPactMetrics.cardCorner,
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: share,
              child: ColoredBox(color: tint ?? context.yellow),
            ),
          ),
          Semantics(
            label: '${pact.title}. ${pact.schedule}',
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    10,
                    onEdit == null ? 14 : 4,
                    10,
                  ),
                  child: Row(
                    children: [
                      HugeIcon(
                        icon: PactIcon.find(pact.iconKey).data,
                        color: context.ink,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${pact.daysPerWeek}',
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Tooltip(
                          message: pact.schedule,
                          child: Text(
                            pact.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.ink,
                              fontSize: 19,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (onEdit != null)
                        IconButton(
                          tooltip: 'Edit ${pact.title}',
                          onPressed: onEdit,
                          icon: AppIcon(
                            icon: HugeIconsStrokeRounded.moreHorizontal,
                            color: context.ink,
                            size: 22,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pacts page's own loading shapes: the week card, the list heading and a
/// few bars, so the page does not rearrange itself the moment it loads.
class PactsSkeletonBody extends StatelessWidget {
  const PactsSkeletonBody({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSurface(
        fillColor: WeekPactColors.stone,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SkeletonBar(width: 150, height: 18),
              const SizedBox(height: 16),
              const SkeletonBar(width: 210, height: 26),
              const SizedBox(height: 14),
              const SkeletonBar(height: 10, radius: 999),
              const SizedBox(height: 10),
              const SkeletonBar(width: 170, height: 12),
              const SizedBox(height: 18),
              Divider(height: 1, color: context.border),
              const SizedBox(height: 6),
              for (var i = 0; i < 2; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SkeletonBar(width: 22, height: 22),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBar(height: 14)),
                      SizedBox(width: 12),
                      SkeletonBar(width: 40, height: 14),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Row(
        children: [
          SkeletonBar(width: 120, height: 20),
          Spacer(),
          SkeletonBar(width: 84, height: 10),
        ],
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        AppSurface(
          borderRadius: WeekPactMetrics.cardCorner,
          builder: (context) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  SkeletonBar(width: 22, height: 22),
                  SizedBox(width: 10),
                  SkeletonBar(width: 22, height: 28),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBar(height: 16)),
                  SizedBox(width: 12),
                  SkeletonBar(width: 22, height: 22),
                ],
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const SkeletonBar(height: 48, radius: WeekPactMetrics.controlRadius),
    ],
  );
}
