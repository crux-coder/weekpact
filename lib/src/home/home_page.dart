import '../recaps/weekly_recap.dart';
import '../onboarding/crew_setup_page.dart';
import '../auth/account_page.dart';
import 'home_surface.dart';

import 'package:flutter/services.dart';

import '../crew/crew_week_page.dart';

import 'dart:async';

import 'home_backend.dart';

import 'package:flutter/material.dart';

import '../pacts/pacts_backend.dart';
import '../pacts/pacts_page.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/auth_backend.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_page.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'today_widgets.dart';
import 'latest_activity_row.dart';
import 'expandable_home_panels.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.user,
    required this.authBackend,
    required this.crewBackend,
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
  });

  final AuthUser user;
  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final PactsBackend pactsBackend;
  final HomeBackend homeBackend;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _navigationItems = [
    AppNavigationItem(
      label: 'Home',
      icon: HugeIconsStrokeRounded.home01,
      color: WeekPactColors.softYellow,
    ),
    AppNavigationItem(
      label: 'Pacts',
      icon: HugeIconsStrokeRounded.agreement02,
      color: WeekPactColors.mintGreen,
    ),
    AppNavigationItem(
      label: 'Crews',
      icon: HugeIconsStrokeRounded.userGroup,
      color: WeekPactColors.softYellow,
    ),
    AppNavigationItem(
      label: 'Account',
      icon: HugeIconsStrokeRounded.userAccount,
      color: WeekPactColors.softCoral,
    ),
  ];

  late final PageController _pageController;
  int _selectedIndex = 0;
  int _homeRevision = 0;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectDestination(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _startCrew([CrewDetails? crew]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewSetupPage(
          crewBackend: widget.crewBackend,
          pactsBackend: widget.pactsBackend,
          homeBackend: widget.homeBackend,
          userId: widget.user.id,
          initialCrew: crew,
        ),
      ),
    );
    if (mounted) {
      setState(() => _homeRevision++);
      _selectDestination(0);
    }
  }

  Future<void> _signOut() async {
    setState(() => _signingOut = true);
    try {
      await widget.authBackend.signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: _selectedIndex == 0 ? Colors.transparent : null,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _HomeDestination(
            key: ValueKey(_homeRevision),
            backend: widget.homeBackend,
            pactsBackend: widget.pactsBackend,
            userId: widget.user.id,
            active: _selectedIndex == 0,
            onStartCrew: _startCrew,
            onOpenCrews: () => _selectDestination(2),
            onOpenPacts: () => _selectDestination(1),
          ),
          PactsPage(
            active: _selectedIndex == 1,
            backend: widget.pactsBackend,
            onOpenCrews: () => _selectDestination(2),
          ),
          CrewPage(
            active: _selectedIndex == 2,
            onInviteAccepted: () => _selectDestination(0),
            onCrewLeft: () => _selectDestination(0),
            onCrewCreated: _startCrew,
            backend: widget.crewBackend,
            profileBackend: widget.homeBackend,
            currentUserEmail: widget.user.email,
          ),
          AccountPage(
            user: widget.user,
            backend: widget.authBackend,
            signingOut: _signingOut,
            onSignOut: _signOut,
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavigationBar(
        items: _navigationItems,
        selectedIndex: _selectedIndex,
        onSelected: _selectDestination,
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: HomeBackground(child: scaffold),
    );
  }
}

class _HomeDestination extends StatefulWidget {
  const _HomeDestination({
    super.key,
    required this.backend,
    required this.pactsBackend,
    required this.userId,
    required this.active,
    required this.onOpenCrews,
    required this.onOpenPacts,
    required this.onStartCrew,
  });
  final HomeBackend backend;
  final PactsBackend pactsBackend;
  final String userId;
  final bool active;
  final VoidCallback onOpenCrews;
  final VoidCallback onOpenPacts;
  final VoidCallback onStartCrew;
  @override
  State<_HomeDestination> createState() => _HomeDestinationState();
}

class _HomeDestinationState extends State<_HomeDestination>
    with WidgetsBindingObserver {
  List<PactCrew>? _crews;
  PactCrew? _crew;
  CrewWeek? _week;
  String? _error;
  int _request = 0;
  Timer? _timer;
  String? _savingPact;
  String? _saveError;
  WeeklyRecap? _recap;
  String? _presentedRecap;
  bool _recapOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.active && _savingPact == null) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomeDestination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.active &&
        _savingPact == null) {
      _refresh();
    }
  }

  Future<void> _refresh({String? crewId}) async {
    if (_savingPact != null) return;
    final request = ++_request;
    try {
      final crews = await widget.pactsBackend.fetchCrews();
      if (!mounted || request != _request) return;
      final matches = crews.where((c) => c.id == (crewId ?? _crew?.id));
      final crew = matches.isNotEmpty ? matches.first : crews.firstOrNull;
      setState(() {
        _crews = crews;
        if (crew?.id != _crew?.id) _week = null;
        _crew = crew;
        _error = null;
      });
      final week = crew == null
          ? null
          : await widget.backend.fetchWeek(crew.id);
      if (mounted && request == _request) {
        setState(() => _week = week);
        if (crew != null && widget.backend is RecapBackend) {
          try {
            final recap = await (widget.backend as RecapBackend).fetchRecap(
              crew.id,
            );
            if (!mounted || request != _request || _crew?.id != crew.id) return;
            setState(() => _recap = recap);
            final key = '${crew.id}:${recap?.weekStart}';
            if (recap != null &&
                !recap.seen &&
                widget.active &&
                !_recapOpen &&
                _presentedRecap != key &&
                ModalRoute.of(context)?.isCurrent == true) {
              _presentedRecap = key;
              await _openRecap();
            }
          } catch (_) {
            /* A recap outage must not block today's check-ins. */
          }
        }
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load your week. Please try again.');
      }
    }
  }

  Future<void> _togglePact(String pactId) async {
    final crew = _crew;
    final week = _week;
    if (_savingPact != null || crew == null || week == null) return;
    ++_request; // Discard older reads while saving this selection.
    final selected = week.checkedToday(widget.userId);
    if (!selected.add(pactId)) selected.remove(pactId);
    setState(() {
      _savingPact = pactId;
      _saveError = null;
    });
    try {
      await widget.backend.saveCheckIns(
        crewId: crew.id,
        today: week.today,
        pactIds: selected,
      );
      if (!mounted) return;
      if (selected.contains(pactId)) {
        // Haptics are best-effort and must never turn a saved check-in into an error.
        unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
      }
      setState(() {
        _week = CrewWeek(
          today: week.today,
          streakWeeks: week.streakWeeks,
          weekStart: week.weekStart,
          timezone: week.timezone,
          pacts: week.pacts,
          members: week.members,
          latestActivity:
              week.latestActivity?.userId == widget.userId &&
                  week.latestActivity?.pactId == pactId &&
                  !selected.contains(pactId)
              ? null
              : week.latestActivity,
          checkIns: [
            ...week.checkIns.where(
              (i) => i.userId != widget.userId || i.day != week.today,
            ),
            ...selected.map((id) => PactCheckIn(id, widget.userId, week.today)),
          ],
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'Could not save. Tap the pact to retry.');
      }
    } finally {
      if (mounted) setState(() => _savingPact = null);
    }
    if (mounted && _saveError == null) await _refresh();
  }

  Future<void> _openRecap() async {
    final recap = _recap;
    final crew = _crew;
    if (recap == null || crew == null || _recapOpen) return;
    _recapOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WeeklyRecapPage(recap: recap)),
    );
    _recapOpen = false;
    if (!mounted) return;
    try {
      await (widget.backend as RecapBackend).fetchRecap(
        crew.id,
        markSeen: recap.weekStart,
      );
    } catch (_) {
      /* Retry on the next visit. */
    }
  }

  Future<void> _openCrewWeek() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewWeekPage(
          crew: _crew!,
          backend: widget.backend,
          userId: widget.userId,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final week = _week;
    final loading =
        _error == null && (_crews == null || (_crew != null && week == null));
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Preserve a complete, non-scrolling composition even when
                // safe areas or landscape leave less than its minimum height.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight.clamp(
                      404 +
                          LatestActivityRow.height +
                          (_saveError == null ? 0 : 40),
                      double.infinity,
                    ),
                    child: Builder(
                      builder: (context) {
                        if (loading) return const TodaySkeleton();
                        if (_error != null) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: context.ink),
                                ),
                                TextButton(
                                  onPressed: _refresh,
                                  child: const Text('TRY AGAIN'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (_crews != null && _crews!.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Your week starts with a crew.',
                                  style: TextStyle(
                                    color: context.ink,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                AppButton(
                                  label: 'START YOUR CREW',
                                  onPressed: widget.onStartCrew,
                                ),
                                TextButton(
                                  onPressed: widget.onOpenCrews,
                                  child: const Text(
                                    'Already invited? View invitations',
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        if (week == null) return const SizedBox.shrink();
                        const crewHeight = 180.0;
                        return ExpandableHomePanels(
                          showCrewCheckIns: true,
                          key: ValueKey(_crew!.id),
                          backend: widget.backend,
                          crewId: _crew!.id,
                          week: week,
                          userId: widget.userId,
                          active: widget.active,
                          top: CrewTitleBanner.height + 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: CrewTitleBanner(
                                      name: _crew!.name,
                                      completed: week.completed(widget.userId),
                                      target: week.target,
                                    ),
                                  ),
                                  if (_recap != null)
                                    IconButton(
                                      tooltip: 'Last week’s recap',
                                      onPressed: _openRecap,
                                      icon: Icon(
                                        Icons.auto_awesome_outlined,
                                        color: context.ink,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const SizedBox(height: LatestActivityRow.height),
                              const SizedBox(height: 12),
                              TodayCrewCard(
                                showGroups: false,
                                height: crewHeight,
                                crewName: _crew!.name,
                                week: week,
                                userId: widget.userId,
                                onOpen: _openCrewWeek,
                              ),
                              const SizedBox(height: 12),
                              if (_saveError != null)
                                SizedBox(
                                  height: 40,
                                  child: Text(
                                    _saveError!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: const Color(0xFFFFB4A9),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: week.pacts.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'No pacts yet.',
                                              style: TextStyle(
                                                color: context.ink,
                                                fontSize: 24,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            AppButton(
                                              label: _crew!.isOwner
                                                  ? 'SET UP YOUR FIRST PACT'
                                                  : 'VIEW PACTS',
                                              onPressed: _crew!.isOwner
                                                  ? widget.onStartCrew
                                                  : widget.onOpenPacts,
                                            ),
                                          ],
                                        ),
                                      )
                                    : LayoutBuilder(
                                        builder: (context, space) =>
                                            TodayPactsCard(
                                              horizontalBleed: 12,
                                              height: space.maxHeight,
                                              week: week,
                                              userId: widget.userId,
                                              savingPact: _savingPact,
                                              onToggle: _togglePact,
                                            ),
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
