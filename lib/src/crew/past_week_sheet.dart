import 'package:flutter/material.dart';
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

  @override
  State<PastWeekSheet> createState() => _PastWeekSheetState();
}

class _PastWeekSheetState extends State<PastWeekSheet> {
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (context, scroll) => Container(
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
          child: ListView(
            key: const ValueKey('past-week-sheet'),
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
                        _WeekChip(label: _lastWeek ? 'LAST WEEK' : 'PAST WEEK'),
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
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: WeekPactColors.graphite,
                      side: const BorderSide(
                        color: WeekPactColors.graphiteEdge,
                      ),
                      shape: WeekPactMetrics.buttonShape,
                    ),
                    icon: const AppIcon(icon: HugeIconsStrokeRounded.cancel01),
                  ),
                ],
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
                    onIndexChanged: (index) => setState(() => _index = index),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
