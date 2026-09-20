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
import 'crew_pact_week_card.dart';

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
  // Under a full viewport the neighbouring cards peek in at either edge, so
  // the carousel says it can be swiped without an arrow to explain it.
  static const _peek = .88;
  final _pages = PageController(viewportFraction: _peek);
  CrewWeek? _week;
  String? _error;
  int _request = 0;
  int _index = 0;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() => _refreshing = true);
    try {
      final week = await widget.backend.fetchWeek(widget.crew.id);
      if (!mounted || request != _request) return;
      final previous = _week?.pacts.elementAtOrNull(_index)?.id;
      final selected = week.pacts.indexWhere((pact) => pact.id == previous);
      setState(() {
        _week = week;
        _error = null;
        _index = selected < 0 ? 0 : selected;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == _request && _pages.hasClients) {
          _pages.jumpToPage(_index);
        }
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

  void _showPact(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
      return;
    }
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
    );
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
    return Scaffold(
      body: _CrewRefreshViewport(
        onRefresh: _refresh,
        child: SafeArea(
          child: Center(
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
                        height: math.max(
                          space.maxHeight,
                          700 + extraText * 420,
                        ),
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
                              week == null
                                  ? 'This week'
                                  : 'This week · ${crewDateLabel(DateTime.parse(week.weekStart))} – ${crewDateLabel(DateTime.parse(week.weekStart).add(const Duration(days: 6)))}',
                              style: TextStyle(
                                color: context.muted,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_error != null) ...[
                              Text(
                                _error!,
                                style: TextStyle(color: context.errorInk),
                              ),
                              TextButton(
                                onPressed: _refreshing ? null : _refresh,
                                child: const Text('TRY AGAIN'),
                              ),
                            ],
                            if (week == null)
                              Expanded(
                                child: _refreshing
                                    ? const _CrewWeekSkeleton()
                                    : const Center(
                                        child: Text('Your crew’s week'),
                                      ),
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
                                child: week.pacts.isEmpty
                                    ? AppSurface(
                                        builder: (_) => const Center(
                                          child: Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Text(
                                              'No pacts yet. Your crew’s weekly activity will appear here.',
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      )
                                    // The carousel alone runs past the page's
                                    // margin, so the pacts either side reach
                                    // the screen's edges instead of stopping
                                    // short of it.
                                    : LayoutBuilder(
                                        builder: (context, box) => OverflowBox(
                                          minWidth:
                                              box.maxWidth +
                                              2 * WeekPactMetrics.pageInset,
                                          maxWidth:
                                              box.maxWidth +
                                              2 * WeekPactMetrics.pageInset,
                                          child: PageView.builder(
                                            key: const ValueKey(
                                              'crew-pact-carousel',
                                            ),
                                            controller: _pages,
                                            physics:
                                                MediaQuery.disableAnimationsOf(
                                                  context,
                                                )
                                                ? const ClampingScrollPhysics()
                                                : const _CarouselSpringPhysics(),
                                            itemCount: week.pacts.length,
                                            onPageChanged: (index) =>
                                                setState(() => _index = index),
                                            itemBuilder: (context, index) =>
                                                Padding(
                                                  // The card's raised edge is
                                                  // painted below its own box, and
                                                  // the carousel clips its pages,
                                                  // so the page leaves that edge
                                                  // room to show.
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        5,
                                                        0,
                                                        5,
                                                        WeekPactMetrics
                                                                .controlDepth +
                                                            1,
                                                      ),
                                                  child: CrewPactWeekCard(
                                                    key: ValueKey(
                                                      week.pacts[index].id,
                                                    ),
                                                    week: week,
                                                    pact: week.pacts[index],
                                                    tint:
                                                        WeekPactColors.pactTint(
                                                          index,
                                                        ),
                                                    members: members,
                                                    userId: widget.userId,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                              ),
                              if (week.pacts.length > 1)
                                SizedBox(
                                  height: 44,
                                  child: Center(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        children: [
                                          for (
                                            var i = 0;
                                            i < week.pacts.length;
                                            i++
                                          )
                                            Semantics(
                                              selected: i == _index,
                                              child: IconButton(
                                                tooltip:
                                                    'Show ${week.pacts[i].title}',
                                                onPressed: () => _showPact(i),
                                                icon: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 150,
                                                  ),
                                                  width: i == _index ? 20 : 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(
                                                    color: context.ink
                                                        .withValues(
                                                          alpha: i == _index
                                                              ? 1
                                                              : .25,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(height: 12),
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
          ),
        ),
      ),
    );
  }
}

class _CarouselSpringPhysics extends BouncingScrollPhysics {
  const _CarouselSpringPhysics({super.parent});

  @override
  _CarouselSpringPhysics applyTo(ScrollPhysics? ancestor) =>
      _CarouselSpringPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: 0.75);
}

/// Allows the refresh gesture while keeping the content exactly one viewport.
class _CrewRefreshViewport extends StatelessWidget {
  const _CrewRefreshViewport({required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => WeekPactBackground(
    child: RefreshIndicator(
      onRefresh: () {
        unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
        return onRefresh();
      },
      color: WeekPactColors.black,
      backgroundColor: WeekPactColors.cream,
      child: CustomScrollView(
        key: const ValueKey('crew-refresh-viewport'),
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [SliverFillRemaining(hasScrollBody: true, child: child)],
      ),
    ),
  );
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
                : WeekPactColors.stone,
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
