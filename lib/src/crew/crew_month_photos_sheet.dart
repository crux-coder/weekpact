import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../home/home_backend.dart';
import '../home/stories.dart';
import '../home/story_viewer.dart';
import '../theme/weekpact_theme.dart';
import 'crew_month_calendar.dart';

/// Opens the crew's month in photos as a drawer over the crew week page.
///
/// [week] is the live week: it lends the drawer today, the crew's members and
/// its pacts, so a photo reads with the same name and colour it has
/// everywhere else.
Future<void> showCrewMonthPhotosSheet({
  required BuildContext context,
  required String crewId,
  required HomeBackend backend,
  required String userId,
  required CrewWeek week,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: WeekPactColors.barrier,
  constraints: BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
  builder: (context) => CrewMonthPhotosSheet(
    crewId: crewId,
    backend: backend,
    userId: userId,
    week: week,
  ),
);

/// The month as a calendar of photos: each day the crew kept a photo shows
/// its most-clapped one, with a count when there were more, and opens the
/// day's photos in the story viewer.
class CrewMonthPhotosSheet extends StatefulWidget {
  const CrewMonthPhotosSheet({
    super.key,
    required this.crewId,
    required this.backend,
    required this.userId,
    required this.week,
  });
  final String crewId;
  final HomeBackend backend;
  final String userId;
  final CrewWeek week;

  /// How many months back the chevron goes.
  static const monthsBack = 12;

  @override
  State<CrewMonthPhotosSheet> createState() => _CrewMonthPhotosSheetState();
}

class _CrewMonthPhotosSheetState extends State<CrewMonthPhotosSheet> {
  late final DateTime _today = DateTime.parse(widget.week.today);
  late final DateTime _thisMonth = DateTime(_today.year, _today.month);
  late DateTime _month = _thisMonth;

  /// Months already loaded, so stepping back and forth does not refetch.
  final _loaded = <DateTime, List<PactStory>>{};
  final _failed = <DateTime>{};

  @override
  void initState() {
    super.initState();
    _load(_month);
  }

  Future<void> _load(DateTime month) async {
    setState(() => _failed.remove(month));
    try {
      final checkIns = await widget.backend.fetchMonthPhotos(
        widget.crewId,
        monthStart: _isoDay(month),
      );
      if (!mounted) return;
      setState(() => _loaded[month] = _stories(checkIns));
    } catch (_) {
      if (mounted) setState(() => _failed.add(month));
    }
  }

  /// The check-ins as stories, in the colour of their pact. A check-in whose
  /// pact or member has since left the crew is left out, the way the rail
  /// leaves it out.
  List<PactStory> _stories(List<PactCheckIn> checkIns) {
    final pacts = widget.week.pacts;
    final members = {for (final m in widget.week.members) m.id};
    return [
      for (final checkIn in checkIns)
        if (checkIn.photoUrl != null && members.contains(checkIn.userId))
          if (pacts.indexWhere((p) => p.id == checkIn.pactId) case final i
              when i >= 0)
            PactStory(
              checkIn: checkIn,
              pact: pacts[i],
              tint: WeekPactColors.pactTint(i),
              badge: WeekPactColors.pactBadge(i),
            ),
    ];
  }

  DateTime? get _previous {
    final month = DateTime(_month.year, _month.month - 1);
    final first = DateTime(
      _thisMonth.year,
      _thisMonth.month - CrewMonthPhotosSheet.monthsBack,
    );
    return month.isBefore(first) ? null : month;
  }

  DateTime? get _next =>
      _month == _thisMonth ? null : DateTime(_month.year, _month.month + 1);

  void _step(DateTime? month) {
    if (month == null) return;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    setState(() => _month = month);
    if (!_loaded.containsKey(month)) _load(month);
  }

  /// Opens [stories] — one day's — in the story viewer, a member at a time
  /// in the crew's order with the viewer first.
  void _open(List<PactStory> stories) {
    final days = <MemberDay>[];
    final members = [...widget.week.members]
      ..sort(
        (a, b) =>
            (a.id == widget.userId ? 0 : 1) - (b.id == widget.userId ? 0 : 1),
      );
    for (final member in members) {
      final own = stories.where((s) => s.checkIn.userId == member.id).toList()
        ..sort((a, b) => _keptAt(a).compareTo(_keptAt(b)));
      if (own.isEmpty) continue;
      days.add(
        MemberDay(
          member: member,
          stories: own,
          seen: false,
          isViewer: member.id == widget.userId,
        ),
      );
    }
    if (days.isEmpty) return;
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    StoryViewer.open(
      context,
      days: days,
      viewerId: widget.userId,
      backend: widget.backend,
    );
  }

  static DateTime _keptAt(PactStory story) =>
      story.keptAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// The day's photo to show: the most clapped, the earliest among ties.
  static PactStory _cover(List<PactStory> stories) => stories.reduce(
    (a, b) =>
        b.clapCount > a.clapCount ||
            (b.clapCount == a.clapCount && _keptAt(b).isBefore(_keptAt(a)))
        ? b
        : a,
  );

  @override
  Widget build(BuildContext context) {
    final stories = _loaded[_month];
    final failed = _failed.contains(_month);
    final byDay = <String, List<PactStory>>{};
    for (final story in stories ?? const <PactStory>[]) {
      (byDay[story.checkIn.day] ??= []).add(story);
    }
    final title = _month.year == _today.year
        ? crewMonthNames[_month.month - 1]
        : '${crewMonthNames[_month.month - 1]} ${_month.year}';
    final subtitle = failed
        ? 'Could not load photos · Tap to try again'
        : stories == null
        ? 'Loading photos…'
        : stories.isEmpty
        ? 'No photos this month'
        : '${stories.length} ${stories.length == 1 ? 'photo' : 'photos'} · '
              '${byDay.length} ${byDay.length == 1 ? 'day' : 'days'}';
    return Container(
      key: const ValueKey('crew-month-photos-sheet'),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: WeekPactColors.darkCanvas,
        border: Border(
          top: BorderSide(
            color: WeekPactColors.darkBorder,
            width: WeekPactMetrics.border,
          ),
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(WeekPactMetrics.sheetRadius),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.ink.withValues(alpha: .3),
                    borderRadius: WeekPactMetrics.pill,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // A failed month is retried from its own line, so the
                        // sheet keeps its height rather than growing a button.
                        GestureDetector(
                          key: const ValueKey('month-photos-retry'),
                          onTap: failed ? () => _load(_month) : null,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: failed ? context.errorInk : context.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CrewMonthButton(
                    tooltip: 'Previous month',
                    icon: HugeIconsStrokeRounded.arrowLeft01,
                    onPressed: _previous == null
                        ? null
                        : () => _step(_previous),
                  ),
                  const SizedBox(width: 8),
                  CrewMonthButton(
                    tooltip: 'Next month',
                    icon: HugeIconsStrokeRounded.arrowRight01,
                    onPressed: _next == null ? null : () => _step(_next),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                // A swipe across the month steps it the way the chevrons do.
                onHorizontalDragEnd: (drag) {
                  final velocity = drag.velocity.pixelsPerSecond.dx;
                  if (velocity > 300) _step(_previous);
                  if (velocity < -300) _step(_next);
                },
                child: _PhotoGrid(
                  month: _month,
                  today: _today,
                  byDay: byDay,
                  cover: _cover,
                  onOpen: _open,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _isoDay(DateTime day) => day.toIso8601String().substring(0, 10);

/// The month, Monday first, a square per day.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.month,
    required this.today,
    required this.byDay,
    required this.cover,
    required this.onOpen,
  });
  final DateTime month;
  final DateTime today;
  final Map<String, List<PactStory>> byDay;
  final PactStory Function(List<PactStory>) cover;
  final void Function(List<PactStory>) onOpen;

  static const _gap = 5.0;

  /// The month's weeks, padded out with blank ones to six — the most any
  /// month spans — so every month's grid stands the same height.
  static List<DateTime> _sixWeeks(DateTime month) {
    final weeks = monthWeeks(month);
    while (weeks.length < 6) {
      final last = weeks.last;
      weeks.add(DateTime(last.year, last.month, last.day + 7));
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ExcludeSemantics(
        child: Row(
          children: [
            for (final (i, day) in const [
              'M',
              'T',
              'W',
              'T',
              'F',
              'S',
              'S',
            ].indexed) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      for (final monday in _sixWeeks(month)) ...[
        const SizedBox(height: _gap),
        Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _tile(
                    context,
                    DateTime(monday.year, monday.month, monday.day + i),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ],
  );

  Widget _tile(BuildContext context, DateTime day) {
    if (day.month != month.month) return const SizedBox.shrink();
    final stories = byDay[_isoDay(day)];
    final label = '${crewMonthNames[day.month - 1]} ${day.day}';
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: day == today
          ? const BorderSide(color: WeekPactColors.darkInk, width: 2)
          : day.isAfter(today)
          ? BorderSide(
              color: WeekPactColors.darkBorder.withValues(alpha: .5),
              width: 1,
            )
          : BorderSide.none,
    );
    final number = Text(
      '${day.day}',
      style: TextStyle(
        color: stories == null
            ? WeekPactColors.darkMuted.withValues(alpha: .6)
            : WeekPactColors.cream,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        shadows: stories == null
            ? null
            : const [Shadow(color: Color(0x99000000), blurRadius: 3)],
      ),
    );
    if (stories == null) {
      return Semantics(
        container: true,
        label: day.isAfter(today) ? null : '$label: no photos',
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: day.isAfter(today) ? null : WeekPactColors.activitySurface,
            shape: shape,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 3, 0, 0),
            child: Align(
              alignment: Alignment.topLeft,
              child: ExcludeSemantics(child: number),
            ),
          ),
        ),
      );
    }
    final shown = cover(stories);
    return Semantics(
      button: true,
      label:
          '$label: ${stories.length} ${stories.length == 1 ? 'photo' : 'photos'}',
      child: GestureDetector(
        key: ValueKey('month-photo-${_isoDay(day)}'),
        onTap: () => onOpen(stories),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(color: shown.tint, shape: shape),
          foregroundDecoration: ShapeDecoration(shape: shape),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                shown.photoUrl!,
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              Positioned(
                left: 5,
                top: 3,
                child: ExcludeSemantics(child: number),
              ),
              if (stories.length > 1)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x8C000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${stories.length}',
                        style: const TextStyle(
                          color: WeekPactColors.cream,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
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
  }
}
