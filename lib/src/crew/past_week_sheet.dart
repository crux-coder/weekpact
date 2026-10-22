import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/page_frame.dart';
import 'crew_pact_carousel.dart';
import 'crew_pact_week_card.dart';

/// Opens a finished week as a sheet over the crew week page.
///
/// A past week never becomes the page. It rises over the live week, which
/// stays dimmed behind it, so there is no mistaking one for the other: the
/// crew's name is not repeated because it is still visible above the sheet,
/// and the sheet leads with the date instead. [currentWeekStart] is the live
/// week's Monday, so the sheet can say "last week" when that is what it is.
///
/// The sheet is open or closed, never parked in between: it springs up to one
/// height, and a drag down either passes [PastWeekSheet.closeThreshold] (or is
/// flung) and closes it, or springs it back.
Future<void> showPastWeekSheet({
  required BuildContext context,
  required PactCrew crew,
  required HomeBackend backend,
  required String userId,
  required String weekStart,
  required String currentWeekStart,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: WeekPactColors.barrier,
  // The sheet tracks the drag itself, so it can spring back or close.
  enableDrag: false,
  sheetAnimationStyle: AnimationStyle(
    duration: _SheetSpring.duration,
    curve: const _SheetSpring(),
    reverseDuration: const Duration(milliseconds: 240),
    reverseCurve: Curves.easeInCubic,
  ),
  constraints: BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width),
  builder: (context) => PastWeekSheet(
    crew: crew,
    backend: backend,
    userId: userId,
    weekStart: weekStart,
    currentWeekStart: currentWeekStart,
  ),
);

class PastWeekSheet extends StatefulWidget {
  const PastWeekSheet({
    super.key,
    required this.crew,
    required this.backend,
    required this.userId,
    required this.weekStart,
    required this.currentWeekStart,
  });
  final PactCrew crew;
  final HomeBackend backend;
  final String userId;
  final String weekStart;
  final String currentWeekStart;

  /// How far down, as a share of its height, the sheet has to be dragged
  /// before letting go closes it rather than springing it back.
  static const closeThreshold = .25;

  /// A downward fling faster than this closes the sheet however far it went.
  static const closeVelocity = 900.0;

  @override
  State<PastWeekSheet> createState() => _PastWeekSheetState();
}

/// The sheet's rise: a spring settling from below with a slight overshoot,
/// drawn as a curve so the modal route can run it.
class _SheetSpring extends Curve {
  const _SheetSpring();

  static const duration = Duration(milliseconds: 560);
  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 190, ratio: .82),
    0,
    1,
    0,
  );

  @override
  double transformInternal(double t) =>
      _spring.x(t * duration.inMilliseconds / 1000);
}

