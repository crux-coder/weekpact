import '../widgets/avatar_shape.dart';
import '../crew/crew_switcher.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'home_surface.dart';
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

/// A completed day or check-in: a cream inset with a green mark, legible on
/// every card tint. The raised edge is mixed per card from its own colour.
const _doneFill = WeekPactColors.cream;
const _doneMark = WeekPactColors.doneMark;

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
    child: Padding(
      key: const ValueKey('crew-title-container'),
      padding: const EdgeInsets.only(top: 7, bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_streak(context), const SizedBox(width: 10), _crew(context)],
      ),
    ),
  );

  Widget _crew(BuildContext context) => Expanded(
    child:
        selector ??
        CrewHeaderSurface(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
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
        ),
  );

  Widget _streak(BuildContext context) => SizedBox(
    width: 100,
    child: CrewHeaderSurface(
      child: Tooltip(
        message: 'View week',
        child: Semantics(
          label: 'Crew streak',
          value: '$streakWeeks ${streakWeeks == 1 ? 'week' : 'weeks'}',
          button: onOpen != null,
          child: InkWell(
            onTap: onOpen,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CrewControlLabel('CREW STREAK'),
                    const SizedBox(height: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            HugeIcon(
                              icon: HugeIconsStrokeRounded.fire,
                              color: streakWeeks > 0
                                  ? WeekPactColors.streak
                                  : context.muted,
                              size: 28,
                              strokeWidth: 2,
                            ),
                            const SizedBox(width: 6),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '$streakWeeks'),
                                  TextSpan(
                                    text: streakWeeks == 1 ? ' week' : ' weeks',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              key: const ValueKey('crew-header-streak'),
                              style: TextStyle(
                                color: context.ink,
                                fontSize: 28,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
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
                      'YOUR PACTS',
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
                        fontFamily: WeekPactType.secondary,
                        fontFamilyFallback: WeekPactType.secondaryFallback,
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
                // Keep card width stable even when there is no next card.
                final reserve = peek;
                final width = space.maxWidth - reserve * 2;
                final viewportWidth =
                    space.maxWidth + widget.horizontalBleed * 2;
                final previousTravel =
                    (viewportWidth + width) / 2 - peek * .65 - 2;
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
                                              (previousTravel / viewportWidth -
                                                  1) -
                                          12,
                                      0,
                                    )
                                  : Offset(
                                      (depth * peek - stackX - 12) / stackScale,
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
                                          color: WeekPactColors.pactTint(index),
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
                          borderRadius: WeekPactMetrics.pill,
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

/// One short pop when a check-in lands. It runs after the check-in drawer has
/// finished closing, and the buzz comes from the save itself.
class _PactCompletionEffectState extends State<_PactCompletionEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_animation);

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
    builder: (context, child) => Transform.scale(
      scale: _animation.isAnimating ? _scale.value : 1.0,
      child: child,
    ),
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
    // Completion reads as a cream inset with a green mark, so the cue works on
    // every card tint instead of fighting the warm ones. Its edge is mixed from
    // the card's own colour, which keeps the raised edge in family.
    final doneEdge = Color.lerp(color, Colors.black, .35)!;
    return HomeSurface(
      tint: color,
      radius: WeekPactMetrics.cardCorner,
      raised: true,
      depth: WeekPactMetrics.cardDepth,
      shape: WeekPactMetrics.pactCardShape,
      outlineColor: Color.lerp(color, Colors.black, .28),
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
                        const SizedBox(width: 72, height: 52),
                      ],
                    ),
                    const SizedBox(height: 10),
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
                                    fontFamily: WeekPactType.secondary,
                                    fontFamilyFallback:
                                        WeekPactType.secondaryFallback,
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
                                            : _ink.withValues(alpha: .20),
                                        borderRadius: WeekPactMetrics.pill,
                                        border: i < completed
                                            ? Border.all(
                                                color: WeekPactColors.inkEdge,
                                              )
                                            : null,
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
                              decoration: BoxDecoration(
                                color: done
                                    ? _doneFill
                                    : Colors.white.withValues(alpha: .35),
                                border: Border.all(
                                  color: _ink.withValues(
                                    alpha: current ? .75 : 0,
                                  ),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(
                                  WeekPactMetrics.controlRadius,
                                ),
                                boxShadow: done
                                    ? [
                                        BoxShadow(
                                          color: doneEdge,
                                          offset: WeekPactMetrics.raisedOffset,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
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
                                      style: TextStyle(
                                        fontWeight: current
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        fontFamily: WeekPactType.secondary,
                                        fontFamilyFallback:
                                            WeekPactType.secondaryFallback,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${date.day}',
                                      key: ValueKey(
                                        'pact-date-${pact.id}-$day',
                                      ),
                                      style: TextStyle(
                                        fontFamily: WeekPactType.secondary,
                                        fontFamilyFallback:
                                            WeekPactType.secondaryFallback,
                                        fontSize: 16,
                                        fontWeight: current
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: _ink.withValues(
                                          alpha: future ? .65 : 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      height: 12,
                                      child: done
                                          ? const HugeIcon(
                                              icon: HugeIconsStrokeRounded
                                                  .checkmarkCircle02,
                                              color: _doneMark,
                                              size: 12,
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    if (checked)
                      _CompletedCheckIn(
                        pactTitle: pact.title,
                        busy: busy,
                        onUndo: onToggle,
                        edge: doneEdge,
                      )
                    else
                      Container(
                        width: double.infinity,
                        decoration: const ShapeDecoration(
                          shape: WeekPactMetrics.buttonShape,
                          shadows: [
                            BoxShadow(
                              color: WeekPactColors.inkEdge,
                              offset: WeekPactMetrics.raisedOffset,
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          key: ValueKey('check-in-${pact.title}'),
                          onPressed: onToggle,
                          style: FilledButton.styleFrom(
                            backgroundColor: _ink,
                            foregroundColor: homePaper,
                            minimumSize: const Size(0, 48),
                            shape: WeekPactMetrics.buttonShape.copyWith(
                              side: const BorderSide(
                                color: WeekPactColors.inkEdge,
                              ),
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
                              fontFamily: WeekPactType.secondary,
                              fontFamilyFallback:
                                  WeekPactType.secondaryFallback,
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
          // Give the strip behind the active card a readable weekly score.
          // Both edges of its reveal are eased so the digits never kink or
          // overshoot while the gesture drags the stack back and forth: they
          // glide onto the rule as the card falls into the second slot and
          // leave with the icon as it is drawn forward.
          final peekReveal =
              Curves.easeInOut.transform(
                ((depth - .55) / .45).clamp(0.0, 1.0),
              ) *
              Curves.easeInOut.transform(
                (1 - (depth - 1) / .55).clamp(0.0, 1.0),
              );
          // Hold the type at its strip size instead of following the icon, which
          // grows to full size as the card comes forward.
          final readoutFont = previewSize * .95 / stackScale;
          // Fade faster than the digits travel, so the pair is gone before it
          // is close enough to read as one smudged glyph.
          final peekOpacity = peekReveal * peekReveal;
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
                  // Preserve the icon’s spacing so stacked previews stay visible.
                  right: -6,
                  top: 0,
                  child: IgnorePointer(
                    child: SizedBox(
                      key: ValueKey('pact-icon-${pact.id}'),
                      width: iconSize,
                      height: iconSize,

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
                if (peekReveal > 0)
                  Positioned(
                    key: ValueKey('pact-peek-score-${pact.id}'),
                    right: -6,
                    // Ride just under the icon so the two never collide while
                    // the icon is still growing or shrinking.
                    top: iconSize + 4 / stackScale,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Opacity(
                          opacity: peekOpacity,
                          child: SizedBox(
                            width: iconSize,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: Offset(
                                    0,
                                    readoutFont * .38 * (1 - peekReveal),
                                  ),
                                  child: _PeekNumeral(
                                    value: completed,
                                    size: readoutFont,
                                  ),
                                ),
                                // The rule draws itself outward from the centre
                                // as the two numerals close in on it.
                                Container(
                                  height: 1.5,
                                  width: previewSize * .62 / stackScale,
                                  margin: EdgeInsets.symmetric(
                                    vertical: readoutFont * .12,
                                  ),
                                  transform: Matrix4.diagonal3Values(
                                    peekReveal,
                                    1,
                                    1,
                                  ),
                                  transformAlignment: Alignment.center,
                                  color: _ink.withValues(
                                    alpha: .55 * peekOpacity,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(
                                    0,
                                    -readoutFont * .38 * (1 - peekReveal),
                                  ),
                                  child: _PeekNumeral(
                                    value: pact.daysPerWeek,
                                    size: readoutFont * .86,
                                    alpha: .7,
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
          );
        },
      ),
    );
  }
}

/// A single digit in the stacked score shown on a card's exposed strip.
class _PeekNumeral extends StatelessWidget {
  const _PeekNumeral({required this.value, required this.size, this.alpha = 1});

  final int value;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Text(
    '$value',
    maxLines: 1,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontFamily: WeekPactType.secondary,
      fontFamilyFallback: WeekPactType.secondaryFallback,
      fontSize: size,
      height: 1,
      fontWeight: FontWeight.w900,
      color: _ink.withValues(alpha: alpha),
    ),
  );
}

class _CompletedCheckIn extends StatelessWidget {
  const _CompletedCheckIn({
    required this.pactTitle,
    required this.busy,
    required this.onUndo,
    required this.edge,
  });

  final Color edge;

  final String pactTitle;
  final bool busy;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    decoration: ShapeDecoration(
      color: _doneFill,
      shape: WeekPactMetrics.buttonShape.copyWith(
        side: BorderSide(color: edge),
      ),
      shadows: [BoxShadow(color: edge, offset: WeekPactMetrics.raisedOffset)],
    ),
    padding: const EdgeInsets.only(left: 10),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HugeIcon(
                    icon: HugeIconsStrokeRounded.checkmarkCircle02,
                    color: _doneMark,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Checked in today',
                      style: TextStyle(
                        color: _ink,
                        fontFamily: WeekPactType.secondary,
                        fontFamilyFallback: WeekPactType.secondaryFallback,
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
        Container(width: 1, height: 20, color: _ink.withValues(alpha: .10)),
        SizedBox(
          width: 80,
          height: 56,
          child: Tooltip(
            message: 'Undo check-in',
            child: TextButton(
              key: ValueKey('check-in-$pactTitle'),
              onPressed: busy ? null : onUndo,
              style: TextButton.styleFrom(
                foregroundColor: _ink,
                minimumSize: const Size(80, 56),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                shape: const ContinuousRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(WeekPactMetrics.panelCurve),
                  ),
                ),
              ),
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _doneMark,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          fontFamily: WeekPactType.secondary,
                          fontFamilyFallback: WeekPactType.secondaryFallback,
                          fontSize: 13,
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

/// The crew's freshest check-in, in the strip above the crew tiles. It is the
/// one line on Home that changes without the viewer doing anything, so it opens
/// the feed rather than restating what the tiles below already show.
class LatestCheckInStrip extends StatelessWidget {
  const LatestCheckInStrip({
    super.key,
    required this.week,
    required this.userId,
    this.now,
    this.onOpenFeed,
  });

  final CrewWeek week;
  final String userId;
  final DateTime? now;
  final VoidCallback? onOpenFeed;

  /// How long ago, at the coarseness a feed reads at.
  static String age(DateTime at, DateTime now) {
    final elapsed = now.difference(at);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final activity = week.latestActivity;
    final member = week.members
        .where((m) => m.id == activity?.userId)
        .firstOrNull;
    final pact = week.pacts.where((p) => p.id == activity?.pactId).firstOrNull;
    final hasActivity = activity != null && member != null;
    final name = activity?.userId == userId
        ? 'You'
        : member == null || member.displayName.trim().isEmpty
        ? 'A crew member'
        : member.displayName.trim().split(RegExp(r'\s+')).first;
    final detail = hasActivity
        ? '${pact?.title ?? 'a pact'} · ${age(activity.createdAt, now ?? DateTime.now())}'
        : null;
    final message = hasActivity
        ? '$name checked in'
        : 'Nobody has checked in yet today';
    final open = onOpenFeed;
    return Semantics(
      button: open != null,
      label: hasActivity
          ? 'Latest check-in: $message · $detail'
          : 'Latest check-in: $message',
      hint: open == null ? null : 'Open the feed',
      child: ExcludeSemantics(
        // Its own surface, so the crew's latest reads as a thing to open rather
        // than a caption on the tiles below it.
        child: CrewHeaderSurface(
          child: InkWell(
            onTap: open,
            child: Padding(
              key: const ValueKey('latest-check-in'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (hasActivity) ...[
                    FlatAvatar(
                      radius: 13,
                      backgroundColor: WeekPactColors.mintGreen,
                      child: AvatarClip(
                        child: member.avatarUrl == null
                            ? Text(
                                member.initials,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 10,
                                ),
                              )
                            : Image.network(
                                member.avatarUrl!,
                                width: 26,
                                height: 26,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(
                                  member.initials,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      // Text.rich, not RichText: the latter ignores the ambient
                      // text style and would fall back to the platform font.
                      child: Text.rich(
                        maxLines: 1,
                        TextSpan(
                          style: TextStyle(
                            color: context.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          children: [
                            TextSpan(text: message),
                            if (detail != null)
                              TextSpan(
                                text: '  ·  $detail',
                                style: TextStyle(
                                  color: context.muted,
                                  fontFamily: WeekPactType.secondary,
                                  fontFamilyFallback:
                                      WeekPactType.secondaryFallback,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (open != null) ...[
                    const SizedBox(width: 8),
                    HugeIcon(
                      icon: HugeIconsStrokeRounded.arrowRight01,
                      color: context.muted,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
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
    this.height = groupHeight + headingHeight,
    this.showGroups = true,
    this.onOpenFeed,
    this.now,
  });
  final CrewWeek week;
  final String userId;
  final String crewName;
  final VoidCallback onOpen;
  final VoidCallback? onOpenFeed;
  final DateTime? now;
  final double height;
  final bool showGroups;
  // A count, its caption and a row of faces — no taller than that needs.
  static const groupHeight = 86.0;
  // The latest-check-in surface plus the gap to the tiles below it.
  static const headingHeight = 54.0;

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
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LatestCheckInStrip(
                week: week,
                userId: userId,
                now: now,
                onOpenFeed: onOpenFeed,
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

  /// The tile's raised edge, shared by its surface, faces and overflow chip.
  static Color _tileEdge(bool done) =>
      done ? WeekPactColors.mintEdge : WeekPactColors.pendingEdge;

  /// Beyond this the stack stops being faces and becomes a number.
  static const _maxFaces = 3;
  static const _faceSize = 34.0;
  static const _minFaceSize = 24.0;
  static const _overlap = .62;

  /// The words under the count.
  String get caption => everyoneCheckedIn
      ? 'whole crew is in'
      : awaitingFirstCheckIn
      ? 'be the first in today'
      : done
      ? 'checked in'
      : 'not yet';

  /// The tile's own words. When one side is empty the tile speaks for the whole
  /// crew, so a bare count would read as a scoreline nobody asked for.
  String get label => everyoneCheckedIn
      ? 'Whole crew is in'
      : awaitingFirstCheckIn
      ? 'Be the first in today'
      : '${done ? 'Checked in' : 'Not yet'} · ${members.length}';
  String get title => everyoneCheckedIn
      ? 'Whole crew is in today'
      : awaitingFirstCheckIn
      ? 'Nobody has checked in today · ${members.length} to go'
      : '${done ? 'Checked in today' : 'Not yet today'} · ${members.length}';

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: title,
    button: true,
    expanded: showDetails,
    onTap: onOpen,
    hint: showDetails ? 'Collapse members' : 'Show all members',
    child: MouseRegion(
      cursor: showDetails ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: showDetails ? null : onOpen,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: WeekPactMetrics.pactCardShape,
            shadows: [
              BoxShadow(
                color: _tileEdge(done),
                offset: WeekPactMetrics.raisedOffset,
              ),
            ],
          ),
          child: HomeSurface(
            tint: done
                ? WeekPactColors.mintGreen
                : WeekPactColors.pendingCheckIns,
            radius: WeekPactMetrics.cardCorner,
            shape: WeekPactMetrics.pactCardShape,
            outlined: true,
            outlineColor: _tileEdge(done),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDetails)
                      SizedBox(
                        height: 36,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontFamily: WeekPactType.secondary,
                                        fontFamilyFallback:
                                            WeekPactType.secondaryFallback,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (showDetails)
                                IconButton(
                                  tooltip: 'Collapse members',
                                  onPressed: onOpen,
                                  icon: const HugeIcon(
                                    icon: HugeIconsStrokeRounded.arrowUp01,
                                    size: 16,
                                    color: WeekPactColors.mutedLight,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: showDetails
                          ? ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: expandedHeight - 36,
                                maxHeight: expandedHeight - 36,
                                child: Opacity(
                                  opacity: expansion,
                                  child: _memberList(context),
                                ),
                              ),
                            )
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onOpen,
                              child: _collapsed(context),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// Collapsed, the tile leads with the count and lets faces fill the rest.
  /// Nobody on this side means the count would be a zero nobody asked for, so
  /// the state's own words take the whole tile instead.
  Widget _collapsed(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: members.isEmpty
        ? Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                done ? 'No one yet' : 'All checked in',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WeekPactColors.mutedLight,
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 12,
                ),
              ),
            ),
          )
        : Row(
            key: ValueKey(done ? 'checked-members' : 'pending-members'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                // Scale the count and its caption together, so a large text
                // setting shrinks the block instead of overflowing the tile.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${members.length}',
                        key: ValueKey(done ? 'checked-count' : 'pending-count'),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: _ink,
                          fontFamily: WeekPactType.secondary,
                          fontFamilyFallback: WeekPactType.secondaryFallback,
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _faces(context)),
            ],
          ),
  );

  /// Overlapping faces, as many as the tile can hold, with the remainder as a
  /// “+n” chip. Past that the chip stands alone — the expanded list is where
  /// a big crew is actually read.
  Widget _faces(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      if (space.maxWidth < 24 || space.maxHeight < 20) {
        return const SizedBox.shrink();
      }
      // Faces overlap, so each extra one costs well under its own width. Fit as
      // many slots as the tile allows, shrinking the faces before dropping one,
      // and never below a size that still reads as a person.
      final maxSize = math.min(_faceSize, space.maxHeight);
      var slots = math.min(_maxFaces, members.length);
      var size = maxSize;
      while (slots > 0) {
        size = math.min(maxSize, space.maxWidth / (1 + (slots - 1) * _overlap));
        if (size >= _minFaceSize) break;
        slots--;
      }
      // Too narrow for a face: the count chip carries the whole crew.
      if (slots == 0) {
        if (space.maxWidth < 20) return const SizedBox.shrink();
        slots = 1;
        size = math.min(maxSize, space.maxWidth);
      }
      final shown = members.length <= slots ? members.length : slots - 1;
      final overflow = members.length - shown;
      slots = shown + (overflow > 0 ? 1 : 0);
      final step = size * _overlap;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: size + (slots - 1) * step,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < shown; i++)
                Positioned(
                  key: ValueKey('crew-member-${members[i].id}'),
                  left: i * step,
                  child: _avatar(context, members[i], done, size),
                ),
              if (overflow > 0)
                Positioned(
                  left: shown * step,
                  child: Tooltip(
                    message: shown == 0
                        ? 'View all ${members.length} members'
                        : 'View $overflow more members',
                    child: Container(
                      key: const ValueKey('crew-overflow'),
                      width: size,
                      height: size,
                      decoration: ShapeDecoration(
                        color: WeekPactColors.cream,
                        shape: AvatarShape(
                          side: BorderSide(color: _ink.withValues(alpha: .25)),
                        ),
                        shadows: [
                          BoxShadow(
                            color: _tileEdge(done),
                            offset: WeekPactMetrics.raisedOffset,
                          ),
                        ],
                      ),
                      child: Center(
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '+$overflow',
                              style: const TextStyle(
                                color: _ink,
                                fontFamily: WeekPactType.secondary,
                                fontFamilyFallback:
                                    WeekPactType.secondaryFallback,
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
      );
    },
  );

  Widget _memberList(BuildContext context) => CrewMemberList(
    members: members,
    done: done,
    userId: userId,
    backend: backend,
    crewId: crewId,
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
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
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
                      decoration: ShapeDecoration(
                        shape: const AvatarShape(),
                        color: homePaper,
                        shadows: [
                          BoxShadow(
                            color: _tileEdge(done),
                            offset: WeekPactMetrics.raisedOffset,
                          ),
                        ],
                      ),
                      child: AvatarClip(
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

  Widget _line(double width, double height, {Color? color}) => Align(
    alignment: Alignment.centerLeft,
    child: SkeletonBar(width: width, height: height, color: color),
  );

  Widget _crewTile(Color color) => Expanded(
    child: HomeSurface(
      tint: color,
      radius: WeekPactMetrics.cardCorner,
      shape: WeekPactMetrics.pactCardShape,
      raised: true,
      outlineColor: color == WeekPactColors.mintGreen
          ? WeekPactColors.mintEdge
          : WeekPactColors.pendingEdge,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      // The loaded tile leads with a count and trails with faces.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [_line(22, 26), const SizedBox(height: 6), _line(46, 8)],
          ),
          const Spacer(),
          const SkeletonBar(width: 34, height: 34, shape: AvatarShape()),
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 7, bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CrewHeaderSurface(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _line(62, 8),
                                const SizedBox(height: 8),
                                _line(145, 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 100,
                        child: CrewHeaderSurface(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _line(70, 8),
                                const SizedBox(height: 8),
                                _line(64, 20),
                              ],
                            ),
                          ),
                        ),
                      ),
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
                    SizedBox(
                      height: TodayCrewCard.headingHeight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SkeletonBar(width: 132, height: 8),
                          SkeletonBar(width: 22, height: 22),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _crewTile(WeekPactColors.mintGreen),
                          const SizedBox(width: 6),
                          _crewTile(WeekPactColors.pendingCheckIns),
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
                          SkeletonBar(width: 88, height: 14),
                          SkeletonBar(width: 42, height: 12),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: LayoutBuilder(
                          builder: (context, bounds) {
                            final peek = math.min(32.0, bounds.maxWidth * .085);
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: peek + 18,
                                  right: 12,
                                  top: 6,
                                  bottom: 6,
                                  child: HomeSurface(
                                    tint: WeekPactColors.pactPalette[1],
                                    shape: WeekPactMetrics.pactCardShape,
                                    raised: true,
                                    depth: WeekPactMetrics.cardDepth,
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
                                          shape: WeekPactMetrics.buttonShape,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  left: peek - 12,
                                  right: peek + 12,
                                  child: HomeSurface(
                                    key: const ValueKey('skeleton-pact-card'),
                                    tint: WeekPactColors.pactPalette.first,
                                    shape: WeekPactMetrics.pactCardShape,
                                    raised: true,
                                    depth: WeekPactMetrics.cardDepth,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
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
                                                  shape: WeekPactMetrics
                                                      .buttonShape,
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
                                          Row(
                                            children: [
                                              for (var i = 0; i < 5; i++) ...[
                                                if (i > 0)
                                                  const SizedBox(width: 5),
                                                Expanded(
                                                  child: SkeletonBar(
                                                    height: math.min(
                                                      10,
                                                      space.maxHeight * .04,
                                                    ),
                                                    radius: 3,
                                                  ),
                                                ),
                                              ],
                                            ],
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
                                          SizedBox(
                                            height: space.maxHeight * .04,
                                          ),
                                          SkeletonBar(
                                            height: math.min(
                                              48,
                                              space.maxHeight * .16,
                                            ),
                                            shape: WeekPactMetrics.buttonShape,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
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
