import '../widgets/avatar_shape.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../home/home_backend.dart';
import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/pact_icon_badge.dart';

/// A date as this app writes one: the month's short name and the day.
///
/// The year is left off, because almost every date drawn here belongs to the
/// week being read and saying 2026 three times on one card is noise. Pass
/// [now] where the date can be an old one — a crew's start, say — and the year
/// comes back whenever it is not the year we are in: `SEP 7` a few weeks after
/// the fact is a date, `SEP 7` from a crew started last September is a lie.
String crewDateLabel(DateTime date, {DateTime? now}) {
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
  final label = '${months[date.month - 1]} ${date.day}';
  return now == null || date.year == now.year ? label : '$label, ${date.year}';
}

/// A plain carousel page: one pact and the crew's days aligned in one calendar.
class CrewPactWeekCard extends StatelessWidget {
  const CrewPactWeekCard({
    super.key,
    required this.week,
    required this.pact,
    required this.members,
    required this.userId,
    this.tint,
    this.badge,
  });

  /// The card's tint, and the deeper companion its icon badge is drawn in.
  /// Both come from the pact's place in the crew's list, so they stay a pair.
  final Color? tint;
  final Color? badge;
  final CrewWeek week;
  final CrewPact pact;
  final List<WeekMember> members;
  final String userId;