class _PastWeekSheetState extends State<PastWeekSheet>
    with SingleTickerProviderStateMixin {
  /// How far below its open height the sheet is being held, in pixels.
  late final _offset = AnimationController.unbounded(vsync: this);
  final _scroll = ScrollController();
  bool _pastThreshold = false;
  CrewWeek? _week;
  String? _error;
  bool _loading = false;
  int _index = 0;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final week = await widget.backend.fetchWeek(
        widget.crew.id,
        weekStart: widget.weekStart,
      );
      if (!mounted || request != _request) return;
      setState(() => _week = week);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load that week. Try again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _offset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _dragBy(double dy, double height) {
    _offset.stop();
    _offset.value = math.max(0, _offset.value + dy);
    // A tick as the drag crosses the line, either way, so letting go is
    // never a surprise.
    final past = _offset.value > height * PastWeekSheet.closeThreshold;
    if (past != _pastThreshold) {
      _pastThreshold = past;
      unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    }
  }

  void _settle(double velocity, double height) {
    if (_offset.value <= 0) return;
    _pastThreshold = false;
    if (_offset.value > height * PastWeekSheet.closeThreshold ||
        velocity > PastWeekSheet.closeVelocity) {
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
      Navigator.of(context).pop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = 0;
      return;
    }
    _offset.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 320, ratio: .8),
        _offset.value,
        0,
        velocity,
      ),
    );
  }

  /// The list drives the sheet while it is at its top: pulling down past the
  /// top moves the sheet instead, and pushing back up takes the sheet up
  /// before the list scrolls again.
  bool _onScroll(ScrollNotification note, double height) {
    if (note.depth != 0 || note.metrics.axis != Axis.vertical) return false;
    if (note is OverscrollNotification &&
        note.dragDetails != null &&
        note.overscroll < 0) {
      _dragBy(-note.overscroll, height);
    } else if (note is ScrollUpdateNotification &&
        note.dragDetails != null &&
        _offset.value > 0 &&
        (note.scrollDelta ?? 0) > 0) {
      final taken = math.min(_offset.value, note.scrollDelta!);
      _dragBy(-taken, height);
      _scroll.jumpTo(note.metrics.pixels - taken);
    } else if (note is ScrollEndNotification) {
      _settle(note.dragDetails?.velocity.pixelsPerSecond.dy ?? 0, height);
    }
    return false;
  }

  bool get _lastWeek =>
      DateTime.parse(widget.currentWeekStart)
          .difference(DateTime.parse(widget.weekStart))
          .inDays ==
      7;

  String get _dates {
    final start = DateTime.parse(widget.weekStart);
    final end = start.add(const Duration(days: 6));
    return end.month == start.month
        ? '${crewDateLabel(start)} – ${end.day}'
        : '${crewDateLabel(start)} – ${crewDateLabel(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    final members = [...?week?.members]
      ..sort((a, b) {
        if (a.id == b.id) return 0;
        if (a.id == widget.userId) return -1;
        if (b.id == widget.userId) return 1;
        return a.displayName.compareTo(b.displayName);
      });
    // The card asks for room for four members and a pager, and shrinks to
    // whatever it gets; this is the height at which it need not shrink.
    final deckHeight =
        320 + (members.length.clamp(1, 4)) * 56 + (members.length > 4 ? 48 : 0);
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight * .92;
        final sheet = Container(
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
          child: Semantics(
            label: '${_lastWeek ? 'Last week' : 'Past week'}, $_dates',
            explicitChildNodes: true,
            child: NotificationListener<ScrollNotification>(
              onNotification: (note) => _onScroll(note, height),
              child: ListView(
                key: const ValueKey('past-week-sheet'),
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (drag) =>
                        _dragBy(drag.delta.dy, height),
                    onVerticalDragEnd: (drag) =>
                        _settle(drag.velocity.pixelsPerSecond.dy, height),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _WeekChip(
                                    label: _lastWeek
                                        ? 'LAST WEEK'
                                        : 'PAST WEEK',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _dates,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: 'Back to this week',
                              onPressed: () {
                                unawaited(
                                  HapticFeedback.lightImpact().catchError(
                                    (Object _) {},
                                  ),
                                );
                                Navigator.of(context).pop();
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: WeekPactColors.graphite,
                                side: const BorderSide(
                                  color: WeekPactColors.graphiteEdge,
                                ),
                                shape: WeekPactMetrics.buttonShape,
                              ),
                              icon: const AppIcon(
                                icon: HugeIconsStrokeRounded.cancel01,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: context.errorInk)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('TRY AGAIN'),
                      ),
                    ),
                  ] else if (week == null)
                    _PastWeekSkeleton(deckHeight: deckHeight.toDouble())
                  else ...[
                    _ClosedWeekBanner(week: week),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Crew pacts',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (week.pacts.isNotEmpty)
                          Text(
                            '${_index + 1} / ${week.pacts.length}',
                            style: TextStyle(
                              color: context.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: deckHeight.toDouble(),
                      child: CrewPactCarousel(
                        week: week,
                        members: members,
                        userId: widget.userId,
                        onIndexChanged: (index) =>
                            setState(() => _index = index),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
        return AnimatedBuilder(
          animation: _offset,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _offset.value),
            child: child,
          ),
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Canvas below the sheet's foot, so the spring's overshoot
                // lifts the sheet without opening a gap under it.
                Positioned(
                  left: 0,
                  right: 0,
                  top: height - 1,
                  height: 96,
                  child: const ColoredBox(color: WeekPactColors.darkCanvas),
                ),
                Positioned.fill(child: sheet),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The small grey pill above the date that says what kind of week this is.
class _WeekChip extends StatelessWidget {
  const _WeekChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WeekPactColors.graphite,
      border: Border.all(color: WeekPactColors.graphiteEdge),
      borderRadius: WeekPactMetrics.pill,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: WeekPactColors.darkMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Where the live page has a dial and a streak, a finished week has one
/// line: what the crew made of it, and a lock, because nothing here can be
/// changed any more.
class _ClosedWeekBanner extends StatelessWidget {
  const _ClosedWeekBanner({required this.week});
  final CrewWeek week;

  @override
  Widget build(BuildContext context) {
    final total = week.members.length;
    final hit = week.members
        .where((member) => week.target > 0 && week.percent(member.id) >= 100)
        .length;
    final line = total == 0
        ? 'No members that week'
        : hit == total
        ? 'All $total hit their target'
        : hit == 0
        ? 'No one hit their target'
        : '$hit of $total hit their target';
    final kept = week.percentCrew >= 100;
    return Semantics(
      label: 'Week closed: ${week.percentCrew}% crew progress, $line',
      child: ExcludeSemantics(
        child: AppSurface(
          fillColor: kept ? WeekPactColors.mintGreen : WeekPactColors.stone,
          builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Text(
                  '${week.percentCrew}%',
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Week closed',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        line,
                        style: TextStyle(fontSize: 12, color: context.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: context.ink.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(
                      WeekPactMetrics.controlRadius,
                    ),
                  ),
                  child: const AppIcon(
                    icon: HugeIconsStrokeRounded.squareLock02,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PastWeekSkeleton extends StatelessWidget {
  const _PastWeekSkeleton({required this.deckHeight});
  final double deckHeight;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading that week',
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        key: const ValueKey('past-week-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SkeletonBar(height: 74, shape: WeekPactMetrics.pactCardShape),
          const SizedBox(height: 18),
          const SkeletonBar(width: 132, height: 22),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: SkeletonBar(
              height: deckHeight - 44,
              shape: WeekPactMetrics.pactCardShape,
            ),
          ),
        ],
      ),
    ),
  );
}
