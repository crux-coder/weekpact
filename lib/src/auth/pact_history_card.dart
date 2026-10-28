import 'package:flutter/material.dart';

import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/pact_icon_badge.dart';
import 'pact_history.dart';

/// One pact on a profile: its badge and name, the line that says how long
/// and how well, and a calendar of the last sixteen weeks, a column each,
/// with the days kept filled in and the weeks on target set off underneath.
///
/// The wall under it shows what a check-in looked like; this shows the shape
/// of them over time, which is what tells somebody they are a person who
/// runs rather than a person who ran on Tuesday.
class PactHistoryCard extends StatelessWidget {
  const PactHistoryCard({super.key, required this.history, this.onTap});

  final PactHistory history;

  /// Opens the pact's check-ins on the wall below.
  final VoidCallback? onTap;

  static const shape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(WeekPactMetrics.panelCurve)),
  );

  @override
  Widget build(BuildContext context) {
    final tint = WeekPactColors.pactTint(history.pactIndex);
    final badge = WeekPactColors.pactBadge(history.pactIndex);
    final ink = WeekPactColors.black;
    final run = history.run;
    return Semantics(
      button: onTap != null,
      label:
          '${history.title}, ${history.crewName}: ${history.summary}'
          '${run > 1 ? ', $run weeks running' : ''}',
      excludeSemantics: true,
      child: Material(
        color: tint,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PactIconBadge(
                      icon: PactIcon.find(history.iconKey).data,
                      tint: badge,
                      size: 36,
                      depth: 1,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            history.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            history.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink.withValues(alpha: .74),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (run > 1) ...[
                      const SizedBox(width: 8),
                      _RunPill(weeks: run, badge: badge),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                PactCalendar(history: history, badge: badge, ink: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "3 wks running": the weeks on target in a row, in the pact's badge colour.
class _RunPill extends StatelessWidget {
  const _RunPill({required this.weeks, required this.badge});

  final int weeks;
  final Color badge;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    decoration: BoxDecoration(color: badge, borderRadius: WeekPactMetrics.pill),
    child: Text(
      '$weeks wks running',
      style: const TextStyle(
        color: WeekPactColors.black,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Sixteen weeks as columns of seven days, Monday at the top, this week on
/// the right. A day kept is a solid square, a day not kept a faint one, and a
/// day still to come is left blank; a column whose week met the target is
/// set on a pale strip, so the eye reads the weeks on target as a row of
/// bars under the days.
class PactCalendar extends StatelessWidget {
  const PactCalendar({
    super.key,
    required this.history,
    required this.badge,
    required this.ink,
  });

  final PactHistory history;
  final Color badge;
  final Color ink;

  static const gap = 3.0;
  static const maxCell = 20.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = PactHistory.calendarWeeks;
      final cell = ((constraints.maxWidth - gap * (columns - 1)) / columns)
          .clamp(4.0, maxCell);
      final width = cell * columns + gap * (columns - 1);
      final height = cell * 7 + gap * 6;
      return SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _CalendarPainter(
            history: history,
            cell: cell,
            badge: badge,
            ink: ink,
          ),
        ),
      );
    },
  );
}

class _CalendarPainter extends CustomPainter {
  _CalendarPainter({
    required this.history,
    required this.cell,
    required this.badge,
    required this.ink,
  });

  final PactHistory history;
  final double cell;
  final Color badge;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final kept = history.days.toSet();
    final met = {
      for (final week in history.weeks)
        if (history.met(week)) week.start,
    };
    final first = history.firstDay;
    final today = history.today;
    final mondays = history.calendarMondays;
    final radius = Radius.circular(cell * .28);
    final strip = Paint()..color = ink.withValues(alpha: .08);
    final faint = Paint()..color = ink.withValues(alpha: .12);
    final solid = Paint()..color = badge;
    const gap = PactCalendar.gap;
    for (var column = 0; column < mondays.length; column++) {
      final monday = mondays[column];
      final x = column * (cell + gap);
      if (met.contains(monday)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - gap / 2, -gap / 2, cell + gap, size.height + gap),
            Radius.circular(cell * .4),
          ),
          strip,
        );
      }
      final start = DateTime.parse(monday);
      for (var row = 0; row < 7; row++) {
        final day = PactHistory.isoDay(start.add(Duration(days: row)));
        if (day.compareTo(today) > 0) continue;
        final y = row * (cell + gap);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cell, cell),
          radius,
        );
        if (kept.contains(day)) {
          canvas.drawRRect(rect, solid);
        } else if (first != null && day.compareTo(first) >= 0) {
          canvas.drawRRect(rect, faint);
        } else {
          canvas.drawRRect(rect, Paint()..color = ink.withValues(alpha: .05));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CalendarPainter old) =>
      old.history != history ||
      old.cell != cell ||
      old.badge != badge ||
      old.ink != ink;
}
