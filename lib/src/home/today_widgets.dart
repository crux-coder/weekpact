import 'package:card_swiper/card_swiper.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../goals/goal_icons.dart';
import '../goals/goals_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/page_frame.dart';
import 'home_backend.dart';

const _ink = WeekPactColors.outlineInk;
BoxDecoration _panel(Color color, [double radius = 18]) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: _ink, width: 2),
);

/// A compact crew nameplate that keeps the home screen's fixed layout.
class CrewTitleBanner extends StatelessWidget {
  const CrewTitleBanner({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Material(
    color: context.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: _ink, width: 2),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      height: 60,
      child: Row(
        children: [
          Container(
            width: 58,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: WeekPactColors.lavender,
              border: Border(right: BorderSide(color: _ink, width: 2)),
            ),
            child: const Center(
              child: HugeIcon(
                icon: HugeIconsStrokeRounded.userGroup,
                color: _ink,
                size: 29,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Tooltip(
              message: name,
              child: Semantics(
                header: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 25,
                        height: 1.3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ExcludeSemantics(
            child: SizedBox(
              width: 22,
              height: 26,
              child: Stack(
                children: [
                  Positioned(
                    top: 1,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: WeekPactColors.salmon,
                        border: Border.all(color: _ink),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 1,
                    left: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: WeekPactColors.lime,
                        border: Border.all(color: _ink),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    ),
  );
}

class TodayGoalsCard extends StatefulWidget {
  const TodayGoalsCard({
    super.key,
    required this.week,
    this.height,
    required this.userId,
    required this.savingGoal,
    required this.onToggle,
  });
  final double? height;
  final CrewWeek week;
  final String userId;
  final String? savingGoal;
  final ValueChanged<String>? onToggle;
  @override
  State<TodayGoalsCard> createState() => _TodayGoalsCardState();
}

class _TodayGoalsCardState extends State<TodayGoalsCard> {
  final _controller = SwiperController();
  int _index = 0;
  List<CrewGoal> get _goals {
    final checked = widget.week.checkedToday(widget.userId);
    return [
      ...widget.week.goals.where((g) => !checked.contains(g.id)),
      ...widget.week.goals.where((g) => checked.contains(g.id)),
    ];
  }

  @override
  void didUpdateWidget(covariant TodayGoalsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.week.checkedToday(oldWidget.userId);
    final after = widget.week.checkedToday(widget.userId);
    final completed = after.difference(before).isNotEmpty;
    if (completed || _index >= _goals.length) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.move(0, animation: false);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _controller.move(
      index,
      animation: !MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goals = _goals;
    if (goals.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final height = widget.height ?? (370 + math.max(0.0, scale - 1) * 200);
    final cardHeight = math.max(80.0, height - 48);
    final visibleDots = math.min(5, goals.length);
    final start = math.max(0, math.min(_index - 2, goals.length - visibleDots));
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: cardHeight,
            child: LayoutBuilder(
              builder: (context, space) => Swiper(
                key: const ValueKey('goal-stack'),
                controller: _controller,
                itemCount: goals.length,
                layout: SwiperLayout.STACK,
                itemWidth: space.maxWidth - (goals.length > 1 ? 32 : 0),
                itemHeight: cardHeight - 4,
                axisDirection: AxisDirection.right,
                scrollDirection: Axis.horizontal,
                loop: false,
                autoplay: false,
                duration: MediaQuery.disableAnimationsOf(context) ? 0 : 280,
                onIndexChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: SizedBox.expand(
                    child: _GoalCard(
                      key: ValueKey(goals[index].id),
                      goal: goals[index],
                      week: widget.week,
                      userId: widget.userId,
                      color: [
                        WeekPactColors.sky,
                        WeekPactColors.lavender,
                        WeekPactColors.lime,
                      ][widget.week.goals.indexOf(goals[index]) % 3],
                      busy: widget.savingGoal == goals[index].id,
                      onToggle:
                          widget.savingGoal != null || widget.onToggle == null
                          ? null
                          : () => widget.onToggle!(goals[index].id),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (goals.length > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var dot = start; dot < start + visibleDots; dot++)
                  Semantics(
                    selected: dot == _index,
                    child: IconButton(
                      tooltip: 'Goal ${dot + 1} of ${goals.length}',
                      onPressed: () => _goTo(dot),
                      style: IconButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints(minHeight: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 6,
                      ),
                      icon: Container(
                        width: dot == _index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot == _index
                              ? context.ink
                              : context.muted.withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
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

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    super.key,
    required this.goal,
    required this.week,
    required this.userId,
    required this.color,
    required this.busy,
    required this.onToggle,
  });
  final CrewGoal goal;
  final CrewWeek week;
  final String userId;
  final Color color;
  final bool busy;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final checked = week.checkedToday(userId).contains(goal.id);
    final start = DateTime.parse(week.weekStart);
    final completed = week.days(goal.id, userId);
    return Container(
      decoration: _panel(color),
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumHeight =
              310 +
              math.max(0.0, MediaQuery.textScalerOf(context).scale(1) - 1) *
                  300;
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: constraints.maxWidth,
              height: math.max(minimumHeight, constraints.maxHeight),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: _ink),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: _panel(WeekPactColors.softYellow, 12),
                          child: Center(
                            child: HugeIcon(
                              icon: GoalIcon.find(goal.iconKey).data,
                              color: _ink,
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            goal.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 25,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$completed',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'of ${goal.daysPerWeek} days this week',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Semantics(
                              label: 'Weekly goal progress',
                              value: '$completed of ${goal.daysPerWeek} days',
                              child: Row(
                                children: List.generate(
                                  goal.daysPerWeek,
                                  (i) => Expanded(
                                    child: Container(
                                      height: 10,
                                      margin: EdgeInsets.only(
                                        right: i == goal.daysPerWeek - 1
                                            ? 0
                                            : 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: i < completed
                                            ? _ink
                                            : _ink.withValues(alpha: .12),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(7, (i) {
                        final date = start.add(Duration(days: i));
                        final day =
                            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                        final done = week.checkIns.any(
                          (c) =>
                              c.goalId == goal.id &&
                              c.userId == userId &&
                              c.day == day,
                        );
                        final future = day.compareTo(week.today) > 0;
                        final current = day == week.today;
                        return Expanded(
                          child: Semantics(
                            label:
                                '$day: ${done
                                    ? 'completed'
                                    : future
                                    ? 'upcoming'
                                    : 'not completed'}',
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              decoration: BoxDecoration(
                                color: current
                                    ? WeekPactColors.softYellow
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    [
                                      'M',
                                      'T',
                                      'W',
                                      'T',
                                      'F',
                                      'S',
                                      'S',
                                    ][date.weekday - 1],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 25,
                                    height: 25,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: done
                                          ? WeekPactColors.lime
                                          : future
                                          ? _ink.withValues(alpha: .14)
                                          : Colors.transparent,
                                      border: future
                                          ? null
                                          : Border.all(
                                              color: _ink,
                                              width: current ? 3 : 1.5,
                                            ),
                                    ),
                                    child: done
                                        ? const Icon(
                                            Icons.check,
                                            color: _ink,
                                            size: 18,
                                          )
                                        : Center(
                                            child: Text(
                                              '${date.day}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: current
                                                    ? FontWeight.w900
                                                    : FontWeight.w500,
                                                color: _ink.withValues(
                                                  alpha: future ? .45 : 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: ValueKey('check-in-${goal.title}'),
                        onPressed: onToggle,
                        style: FilledButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                checked
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 22,
                              ),
                        label: Text(
                          checked ? 'Undo check-in' : 'Mark done',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class TodayCrewCard extends StatelessWidget {
  const TodayCrewCard({
    super.key,
    required this.week,
    required this.userId,
    required this.onOpen,
    this.crewName = '',
    this.height = 206,
  });
  final CrewWeek week;
  final String userId;
  final String crewName;
  final VoidCallback onOpen;
  final double height;

  @override
  Widget build(BuildContext context) {
    final checked = week.members
        .where((m) => week.checkedToday(m.id).isNotEmpty)
        .toList();
    final pending = week.members
        .where((m) => week.checkedToday(m.id).isEmpty)
        .toList();
    final total = week.members.length;
    final progress = total == 0 ? 0.0 : checked.length / total;
    final headline = total == 0
        ? 'Build your crew'
        : pending.isEmpty
        ? 'Everyone checked in!'
        : checked.isEmpty
        ? 'Let’s get started'
        : pending.length == 1
        ? 'One more to go'
        : '${pending.length} more to go';
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Transform.translate(
              offset: const Offset(0, 2),
              child: Container(
                key: const ValueKey('crew-title-tab'),
                margin: const EdgeInsets.only(left: 12),
                height: 26,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: const BoxDecoration(
                  color: WeekPactColors.softYellow,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  border: Border(
                    top: BorderSide(color: _ink, width: 2),
                    left: BorderSide(color: _ink, width: 2),
                    right: BorderSide(color: _ink, width: 2),
                  ),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups_2_outlined, size: 16, color: _ink),
                      SizedBox(width: 5),
                      Text(
                        'CREW',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Material(
              key: const ValueKey('crew-board'),
              color: const Color(0xFFFFFBEF),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                side: const BorderSide(color: _ink, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              borderOnForeground: true,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.zero,
                      child: Semantics(
                        label: 'Crew check-in progress',
                        value:
                            '${(progress * 100).round()} percent; ${checked.length} of $total members checked in',
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: progress, end: progress),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => LayoutBuilder(
                            builder: (context, space) => Stack(
                              children: [
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      key: const ValueKey('crew-progress-fill'),
                                      widthFactor: value,
                                      heightFactor: 1,
                                      child: ClipPath(
                                        clipper: _CrewFillClipper(
                                          wavy: value > 0 && value < 1,
                                        ),
                                        child: const ColoredBox(
                                          color: WeekPactColors.lime,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  left: 8,
                                  right: value >= .45
                                      ? space.maxWidth * (1 - value) + 8
                                      : 8,
                                  height: 44,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          headline,
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 23,
                                            height: 1.1,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${checked.length} of $total checked in',
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 54,
                                  bottom: 4,
                                  left: 0,
                                  width: space.maxWidth * value,
                                  child: SizedBox(
                                    key: const ValueKey('checked-members'),
                                    child: _members(context, checked, true),
                                  ),
                                ),
                                Positioned(
                                  top: value >= .45 ? 4 : 54,
                                  bottom: 4,
                                  right: 0,
                                  width: space.maxWidth * (1 - value),
                                  child: SizedBox(
                                    key: const ValueKey('pending-members'),
                                    child: _members(context, pending, false),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 48,
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: _ink, width: 1)),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 2, 4, 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          color: Color(0xFFFF982B),
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${week.streakWeeks} week${week.streakWeeks == 1 ? '' : 's'} streak',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Tooltip(
                              message: 'View week',
                              child: FilledButton(
                                onPressed: onOpen,
                                style: FilledButton.styleFrom(
                                  backgroundColor: WeekPactColors.lavender,
                                  foregroundColor: _ink,
                                  minimumSize: const Size(40, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  side: BorderSide.none,
                                  padding: EdgeInsets.zero,
                                  shape: const CircleBorder(),
                                ),
                                child: const Icon(
                                  Icons.arrow_forward,
                                  size: 24,
                                  semanticLabel: 'Open crew',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _members(
    BuildContext context,
    List<WeekMember> members,
    bool done,
  ) => ClipRect(
    child: LayoutBuilder(
      builder: (context, space) {
        if (members.isEmpty || space.maxWidth < 1) {
          return const SizedBox.shrink();
        }
        if (space.maxWidth < 48) {
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TextButton(
                onPressed: onOpen,
                child: Text(
                  '+${members.length}',
                  style: TextStyle(color: _ink),
                ),
              ),
            ),
          );
        }
        final size = math.min(
          done ? 40.0 : 48.0,
          math.max(1.0, math.min(space.maxWidth - 16, space.maxHeight - 18)),
        );
        final step = size - 7;
        final capacity = math.max(
          1,
          ((space.maxWidth - 16 - size) / math.max(1, step)).floor() + 1,
        );
        final shown = members.length > capacity ? capacity - 1 : members.length;
        final slots = shown + (members.length > shown ? 1 : 0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: done ? Alignment.centerLeft : Alignment.center,
            child: SizedBox(
              width: size + math.max(0, slots - 1) * step,
              height: size + 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < shown; i++)
                    Positioned(
                      left: i * step,
                      top: 0,
                      child: _avatar(context, members[i], done, size),
                    ),
                  if (members.length > shown)
                    Positioned(
                      left: shown * step,
                      top: 0,
                      child: Tooltip(
                        message: 'View ${members.length - shown} more members',
                        child: InkWell(
                          onTap: onOpen,
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEF),
                              shape: BoxShape.circle,
                              border: Border.all(color: _ink, width: 2),
                            ),
                            child: Center(
                              child: FittedBox(
                                child: Text(
                                  '+${members.length - shown}',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _avatar(
    BuildContext context,
    WeekMember member,
    bool done,
    double size,
  ) {
    final ink = _ink;
    final statusColor = done
        ? const Color(0xFF368447)
        : const Color(0xFFD47A20);
    final fallback = Center(
      child: Text(
        member.initials,
        style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w900),
      ),
    );
    return Tooltip(
      message:
          '${member.displayName.isEmpty ? 'Crew member' : member.displayName}${member.id == userId ? ' (you)' : ''}: ${done ? 'Checked in' : 'Not yet'}',
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: ValueKey('crew-avatar-${member.id}'),
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? const Color(0xFF97BA7C) : context.surface,
                        border: Border.all(color: statusColor, width: 3),
                      ),
                      child: ClipOval(
                        child: member.avatarUrl == null
                            ? fallback
                            : Image.network(
                                member.avatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => fallback,
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done
                            ? const Color(0xFF4C9653)
                            : const Color(0xFFFFFBEF),
                        border: Border.all(color: _ink),
                      ),
                      child: done
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 11,
                            )
                          : Icon(Icons.schedule, color: _ink, size: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 13,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  member.displayName.trim().isEmpty
                      ? 'Member'
                      : member.displayName.trim().split(RegExp(r'\s+')).first,
                  style: TextStyle(
                    color: ink,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TodaySkeleton extends StatelessWidget {
  const TodaySkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SkeletonBar(width: 120, height: 28),
      SizedBox(height: 12),
      Expanded(flex: 3, child: SkeletonBar(height: 200)),
      SizedBox(height: 16),
      Expanded(flex: 2, child: SkeletonBar(height: 120)),
    ],
  );
}

/// Rounded inset fill with a soft scalloped boundary between member groups.
class _CrewFillClipper extends CustomClipper<Path> {
  const _CrewFillClipper({required this.wavy});
  final bool wavy;

  @override
  Path getClip(Size size) {
    // The enclosing card clips its outer corners and paints the border.
    if (!wavy || size.width == 0) {
      return Path()..addRect(Offset.zero & size);
    }
    final amplitude = math.min(3.0, size.width / 4);
    final baseline = size.width - amplitude;
    final edge = Path()
      ..moveTo(0, 0)
      ..lineTo(baseline, 0);
    // Three complete sine waves with identical amplitude and wavelength.
    const samples = 144;
    for (var i = 1; i <= samples; i++) {
      final fraction = i / samples;
      edge.lineTo(
        baseline + amplitude * math.sin(fraction * math.pi * 6),
        size.height * fraction,
      );
    }
    edge
      ..lineTo(0, size.height)
      ..close();
    final leftCorners = Path()
      ..addRRect(RRect.fromRectAndCorners(Offset.zero & size));
    return Path.combine(PathOperation.intersect, leftCorners, edge);
  }

  @override
  bool shouldReclip(_CrewFillClipper oldClipper) => oldClipper.wavy != wavy;
}
