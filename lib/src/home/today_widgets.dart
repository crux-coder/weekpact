import '../widgets/check_in_feedback.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../goals/goal_icons.dart';
import '../goals/goals_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/brutal_widgets.dart';
import '../widgets/page_frame.dart';
import 'home_backend.dart';

class TodayHeader extends StatelessWidget {
  const TodayHeader({
    super.key,
    this.day,
    required this.crews,
    this.selected,
    this.onSelect,
  });
  final String? day;
  final List<GoalCrew> crews;
  final GoalCrew? selected;
  final ValueChanged<String>? onSelect;
  @override
  Widget build(BuildContext context) {
    final date = day == null ? DateTime.now() : DateTime.parse(day!);
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'TODAY',
                style: TextStyle(
                  color: context.ink,
                  fontSize: 54,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
            ),
            if (selected != null)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: BrutalShadow(
                    fillColor: context.mint,
                    shadowOffset: WeekPactMetrics.smallShadow,
                    child: PopupMenuButton<String>(
                      tooltip: 'Select crew',
                      enabled: crews.length > 1 && onSelect != null,
                      onSelected: onSelect,
                      itemBuilder: (_) => crews
                          .map(
                            (c) =>
                                PopupMenuItem(value: c.id, child: Text(c.name)),
                          )
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                selected!.name.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.ink,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (crews.length > 1) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: context.ink,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}'
              .toUpperCase(),
          style: TextStyle(
            color: context.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class TodayGoalsCard extends StatelessWidget {
  const TodayGoalsCard({
    super.key,
    required this.week,
    required this.userId,
    required this.savingGoal,
    required this.onToggle,
  });
  final CrewWeek week;
  final String userId;
  final String? savingGoal;
  final ValueChanged<String>? onToggle;
  @override
  Widget build(BuildContext context) {
    final checked = week.checkedToday(userId);
    final done = week.goals.where((g) => checked.contains(g.id)).length;
    return BrutalTabbedCard(
      title: 'YOUR GOALS',
      tabColor: context.yellow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 16, 14, 18),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '$done OF ${week.goals.length} DONE',
                  style: TextStyle(
                    color: context.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 13,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: context.border,
                        width: WeekPactMetrics.border,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: week.goals.isEmpty
                              ? 0
                              : done / week.goals.length,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.yellow,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < week.goals.length; index++) ...[
              _TodayGoalRow(
                key: ValueKey(week.goals[index].id),
                goal: week.goals[index],
                checked: checked.contains(week.goals[index].id),
                progress: week.days(week.goals[index].id, userId),
                color: [context.yellow, context.mint, context.coral][index % 3],
                busy: savingGoal == week.goals[index].id,
                onTap: savingGoal != null || onToggle == null
                    ? null
                    : () => onToggle!(week.goals[index].id),
              ),
              if (index < week.goals.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayGoalRow extends StatelessWidget {
  const _TodayGoalRow({
    super.key,
    required this.goal,
    required this.checked,
    required this.progress,
    required this.color,
    required this.busy,
    this.onTap,
  });
  final CrewGoal goal;
  final bool checked;
  final int progress;
  final Color color;
  final bool busy;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: goal.title,
    checked: checked,
    enabled: onTap != null,
    button: true,
    child: CheckInFeedback(
      checked: checked,
      color: context.ink,
      child: Material(
        color: checked ? context.mint : context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: context.border,
            width: WeekPactMetrics.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('check-in-${goal.title}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: context.border,
                      width: WeekPactMetrics.border,
                    ),
                  ),
                  child: HugeIcon(
                    icon: GoalIcon.find(goal.iconKey).data,
                    color: context.ink,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: List.generate(
                          goal.daysPerWeek,
                          (i) => Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < progress
                                  ? color
                                  : context.border.withValues(alpha: .22),
                              border: i < progress
                                  ? Border.all(
                                      color: context.border,
                                      width: WeekPactMetrics.fineBorder,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: checked ? context.mint : context.surface,
                    border: Border.all(
                      color: context.border,
                      width: WeekPactMetrics.border,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.ink,
                          ),
                        )
                      : checked
                      ? HugeIcon(
                          icon: HugeIconsStrokeRounded.tick02,
                          color: context.ink,
                          size: 26,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class TodayCrewCard extends StatelessWidget {
  const TodayCrewCard({
    super.key,
    required this.week,
    required this.userId,
    required this.onOpen,
  });
  final CrewWeek week;
  final String userId;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final members = [...week.members]
      ..sort(
        (a, b) => a.id == userId
            ? -1
            : b.id == userId
            ? 1
            : a.email.compareTo(b.email),
      );
    final done = members
        .where((m) => week.checkedToday(m.id).isNotEmpty)
        .length;
    return BrutalTabbedCard(
      title: 'YOUR CREW',
      tabTrailing: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIconsStrokeRounded.fire,
              color: context.ink,
              size: 20,
            ),
            const SizedBox(width: 5),
            Text(
              '${week.streakWeeks} ${week.streakWeeks == 1 ? 'WEEK' : 'WEEKS'} STREAK',
              style: TextStyle(
                color: context.ink,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
      tabColor: context.mint,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in members.take(5))
                    Tooltip(
                      message: m.email,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: m.id == userId
                                  ? context.yellow
                                  : context.mint,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: context.border,
                                width: WeekPactMetrics.border,
                              ),
                            ),
                            child: Text(
                              m.id == userId
                                  ? 'YOU'
                                  : m.email
                                        .split('@')
                                        .first
                                        .substring(
                                          0,
                                          math.min(
                                            2,
                                            m.email.split('@').first.length,
                                          ),
                                        )
                                        .toUpperCase(),
                              style: TextStyle(
                                color: context.ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -1,
                            bottom: -2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: week.checkedToday(m.id).isNotEmpty
                                    ? context.mint
                                    : context.surface,
                                border: Border.all(
                                  color: context.border,
                                  width: WeekPactMetrics.border,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (members.length > 5)
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: Text(
                          '+${members.length - 5}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      '$done OF ${members.length} CHECKED IN TODAY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'View week',
                    onPressed: onOpen,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: HugeIcon(
                      icon: HugeIconsStrokeRounded.arrowRight01,
                      color: context.ink,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      BrutalTabbedCard(
        title: 'YOUR GOALS',
        tabColor: context.yellow,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const SkeletonBar(height: 18),
              const SizedBox(height: 18),
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SkeletonBar(width: 42, height: 44),
                      SizedBox(width: 12),
                      Expanded(child: SkeletonBar(height: 54)),
                      SizedBox(width: 12),
                      SkeletonBar(width: 36, height: 36),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      BrutalTabbedCard(
        title: 'YOUR CREW',
        tabColor: context.mint,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonBar(height: 80),
        ),
      ),
    ],
  );
}
