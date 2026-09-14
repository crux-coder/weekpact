import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'pact_icons.dart';
import 'pacts_backend.dart';

class WeeklyRhythmCard extends StatelessWidget {
  const WeeklyRhythmCard({super.key, required this.pacts});
  final List<CrewPact> pacts;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: WeekPactColors.softYellow,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your weekly rhythm',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${pacts.fold<int>(0, (total, pact) => total + pact.daysPerWeek)}',
                        key: const ValueKey('weekly-rhythm-target'),
                        style: const TextStyle(
                          fontSize: 64,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Text(
                      'planned check-ins',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // A week motif, not a completion chart or a prescribed daily schedule.
              Expanded(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Column(
                              children: [
                                Container(
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: WeekPactColors.black,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                FittedBox(
                                  child: Text(
                                    day,
                                    style: TextStyle(
                                      color: context.muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Your weekly target across ${pacts.length} ${pacts.length == 1 ? 'pact' : 'pacts'}.',
            style: TextStyle(color: context.muted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
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
    builder: (context) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: pact.frequency == PactFrequency.daily
                      ? WeekPactColors.softYellow
                      : WeekPactColors.mintGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: HugeIcon(
                  icon: PactIcon.find(pact.iconKey).data,
                  color: context.ink,
                  size: 24,
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
                    icon: HugeIcon(
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
