// card_swiper exposes the transformer option but does not re-export its builder.
// ignore: implementation_imports
import 'package:card_swiper/src/transformer_page_view/transformer_page_view.dart';

import 'home_glass.dart';

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

const _ink = Color(0xFFF6F3FF);
BoxDecoration _panel(Color color, [double radius = 18]) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [color.withValues(alpha: .28), color.withValues(alpha: .08)],
  ),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white.withValues(alpha: .3)),
);

class CrewTitleBanner extends StatelessWidget {
  const CrewTitleBanner({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Row(
      children: [
        HomeGlassSurface(
          radius: 16,
          padding: const EdgeInsets.all(12),
          child: const HugeIcon(
            icon: HugeIconsStrokeRounded.userGroup,
            color: _ink,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'YOUR CREW',
                style: TextStyle(
                  color: Color(0xFFBDB7D8),
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class TodayGoalsCard extends StatefulWidget {
  const TodayGoalsCard({
    super.key,
    required this.week,
    this.height,
    this.horizontalBleed = 0,
    required this.userId,
    required this.savingGoal,
    required this.onToggle,
  });
  final double? height;
  final double horizontalBleed;
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
  List<CrewGoal> get _goals => widget.week.goals;

  @override
  void didUpdateWidget(covariant TodayGoalsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_goals.isEmpty) {
      _index = 0;
      return;
    }
    final previousId = _index < oldWidget.week.goals.length
        ? oldWidget.week.goals[_index].id
        : null;
    final retainedIndex = _goals.indexWhere((goal) => goal.id == previousId);
    final nextIndex = retainedIndex >= 0
        ? retainedIndex
        : math.min(_index, _goals.length - 1);
    if (nextIndex != _index) {
      _index = nextIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _goals.isNotEmpty) {
          _controller.move(_index, animation: false);
        }
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
              builder: (context, space) => OverflowBox(
                minWidth: space.maxWidth + widget.horizontalBleed * 2,
                maxWidth: space.maxWidth + widget.horizontalBleed * 2,
                child: Swiper(
                  key: const ValueKey('goal-stack'),
                  controller: _controller,
                  itemCount: goals.length,
                  layout: SwiperLayout.DEFAULT,
                  viewportFraction:
                      space.maxWidth *
                      (goals.length > 1 ? .84 : 1) /
                      (space.maxWidth + widget.horizontalBleed * 2),
                  transformer: PageTransformerBuilder(
                    builder: (child, info) {
                      final position = (info.position ?? 0).clamp(-1.0, 1.0);
                      final reduced = MediaQuery.disableAnimationsOf(context);
                      final angle = reduced ? 0.0 : -position * .42;
                      final scale = reduced ? 1.0 : 1 - position.abs() * .12;
                      return Transform(
                        key: ValueKey('goal-coverflow-${info.index}'),
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0012)
                          ..rotateY(angle)
                          ..scaleByDouble(scale, scale, 1, 1),
                        child: IgnorePointer(
                          ignoring: position.abs() > .5,
                          child: child,
                        ),
                      );
                    },
                  ),
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
                              ? _ink
                              : Colors.white.withValues(alpha: .25),
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
    return HomeGlassSurface(
      tint: color,
      backingOpacity: .96,
      padding: const EdgeInsets.all(18),
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
                          decoration: _panel(WeekPactColors.lavender, 16),
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
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: current
                                      ? const [
                                          Color(0xB77F52D8),
                                          Color(0x905038A6),
                                        ]
                                      : const [
                                          Color(0x285F658F),
                                          Color(0x153F4166),
                                        ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: current ? .4 : .18,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(24),
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
                                          ? const Color(0xFF488E7D)
                                          : Colors.transparent,
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
                          backgroundColor: const Color(0xFFD5C7FF),
                          foregroundColor: const Color(0xFF28213F),
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
    this.height = 180,
    this.animate = true,
  });
  final CrewWeek week;
  final String userId;
  final String crewName;
  final VoidCallback onOpen;
  final double height;
  final bool animate;

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
          Expanded(
            child: HomeGlassSurface(
              key: const ValueKey('crew-board'),
              radius: 26,
              sheen: .1,
              tint: const Color(0xFF94B5D7),
              child: Column(
                children: [
                  Container(
                    key: const ValueKey('crew-status-header'),
                    height: 42,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0x0FFFFFFF),
                      border: Border(
                        bottom: BorderSide(color: Color(0x35FFFFFF)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              headline,
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${checked.length} of $total checked in',
                              style: const TextStyle(
                                color: Color(0xFFD6D2EA),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                                      child: _FlowingCrewFill(
                                        wavy: value > 0 && value < 1,
                                        animate: animate,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  bottom: 4,
                                  left: 0,
                                  width: space.maxWidth * value,
                                  child: SizedBox(
                                    key: const ValueKey('checked-members'),
                                    child: _members(context, checked, true),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
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
                      border: Border(
                        top: BorderSide(color: Color(0x35FFFFFF), width: 1),
                      ),
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
                              style: const TextStyle(color: _ink, fontSize: 13),
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
                                  backgroundColor: const Color(0xFFCAB8FA),
                                  foregroundColor: const Color(0xFF28213F),
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
                              color: const Color(0xFF34354F),
                              borderRadius: BorderRadius.circular(size * .32),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .25),
                              ),
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
        ? const Color(0xFF88E2B5)
        : const Color(0xFFFFC27B);
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
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(size * .32),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: .24),
                            statusColor.withValues(alpha: .16),
                            const Color(0x80403D60),
                          ],
                        ),
                        border: Border.all(
                          color: statusColor.withValues(alpha: .55),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(size * .25),
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
                    fontWeight: FontWeight.w500,
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

class _FlowingCrewFill extends StatefulWidget {
  const _FlowingCrewFill({required this.wavy, required this.animate});
  final bool wavy;
  final bool animate;
  @override
  State<_FlowingCrewFill> createState() => _FlowingCrewFillState();
}

class _FlowingCrewFillState extends State<_FlowingCrewFill>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _FlowingCrewFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final enabled =
        widget.animate &&
        widget.wavy &&
        _resumed &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled && !_phase.isAnimating) _phase.repeat();
    if (!enabled) _phase.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ClipPath(
      clipper: _CrewFillClipper(wavy: widget.wavy, phase: _phase),
      child: const ColoredBox(color: Color(0x9034BD83)),
    ),
  );
}

// Uniform flowing edge for the progress fill.
Path _crewWaveEdge(Size size, double phase) {
  final amplitude = math.min(3.0, size.width / 4);
  final baseline = size.width - amplitude;
  final edge = Path()
    ..moveTo(baseline + amplitude * math.sin(phase * math.pi * 2), 0);
  for (var i = 1; i <= 144; i++) {
    final fraction = i / 144;
    edge.lineTo(
      baseline + amplitude * math.sin((fraction * 3 + phase) * math.pi * 2),
      size.height * fraction,
    );
  }
  return edge;
}

class _CrewFillClipper extends CustomClipper<Path> {
  _CrewFillClipper({required this.wavy, required this.phase})
    : super(reclip: phase);
  final bool wavy;
  final Animation<double> phase;
  @override
  Path getClip(Size size) {
    if (!wavy || size.isEmpty) return Path()..addRect(Offset.zero & size);
    return _crewWaveEdge(size, phase.value)
      ..lineTo(0, size.height)
      ..lineTo(0, 0)
      ..close();
  }

  @override
  bool shouldReclip(_CrewFillClipper old) =>
      old.wavy != wavy || old.phase != phase;
}
