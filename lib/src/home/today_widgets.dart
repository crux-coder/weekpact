import 'dart:async';

import 'package:flutter/services.dart';

import 'home_surface.dart';

import 'package:card_swiper/card_swiper.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../goals/goal_icons.dart';
import '../goals/goals_backend.dart';
import '../widgets/page_frame.dart';
import 'home_backend.dart';

const _ink = homeInk;
BoxDecoration _panel(Color color, [double radius = 12]) =>
    BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius));

class CrewTitleBanner extends StatelessWidget {
  const CrewTitleBanner({
    super.key,
    required this.name,
    required this.completed,
    required this.target,
  });
  final String name;
  final int completed;
  final int target;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: LayoutBuilder(
      builder: (context, constraints) => OverflowBox(
        minWidth: constraints.maxWidth + 24,
        maxWidth: constraints.maxWidth + 24,
        child: Container(
          key: const ValueKey('crew-title-container'),
          width: constraints.maxWidth + 24,
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
          decoration: BoxDecoration(
            color: const Color(0xFF191B19),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'YOUR CREW',
                        style: TextStyle(
                          color: Color(0xFFB8BEB5),
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: homePaper,
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SizedBox(
                width: 36,
                height: 32,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'THIS\nWEEK',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Color(0xFFB8BEB5),
                      fontSize: 10,
                      height: 1.25,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Your week: $completed of $target check-ins',
                child: Semantics(
                  label: 'Your weekly progress',
                  value: '$completed of $target check-ins',
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: 44,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: target == 0
                              ? 0
                              : (completed / target).clamp(0.0, 1.0),
                        ),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 350),
                        builder: (context, progress, _) => Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 3,
                                strokeCap: StrokeCap.round,
                                color: const Color(0xFFD0E5BA),
                                backgroundColor: homePaper.withValues(
                                  alpha: .14,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${(progress * 100).round()}%',
                                  style: const TextStyle(
                                    color: homePaper,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
            height: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        color: homePaper,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(_index + 1).toString().padLeft(2, '0')} / ${goals.length.toString().padLeft(2, '0')}',
                      key: const ValueKey('goal-position'),
                      style: const TextStyle(
                        color: Color(0xFFB8BEB5),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: cardHeight,
            child: LayoutBuilder(
              builder: (context, space) => OverflowBox(
                minWidth: space.maxWidth + widget.horizontalBleed * 2,
                maxWidth: space.maxWidth + widget.horizontalBleed * 2,
                // Reserve paint space for the stacked cards during transitions.
                minHeight: cardHeight + 48,
                maxHeight: cardHeight + 48,
                child: Swiper(
                  key: const ValueKey('goal-stack'),
                  controller: _controller,
                  itemCount: goals.length,
                  layout: SwiperLayout.STACK,
                  itemWidth: space.maxWidth,
                  itemHeight: cardHeight - 20,
                  axisDirection: AxisDirection.right,
                  scrollDirection: Axis.horizontal,
                  loop: goals.length > 1,
                  autoplay: false,
                  duration: MediaQuery.disableAnimationsOf(context) ? 0 : 280,
                  onIndexChanged: (index) {
                    if (index == _index) return;
                    setState(() => _index = index);
                    unawaited(
                      HapticFeedback.selectionClick().catchError((Object _) {}),
                    );
                  },
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 2,
                    ),
                    child: Builder(
                      builder: (context) {
                        // Follow the stack's interpolated transforms, rather
                        // than snapping offsets when the selected index changes.
                        var stackScale = 1.0;
                        var stackX = 0.0;
                        var transforms = 0;
                        context.visitAncestorElements((element) {
                          final ancestor = element.widget;
                          if (ancestor is Transform) {
                            if (transforms == 0) {
                              stackScale = ancestor.transform.storage[0];
                            } else {
                              stackX = ancestor.transform.storage[12];
                            }
                            transforms++;
                          }
                          return transforms < 2;
                        });
                        final depth = (1 - stackScale) / .1;
                        return Transform.translate(
                          key: ValueKey('goal-slide-stack-$index'),
                          offset: stackScale >= 1
                              ? Offset.zero
                              : Offset(
                                  -(space.maxWidth * (1 - stackScale) / 2 +
                                          stackX) /
                                      stackScale,
                                  ((cardHeight - 20) * (1 - stackScale) / 2 +
                                          depth * 7) /
                                      stackScale,
                                ),
                          child: SizedBox.expand(
                            child: _GoalCompletionEffect(
                              key: ValueKey('completion-${goals[index].id}'),
                              completed: widget.week
                                  .checkedToday(widget.userId)
                                  .contains(goals[index].id),
                              child: _GoalCard(
                                key: ValueKey(goals[index].id),
                                goal: goals[index],
                                week: widget.week,
                                userId: widget.userId,
                                color: [
                                  const Color(0xFFF5F6F5),
                                  const Color(0xFFF4D88F),
                                  const Color(0xFFE0EED4),
                                ][widget.week.goals.indexOf(goals[index]) % 3],
                                busy: widget.savingGoal == goals[index].id,
                                onToggle:
                                    widget.savingGoal != null ||
                                        widget.onToggle == null
                                    ? null
                                    : () => widget.onToggle!(goals[index].id),
                              ),
                            ),
                          ),
                        );
                      },
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
                              ? homePaper
                              : homePaper.withValues(alpha: .3),
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

/// Celebrates a confirmed state change, never the tap or an initial load.
class _GoalCompletionEffect extends StatefulWidget {
  const _GoalCompletionEffect({
    super.key,
    required this.completed,
    required this.child,
  });
  final bool completed;
  final Widget child;
  @override
  State<_GoalCompletionEffect> createState() => _GoalCompletionEffectState();
}

class _GoalCompletionEffectState extends State<_GoalCompletionEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  @override
  void didUpdateWidget(covariant _GoalCompletionEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.completed) _animation.stop();
    if (widget.completed &&
        !oldWidget.completed &&
        !MediaQuery.disableAnimationsOf(context)) {
      _animation.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _animation.stop();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) {
      final active = _animation.isAnimating;
      final pulse = active ? math.sin(_animation.value * math.pi) : 0.0;
      return Transform.scale(
        scale: 1 - pulse * .018,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (active)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: pulse,
                      child: Container(
                        key: const ValueKey('goal-completion-effect'),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8DBD70).withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF80AB64),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(0, -12 * _animation.value),
                            child: Transform.scale(
                              scale:
                                  .85 +
                                  .15 *
                                      Curves.easeOut.transform(
                                        _animation.value,
                                      ),
                              child: Container(
                                width: 58,
                                height: 58,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD0E5BA),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF375D31),
                                  size: 34,
                                ),
                              ),
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
      );
    },
  );
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
    return HomeSurface(
      tint: color,
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumHeight =
              362 +
              math.max(0.0, MediaQuery.textScalerOf(context).scale(1) - 1) *
                  340;
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: goal.title,
                            child: Text(
                              goal.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 25,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: _panel(const Color(0xFFE1E5DC), 12),
                          child: Center(
                            child: HugeIcon(
                              icon: GoalIcon.find(goal.iconKey).data,
                              color: _ink,
                              size: 30,
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
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '$completed',
                                        style: const TextStyle(
                                          fontSize: 84,
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '/ ${goal.daysPerWeek}',
                                        style: const TextStyle(
                                          fontSize: 54,
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Text(
                                  'days this week',
                                  style: TextStyle(
                                    fontSize: 18,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
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
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: current
                                    ? const Color(0xFFD0E5BA)
                                    : Colors.white.withValues(alpha: .35),
                                border: Border.all(
                                  color: _ink.withValues(
                                    alpha: current ? .18 : .06,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(8),
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
                                  Text(
                                    '${date.day}',
                                    key: ValueKey('goal-date-${goal.id}-$day'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: current
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      color: _ink.withValues(
                                        alpha: future ? .4 : 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 12,
                                    child: done
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: Color(0xFF4C8050),
                                            size: 12,
                                          )
                                        : Center(
                                            child: Container(
                                              width: current ? 12 : 3,
                                              height: 3,
                                              decoration: BoxDecoration(
                                                color: _ink.withValues(
                                                  alpha: current ? .7 : .12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(2),
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
                          foregroundColor: homePaper,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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
    return SizedBox(
      key: const ValueKey('crew-board'),
      height: height,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, space) {
                final available = math.max(0.0, space.maxWidth - 6);
                final total = checked.length + pending.length;
                final minimum = math.min(96.0, available / 2);
                final fraction = total == 0 ? .5 : checked.length / total;
                final targetWidth = (available * fraction).clamp(
                  minimum,
                  available - minimum,
                );
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: targetWidth, end: targetWidth),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, width, _) {
                    final checkedWidth = width.clamp(
                      minimum,
                      available - minimum,
                    );
                    return CustomPaint(
                      foregroundPainter: _CrewConnectionPainter(checkedWidth),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            key: const ValueKey('checked-tile'),
                            width: checkedWidth,
                            child: _groupTile(
                              context,
                              title: 'Checked in · ${checked.length}',
                              members: checked,
                              done: true,
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            key: const ValueKey('pending-tile'),
                            width: available - checkedWidth,
                            child: _groupTile(
                              context,
                              title: 'Not yet · ${pending.length}',
                              members: pending,
                              done: false,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(
            height: 42,
            child: Row(
              children: [
                const Icon(
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
                      style: const TextStyle(color: homePaper, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      message: 'View week',
                      child: TextButton(
                        onPressed: onOpen,
                        style: TextButton.styleFrom(
                          foregroundColor: homePaper,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open crew',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 5),
                              Icon(Icons.north_east, size: 16),
                            ],
                          ),
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
    );
  }

  Widget _groupTile(
    BuildContext context, {
    required String title,
    required List<WeekMember> members,
    required bool done,
  }) => HomeSurface(
    tint: done ? const Color(0xFFD0E5BA) : const Color(0xFFF5F6F5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            height: 22,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              key: ValueKey(done ? 'checked-members' : 'pending-members'),
              child: members.isEmpty
                  ? Center(
                      child: Text(
                        done ? 'No check-ins yet' : 'All checked in',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF646B60),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : _members(context, members, done),
            ),
          ),
        ),
      ],
    ),
  );

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
          48.0,
          math.max(1.0, math.min(space.maxWidth - 16, space.maxHeight - 18)),
        );
        final step = size * .72;
        final capacity = math.max(
          1,
          ((space.maxWidth - 16 - size) / math.max(1, step)).floor() + 1,
        );
        final shown = members.length > capacity ? capacity - 1 : members.length;
        final slots = shown + (members.length > shown ? 1 : 0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: size + math.max(0, slots - 1) * step,
              height: size + 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < shown; i++)
                    Positioned(
                      key: ValueKey('crew-member-${members[i].id}'),
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
                              color: const Color(0xFFF7F3E9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _ink.withValues(alpha: .25),
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
        ? const Color(0xFF4C8C5D)
        : const Color(0xFFC48A42);
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
                        shape: BoxShape.circle,
                        color: homePaper,
                        border: Border.all(color: statusColor, width: 1),
                      ),
                      child: ClipOval(
                        child: member.avatarUrl == null
                            ? fallback
                            : Image.network(
                                member.avatarUrl!,
                                gaplessPlayback: true,
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

/// Joins the facing edges without changing either tile's layout or hit targets.
class _CrewConnectionPainter extends CustomPainter {
  const _CrewConnectionPainter(this.split);
  final double split;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height < 48) return;
    final left = split - 1;
    final right = split + 7;
    final middle = split + 3;
    const top = 18.0;
    final bottom = size.height - top;
    final upper = Path()
      ..moveTo(left, top)
      ..cubicTo(left, top + 12, right, top + 12, right, top);
    final lower = Path()
      ..moveTo(right, bottom)
      ..cubicTo(right, bottom - 12, left, bottom - 12, left, bottom);
    final bridge = Path()
      ..addPath(upper, Offset.zero)
      ..lineTo(right, bottom)
      ..cubicTo(right, bottom - 12, left, bottom - 12, left, bottom)
      ..close();
    canvas.save();
    canvas.clipPath(bridge);
    canvas.drawRect(
      Rect.fromLTRB(left, top, middle, bottom),
      Paint()..color = const Color(0xFFD0E5BA),
    );
    canvas.drawRect(
      Rect.fromLTRB(middle, top, right, bottom),
      Paint()..color = const Color(0xFFF5F6F5),
    );
    canvas.restore();
    final outline = Paint()
      ..color = homeInk.withValues(alpha: .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(upper, outline);
    canvas.drawPath(lower, outline);
  }

  @override
  bool shouldRepaint(covariant _CrewConnectionPainter oldDelegate) =>
      split != oldDelegate.split;
}
