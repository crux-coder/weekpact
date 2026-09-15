import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../home/home_backend.dart';
import '../widgets/app_components.dart';
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
                borderRadius: BorderRadius.circular(6),
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

class PactSquareGrid extends StatelessWidget {
  const PactSquareGrid({super.key, required this.pacts, this.onEdit});
  final List<CrewPact> pacts;
  final ValueChanged<CrewPact>? onEdit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final columns =
          space.maxWidth >= 340 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3
          ? 2
          : 1;
      final side = (space.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final pact in pacts)
            SizedBox.square(
              dimension: side,
              child: PactManagementCard(
                key: ValueKey('pact-management-${pact.id}'),
                pact: pact,
                onEdit: onEdit == null ? null : () => onEdit!(pact),
              ),
            ),
        ],
      );
    },
  );
}

class PactManagementCard extends StatelessWidget {
  const PactManagementCard({super.key, required this.pact, this.onEdit});
  final CrewPact pact;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => AppSurface(
    shape: WeekPactMetrics.pactCardShape,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,

                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: HugeIcon(
                    icon: PactIcon.find(pact.iconKey).data,
                    color: context.ink,
                    size: 24,
                  ),
                ),
              ),
              const Spacer(),
              if (onEdit != null)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    tooltip: 'Edit ${pact.title}',
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    icon: AppIcon(
                      icon: HugeIconsStrokeRounded.pencilEdit02,
                      color: context.ink,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Tooltip(
                message: pact.title,
                child: Text(
                  pact.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, thickness: 1, color: context.border),
          const SizedBox(height: 8),
          Semantics(
            label: pact.schedule,
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${pact.daysPerWeek}',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'days / week',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
