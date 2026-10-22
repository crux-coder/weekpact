import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../home/home_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import 'crew_pact_week_card.dart';

/// The Monday on or before [day].
DateTime mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

String _isoDay(DateTime day) => day.toIso8601String().substring(0, 10);

/// The months by name, January first.
const crewMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The Mondays of every week that has a day in [month], first to last.
List<DateTime> monthWeeks(DateTime month) {
  final last = DateTime(month.year, month.month + 1, 0);
  return [
    for (
      var monday = mondayOf(DateTime(month.year, month.month));
      !monday.isAfter(last);
      monday = DateTime(monday.year, monday.month, monday.day + 7)
    )
      monday,
  ];
}

/// The crew's month as a calendar: a row per week, a square per day shaded by
/// how much of the crew was out, and the week's crew progress on the right. A
/// week the whole crew kept is wrapped in the podium's gold. A finished week
/// is a raised row with a chevron, and opens with [onOpenWeek]; the live one
/// is the page above, so it stays flat and does not.
///
/// Months slide in from the side they were stepped to, by the chevrons or by
/// a swipe across the calendar.
class CrewMonthCalendar extends StatefulWidget {
  const CrewMonthCalendar({
    super.key,
    required this.month,
    required this.weeks,
    required this.current,
    required this.onOpenWeek,
    this.onPrevious,
    this.onNext,
    this.headerHeight = 44,
  });

  /// The first of the month on show.
  final DateTime month;

  /// Finished weeks, by their Monday as `yyyy-MM-dd`.
  final Map<String, CrewWeekSummary> weeks;

  /// The week in progress, drawn from its own check-ins up to today.
  final CrewWeek current;

  final ValueChanged<CrewWeekSummary> onOpenWeek;

  /// Null when there is no month that way.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// The header's height, which is what shows under the fold.
  final double headerHeight;

  @override
  State<CrewMonthCalendar> createState() => _CrewMonthCalendarState();
}

class _CrewMonthCalendarState extends State<CrewMonthCalendar> {
  static const _slide = Duration(milliseconds: 420);

  /// Which way the last step went: 1 forward in time, -1 back.
  int _direction = 1;

  @override
  void didUpdateWidget(CrewMonthCalendar old) {
    super.didUpdateWidget(old);
    if (widget.month != old.month) {
      _direction = widget.month.isAfter(old.month) ? 1 : -1;
    }
  }

  void _step(VoidCallback? action) {
    if (action == null) return;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    action();
  }

  /// The incoming month slides in from the side it was stepped to and the
  /// outgoing one leaves by the other, both fading, so the two never read as
  /// one calendar.
  Widget _transition(Widget child, Animation<double> animation, Key current) {
    final incoming = child.key == current;
    final from = Offset((incoming ? 1 : -1) * _direction * .35, 0);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: from, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }

  static Widget _stackTop(Widget? current, List<Widget> previous) =>
      Stack(alignment: Alignment.topCenter, children: [...previous, ?current]);

