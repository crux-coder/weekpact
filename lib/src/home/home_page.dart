import 'photo_check_in_sheet.dart';
import '../crew/crew_selection_store.dart';
import '../onboarding/crew_setup_page.dart';
import '../auth/account_page.dart';
import 'home_surface.dart';

import 'package:flutter/services.dart';

import 'dart:async';

import '../crew/crew_week_page.dart';

import '../feed/feed_page.dart';
import 'home_backend.dart';

import 'package:flutter/material.dart';

import '../crew/crew_switcher.dart';
import '../pacts/pacts_backend.dart';
import '../pacts/pacts_page.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/auth_backend.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_page.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'today_widgets.dart';
import 'expandable_home_panels.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.user,
    required this.authBackend,
    required this.crewBackend,
    this.initialCrewId,
    this.crewSelectionStore,
    this.captureCheckInPhoto,
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
  });

  final AuthUser user;
  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final String? initialCrewId;
  final CrewSelectionStore? crewSelectionStore;
  final CheckInPhotoCapture? captureCheckInPhoto;
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
      color: WeekPactColors.stone,
    ),
    AppNavigationItem(
      label: 'Feed',
      icon: HugeIconsStrokeRounded.image02,
      color: WeekPactColors.coolGrey,
    ),
    AppNavigationItem(
      label: 'Pacts',
      icon: HugeIconsStrokeRounded.agreement02,
      color: WeekPactColors.mintGreen,
    ),
    AppNavigationItem(
      label: 'Crews',
      icon: HugeIconsStrokeRounded.userGroup,
      color: WeekPactColors.stone,
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
  String? _selectedCrewId;
  String get _accountId => widget.user.id.isNotEmpty
      ? widget.user.id
      : widget.user.email.toLowerCase();

  void _selectCrew(String id) {
    if (_selectedCrewId == id) return;
    setState(() => _selectedCrewId = id);
    unawaited(_rememberCrew(id));
  }

  Future<void> _rememberCrew(String id) async {
    try {
      await widget.crewSelectionStore?.save(_accountId, id);
    } catch (_) {
      if (!mounted || _selectedCrewId != id) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remember your crew for next time.'),
        ),
      );
    }
  }

  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _selectedCrewId =
        widget.initialCrewId ?? widget.crewSelectionStore?.read(_accountId);
    if (widget.initialCrewId != null) {
      unawaited(_rememberCrew(widget.initialCrewId!));
    }
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
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
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
    if (crew != null) _selectCrew(crew.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewSetupPage(
          crewBackend: widget.crewBackend,
          pactsBackend: widget.pactsBackend,
          homeBackend: widget.homeBackend,
          userId: widget.user.id,
          initialCrew: crew,
          crewId: _selectedCrewId,
          captureCheckInPhoto: widget.captureCheckInPhoto,
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
            selectedCrewId: _selectedCrewId,
            onCrewSelected: _selectCrew,
            pactsBackend: widget.pactsBackend,
            userId: widget.user.id,
            captureCheckInPhoto: widget.captureCheckInPhoto,
            active: _selectedIndex == 0,
            onStartCrew: _startCrew,
            onOpenCrews: () => _selectDestination(3),
            onOpenPacts: () => _selectDestination(2),
            onOpenFeed: () => _selectDestination(1),
          ),
          FeedPage(
            backend: widget.homeBackend,
            userId: widget.user.id,
            active: _selectedIndex == 1,
          ),
          PactsPage(
            active: _selectedIndex == 2,
            backend: widget.pactsBackend,
            loadWeek: widget.homeBackend.fetchWeek,
            userId: widget.user.id,
            selectedCrewId: _selectedCrewId,
            onCrewSelected: _selectCrew,
            onOpenCrews: () => _selectDestination(3),
          ),
          CrewPage(
            active: _selectedIndex == 3,
            onInviteAccepted: () => _selectDestination(0),
            onCrewLeft: () => _selectDestination(0),
            onCrewCreated: _startCrew,
            backend: widget.crewBackend,
            selectedCrewId: _selectedCrewId,
            onCrewSelected: _selectCrew,
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
    this.captureCheckInPhoto,
    this.selectedCrewId,
    this.onCrewSelected,
    required this.onOpenCrews,
    required this.onOpenPacts,
    required this.onOpenFeed,
    required this.onStartCrew,
  });
  final CheckInPhotoCapture? captureCheckInPhoto;
  final HomeBackend backend;
  final PactsBackend pactsBackend;
  final String userId;
  final String? selectedCrewId;
  final ValueChanged<String>? onCrewSelected;
  final bool active;
  final VoidCallback onOpenCrews;
  final VoidCallback onOpenPacts;
  final VoidCallback onOpenFeed;
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
    if (widget.active &&
        (!oldWidget.active ||
            (widget.selectedCrewId != oldWidget.selectedCrewId &&
                widget.selectedCrewId != _crew?.id))) {
      _refresh();
    }
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
      final matches = crews.where(
        (c) => c.id == (crewId ?? widget.selectedCrewId ?? _crew?.id),
      );
      final crew = matches.isNotEmpty ? matches.first : crews.firstOrNull;
      setState(() {
        _crews = crews;
        if (crew?.id != _crew?.id) _week = null;
        _crew = crew;
        _error = null;
      });
      if (crew != null && crew.id != widget.selectedCrewId) {
        widget.onCrewSelected?.call(crew.id);
      }
      final week = crew == null
          ? null
          : await widget.backend.fetchWeek(crew.id);
      if (mounted && request == _request) {
        setState(() => _week = week);
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
      if (selected.contains(pactId)) {
        final saved = await showPhotoCheckIn(
          userId: widget.userId,
          context: context,
          backend: widget.backend,
          crewId: crew.id,
          pactId: pactId,
          pactTitle: week.pacts.firstWhere((p) => p.id == pactId).title,
          today: week.today,
          selectedPactIds: selected,
          capturePhoto: widget.captureCheckInPhoto,
        );
        if (!saved) return;
      } else {
        await widget.backend.saveCheckIns(
          crewId: crew.id,
          today: week.today,
          pactIds: selected,
        );
      }
      if (!mounted) return;
      if (selected.contains(pactId)) {
        // Haptics are best-effort and must never turn a saved check-in into an error.
        unawaited(HapticFeedback.heavyImpact().catchError((Object _) {}));
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
      if (mounted) {
        setState(() => _savingPact = null);
        if (_saveError == null) await _refresh();
      }
    }
  }

  /// The crew switcher, as Pacts and Crews carry it: the same compact control
  /// under the page's own heading, so switching crews is the one gesture
  /// wherever you are. Null until the crews are in — there is nothing to
  /// switch between yet, and the heading stands alone until there is.
  Widget? _selector() {
    final crews = _crews;
    if (crews == null || crews.isEmpty) return null;
    return CrewSwitcher(
      key: const ValueKey('home-crew-switcher'),
      compact: true,
      // Home stacks the switcher on the crew panel at the same width, so it
      // takes the corner that column is cut to rather than the standalone
      // control's own.
      curve: CrewWeekButton.frameCurve,
      crews: crews,
      selectedId: _crew?.id ?? widget.selectedCrewId,
      loadWeek: widget.backend.fetchWeek,
      // A switch mid-save would save the check-in against the crew being
      // left, so the control waits for the write to land.
      onSelected: _savingPact != null ? null : widget.onCrewSelected,
    );
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
      child: RefreshIndicator(
        onRefresh: () {
          unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
          return _refresh();
        },
        color: WeekPactColors.black,
        backgroundColor: WeekPactColors.cream,
        child: CustomScrollView(
          key: const ValueKey('home-refresh-viewport'),
          physics: MediaQuery.disableAnimationsOf(context)
              ? const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                )
              : const _HomeRefreshPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: true,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Preserve a complete, non-scrolling composition even when
                        // safe areas or landscape leave less than its minimum height.
                        final pageHeight = constraints.maxHeight.clamp(
                          // Heading and its switcher, the crew panel and a
                          // usable pact card; shorter viewports scale down.
                          312 +
                              HomeHeader.height +
                              HomeCrewPanel.height +
                              (_saveError == null ? 0 : 40),
                          double.infinity,
                        );
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: pageHeight,
                            child: Builder(
                              builder: (context) {
                                final selector = _selector();
                                if (loading) {
                                  // The switcher stays mounted through a
                                  // switch, so the hand it is putting away
                                  // finishes its flight rather than blinking
                                  // out with the page under it.
                                  return TodaySkeleton(selector: selector);
                                }
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
                                            fontWeight: FontWeight.w700,
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
                                if (week == null) {
                                  return const SizedBox.shrink();
                                }
                                return ExpandableHomePanels(
                                  key: ValueKey(_crew!.id),
                                  backend: widget.backend,
                                  crewId: _crew!.id,
                                  week: week,
                                  userId: widget.userId,
                                  active: widget.active,
                                  // The crew panel is empty, so nothing
                                  // unfolds over it and there is no tile for
                                  // a panel to line up with.
                                  showCrewCheckIns: false,
                                  top:
                                      HomeHeader.height +
                                      12 +
                                      CrewWeekButton.pad,
                                  inset: CrewWeekButton.pad,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      HomeHeader(
                                        streakWeeks: week.streakWeeks,
                                        selector: selector,
                                      ),
                                      const SizedBox(height: 12),
                                      HomeCrewPanel(
                                        key: const ValueKey('home-crew-panel'),
                                        week: week,
                                        userId: widget.userId,
                                        onOpenWeek: _openCrewWeek,
                                        backend: widget.backend,
                                        crewId: _crew!.id,
                                        active: widget.active,
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
                                              color: context.errorInk,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: week.pacts.isEmpty
                                            ? Center(
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'No pacts yet.',
                                                      style: TextStyle(
                                                        color: context.ink,
                                                        fontSize: 24,
                                                        fontWeight:
                                                            FontWeight.w700,
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
                                                      height: space.maxHeight,
                                                      horizontalBleed: 12,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeRefreshPhysics extends BouncingScrollPhysics {
  const _HomeRefreshPhysics({super.parent});

  @override
  _HomeRefreshPhysics applyTo(ScrollPhysics? ancestor) =>
      _HomeRefreshPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: .75);
}