  /// The card's height for a crew of [count]: its content and the padding
  /// around it. [extraText] is how far the text scale is above 1. A page
  /// gives the card this, so it stands no taller than what it draws.
  static double heightFor(int count, {double extraText = 0}) =>
      _contentHeight(count) + _extraTextHeight(count, extraText) + 2 * 16;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      fillColor: tint,
      shape: WeekPactMetrics.pactCardShape,
      borderWidth: 1,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, space) {
            final extraText = math.max(
              0.0,
              MediaQuery.textScalerOf(context).scale(1) - 1,
            );
            // Four people are on the card at once, every row at its full
            // height, and a bigger crew shows half of a fifth and scrolls
            // inside the card (see [heightFor]): it does not get smaller
            // check-ins. Only a card given less than that, on a page that
            // cannot grow, scales down.
            final contentHeight = math.max(
              space.maxHeight,
              _contentHeight(members.length) +
                  _extraTextHeight(members.length, extraText),
            );
            final shrink = math.min(1.0, space.maxHeight / contentHeight);
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                // Compensate for height fitting so the calendar still spans
                // the card's full width on shorter screens.
                width: space.maxWidth / shrink,
                height: contentHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            pact.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        PactIconBadge(
                          icon: PactIcon.find(pact.iconKey).data,
                          tint: badge ?? WeekPactColors.pactBadge(0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (members.isEmpty)
                      const Expanded(
                        child: Center(child: Text('No members to show.')),
                      )
                    else
                      Expanded(
                        child: Column(
                          children: [
                            _CalendarHeader(week: week),
                            Expanded(
                              child: _MemberRows(
                                week: week,
                                pact: pact,
                                members: members,
                                userId: userId,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Divider(color: context.border, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Crew total',
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.1,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${members.length} members · ${week.pacts.length} pacts',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          fit: FlexFit.tight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${members.fold(0, (sum, member) => sum + week.completed(member.id))} / ${week.target * members.length}',
                                  style: const TextStyle(
                                    fontSize: 26,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'CHECK-INS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 1.5,
                                    color: context.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const _nameWidth = 52.0;

/// One person's row: a day cell at its full height, with its edge's room.
const _rowHeight = 54.0;

/// The most people a card shows whole; a bigger crew shows half of the next
/// one too, so the cut-off row says the list scrolls.
const _wholeRows = 4;

/// How many rows a crew of [count] has in view.
double _visibleRows(int count) =>
    count > _wholeRows ? _wholeRows + .5 : count.toDouble();

/// The room between the dates and the people, which holds the up arrow, and
/// under the people of a crew that scrolls, which holds the down arrow.
const _arrowRoom = 20.0;

/// What the card's content needs for [count] people: the title, the dates
/// and the crew total, the rows in view, and the room for the down arrow
/// when the list scrolls.
double _contentHeight(int count) =>
    _chromeHeight +
    _visibleRows(count) * _rowHeight +
    (count > _wholeRows ? _arrowRoom : 0);

/// Everything on the card but the rows, at text scale 1: the title row (as
/// tall as the pact's badge), the gap under it, the dates, the room above the
/// rows, the gap and divider over the crew total, and the crew total itself.
/// Any more than the card draws is left as empty room under the rows.
const _chromeHeight = 56.0 + 12 + 44 + _arrowRoom + 8 + 1 + 10 + 40;

/// What larger text adds to the card's content for [count] people.
double _extraTextHeight(int count, double extraText) =>
    extraText * (220 + _visibleRows(count) * 50);

/// The crew's rows: four and a half in view, and the rest scrolled to inside
/// the card. An arrow above says there are people scrolled past,
/// and one below says there are more to come.
class _MemberRows extends StatefulWidget {
  const _MemberRows({
    required this.week,
    required this.pact,
    required this.members,
    required this.userId,
  });
  final CrewWeek week;
  final CrewPact pact;
  final List<WeekMember> members;
  final String userId;

  @override
  State<_MemberRows> createState() => _MemberRowsState();
}

class _MemberRowsState extends State<_MemberRows> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Moves the list a page's worth of people up or down.
  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    _scroll.animateTo(
      (position.pixels + direction * (_wholeRows - 1) * _rowHeight).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final scrolls = members.length > _wholeRows;
    return Column(
      children: [
        // Room between the dates and the people: the header labels the grid,
        // it is not a row of it. It holds the up arrow once the list has
        // been scrolled.
        SizedBox(
          height: _arrowRoom,
          child: !scrolls
              ? null
              : _ScrollArrow(
                  controller: _scroll,
                  up: true,
                  onTap: () => _page(-1),
                ),
        ),
        // Each person gets one row's height and the rows stack from the top:
        // spread over the card, two people read as two unrelated strips. The
        // list stands four and a half rows tall at most; a card given less
        // shows less, rather than overflowing.
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _visibleRows(members.length) * _rowHeight,
            ),
            child: _EdgeFade(
              controller: scrolls ? _scroll : null,
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.zero,
                // A crew that fits leaves vertical drags to the page, so
                // pulling down on the card still refreshes it.
                physics: scrolls
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemExtent: _rowHeight,
                itemCount: members.length,
                itemBuilder: (context, index) => _MemberDays(
                  week: widget.week,
                  pact: widget.pact,
                  member: members[index],
                  isYou: members[index].id == widget.userId,
                ),
              ),
            ),
          ),
        ),
        if (scrolls)
          SizedBox(
            height: _arrowRoom,
            child: _ScrollArrow(
              controller: _scroll,
              up: false,
              onTap: () => _page(1),
            ),
          ),
      ],
    );
  }
}

/// Fades the list out at an end that has people scrolled past it, so the rows
/// run under the edge rather than stopping at a hard line. Each fade comes in
/// over the first row's worth of scrolling. A list that does not scroll, with
/// no [controller], is drawn as it is.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.controller, required this.child});
  final ScrollController? controller;
  final Widget child;

  /// How far into the list each fade reaches.
  static const _depth = 24.0;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return child;
    return ListenableBuilder(
      listenable: controller,
      child: child,
      builder: (context, child) {
        final position =
            controller.hasClients && controller.position.hasContentDimensions
            ? controller.position
            : null;
        // Before the list is laid out it sits at the top, with more below.
        final top = position == null
            ? 0.0
            : (position.extentBefore / _rowHeight).clamp(0.0, 1.0);
        final bottom = position == null
            ? 1.0
            : (position.extentAfter / _rowHeight).clamp(0.0, 1.0);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final depth = math.min(_depth / bounds.height, .5);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 1 - top),
                Colors.black,
                Colors.black,
                Colors.black.withValues(alpha: 1 - bottom),
              ],
              stops: [0, depth, 1 - depth, 1],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// An arrow that shows while the list has people scrolled out of view on its
/// side: above for those scrolled past, below for those still to come.
class _ScrollArrow extends StatelessWidget {
  const _ScrollArrow({
    required this.controller,
    required this.up,
    required this.onTap,
  });
  final ScrollController controller;
  final bool up;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Before the list is laid out it sits at the top, so only the down
        // arrow shows.
        final shown =
            controller.hasClients && controller.position.hasContentDimensions
            ? (up
                      ? controller.position.extentBefore
                      : controller.position.extentAfter) >
                  .5
            : !up;
        return IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Semantics(
              button: true,
              label: up ? 'Show earlier members' : 'Show more members',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Center(
                  child: HugeIcon(
                    icon: up
                        ? HugeIconsStrokeRounded.arrowUp01
                        : HugeIconsStrokeRounded.arrowDown01,
                    size: 18,
                    strokeWidth: 2,
                    color: context.muted,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({required this.week});
  final CrewWeek week;

  @override
  Widget build(BuildContext context) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final start = DateTime.parse(week.weekStart);
    return Row(
      children: [
        // The column of faces is headed too, so the row of days does not
        // start over a gap.
        SizedBox(
          width: _nameWidth,
          child: Tooltip(
            message: 'Crew',
            child: Center(
              child: HugeIcon(
                icon: HugeIconsStrokeRounded.userGroup,
                size: 22,
                strokeWidth: 1.8,
                color: context.muted,
              ),
            ),
          ),
        ),
        for (var index = 0; index < 7; index++)
          Expanded(
            child: Builder(
              builder: (_) {
                final date = start.add(Duration(days: index));
                final today =
                    date.toIso8601String().substring(0, 10) == week.today;
                final label = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          letterSpacing: .2,
                          fontWeight: FontWeight.w600,
                          color: today ? WeekPactColors.cream : context.muted,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: today ? FontWeight.w600 : FontWeight.w700,
                          color: today ? WeekPactColors.cream : context.muted,
                        ),
                      ),
                    ),
                  ],
                );
                if (!today) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
                    child: label,
                  );
                }
                // Today is marked once, here: an ink squircle raised off the
                // card, rather than a tint washed down the whole column, which
                // had to be a different colour on every pact card to be seen.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
                  child: AppSurface(
                    fillColor: context.ink,
                    resolveTone: false,
                    borderRadius: WeekPactMetrics.controlRadius,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: label,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _MemberDays extends StatelessWidget {
  const _MemberDays({
    required this.week,
    required this.pact,
    required this.member,
    required this.isYou,
  });
  final CrewWeek week;
  final CrewPact pact;
  final WeekMember member;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final name = member.displayName.trim().isEmpty
        ? (isYou ? 'You' : 'Member')
        : member.displayName.trim().split(RegExp(r'\s+')).first;
    final dates = week.checkIns
        .where(
          (checkIn) => checkIn.pactId == pact.id && checkIn.userId == member.id,
        )
        .map((checkIn) => checkIn.day)
        .toSet();
    final start = DateTime.parse(week.weekStart);
    return LayoutBuilder(
      builder: (context, box) {
        // One measure for the whole row: the largest square that fits both
        // the row's height and a day's column, less the air around it and
        // the raised edge below. The face and every day are drawn at it, so
        // a person and their days always read as one row of equal tiles.
        final thin = box.maxHeight < 36;
        final air = thin ? 1.0 : 3.0;
        final column = (box.maxWidth - _nameWidth) / 7;
        final size = math
            .min(
              _faceSize,
              math.min(
                box.maxHeight - 2 * air - _edgeRoom,
                column - 2 * (thin ? 2 : 3),
              ),
            )
            .floorToDouble()
            .clamp(1.0, _faceSize)
            .toDouble();
        final fallback = size < 14
            ? null
            : Center(
                child: Text(
                  member.initials,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: math.min(13, size * .38),
                    height: 1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
        return Row(
          children: [
            SizedBox(
              width: _nameWidth,
              // The face alone, centred on the row of cells it belongs to.
              // The name under it pushed the avatar off that line and had to
              // be truncated to fit anyway; the tooltip still carries it.
              child: Tooltip(
                message: '$name${isYou ? ' (you)' : ''}',
                child: Center(
                  child: Container(
                    width: size,
                    height: size,
                    clipBehavior: Clip.antiAlias,
                    decoration: ShapeDecoration(
                      shape: const AvatarShape(),
                      color: context.ink.withValues(alpha: .06),
                    ),
                    child: member.avatarUrl?.trim().isNotEmpty == true
                        ? Image.network(
                            member.avatarUrl!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                fallback ?? const SizedBox.shrink(),
                          )
                        : fallback,
                  ),
                ),
              ),
            ),
            for (var index = 0; index < 7; index++)
              Expanded(
                child: Builder(
                  builder: (_) {
                    final date = start.add(Duration(days: index));
                    final key = date.toIso8601String().substring(0, 10);
                    final future = key.compareTo(week.today) > 0;
                    final today = key == week.today;
                    final done = !future && dates.contains(key);
                    final status = future
                        ? 'Upcoming'
                        : done
                        ? 'Completed'
                        : today
                        ? 'Not checked in yet'
                        : 'No check-in';
                    return Semantics(
                      label:
                          '$name, ${pact.title}, ${crewDateLabel(date)}: $status',
                      child: Tooltip(
                        message: '${crewDateLabel(date)} · $status',
                        child: Center(
                          child: _DayCell(
                            size: size,
                            done: done,
                            today: today,
                            future: future,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The largest a face, and so a day, is drawn.
const _faceSize = 42.0;

/// The room under a raised cell for its edge, so it never touches the row
/// below.
const _edgeRoom = 2.0;

/// One day of one person's week, drawn as the app's raised cell: the same
/// outline and 2px bottom edge a pact day or a button carries, so the calendar
/// reads as a grid of pressable tiles rather than a field of pips. It is a
/// square the size of the face that heads its row, so a person and their
/// days read as one row of equal tiles at any crew size.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.size,
    required this.done,
    required this.today,
    required this.future,
  });

  /// The cell's side: the same as the face at the head of its row.
  final double size;
  final bool done;
  final bool today;
  final bool future;

  @override
  Widget build(BuildContext context) {
    // A check-in and today are raised; the rest are flat slots waiting to be
    // filled. Today's is the whitest face on the card, so the column you can
    // still act on stands out from the days that have already gone.
    final face = done
        ? WeekPactColors.keptDay
        : today
        ? Colors.white
        : WeekPactColors.cream.withValues(alpha: future ? .35 : .6);
    // The edge is the cell's own fill pushed towards black, the way every
    // other raised surface builds its shadow, rather than a flat grey laid
    // under it.
    final edge = done
        ? Color.lerp(WeekPactColors.keptDay, Colors.black, .22)!
        : Color.lerp(Colors.white, Colors.black, .20)!;
    // A small cell keeps its fill and gives up the tick and dot once there is
    // no room to read them.
    final marked = size >= 22;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: face,
          // The same squircle every card, button and tile is cut to, stepped
          // down to a cell's corner.
          shape: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(
              WeekPactMetrics.curveFor(
                math.min(WeekPactMetrics.controlRadius, size / 2),
              ),
            ),
            side: BorderSide(
              color: done
                  ? Color.lerp(WeekPactColors.keptDay, Colors.black, .28)!
                  : today
                  ? Color.lerp(Colors.white, Colors.black, .28)!
                  : context.ink.withValues(alpha: future ? .05 : .10),
            ),
          ),
          shadows: done || today
              ? [BoxShadow(color: edge, offset: WeekPactMetrics.raisedOffset)]
              : null,
        ),
        child: !marked
            ? null
            : Center(
                child: done
                    ? HugeIcon(
                        icon: HugeIconsStrokeRounded.tick02,
                        size: math.min(18, size * .45),
                      )
                    : Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.muted.withValues(
                            alpha: future ? .18 : .35,
                          ),
                        ),
                      ),
              ),
      ),
    );
  }
}