  @override
  Widget build(BuildContext context) {
    final month = widget.month;
    final today = DateTime.parse(widget.current.today);
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : _slide;
    // The year is said only once the month is not this year's.
    final title = month.year == today.year
        ? crewMonthNames[month.month - 1]
        : '${crewMonthNames[month.month - 1]} ${month.year}';
    final key = ValueKey(month);
    return Column(
      key: const ValueKey('crew-month-calendar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.headerHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: duration,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) =>
                        _transition(child, animation, key),
                    child: Text(
                      title,
                      key: key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              CrewMonthButton(
                tooltip: 'Previous month',
                icon: HugeIconsStrokeRounded.arrowLeft01,
                onPressed: widget.onPrevious == null
                    ? null
                    : () => _step(widget.onPrevious),
              ),
              const SizedBox(width: 8),
              CrewMonthButton(
                tooltip: 'Next month',
                icon: HugeIconsStrokeRounded.arrowRight01,
                onPressed: widget.onNext == null
                    ? null
                    : () => _step(widget.onNext),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          // A swipe across the calendar steps months the way the chevrons do.
          onHorizontalDragEnd: (drag) {
            final velocity = drag.velocity.pixelsPerSecond.dx;
            if (velocity > 300) _step(widget.onPrevious);
            if (velocity < -300) _step(widget.onNext);
          },
          child: AppSurface(
            fillColor: WeekPactColors.neutralInset,
            builder: (context) => Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: _WeekGrid(
                      trailing: const SizedBox.shrink(),
                      children: [
                        for (final day in const [
                          'M',
                          'T',
                          'W',
                          'T',
                          'F',
                          'S',
                          'S',
                        ])
                          Center(
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: WeekPactColors.mutedLight,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // A month of five weeks and one of six differ by a row; the
                  // card eases between them rather than jumping.
                  ClipRect(
                    child: AnimatedSize(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: duration,
                        layoutBuilder: _stackTop,
                        transitionBuilder: (child, animation) =>
                            _transition(child, animation, key),
                        child: Column(
                          key: key,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final monday in monthWeeks(month))
                              _weekRow(monday, today),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ExcludeSemantics(
          child: Text(
            'Tap a week to see its pacts',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _weekRow(DateTime monday, DateTime today) {
    final current = widget.current;
    final start = _isoDay(monday);
    final live = start == current.weekStart;
    final summary = widget.weeks[start];
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final int? percent = live ? current.percentCrew : summary?.percent;
    final kept = !live && (percent ?? 0) >= 100;
    final open = live || summary == null ? null : summary;
    final grid = _WeekGrid(
      trailing: percent == null
          ? const SizedBox.shrink()
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$percent%',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kept
                            ? WeekPactColors.doneMark
                            : WeekPactColors.mutedLight,
                      ),
                    ),
                  ),
                ),
                if (open != null)
                  const HugeIcon(
                    icon: HugeIconsStrokeRounded.arrowRight01,
                    size: 14,
                    strokeWidth: 2,
                    color: WeekPactColors.mutedLight,
                  ),
              ],
            ),
      children: [
        for (var i = 0; i < 7; i++)
          _Day(
            date: days[i],
            inMonth: days[i].month == widget.month.month,
            today: live && _isoDay(days[i]) == current.today,
            share: live
                ? (days[i].isAfter(today)
                      ? null
                      : current.shareOut(_isoDay(days[i])))
                : summary?.shareOut.elementAtOrNull(i),
          ),
      ],
    );
    if (open == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Padding(padding: const EdgeInsets.all(4), child: grid),
      );
    }
    final end = monday.add(const Duration(days: 6));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        button: true,
        label:
            'Week of ${crewDateLabel(monday)} to ${crewDateLabel(end)}: ${open.percent}% crew progress',
        child: ExcludeSemantics(
          child: _WeekButton(
            kept: kept,
            onTap: () {
              unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
              widget.onOpenWeek(open);
            },
            child: grid,
          ),
        ),
      ),
    );
  }
}

/// A finished week's row as a raised plate that sinks onto its edge while
/// pressed: the same lifted-edge language as every other control here, so it
/// reads as something to tap. A week the whole crew kept is gold.
class _WeekButton extends StatefulWidget {
  const _WeekButton({
    required this.kept,
    required this.onTap,
    required this.child,
  });
  final bool kept;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_WeekButton> createState() => _WeekButtonState();
}

class _WeekButtonState extends State<_WeekButton> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.kept
        ? Color.lerp(WeekPactColors.neutralInset, WeekPactColors.gold, .4)!
        : WeekPactColors.cream;
    final edge = Color.lerp(face, Colors.black, widget.kept ? .3 : .2)!;
    const depth = WeekPactMetrics.controlDepth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: widget.onTap,
      child: Padding(
        // The edge is drawn below the plate, so the row leaves it room.
        padding: const EdgeInsets.only(bottom: depth),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _pressed ? depth : 0, 0),
          decoration: BoxDecoration(
            color: _pressed ? Color.lerp(face, Colors.black, .06) : face,
            borderRadius: BorderRadius.circular(
              WeekPactMetrics.controlRadius + 4,
            ),
            border: Border.all(color: edge),
            boxShadow: [
              BoxShadow(color: edge, offset: Offset(0, _pressed ? 0 : depth)),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Seven equal day columns and a fixed one for the week's percentage, so the
/// weekday letters and every row line up.
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({required this.children, required this.trailing});
  final List<Widget> children;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 5),
        Expanded(child: children[i]),
      ],
      const SizedBox(width: 6),
      SizedBox(width: 48, child: trailing),
    ],
  );
}

/// One day: raised and green when some of the crew was out, the check mark's
/// deeper green when all of it was, a flat pale slot when nobody was, and a
/// dashed outline for a day that has not come yet. A day of the next or last
/// month only shows its number.
class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.inMonth,
    required this.today,
    required this.share,
  });
  final DateTime date;
  final bool inMonth;
  final bool today;

  /// Null for a day with nothing to show: still to come, or before the crew.
  final double? share;

  @override
  Widget build(BuildContext context) {
    final share = inMonth ? this.share : null;
    final out = (share ?? 0) > 0;
    final full = (share ?? 0) >= 1;
    final face = full
        ? WeekPactColors.doneMark
        : out
        ? Color.lerp(
            WeekPactColors.cream,
            WeekPactColors.keptDay,
            .45 + .55 * share!,
          )!
        : share == null
        ? Colors.transparent
        : WeekPactColors.cream.withValues(alpha: .6);
    return Padding(
      padding: const EdgeInsets.only(bottom: WeekPactMetrics.controlDepth),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: face,
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
            border: today
                ? Border.all(color: WeekPactColors.outlineInk, width: 2)
                : out
                ? Border.all(color: Color.lerp(face, Colors.black, .28)!)
                : share == null
                ? null
                : Border.all(
                    color: WeekPactColors.outlineInk.withValues(alpha: .10),
                  ),
            boxShadow: out
                ? [
                    BoxShadow(
                      color: Color.lerp(face, Colors.black, .22)!,
                      offset: WeekPactMetrics.raisedOffset,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: full
                        ? WeekPactColors.cream
                        : inMonth
                        ? WeekPactColors.outlineInk.withValues(
                            alpha: share == null ? .4 : 1,
                          )
                        : WeekPactColors.outlineInk.withValues(alpha: .22),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The graphite chevron that steps a month calendar back or forward.
class CrewMonthButton extends StatelessWidget {
  const CrewMonthButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final List<List<dynamic>> icon;
  final VoidCallback? onPressed;

  @override
  // The past-week sheet's graphite button, faded rather than hidden when there
  // is no month that way.
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .35 : 1,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: WeekPactColors.graphite,
        disabledBackgroundColor: WeekPactColors.graphite,
        side: const BorderSide(color: WeekPactColors.graphiteEdge),
        shape: WeekPactMetrics.buttonShape,
      ),
      icon: AppIcon(icon: icon, size: 18, color: WeekPactColors.cream),
    ),
  );
}
