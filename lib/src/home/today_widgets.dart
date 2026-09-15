import '../crew/crew_switcher.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'home_surface.dart';
import 'latest_activity_row.dart';
import '../theme/weekpact_theme.dart';

import 'package:card_swiper/card_swiper.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../widgets/page_frame.dart';
import '../widgets/edge_bounce.dart';
import 'home_backend.dart';
import 'crew_member_list.dart';

const _ink = homeInk;
BoxDecoration _panel(
  Color color, [
  double radius = WeekPactMetrics.cardRadius,
]) => BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius));

class CrewTitleBanner extends StatelessWidget {
  static const height = 76.0;
  const CrewTitleBanner({
    super.key,
    required this.name,
    required this.streakWeeks,
    this.onOpen,
    this.selector,
  });
  final Widget? selector;
  final VoidCallback? onOpen;
  final String name;
  final int streakWeeks;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: LayoutBuilder(
      builder: (context, constraints) => OverflowBox(
        minWidth: constraints.maxWidth + 24,
        maxWidth: constraints.maxWidth + 24,
        child: Container(
          key: const ValueKey('crew-title-container'),
          width: constraints.maxWidth + 24,
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
          decoration: BoxDecoration(
            color: context.canvas,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child:
                    selector ??
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CrewControlLabel('YOUR CREW'),
                        const SizedBox(height: 4),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              style: TextStyle(
                                color: context.ink,
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
              SizedBox(
                width: 110,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CrewControlLabel('CREW STREAK'),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: 'View week',
                      child: InkWell(
                        onTap: onOpen,
                        borderRadius: BorderRadius.circular(
                          WeekPactMetrics.cardRadius,
                        ),
                        child: Semantics(
                          label: 'Crew streak',
                          value:
                              '$streakWeeks ${streakWeeks == 1 ? 'week' : 'weeks'}',
                          child: ExcludeSemantics(
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: context.canvas,
                                borderRadius: BorderRadius.circular(
                                  WeekPactMetrics.cardRadius,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x40000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  children: [
                                    HugeIcon(
                                      icon: HugeIconsStrokeRounded.fire,
                                      color: streakWeeks > 0
                                          ? const Color(0xFFE67D45)
                                          : context.muted,
                                      size: 34,
                                    ),
                                    const SizedBox(width: 6),
                                    Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: '$streakWeeks'),
                                          TextSpan(
                                            text: streakWeeks == 1
                                                ? ' week'
                                                : ' weeks',
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      key: const ValueKey('crew-header-streak'),
                                      style: TextStyle(
                                        color: context.ink,
                                        fontSize: 30,
                                        height: 1.1,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
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
            ],
          ),
        ),
      ),
    ),
  );
}

class TodayPactsCard extends StatefulWidget {
  const TodayPactsCard({
    super.key,
    required this.week,
    this.height,
    this.horizontalBleed = 0,
    required this.userId,
    required this.savingPact,
    required this.onToggle,
  });
  final double? height;
  final double horizontalBleed;
  final CrewWeek week;
  final String userId;
  final String? savingPact;
  final ValueChanged<String>? onToggle;
  @override
  State<TodayPactsCard> createState() => _TodayPactsCardState();
}

class _TodayPactsCardState extends State<TodayPactsCard> {
  final _controller = SwiperController();
  int _index = 0;
  List<CrewPact> get _pacts => widget.week.pacts;

  @override
  void didUpdateWidget(covariant TodayPactsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pacts.isEmpty) {
      _index = 0;
      return;
    }
    final previousId = _index < oldWidget.week.pacts.length
        ? oldWidget.week.pacts[_index].id
        : null;
    final retainedIndex = _pacts.indexWhere((pact) => pact.id == previousId);
    final nextIndex = retainedIndex >= 0
        ? retainedIndex
        : math.min(_index, _pacts.length - 1);
    if (nextIndex != _index) {
      _index = nextIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pacts.isNotEmpty) {
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
    final pacts = _pacts;
    if (pacts.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final height = widget.height ?? (370 + math.max(0.0, scale - 1) * 200);
    final cardHeight = math.max(
      80.0,
      math.min(height - 48, 410 + math.max(0.0, scale - 1) * 200),
    );
    final visibleDots = math.min(5, pacts.length);
    final start = math.max(0, math.min(_index - 2, pacts.length - visibleDots));
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
                    child: Text(
                      'TODAY',
                      style: TextStyle(
                        color: context.ink,
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
                      '${pacts.length} ${pacts.length == 1 ? 'pact' : 'pacts'}',
                      key: const ValueKey('pact-position'),
                      style: TextStyle(
                        color: context.muted,
                        fontFamily: 'Roboto',
                        fontFamilyFallback: const ['Arial'],
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
              builder: (context, space) {
                final previewCount = math.min(1, pacts.length - 1);
                final peek = math.min(32.0, space.maxWidth * .085);
                // Keep the same centered card size even when there is no next card.
                final reserve = peek;
                final width = space.maxWidth - reserve * 2;
                final viewportWidth =
                    space.maxWidth + widget.horizontalBleed * 2;
                final previousTravel =
                    (viewportWidth + width) / 2 - peek * .65 + 10;
                return OverflowBox(
                  minWidth: space.maxWidth + widget.horizontalBleed * 2,
                  maxWidth: space.maxWidth + widget.horizontalBleed * 2,
                  // Reserve paint space for the stacked cards during transitions.
                  minHeight: cardHeight + 48,
                  maxHeight: cardHeight + 48,
                  child: EdgeBounce(
                    atStart: _index == 0,
                    atEnd: _index == pacts.length - 1,
                    child: Swiper(
                      key: const ValueKey('pact-stack'),
                      controller: _controller,
                      itemCount: pacts.length,
                      layout: SwiperLayout.STACK,
                      itemWidth: width,
                      itemHeight: cardHeight - 20,
                      axisDirection: AxisDirection.right,
                      scrollDirection: Axis.horizontal,
                      loop: false,
                      autoplay: false,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 280,
                      onIndexChanged: (index) {
                        if (index == _index) return;
                        setState(() => _index = index);
                        unawaited(
                          HapticFeedback.mediumImpact().catchError(
                            (Object _) {},
                          ),
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
                            final depth = ((1 - stackScale) / .1).clamp(
                              0.0,
                              3.0,
                            );
                            // The swiper scales around the right edge. Cancel its
                            // native offset so each rear card exposes one strip.
                            return Transform.translate(
                              key: ValueKey('pact-slide-stack-$index'),
                              offset: stackScale >= 1
                                  // Stop the outgoing card with a narrow strip
                                  // still visible at the left edge of the viewport.
                                  ? Offset(
                                      stackX *
                                          (previousTravel / viewportWidth - 1),
                                      0,
                                    )
                                  : Offset(
                                      (depth * peek - stackX) / stackScale,
                                      (depth * 6 -
                                              (cardHeight - 20) *
                                                  (1 - stackScale) /
                                                  2) /
                                          stackScale,
                                    ),
                              child: IgnorePointer(
                                ignoring: stackX < -.01,
                                child: ExcludeSemantics(
                                  excluding: stackX < -.01,
                                  child: Opacity(
                                    opacity: (previewCount + 1 - depth).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: SizedBox.expand(
                                      child: _PactCompletionEffect(
                                        key: ValueKey(
                                          'completion-${pacts[index].id}',
                                        ),
                                        completed: widget.week
                                            .checkedToday(widget.userId)
                                            .contains(pacts[index].id),
                                        child: _PactCard(
                                          depth: depth,
                                          contentOpacity:
                                              1 -
                                              .8 *
                                                  (-stackX / viewportWidth)
                                                      .clamp(0.0, 1.0),
                                          previewWidth: peek,
                                          stackScale: stackScale,
                                          key: ValueKey(pacts[index].id),
                                          pact: pacts[index],
                                          week: widget.week,
                                          userId: widget.userId,
                                          color:
                                              WeekPactColors.pactPalette[index %
                                                  WeekPactColors
                                                      .pactPalette
                                                      .length],
                                          busy:
                                              widget.savingPact ==
                                              pacts[index].id,
                                          onToggle:
                                              widget.savingPact != null ||
                                                  widget.onToggle == null
                                              ? null
                                              : () => widget.onToggle!(
                                                  pacts[index].id,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (pacts.length > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var dot = start; dot < start + visibleDots; dot++)
                  Semantics(
                    selected: dot == _index,
                    child: IconButton(
                      tooltip: 'Pact ${dot + 1} of ${pacts.length}',
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
                              : context.ink.withValues(alpha: .3),
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
class _PactCompletionEffect extends StatefulWidget {
  const _PactCompletionEffect({
    super.key,
    required this.completed,
    required this.child,
  });
  final bool completed;
  final Widget child;
  @override
  State<_PactCompletionEffect> createState() => _PactCompletionEffectState();
}

class _PactCompletionEffectState extends State<_PactCompletionEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  @override
  void didUpdateWidget(covariant _PactCompletionEffect oldWidget) {
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
                        key: const ValueKey('pact-completion-effect'),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8DBD70).withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(
                            WeekPactMetrics.cardRadius,
                          ),
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
                                child: const HugeIcon(
                                  icon: HugeIconsStrokeRounded.tick02,
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

class _PactCard extends StatelessWidget {
  const _PactCard({
    super.key,
    required this.pact,
    required this.week,
    required this.userId,
    required this.color,
    required this.busy,
    required this.onToggle,
    this.depth = 0,
    this.contentOpacity = 1,
    this.previewWidth = 40,
    this.stackScale = 1,
  });
  final double depth;
  final double contentOpacity;
  final double previewWidth;
  final double stackScale;
  final CrewPact pact;
  final CrewWeek week;
  final String userId;
  final Color color;
  final bool busy;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final checked = week.checkedToday(userId).contains(pact.id);
    final start = DateTime.parse(week.weekStart);
    final completed = week.days(pact.id, userId);
    return HomeSurface(
      tint: color,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumHeight =
              382 +
              math.max(0.0, MediaQuery.textScalerOf(context).scale(1) - 1) *
                  340;
          final shrink =
              constraints.maxHeight /
              math.max(minimumHeight, constraints.maxHeight);
          final reveal = (1 - depth).clamp(0.0, 1.0);
          final content = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              // Compensate for height scaling so the calendar and
              // action still span the entire inner width of the active card.
              width: constraints.maxWidth / shrink,
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
                            message: pact.title,
                            child: Text(
                              pact.title,
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
                        const SizedBox(width: 72, height: 60),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topLeft,
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
                                        '/ ${pact.daysPerWeek}',
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
                                    fontFamily: 'Roboto',
                                    fontFamilyFallback: ['Arial'],
                                    fontSize: 18,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Semantics(
                              key: ValueKey('pact-progress-${pact.id}'),
                              label: 'Weekly pact progress',
                              value: '$completed of ${pact.daysPerWeek} days',
                              child: Row(
                                children: List.generate(
                                  pact.daysPerWeek,
                                  (i) => Expanded(
                                    child: Container(
                                      height: 10,
                                      margin: EdgeInsets.only(
                                        right: i == pact.daysPerWeek - 1
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
                              c.pactId == pact.id &&
                              c.userId == userId &&
                              c.day == day,
                        );
                        final future = day.compareTo(week.today) > 0;
                        final current = day == week.today;
                        return Expanded(
                          child: Semantics(
                            label:
                                '$day${current ? ', today' : ''}: ${done
                                    ? 'completed'
                                    : future
                                    ? 'upcoming'
                                    : 'not completed'}',
                            child: Container(
                              key: ValueKey('pact-day-${pact.id}-$day'),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: done
                                    ? WeekPactColors.mintGreen
                                    : Colors.white.withValues(alpha: .35),
                                border: Border.all(
                                  color: _ink.withValues(
                                    alpha: current ? .65 : .06,
                                  ),
                                  width: current ? 2 : 1,
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
                                      fontFamily: 'Roboto',
                                      fontFamilyFallback: ['Arial'],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${date.day}',
                                    key: ValueKey('pact-date-${pact.id}-$day'),
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontFamilyFallback: const ['Arial'],
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
                                        ? const HugeIcon(
                                            icon: HugeIconsStrokeRounded
                                                .checkmarkCircle02,
                                            color: Color(0xFF4C8050),
                                            size: 12,
                                          )
                                        : future
                                        ? const SizedBox.shrink()
                                        : HugeIcon(
                                            icon: HugeIconsStrokeRounded.circle,
                                            color: _ink.withValues(
                                              alpha: current ? .7 : .3,
                                            ),
                                            size: 12,
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
                    if (checked)
                      _CompletedCheckIn(
                        pactTitle: pact.title,
                        busy: busy,
                        onUndo: onToggle,
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: ValueKey('check-in-${pact.title}'),
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
                              : HugeIcon(
                                  icon: HugeIconsStrokeRounded.circle,
                                  size: 22,
                                ),
                          label: Text(
                            'Check in',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Roboto',
                              fontFamilyFallback: ['Arial'],
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
          final fullIconSize = 60 * shrink;
          // Keep preview icons inside the exposed strip, then grow them around
          // the same top-right anchor as their card becomes active.
          final previewSize = math.min(
            fullIconSize * .6,
            math.max(8.0, previewWidth - 16),
          );
          final renderedIconSize = depth <= 1
              ? fullIconSize + (previewSize - fullIconSize) * depth
              : previewSize * (1 - .25 * (depth - 1)).clamp(.5, 1.0);
          final iconSize = renderedIconSize / stackScale;
          // Fade foreground content with the gesture while retaining the card tint.
          return Opacity(
            key: ValueKey('pact-content-opacity-${pact.id}'),
            opacity: contentOpacity,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                ExcludeSemantics(
                  excluding: reveal < 1,
                  child: IgnorePointer(
                    ignoring: reveal < 1,
                    child: Opacity(opacity: reveal, child: content),
                  ),
                ),
                Positioned(
                  // Preserve the icon’s inset so stacked previews stay visible.
                  right: -6,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      key: ValueKey('pact-icon-${pact.id}'),
                      width: iconSize,
                      height: iconSize,
                      decoration: _panel(
                        color == WeekPactColors.cream
                            ? WeekPactColors.mintGreen
                            : Color.lerp(color, _ink, .06)!,
                        10 * shrink,
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: PactIcon.find(pact.iconKey).data,
                          color: _ink,
                          size: iconSize * .6,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompletedCheckIn extends StatelessWidget {
  const _CompletedCheckIn({
    required this.pactTitle,
    required this.busy,
    required this.onUndo,
  });

  final String pactTitle;
  final bool busy;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      color: WeekPactColors.mintGreen,
      borderRadius: BorderRadius.circular(8),
    ),
    padding: const EdgeInsets.only(left: 10, right: 4),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HugeIcon(
                    icon: HugeIconsStrokeRounded.checkmarkCircle02,
                    color: Color(0xFF4C8050),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Checked in today',
                      style: TextStyle(
                        color: _ink,
                        fontFamily: 'Roboto',
                        fontFamilyFallback: ['Arial'],
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(width: 1, height: 24, color: _ink.withValues(alpha: .10)),
        SizedBox(
          width: 56,
          height: 48,
          child: Tooltip(
            message: 'Undo check-in',
            child: TextButton(
              key: ValueKey('check-in-$pactTitle'),
              onPressed: busy ? null : onUndo,
              style: TextButton.styleFrom(
                foregroundColor: _ink,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4C8050),
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontFamilyFallback: ['Arial'],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
  );
}

class TodayCrewCard extends StatelessWidget {
  const TodayCrewCard({
    super.key,
    required this.week,
    required this.userId,
    required this.onOpen,
    this.crewName = '',
    this.height = groupHeight + headingHeight,
    this.showGroups = true,
  });
  final CrewWeek week;
  final String userId;
  final String crewName;
  final VoidCallback onOpen;
  final double height;
  final bool showGroups;
  static const groupHeight = 106.0;
  static const headingHeight = 24.0;

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
          SizedBox(
            height: headingHeight,
            child: Align(
              alignment: Alignment.topLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'TODAY’S CHECK-INS',
                  style: TextStyle(
                    color: context.muted,
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const ['Arial'],
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, space) {
                if (!showGroups) return const SizedBox.shrink();
                if (checked.isEmpty || pending.isEmpty) {
                  final allCheckedIn = checked.isNotEmpty;
                  return SizedBox(
                    key: ValueKey(
                      allCheckedIn ? 'checked-tile' : 'pending-tile',
                    ),
                    width: double.infinity,
                    child: CrewCheckInTile(
                      userId: userId,
                      onOpen: onOpen,
                      members: allCheckedIn ? checked : pending,
                      done: allCheckedIn,
                      awaitingFirstCheckIn: !allCheckedIn,
                      everyoneCheckedIn: allCheckedIn,
                    ),
                  );
                }
                final available = math.max(0.0, space.maxWidth - 6);
                final total = checked.length + pending.length;
                final minimum = math.min(140.0, available / 2);
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
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          key: const ValueKey('checked-tile'),
                          width: checkedWidth,
                          child: CrewCheckInTile(
                            userId: userId,
                            onOpen: onOpen,
                            members: checked,
                            done: true,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          key: const ValueKey('pending-tile'),
                          width: available - checkedWidth,
                          child: CrewCheckInTile(
                            userId: userId,
                            onOpen: onOpen,
                            members: pending,
                            done: false,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CrewCheckInTile extends StatelessWidget {
  const CrewCheckInTile({
    super.key,
    required this.members,
    required this.done,
    required this.userId,
    required this.onOpen,
    this.awaitingFirstCheckIn = false,
    this.everyoneCheckedIn = false,
    this.expansion = 0,
    this.showDetails = false,
    this.expandedHeight = TodayCrewCard.groupHeight,
    this.backend,
    this.crewId,
  });
  final List<WeekMember> members;
  final bool done;
  final bool awaitingFirstCheckIn;
  final bool everyoneCheckedIn;
  final String userId;
  final VoidCallback onOpen;
  final double expansion;
  final bool showDetails;
  final double expandedHeight;
  final HomeBackend? backend;
  final String? crewId;
  String get title =>
      '${done ? 'Checked in today' : 'Not yet today'} · ${members.length}';

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: showDetails ? MouseCursor.defer : SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: showDetails ? null : onOpen,
      child: HomeSurface(
        tint: done ? WeekPactColors.mintGreen : WeekPactColors.cream,
        outlined: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: title,
                  excludeSemantics: true,
                  button: true,
                  hint: showDetails ? 'Collapse members' : 'Show all members',
                  child: InkWell(
                    splashFactory: NoSplash.splashFactory,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: SizedBox(
                        height: MediaQuery.textScalerOf(context).scale(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${done
                                    ? everyoneCheckedIn
                                          ? 'EVERYONE SHOWED UP'
                                          : 'CHECKED IN'
                                    : awaitingFirstCheckIn
                                    ? 'LET’S GET STARTED'
                                    : 'NOT YET'} · ${members.length}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _ink,
                                  fontFamily: 'Roboto',
                                  fontSize: 12,
                                  height: 1.1,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ExcludeSemantics(
                              child: RotatedBox(
                                quarterTurns: showDetails ? 2 : 0,
                                child: const HugeIcon(
                                  icon: HugeIconsStrokeRounded.arrowDown01,
                                  color: Color(0xFF555A53),
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: showDetails
                      ? ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            minHeight:
                                expandedHeight -
                                16 -
                                MediaQuery.textScalerOf(context).scale(20),
                            maxHeight:
                                expandedHeight -
                                16 -
                                MediaQuery.textScalerOf(context).scale(20),
                            child: Opacity(
                              opacity: expansion,
                              child: _memberList(context),
                            ),
                          ),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onOpen,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SizedBox(
                              key: ValueKey(
                                done ? 'checked-members' : 'pending-members',
                              ),
                              child: members.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (done) ...[
                                                const HugeIcon(
                                                  icon: HugeIconsStrokeRounded
                                                      .hourglass,
                                                  color: Color(0xFF748368),
                                                  size: 26,
                                                ),
                                                const SizedBox(height: 4),
                                              ],
                                              Text(
                                                done
                                                    ? 'No one yet'
                                                    : 'All checked in',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Color(0xFF555A53),
                                                  fontFamily: 'Roboto',
                                                  fontFamilyFallback: ['Arial'],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  : _members(context, members, done),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _memberList(BuildContext context) => CrewMemberList(
    members: members,
    done: done,
    userId: userId,
    backend: backend,
    crewId: crewId,
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
                style: TextButton.styleFrom(
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: Colors.transparent,
                ),
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
        final step = size + 10;
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
                          splashFactory: NoSplash.splashFactory,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          hoverColor: Colors.transparent,
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
                                    fontFamily: 'Roboto',
                                    fontFamilyFallback: ['Arial'],
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
    final fallback = Center(
      child: Text(
        member.initials,
        style: TextStyle(
          color: ink,
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['Arial'],
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
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
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: homePaper,
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
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const ['Arial'],
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

class TodaySkeleton extends StatefulWidget {
  const TodaySkeleton({super.key});
  @override
  State<TodaySkeleton> createState() => _TodaySkeletonState();
}

class _TodaySkeletonState extends State<TodaySkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final _opacity = Tween<double>(
    begin: .65,
    end: 1,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _line(double width, double height) => Align(
    alignment: Alignment.centerLeft,
    child: SkeletonBar(width: width, height: height),
  );

  Widget _crewTile(Color color) => Expanded(
    child: HomeSurface(
      tint: color,
      outlined: false,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line(85, 13),
          const Spacer(),
          const Center(child: SkeletonBar(width: 44, height: 44, radius: 22)),
          const SizedBox(height: 8),
          Center(child: SizedBox(width: 36, child: _line(36, 8))),
          const Spacer(),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your home',
    liveRegion: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: CrewTitleBanner.height,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _line(72, 8),
                          const SizedBox(height: 10),
                          _line(145, 22),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _line(90, 8),
                        const SizedBox(height: 8),
                        _line(72, 22),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              HomeSurface(
                key: const ValueKey('skeleton-latest-activity'),
                tint: WeekPactColors.activitySurface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  height: LatestActivityRow.height,
                  child: Row(
                    children: [
                      const Expanded(child: SkeletonBar(height: 12)),
                      const SizedBox(width: 16),
                      const SkeletonBar(width: 40, height: 10),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('skeleton-crew-board'),
                height: TodayCrewCard.groupHeight + TodayCrewCard.headingHeight,
                child: Column(
                  children: [
                    const SizedBox(height: TodayCrewCard.headingHeight),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _crewTile(WeekPactColors.mintGreen),
                          const SizedBox(width: 6),
                          _crewTile(WeekPactColors.cream),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 24,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SkeletonBar(width: 50, height: 14),
                          SkeletonBar(width: 42, height: 12),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 42,
                              right: 0,
                              top: 6,
                              bottom: 6,
                              child: HomeSurface(
                                tint: WeekPactColors.pactPalette[1],
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      28,
                                      8,
                                      0,
                                    ),
                                    child: SkeletonBar(
                                      width: 24,
                                      height: 24,
                                      radius: 7,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              left: 32,
                              right: 32,
                              child: HomeSurface(
                                key: const ValueKey('skeleton-pact-card'),
                                tint: WeekPactColors.pactPalette.first,
                                padding: const EdgeInsets.all(12),
                                child: LayoutBuilder(
                                  builder: (context, space) => Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: _line(150, 20)),
                                            const SizedBox(width: 12),
                                            SkeletonBar(
                                              width: math.min(
                                                44,
                                                space.maxHeight * .16,
                                              ),
                                              height: math.min(
                                                44,
                                                space.maxHeight * .16,
                                              ),
                                              radius: 10,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _line(
                                              110,
                                              math.min(
                                                58,
                                                space.maxHeight * .18,
                                              ),
                                            ),
                                            SizedBox(
                                              height: space.maxHeight * .02,
                                            ),
                                            _line(
                                              100,
                                              math.min(
                                                13,
                                                space.maxHeight * .05,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SkeletonBar(
                                        height: math.min(
                                          10,
                                          space.maxHeight * .04,
                                        ),
                                      ),
                                      Spacer(),
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          children: [
                                            for (
                                              var day = 0;
                                              day < 7;
                                              day++
                                            ) ...[
                                              if (day > 0)
                                                const SizedBox(width: 5),
                                              Expanded(
                                                child: SkeletonBar(
                                                  height: double.infinity,
                                                  radius: 8,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: space.maxHeight * .04),
                                      SkeletonBar(
                                        height: math.min(
                                          48,
                                          space.maxHeight * .16,
                                        ),
                                        radius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 24,
                      child: Center(child: SkeletonBar(width: 32, height: 6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
