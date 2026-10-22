import 'package:hugeicons/hugeicons.dart';
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
import 'crew_month_calendar.dart';
import 'crew_month_photos_sheet.dart';
import 'crew_page_layout.dart';
import 'crew_pact_carousel.dart';
import 'crew_pact_week_card.dart';
import 'crew_switcher.dart';
import 'past_week_sheet.dart';

/// The crew's week so far and, under it, a month calendar of the crew's weeks
/// ([CrewMonthCalendar]). A finished week opens as a sheet over this page
/// ([showPastWeekSheet]), so a past week never looks like the live one.
class CrewWeekPage extends StatefulWidget {
  const CrewWeekPage({
    super.key,
    required this.crew,
    required this.backend,
    required this.userId,
    this.crews = const [],
    this.onCrewSelected,
  });
  final PactCrew crew;
  final HomeBackend backend;
  final String userId;

  /// Every crew the viewer is in, for the switcher in the title. Empty when
  /// the page is only ever about [crew], which then stands without a chevron.
  final List<PactCrew> crews;

  /// Told when the viewer switches crew here, so the page behind follows.
  final ValueChanged<String>? onCrewSelected;

  @override
  State<CrewWeekPage> createState() => _CrewWeekPageState();
}

class _CrewWeekPageState extends State<CrewWeekPage> {
  late PactCrew _crew = widget.crew;

  /// How many finished weeks one fetch brings back.
  static const _historyPage = 12;

