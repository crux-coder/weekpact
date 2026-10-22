import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../home/home_backend.dart';
import '../theme/weekpact_theme.dart';
import 'crew_month_calendar.dart';
import 'crew_switcher.dart';

/// Hugeicons' rounded flame, filled rather than outlined, so the streak's
/// number can stand inside it.
final _solidFlame = [
  for (final element in HugeIconsStrokeRounded.fire02)
    [
      element[0],
      {...(element[1] as Map<String, dynamic>), 'fill': 'currentColor'},
    ],
];

/// The crew's streak on Home, in three equal parts: the flame with the weeks
/// kept in a row; the last six weeks as bars against the full week a streak
/// needs; and this month as squircles — one per day, filled where the crew was
/// out, outlined on today, faintly outlined for the days still to come.
/// "View month" in the header opens the month in photos.
class CrewStreakCard extends StatelessWidget {
  const CrewStreakCard({
    super.key,
    required this.week,
    required this.history,
    required this.onViewMonth,
  });
  final CrewWeek week;

  /// The crew's finished weeks, newest first, for the days of this month
  /// before this week. Null while they are not in hand; those days then read
  /// as not out.
  final List<CrewWeekSummary>? history;
  final VoidCallback onViewMonth;

  /// The card's height, which holds a month of six weeks, so it stands the
  /// same from one month to the next and Home does not move under it: the
  /// header, six rows of dots, and as little around them as reads as a card.
  static const height = 132.0;

  static const _dot = 9.0;
  static const _dotGap = 5.0;
  static const _flame = 56.0;

  /// How many weeks the bars show, this one included, and their size.
  static const _barWeeks = 6;
  static const _barWidth = 9.0;
  static const _barGap = 5.0;
  static const _barHeight = 58.0;

  /// How much of the crew was out on [day]: from this week's own check-ins
  /// while it runs, from the history before that, and null for a day neither
  /// covers.
  double? _shareOn(DateTime day) {
    final iso = day.toIso8601String().substring(0, 10);
    if (iso.compareTo(week.weekStart) >= 0) {
      return iso.compareTo(week.today) <= 0 ? week.shareOut(iso) : null;
    }
    final monday = mondayOf(day).toIso8601String().substring(0, 10);
    final past = history?.where((w) => w.weekStart == monday).firstOrNull;
    return past?.shareOut.elementAtOrNull(day.weekday - DateTime.monday);
  }

  /// The pact the crew kept most on [day], from the same two sources as
  /// [_shareOn]. Null where nobody kept one, or where the history does not
  /// say.
  String? _topPactOn(DateTime day) {
    final iso = day.toIso8601String().substring(0, 10);
    if (iso.compareTo(week.weekStart) >= 0) {
      return iso.compareTo(week.today) <= 0 ? week.topPact(iso) : null;
    }
    final monday = mondayOf(day).toIso8601String().substring(0, 10);
    final past = history?.where((w) => w.weekStart == monday).firstOrNull;
    return past?.topPacts.elementAtOrNull(day.weekday - DateTime.monday);
  }

