import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_icon.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'crew_pact_carousel.dart';
import 'crew_pact_week_card.dart';
import 'past_week_sheet.dart';

/// The crew's week so far and, under it, one row per finished week walking
/// back to the crew's first. A row opens that week as a sheet over this page
/// ([showPastWeekSheet]), so a past week never looks like the live one.
class CrewWeekPage extends StatefulWidget {
  const CrewWeekPage({
    super.key,
    required this.crew,
    required this.backend,
    required this.userId,
  });
  final PactCrew crew;
  final HomeBackend backend;
  final String userId;

  @override
  State<CrewWeekPage> createState() => _CrewWeekPageState();
}

class _CrewWeekPageState extends State<CrewWeekPage> {
  /// How many finished weeks one fetch brings back.
  static const _historyPage = 12;

  /// How much of the past-weeks heading shows under the overview before any
  /// scrolling: enough to say there is more, not enough to crowd the week.
  static const _historyPeek = 44.0;

  CrewWeek? _week;
  String? _error;
  List<CrewWeekSummary>? _history;
  bool _historyFailed = false;
  bool _moreWeeks = false;
  bool _loadingMore = false;
  int _request = 0;
  int _index = 0;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() => _refreshing = true);
    // The list of past weeks is asked for alongside the week, and a failure
    // there is its own: the week still shows, and the list says it could not.
    final history = widget.backend
        .fetchWeekHistory(widget.crew.id, limit: _historyPage)
        .then<List<CrewWeekSummary>?>((weeks) => weeks)
        .catchError((Object _) => null);
    try {
      final week = await widget.backend.fetchWeek(widget.crew.id);
      final weeks = await history;
      if (!mounted || request != _request) return;
      setState(() {
        _week = week;
        _error = null;
        _history = weeks;
        _historyFailed = weeks == null;
        _moreWeeks = (weeks?.length ?? 0) >= _historyPage;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load crew activity. Try again.');
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _loadMoreWeeks() async {
    final history = _history;
    if (history == null || history.isEmpty || _loadingMore) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final more = await widget.backend.fetchWeekHistory(
        widget.crew.id,
        before: history.last.weekStart,
        limit: _historyPage,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _history = [...history, ...more];
        _moreWeeks = more.length >= _historyPage;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _moreWeeks = false);
    } finally {
      if (mounted && request == _request) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _openWeek(CrewWeekSummary week) => showPastWeekSheet(
    context: context,
    crew: widget.crew,
    backend: widget.backend,
    userId: widget.userId,
    weekStart: week.weekStart,
    currentWeekStart: _week?.weekStart ?? week.weekStart,
  );

  /// What the line under the crew's name calls the week on show.
  String _weekLabel(CrewWeek? week) {
    if (week == null) return 'This week';
    final monday = DateTime.parse(week.weekStart);
    return 'This week · ${crewDateLabel(monday)} – ${crewDateLabel(monday.add(const Duration(days: 6)))}';
  }

  /// Whether the page carries a past-weeks section under the overview. Only
  /// when there is something to put there: a crew in its first week has no
  /// history, and the page stays one viewport rather than promising a list
  /// it cannot fill.
  bool get _hasHistory =>
      _week != null && (_historyFailed || (_history?.isNotEmpty ?? false));

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
    return Scaffold(
      body: WeekPactBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => RefreshIndicator(
              onRefresh: () {
                unawaited(
                  HapticFeedback.mediumImpact().catchError((Object _) {}),
                );
                return _refresh();
              },
              color: WeekPactColors.black,
              backgroundColor: WeekPactColors.cream,
              child: CustomScrollView(
                key: const ValueKey('crew-refresh-viewport'),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  // The overview is one viewport, as it always was. With
                  // past weeks beneath it gives up the height of their
                  // heading, so the heading shows under the fold and says
                  // the page goes on.
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height:
                          viewport.maxHeight - (_hasHistory ? _historyPeek : 0),
                      child: _overview(context, week, members),
                    ),
                  ),
                  if (_hasHistory)
                    SliverToBoxAdapter(
                      child: _PastWeeks(
                        weeks: _history ?? const [],
                        failed: _historyFailed,
                        more: _moreWeeks,
                        loadingMore: _loadingMore,
                        onOpen: _openWeek,
                        onMore: _loadMoreWeeks,
                        onRetry: _refreshing ? null : _refresh,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overview(
    BuildContext context,
    CrewWeek? week,
    List<WeekMember> members,
  ) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: LayoutBuilder(
          builder: (context, space) {
            final extraText = math.max(
              0.0,
              MediaQuery.textScalerOf(context).scale(1) - 1,
            );
            // Keep the complete overview in the viewport, including
            // compact phones, landscape, and larger system text.
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: math.max(space.maxWidth, 360 + extraText * 140),
                height: math.max(space.maxHeight, 700 + extraText * 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Back to home',
                          onPressed: () => Navigator.pop(context),
                          icon: const AppIcon(
                            icon: HugeIconsStrokeRounded.arrowLeft02,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      widget.crew.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _weekLabel(week),
                      style: TextStyle(color: context.muted, fontSize: 15),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      Text(_error!, style: TextStyle(color: context.errorInk)),
                      TextButton(
                        onPressed: _refreshing ? null : _refresh,
                        child: const Text('TRY AGAIN'),
                      ),
                    ],
                    if (week == null)
                      Expanded(
                        child: _refreshing
                            ? const _CrewWeekSkeleton()
                            // A failure has its own sentence and its own way
                            // out, above. Standing "Your crew's week" under
                            // those reads as the page carrying on regardless.
                            : _error != null
                            ? const SizedBox.shrink()
                            : const Center(child: Text('Your crew’s week')),
                      )
                    else ...[
                      _WeekSummary(week: week),
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
                      Expanded(
                        child: CrewPactCarousel(
                          week: week,
                          members: members,
                          userId: widget.userId,
                          onIndexChanged: (index) =>
                              setState(() => _index = index),
                        ),
                      ),
                      _TodaySummary(week: week),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// The finished weeks under the overview, newest first: the dates, seven
/// segments for how much of the crew was out each day, and the crew's
/// percentage. Each row opens that week as its own page.
class _PastWeeks extends StatelessWidget {
  const _PastWeeks({
    required this.weeks,
    required this.failed,
    required this.more,
    required this.loadingMore,
    required this.onOpen,
    required this.onMore,
    required this.onRetry,
  });
  final List<CrewWeekSummary> weeks;
  final bool failed;
  final bool more;
  final bool loadingMore;
  final ValueChanged<CrewWeekSummary> onOpen;
  final VoidCallback onMore;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Column(
          key: const ValueKey('crew-past-weeks'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _CrewWeekPageState._historyPeek,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Text(
                      'Past weeks',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!failed)
                    Text(
                      'Crew progress',
                      style: TextStyle(color: context.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (failed) ...[
              Text(
                'Could not load past weeks.',
                style: TextStyle(color: context.errorInk),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('TRY AGAIN'),
                ),
              ),
            ] else ...[
              for (final week in weeks) ...[
                _PastWeekRow(week: week, onTap: () => onOpen(week)),
                const SizedBox(height: 10),
              ],
              if (more)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: loadingMore ? null : onMore,
                    child: Text(loadingMore ? 'LOADING…' : 'EARLIER WEEKS'),
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _PastWeekRow extends StatelessWidget {
  const _PastWeekRow({required this.week, required this.onTap});
  final CrewWeekSummary week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(week.weekStart);
    final end = start.add(const Duration(days: 6));
    // The month is said once unless the week crosses into the next one.
    final dates = end.month == start.month
        ? '${crewDateLabel(start)} – ${end.day}'
        : '${crewDateLabel(start)} – ${crewDateLabel(end)}';
    final kept = week.percent >= 100;
    return Semantics(
      button: true,
      label:
          'Week of ${crewDateLabel(start)} to ${crewDateLabel(end)}: ${week.percent}% crew progress',
      child: AppSurface(
        fillColor: WeekPactColors.neutralInset,
        // The label above says the whole row; the row's own words would only
        // be read out again after it.
        builder: (context) => InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dates,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        for (var day = 0; day < 7; day++) ...[
                          if (day > 0) const SizedBox(width: 4),
                          Expanded(
                            child: _DaySegment(
                              share: week.shareOut.elementAtOrNull(day) ?? 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 50,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${week.percent}%',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: kept ? WeekPactColors.doneMark : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AppIcon(
                    icon: HugeIconsStrokeRounded.arrowRight01,
                    size: 18,
                    color: context.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One day of a finished week, as a share of the crew, drawn as the
/// calendar draws a day: raised, the same kept green when some of the crew
/// was out and the check mark's deeper green when all of it was, and a flat
/// pale slot when nobody was. The outline and the 2pt edge are mixed from
/// the cell's own fill, the way every raised surface here builds its shadow.
///
/// A plain rounded rect at `controlRadius`, not the squircle: on a box this
/// small the continuous corner's path leaves ticks of the outline at the top
/// and bottom edges, and the metrics name the rounded rect for a cell.
class _DaySegment extends StatelessWidget {
  const _DaySegment({required this.share});
  final double share;

  @override
  Widget build(BuildContext context) {
    final out = share > 0;
    final face = share >= 1
        ? WeekPactColors.doneMark
        : out
        ? WeekPactColors.keptDay
        : WeekPactColors.cream.withValues(alpha: .6);
    return Padding(
      // Room below for the raised edge, so it does not touch the row's edge.
      padding: const EdgeInsets.only(bottom: WeekPactMetrics.controlDepth),
      child: SizedBox(
        height: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: face,
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
            border: Border.all(
              color: out
                  ? Color.lerp(face, Colors.black, .28)!
                  : context.ink.withValues(alpha: .10),
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
        ),
      ),
    );
  }
}

class _WeekSummary extends StatelessWidget {
  const _WeekSummary({required this.week});
  final CrewWeek week;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AppSurface(
            fillColor: week.percentCrew >= 100
                ? WeekPactColors.mintGreen
                : WeekPactColors.crewProgress,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${week.percentCrew}%',
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Crew progress',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          // The same squircle, outline and raised edge as the progress card
          // beside it: a plain rounded rect read as a different family.
          child: AppSurface(
            fillColor: WeekPactDarkCard.fill,
            resolveTone: false,
            outlineColor: WeekPactDarkCard.outline,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const AppIcon(
                    icon: HugeIconsStrokeRounded.fire,
                    color: WeekPactDarkCard.muted,
                    size: 30,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          week.streakWeeks == 0
                              ? 'Week 1'
                              : '${week.streakWeeks} ${week.streakWeeks == 1 ? 'week' : 'weeks'}',
                          style: const TextStyle(
                            color: WeekPactDarkCard.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          week.streakWeeks == 0
                              ? 'Start your first crew streak'
                              : 'Crew streak',
                          style: const TextStyle(
                            color: WeekPactDarkCard.muted,
                            fontSize: 12,
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
      ],
    ),
  );
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.week});
  final CrewWeek week;

  @override
  Widget build(BuildContext context) {
    final count = week.members
        .where((member) => week.checkedToday(member.id).isNotEmpty)
        .length;
    return AppSurface(
      fillColor: WeekPactColors.stone,
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const AppIcon(icon: HugeIconsStrokeRounded.userGroup, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count of ${week.members.length} checked in today',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    crewDateLabel(DateTime.parse(week.today)),
                    style: const TextStyle(
                      fontSize: 13,
                      color: WeekPactColors.mutedLight,
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

/// The crew week while it loads: the same blocks in the same places as the
/// page it becomes, so nothing jumps when the week arrives.
class _CrewWeekSkeleton extends StatefulWidget {
  const _CrewWeekSkeleton();

  @override
  State<_CrewWeekSkeleton> createState() => _CrewWeekSkeletonState();
}

class _CrewWeekSkeletonState extends State<_CrewWeekSkeleton>
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

  /// A card-shaped placeholder: the squircle the real surfaces use, so the
  /// loading page has the same silhouette as the loaded one.
  Widget get _card => const SkeletonBar(
    height: double.infinity,
    shape: WeekPactMetrics.pactCardShape,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your crew’s week',
    liveRegion: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: Column(
            key: const ValueKey('crew-week-skeleton'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Crew progress and the streak, side by side.
              SizedBox(
                height: 92,
                child: Row(
                  children: [
                    Expanded(child: _card),
                    const SizedBox(width: 10),
                    Expanded(child: _card),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const SkeletonBar(width: 132, height: 22),
                  const Spacer(),
                  const SkeletonBar(width: 38, height: 16),
                ],
              ),
              const SizedBox(height: 12),
              // The pact carousel's active card, inset the way its page is.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    5,
                    0,
                    5,
                    WeekPactMetrics.controlDepth + 1,
                  ),
                  child: _card,
                ),
              ),
              SizedBox(
                height: 44,
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: SkeletonBar(width: 8, height: 8),
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
  );
}