  /// How much of the calendar's month header shows under the overview before
  /// any scrolling: enough to say there is more, not enough to crowd the week.
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
  DateTime? _shownMonth;

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
        .fetchWeekHistory(_crew.id, limit: _historyPage)
        .then<List<CrewWeekSummary>?>((weeks) => weeks)
        .catchError((Object _) => null);
    try {
      final week = await widget.backend.fetchWeek(_crew.id);
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

  /// How much of the crew was out on [day]: from this week's own check-ins
  /// while it runs, from the loaded history before that, and null for a day
  /// neither covers.
  double? _shareOn(DateTime day) {
    final week = _week;
    if (week == null) return null;
    final iso = day.toIso8601String().substring(0, 10);
    if (iso.compareTo(week.weekStart) >= 0) {
      return iso.compareTo(week.today) <= 0 ? week.shareOut(iso) : null;
    }
    final monday = mondayOf(day).toIso8601String().substring(0, 10);
    final past = _history?.where((w) => w.weekStart == monday).firstOrNull;
    return past?.shareOut.elementAtOrNull(day.weekday - DateTime.monday);
  }

  /// Switches the page to another crew: everything that belonged to the old
  /// one goes, the page shows its skeleton, and the new crew's week loads.
  void _selectCrew(String id) {
    final crew = widget.crews.where((c) => c.id == id).firstOrNull;
    if (crew == null || crew.id == _crew.id) return;
    setState(() {
      _crew = crew;
      _week = null;
      _error = null;
      _history = null;
      _historyFailed = false;
      _moreWeeks = false;
      _shownMonth = null;
      _index = 0;
    });
    widget.onCrewSelected?.call(id);
    _refresh();
  }

  Future<void> _loadMoreWeeks() async {
    final history = _history;
    if (history == null || history.isEmpty || _loadingMore) return;
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final more = await widget.backend.fetchWeekHistory(
        _crew.id,
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

  /// The month the calendar shows: this one until the crew steps back.
  DateTime get _month {
    final shown = _shownMonth;
    if (shown != null) return shown;
    final today = DateTime.parse(_week!.today);
    return DateTime(today.year, today.month);
  }

  /// The crew's first week on record, as far as the history has loaded.
  String get _earliestWeek {
    final history = _history;
    return history == null || history.isEmpty
        ? _week!.weekStart
        : history.last.weekStart;
  }

  /// Whether there is a month before the one on show with any of the crew's
  /// weeks in it: more history to fetch, or a loaded week that starts before
  /// this month does.
  bool get _canGoBack =>
      _moreWeeks ||
      DateTime.parse(_earliestWeek)
          .isBefore(DateTime(_month.year, _month.month));

  bool get _canGoForward {
    final today = DateTime.parse(_week!.today);
    return _month.isBefore(DateTime(today.year, today.month));
  }

  Future<void> _showMonth(int step) async {
    final month = DateTime(_month.year, _month.month + step);
    setState(() => _shownMonth = month);
    // Fetch back until the month's first week is in, or the crew runs out.
    final first = monthWeeks(month).first;
    while (_moreWeeks &&
        mounted &&
        DateTime.parse(_earliestWeek).isAfter(first)) {
      final before = _history?.length;
      await _loadMoreWeeks();
      if (_history?.length == before) break;
    }
  }

  Future<void> _openWeek(CrewWeekSummary week) => showPastWeekSheet(
    context: context,
    crew: _crew,
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
                      child: _History(
                        failed: _historyFailed,
                        onRetry: _refreshing ? null : _refresh,
                        calendar: (_) => CrewMonthCalendar(
                          month: _month,
                          weeks: {
                            for (final past in _history ?? const [])
                              past.weekStart: past,
                          },
                          current: week!,
                          headerHeight: _historyPeek,
                          onOpenWeek: _openWeek,
                          onPrevious: _canGoBack && !_loadingMore
                              ? () => _showMonth(-1)
                              : null,
                          onNext: _canGoForward ? () => _showMonth(1) : null,
                        ),
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
                    // The crew's name is the page's title, as it is on
                    // Home: the same switcher, so the week of another crew
                    // is one tap away rather than a trip back.
                    CrewPageHeading(
                      leading: [
                        IconButton(
                          tooltip: 'Back to home',
                          onPressed: () {
                            unawaited(
                              HapticFeedback.lightImpact().catchError(
                                (Object _) {},
                              ),
                            );
                            Navigator.pop(context);
                          },
                          icon: const AppIcon(
                            icon: HugeIconsStrokeRounded.arrowLeft02,
                          ),
                        ),
                      ],
                      switcher: CrewSwitcher(
                        key: const ValueKey('crew-week-switcher'),
                        crews: widget.crews.isEmpty ? [_crew] : widget.crews,
                        selectedId: _crew.id,
                        onSelected: _selectCrew,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _weekLabel(week),
                      textAlign: TextAlign.center,
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
                      _StreakCard(
                        week: week,
                        shareOn: _shareOn,
                        onViewMonth: () => showCrewMonthPhotosSheet(
                          context: context,
                          crewId: _crew.id,
                          backend: widget.backend,
                          userId: widget.userId,
                          week: week,
                        ),
                      ),
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

/// The crew's history under the overview: a month calendar of its weeks, or
/// a way to try again when the weeks could not be loaded.
class _History extends StatelessWidget {
  const _History({
    required this.failed,
    required this.onRetry,
    required this.calendar,
  });
  final bool failed;
  final VoidCallback? onRetry;
  final WidgetBuilder calendar;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: failed
            ? Column(
                key: const ValueKey('crew-past-weeks'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: _CrewWeekPageState._historyPeek),
                  Text(
                    'Could not load past weeks.',
                    style: TextStyle(color: context.errorInk),
                  ),
                  TextButton(
                    onPressed: onRetry == null
                        ? null
                        : () {
                            unawaited(
                              HapticFeedback.lightImpact().catchError(
                                (Object _) {},
                              ),
                            );
                            onRetry!();
                          },
                    child: const Text('TRY AGAIN'),
                  ),
                ],
              )
            : KeyedSubtree(
                key: const ValueKey('crew-past-weeks'),
                child: calendar(context),
              ),
      ),
    ),
  );
}

/// Hugeicons' rounded flame, filled rather than outlined, so the streak's
/// number can stand inside it.
final _solidFlame = [
  for (final element in HugeIconsStrokeRounded.fire02)
    [
      element[0],
      {...(element[1] as Map<String, dynamic>), 'fill': 'currentColor'},
    ],
];

/// The crew's streak above its pacts: the flame with the weeks kept in a row,
/// and beside it this month as squircles — one per day, filled where the crew
/// was out, outlined on today, faintly outlined for the days still to come.
/// "View month" in the header opens the month in photos.
class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.week,
    required this.shareOn,
    required this.onViewMonth,
  });
  final CrewWeek week;
  final VoidCallback onViewMonth;

  /// How much of the crew was out on a day, or null where nothing is known.
  final double? Function(DateTime day) shareOn;

  static const _dot = 15.0;
  static const _dotGap = 9.0;

  @override
  Widget build(BuildContext context) {
    final weeks = week.streakWeeks;
    final today = DateTime.parse(week.today);
    final month = DateTime(today.year, today.month);
    final flame = weeks > 0
        ? WeekPactColors.streak
        : WeekPactColors.pendingEdge;
    return AppSurface(
      fillColor: WeekPactColors.cream,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 16),
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
                        fontSize: 17,
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
                    foregroundColor: WeekPactColors.doneMark,
                    padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: WeekPactMetrics.buttonShape,
                    textStyle: const TextStyle(
                      fontFamily: WeekPactType.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View month'),
                      SizedBox(width: 2),
                      HugeIcon(
                        icon: HugeIconsStrokeRounded.arrowRight01,
                        size: 16,
                        color: WeekPactColors.doneMark,
                        strokeWidth: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Semantics(
                label:
                    'Crew streak: $weeks ${weeks == 1 ? 'week' : 'weeks'}. ${_daysOut(month, today)} days out this month',
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 80,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  HugeIcon(
                                    icon: _solidFlame,
                                    size: 80,
                                    color: flame,
                                  ),
                                  // The flame's body is low and round; the
                                  // number sits in it, not in the tip.
                                  Align(
                                    alignment: const Alignment(0, .42),
                                    child: Text(
                                      '$weeks',
                                      style: const TextStyle(
                                        color: WeekPactColors.cream,
                                        fontSize: 26,
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
                                fontSize: 22,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // The dots take the other half and sit in its middle, so
                      // flame and month are balanced about the card's centre
                      // rather than the flame centring in whatever the dots
                      // leave over.
                      Expanded(child: Center(child: _monthDots(month, today))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _daysOut(DateTime month, DateTime today) => [
    for (var d = 1; d <= today.day; d++)
      shareOn(DateTime(month.year, month.month, d)),
  ].where((share) => (share ?? 0) > 0).length;

  Widget _monthDots(DateTime month, DateTime today) {
    final ink = WeekPactColors.outlineInk;
    Widget dot(DateTime day) {
      if (day.month != month.month) {
        return const SizedBox.square(dimension: _dot);
      }
      final isToday = day == today;
      final future = day.isAfter(today);
      final out = !future && (shareOn(day) ?? 0) > 0;
      // A squircle, like the app's cards and tiles, at the corner a card
      // this small reads as.
      return Container(
        width: _dot,
        height: _dot,
        decoration: ShapeDecoration(
          color: out
              ? ink
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
              // The streak card.
              SizedBox(height: 172, child: _card),
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
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    ),
  );
}
