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

String crewDateLabel(DateTime date) {
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
  return '${months[date.month - 1]} ${date.day}';
}

/// A plain carousel page: one pact and the crew's days aligned in one calendar.
class CrewPactWeekCard extends StatefulWidget {
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

  @override
  State<CrewPactWeekCard> createState() => _CrewPactWeekCardState();
}

class _CrewPactWeekCardState extends State<CrewPactWeekCard> {
  static const _membersPerPage = 4;
  int _memberPage = 0;

  @override
  Widget build(BuildContext context) {
    final week = widget.week;
    final pact = widget.pact;
    final pageCount = (widget.members.length / _membersPerPage).ceil();
    final page = math.min(_memberPage, math.max(0, pageCount - 1));
    final start = page * _membersPerPage;
    final visible = widget.members.skip(start).take(_membersPerPage).toList();
    return AppSurface(
      fillColor: widget.tint,
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
            final contentHeight = math.max(
              space.maxHeight,
              285 +
                  visible.length * 56 +
                  (pageCount > 1 ? 48 : 0) +
                  extraText * (220 + visible.length * 50),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pact.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 32,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${pact.daysPerWeek} ${pact.daysPerWeek == 1 ? 'day' : 'days'} per person this week',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: context.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        PactIconBadge(
                          icon: PactIcon.find(pact.iconKey).data,
                          tint: widget.badge ?? WeekPactColors.pactBadge(0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${week.pactCompleted(pact)}',
                            style: const TextStyle(
                              fontSize: 42,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' / ${pact.daysPerWeek * widget.members.length}',
                            style: const TextStyle(
                              fontSize: 28,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'CHECK-INS',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        color: context.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (visible.isEmpty)
                      const Expanded(
                        child: Center(child: Text('No members to show.')),
                      )
                    else
                      Expanded(
                        child: Column(
                          children: [
                            _CalendarHeader(week: week),
                            for (final member in visible)
                              Expanded(
                                child: _MemberDays(
                                  week: week,
                                  pact: pact,
                                  member: member,
                                  isYou: member.id == widget.userId,
                                ),
                              ),
                          ],
                        ),
                      ),
                    if (pageCount > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${start + 1}–${start + visible.length} of ${widget.members.length} members',
                                style: TextStyle(
                                  color: context.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous members',
                                onPressed: page == 0
                                    ? null
                                    : () => setState(
                                        () => _memberPage = page - 1,
                                      ),
                                icon: const HugeIcon(
                                  icon: HugeIconsStrokeRounded.arrowLeft01,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next members',
                                onPressed: page == pageCount - 1
                                    ? null
                                    : () => setState(
                                        () => _memberPage = page + 1,
                                      ),
                                icon: const HugeIcon(
                                  icon: HugeIconsStrokeRounded.arrowRight01,
                                ),
                              ),
                            ],
                          ),
                        ],
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
                                '${widget.members.length} members · ${week.pacts.length} pacts',
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
                                  '${widget.members.fold(0, (sum, member) => sum + week.completed(member.id))} / ${week.target * widget.members.length}',
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
const _countWidth = 48.0;

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({required this.week});
  final CrewWeek week;

  @override
  Widget build(BuildContext context) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final start = DateTime.parse(week.weekStart);
    return Row(
      children: [
        const SizedBox(width: _nameWidth),
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
        const SizedBox(width: _countWidth),
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
    final fallback = Center(
      child: Text(
        member.initials,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
    return Row(
      children: [
        SizedBox(
          width: _nameWidth,
          // The face alone, centred on the row of cells it belongs to. The
          // name under it pushed the avatar off that line and had to be
          // truncated to fit anyway; the tooltip still carries it.
          child: Tooltip(
            message: '$name${isYou ? ' (you)' : ''}',
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  width: 42,
                  height: 42,
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
                          errorBuilder: (_, _, _) => fallback,
                        )
                      : fallback,
                ),
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
                    child: _DayCell(done: done, today: today, future: future),
                  ),
                );
              },
            ),
          ),
        SizedBox(
          width: _countWidth,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Semantics(
              label:
                  '$name: ${week.days(pact.id, member.id)} of ${pact.daysPerWeek} check-ins this week',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${week.days(pact.id, member.id)} / ${pact.daysPerWeek}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One day of one person's week, drawn as the app's raised cell: the same
/// outline and 2px bottom edge a pact day or a button carries, so the calendar
/// reads as a grid of pressable tiles rather than a field of pips. The cell
/// fills its column and row instead of sitting as a small square in the
/// middle of one, which is what left the grid full of dead space.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.done,
    required this.today,
    required this.future,
  });
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
    return Padding(
      // The extra two below is the raised edge's room: without it a done
      // cell's edge would touch the cell of the next row.
      padding: const EdgeInsets.fromLTRB(3, 3, 3, 5),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 46),
          child: SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: face,
                // The same squircle every card, button and tile is cut to,
                // stepped down to a cell's corner.
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    WeekPactMetrics.curveFor(WeekPactMetrics.controlRadius),
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
                    ? [
                        BoxShadow(
                          color: edge,
                          offset: WeekPactMetrics.raisedOffset,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: done
                    ? const HugeIcon(
                        icon: HugeIconsStrokeRounded.tick02,
                        size: 18,
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
          ),
        ),
      ),
    );
  }
}