  @override
  Widget build(BuildContext context) {
    final weeks = week.streakWeeks;
    final today = DateTime.parse(week.today);
    final month = DateTime(today.year, today.month);
    final flame = weeks > 0
        ? WeekPactColors.streak
        : WeekPactColors.pendingEdge;
    // Home does not scroll, so a narrow phone or larger system text lays the
    // card out at the room it wants and scales it back into its slot.
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = math.max(
            1.0,
            MediaQuery.textScalerOf(context).scale(1),
          );
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: math.max(box.maxWidth, _minWidth) * scale,
              height: height * scale,
              child: _card(context, weeks, today, month, flame),
            ),
          );
        },
      ),
    );
  }

  /// The narrowest the card is laid out at: the flame and a week of dots
  /// side by side, with room between them.
  static const _minWidth = 320.0;

  Widget _card(
    BuildContext context,
    int weeks,
    DateTime today,
    DateTime month,
    Color flame,
  ) {
    // The crew header's recessed surface, the one the crew's week stood on
    // here before, rather than a paper card of its own.
    return CrewHeaderSurface(
      curve: WeekPactMetrics.cardCurve,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      'Streak',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('streak-view-month'),
                  onPressed: () {
                    unawaited(
                      HapticFeedback.lightImpact().catchError((Object _) {}),
                    );
                    onViewMonth();
                  },
                  style: TextButton.styleFrom(
                    // The card's own ink, like the title beside it: this is
                    // a way into the month, not a mark of anything done.
                    foregroundColor: context.ink,
                    padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: WeekPactMetrics.buttonShape,
                    textStyle: const TextStyle(
                      fontFamily: WeekPactType.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('View month'),
                      const SizedBox(width: 2),
                      // Down, not right: the month opens as a sheet over Home,
                      // not as a page Home is left for.
                      HugeIcon(
                        icon: HugeIconsStrokeRounded.arrowDown01,
                        size: 16,
                        color: context.ink,
                        strokeWidth: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                // The three parts share the card evenly, so its right edge
                // keeps the same margin as its left.
                padding: const EdgeInsets.only(right: 10),
                child: Semantics(
                  label:
                      'Crew streak: $weeks ${weeks == 1 ? 'week' : 'weeks'}. '
                      '${week.percentCrew} per cent of this week kept. '
                      '${_daysOut(month, today)} days out this month',
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: _flame,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    HugeIcon(
                                      icon: _solidFlame,
                                      size: _flame,
                                      color: flame,
                                    ),
                                    // The flame's body is low and round;
                                    // the number sits in it, not in the
                                    // tip.
                                    Align(
                                      alignment: const Alignment(0, .42),
                                      child: Text(
                                        '$weeks',
                                        style: const TextStyle(
                                          color: WeekPactColors.cream,
                                          fontSize: 19,
                                          height: 1,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                weeks == 1 ? 'Week' : 'Weeks',
                                style: TextStyle(
                                  color: flame,
                                  fontSize: 16,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _divider(context),
                        Expanded(child: Center(child: _weekBars(context))),
                        _divider(context),
                        Expanded(
                          child: Center(
                            child: _monthDots(context, month, today),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The hairline between two of the card's three parts.
  Widget _divider(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(vertical: 8),
    color: context.ink.withValues(alpha: .10),
  );

  /// The last six weeks, oldest at the left and this one at the right, each
  /// as tall as the share of it the crew kept, under a dashed line where a
  /// full week stands. A week only joins the streak when it reaches that line,
  /// so the weeks that did take the flame's colour and the rest stay grey.
  /// This week, still running, is drawn in ink so it reads as where you are.
  Widget _weekBars(BuildContext context) {
    final past = [
      for (final w in history ?? const <CrewWeekSummary>[])
        if (w.weekStart.compareTo(week.weekStart) < 0) (w.weekStart, w.percent),
    ].take(_barWeeks - 1).toList().reversed;
    final weeks = [...past, (week.weekStart, week.percentCrew)];
    Widget bar(String weekStart, int percent, {required bool current}) {
      final kept = percent >= 100;
      return Container(
        key: ValueKey('streak-week-bar-$weekStart'),
        width: _barWidth,
        height: math.max(3, _barHeight * percent.clamp(0, 100) / 100),
        decoration: ShapeDecoration(
          color: kept
              ? WeekPactColors.streak
              : current
              ? context.ink.withValues(alpha: .6)
              : context.ink.withValues(alpha: .22),
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(_barWidth * .6),
          ),
        ),
      );
    }

    final width = _barWeeks * _barWidth + (_barWeeks - 1) * _barGap;
    return Column(
      key: const ValueKey('streak-week-bars'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: _barHeight,
          child: CustomPaint(
            // Over the bars, so a kept week meets the line rather than
            // hiding it.
            foregroundPainter: _FullWeekLine(
              context.ink.withValues(alpha: .35),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Fewer weeks than the bars hold leaves the oldest places
                // empty, so this week always stands at the right.
                for (var i = 0; i < _barWeeks - weeks.length; i++) ...[
                  SizedBox(
                    key: ValueKey('streak-week-empty-$i'),
                    width: _barWidth,
                  ),
                  const SizedBox(width: _barGap),
                ],
                for (final (i, (weekStart, percent)) in weeks.indexed) ...[
                  if (i > 0) const SizedBox(width: _barGap),
                  bar(weekStart, percent, current: i == weeks.length - 1),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '$_barWeeks weeks',
          style: TextStyle(
            color: context.muted,
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  int _daysOut(DateTime month, DateTime today) => [
    for (var d = 1; d <= today.day; d++)
      _shareOn(DateTime(month.year, month.month, d)),
  ].where((share) => (share ?? 0) > 0).length;

  Widget _monthDots(BuildContext context, DateTime month, DateTime today) {
    final ink = context.ink;
    Widget dot(DateTime day) {
      if (day.month != month.month) {
        return const SizedBox.square(dimension: _dot);
      }
      final isToday = day == today;
      final future = day.isAfter(today);
      final out = !future && (_shareOn(day) ?? 0) > 0;
      // A day the crew was out wears the badge colour of the pact it kept
      // most, the deeper of the pact's pair, which holds up as a dot on both
      // themes. A day whose pact is not to hand stays in ink.
      final top = out
          ? week.pacts.indexWhere((p) => p.id == _topPactOn(day))
          : -1;
      final fill = top >= 0 ? WeekPactColors.pactBadge(top) : ink;
      // A squircle, like the app's cards and tiles, at the corner a card
      // this small reads as.
      return Container(
        key: ValueKey('streak-day-${day.toIso8601String().substring(0, 10)}'),
        width: _dot,
        height: _dot,
        decoration: ShapeDecoration(
          color: out
              ? fill
              : future || isToday
              ? null
              : ink.withValues(alpha: .07),
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(_dot * .6),
            side: isToday && !out
                ? BorderSide(color: ink, width: 2)
                : future
                ? BorderSide(color: ink.withValues(alpha: .12), width: 1.5)
                : BorderSide.none,
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final monday in monthWeeks(month)) ...[
          if (monday != monthWeeks(month).first)
            const SizedBox(height: _dotGap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: _dotGap),
                dot(DateTime(monday.year, monday.month, monday.day + i)),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The dashed line along the top of the week bars: a full week, the height a
/// week has to reach to join the streak.
class _FullWeekLine extends CustomPainter {
  const _FullWeekLine(this.color);
  final Color color;

  static const _dash = 3.0;
  static const _space = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = -2.0; x < size.width + 2; x += _dash + _space) {
      canvas.drawLine(
        Offset(x, .75),
        Offset(math.min(x + _dash, size.width + 2), .75),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FullWeekLine old) => old.color != color;
}
