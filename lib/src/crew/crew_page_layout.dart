import 'crew_switcher.dart';
import '../widgets/avatar_shape.dart';

import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/page_frame.dart';
import 'crew_roster.dart';

/// Shared heading geometry for every crew-scoped management screen.
class CrewPageHeading extends StatelessWidget {
  const CrewPageHeading({
    super.key,
    required this.title,
    this.actions = const [],
    this.dotColor = WeekPactColors.sky,
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

/// The shared loading shell: the same selector placeholder and progress line
/// on Pacts and Crews, so switching tabs mid-load does not shift the page.
/// Below that each page stands in for its own content — [body] — because a
/// skeleton that shows the wrong shapes is a worse promise than none.
class CrewPageSkeleton extends StatelessWidget {
  const CrewPageSkeleton({
    super.key,
    this.showSelector = true,
    this.label = 'Loading crews',
    this.body,
  });

  final String label;

  final bool showSelector;

  /// What is loading under the progress line. Defaults to the crew roster.
  final Widget? body;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSelector) ...[
            const CrewHeaderSurface(
              child: SizedBox(
                height: 60,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(width: 62, height: 8),
                      SizedBox(height: 8),
                      SkeletonBar(width: 145, height: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          LinearProgressIndicator(
            minHeight: 2,
            color: WeekPactColors.coolGrey,
            backgroundColor: context.ink.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          ),
          const SizedBox(height: 16),
          body ?? const CrewRosterSkeleton(),
        ],
      ),
    ),
  );
}

/// The crew page's own loading shapes: its caption, then a stack of bands.
class CrewRosterSkeleton extends StatelessWidget {
  const CrewRosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: SkeletonBar(width: 120, height: 16),
      ),
      const SizedBox(height: 12),
      CrewRoster(
        children: [
          for (var i = 0; i < 4; i++)
            CrewBand(
              fillColor: i == 0
                  ? WeekPactColors.coolGrey
                  : WeekPactColors.cream,
              builder: (context) => const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: SkeletonBar(height: 40, shape: AvatarShape()),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: SkeletonBar(height: 15)),
                    SizedBox(width: 12),
                    SkeletonBar(width: 54, height: 10),
                    SizedBox(width: 12),
                    SkeletonBar(height: 30, width: 30, shape: CircleBorder()),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
