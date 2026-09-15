import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'crew_people_grid.dart';

/// Shared heading geometry for every crew-scoped management screen.
class CrewPageHeading extends StatelessWidget {
  const CrewPageHeading({
    super.key,
    required this.title,
    this.actions = const [],
    this.dotColor = WeekPactColors.coolGrey,
  });
  final String title;
  final List<Widget> actions;
  final Color dotColor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Row(
      children: [
        Expanded(child: PageHeading(title, dotColor: dotColor)),
        ...actions,
      ],
    ),
  );
}

/// Identical selector placeholder, progress line, and loading cards on Pacts and Crews.
class CrewPageSkeleton extends StatelessWidget {
  const CrewPageSkeleton({
    super.key,
    this.showSelector = true,
    this.label = 'Loading crews',
  });

  final String label;

  final bool showSelector;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSelector) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBar(width: 84, height: 12),
            ),
            const SizedBox(height: 4),
            const SkeletonBar(height: 60),
            const SizedBox(height: 12),
          ],
          LinearProgressIndicator(
            minHeight: 2,
            color: WeekPactColors.coolGrey,
            backgroundColor: context.ink.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBar(width: 120, height: 16),
          ),
          const SizedBox(height: 12),
          CrewPeopleGrid(
            children: [
              for (var i = 0; i < 4; i++)
                AppSurface(
                  fillColor: i == 0
                      ? WeekPactColors.coolGrey
                      : WeekPactColors.cream,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: SkeletonBar(height: 100, radius: 100),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        SkeletonBar(height: 15),
                        SizedBox(height: 8),
                        SkeletonBar(width: 60, height: 10),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
