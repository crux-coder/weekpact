import 'photo_check_in_page.dart';
import '../crew/crew_selection_store.dart';
import '../onboarding/crew_setup_page.dart';
import '../onboarding/crew_start_page.dart';
import '../auth/account_page.dart';
import 'home_surface.dart';

import 'package:flutter/services.dart';

import 'dart:async';

import '../notifications/notifications_page.dart';
import 'home_backend.dart';
import 'nudge_sheet.dart';
import 'stories.dart';
import 'stories_rail.dart';
import 'story_seen_store.dart';
import 'story_viewer.dart';

import 'package:flutter/material.dart';

import '../crew/crew_switcher.dart';
import '../pacts/pacts_backend.dart';
import '../pacts/pacts_page.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/auth_backend.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_page.dart';
import '../crew/crew_week_page.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'today_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.user,
    required this.authBackend,
    required this.crewBackend,
    this.initialCrewId,
    this.crewSelectionStore,
    this.storySeenStore,
    this.captureCheckInPhoto,
    this.pactsBackend = const MissingPactsBackend(),
    this.homeBackend = const MissingHomeBackend(),
    this.onInviteToken,
  });

  final AuthUser user;
  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final String? initialCrewId;

  /// Handed the token from an invite link pasted into the "who are you doing
  /// this with?" page that an empty Home opens. Null where nobody upstream
  /// can act on one, in which case that page does not offer the link.
  final ValueChanged<String>? onInviteToken;
  final CrewSelectionStore? crewSelectionStore;

  /// Which of today's stories this device has already opened. Null keeps them
  /// for the run of the app and no longer.
  final StorySeenStore? storySeenStore;
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
      color: WeekPactColors.sand,
    ),
  ];

  late final PageController _pageController;

  /// The fallback when no store was handed in: stories stay seen for as long
  /// as the app is running.
  late final _seenStore = StorySeenStore.memory();
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

  /// An account with no crew is asked the same question a new one is, rather
  /// than being sent straight into the four-step setup: a link somebody
  /// sent, people to invite, or nobody yet.
  Future<void> _chooseStart() async {
    final onInviteToken = widget.onInviteToken;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => CrewStartPage(
          crewBackend: widget.crewBackend,
          pactsBackend: widget.pactsBackend,
          homeBackend: widget.homeBackend,
          userId: widget.user.id,
          firstName: widget.user.firstName,
          captureCheckInPhoto: widget.captureCheckInPhoto,
          onInviteToken: onInviteToken == null
              ? null
              : (token) {
                  Navigator.of(routeContext).pop();
                  onInviteToken(token);
                },
          onDone: () => Navigator.of(routeContext).pop(),
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
    } catch (_) {
      // Signing out reaches the server, so it fails offline. Without this the
      // row simply flipped back from "Logging out…" to "Log out" and looked
      // like a tap that never landed.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not log out. Check your connection and try again.',
            ),
          ),
        );
      }
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
            seenStore: widget.storySeenStore ?? _seenStore,
            selectedCrewId: _selectedCrewId,
            onCrewSelected: _selectCrew,
            pactsBackend: widget.pactsBackend,
            userId: widget.user.id,
            captureCheckInPhoto: widget.captureCheckInPhoto,
            active: _selectedIndex == 0,
            onStartCrew: _startCrew,
            onChooseStart: _chooseStart,
            onOpenCrews: () => _selectDestination(2),
            onOpenPacts: () => _selectDestination(1),
          ),
          PactsPage(
            active: _selectedIndex == 1,
            backend: widget.pactsBackend,
            loadWeek: widget.homeBackend.fetchWeek,
            userId: widget.user.id,
            selectedCrewId: _selectedCrewId,
            onCrewSelected: _selectCrew,
            onOpenCrews: () => _selectDestination(2),
          ),
          CrewPage(
            active: _selectedIndex == 2,
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
    required this.seenStore,
    this.captureCheckInPhoto,
    this.selectedCrewId,
    this.onCrewSelected,
    required this.onOpenCrews,
    required this.onOpenPacts,
    required this.onStartCrew,
    required this.onChooseStart,
  });
  final CheckInPhotoCapture? captureCheckInPhoto;
  final HomeBackend backend;
  final PactsBackend pactsBackend;
  final String userId;
  final StorySeenStore seenStore;
  final String? selectedCrewId;
  final ValueChanged<String>? onCrewSelected;
  final bool active;
  final VoidCallback onOpenCrews;
  final VoidCallback onOpenPacts;
  final VoidCallback onStartCrew;

  /// For an account with no crew at all: the fork, not the setup.
  final VoidCallback onChooseStart;
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

  /// Today's stories this device has already opened, so a ring that has been
  /// looked at goes grey. Read from the store as the week arrives, because the
  /// week is what says which day "today" is.
  final _seen = <String>{};

  /// Whether each crewmate can be nudged, fetched with the week rather than
  /// on the press, so the offer opens with its button already in the state it
  /// is really in. Empty when the call failed, which the offer takes as "ask
  /// the server" rather than as a refusal — a states call that fell over
  /// should not take the nudge down with it.
  Map<String, CrewNudgeState> _nudges = const {};

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
        setState(() {
          _week = week;
          _seen
            ..clear()
            ..addAll(
              week == null
                  ? const <String>{}
                  : widget.seenStore.read(widget.userId, week.today),
            );
        });
      }
      await _loadNudges(crew?.id, request);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load your week. Please try again.');
      }
    }
  }

  /// Who can be nudged, alongside the week.
  ///
  /// Its own try, outside the week's: the week is the page and a nudge is one
  /// gesture on it, so a states call that fails leaves Home standing and the
  /// offer asking the server for itself. Nothing here ever sets [_error].
  Future<void> _loadNudges(String? crewId, int request) async {
    if (crewId == null) {
      if (mounted && request == _request) {
        setState(() => _nudges = const {});
      }
      return;
    }
    try {
      final states = await widget.backend.fetchNudgeStates(crewId);
      if (mounted && request == _request) setState(() => _nudges = states);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _nudges = const {});
      }
    }
  }

  /// Offers a nudge for a crewmate who has not been out today.
  ///
  /// The last day they kept anything is read off the week already in hand —
  /// [CrewWeek.checkIns] covers this week, which is as far back as the card
  /// needs to look and as far back as it can see without another call.
  Future<void> _nudge(MemberDay day) async {
    final crew = _crew;
    final week = _week;
    if (crew == null || week == null) return;
    final kept =
        week.checkIns
            .where((i) => i.userId == day.member.id)
            .map((i) => i.day)
            .toList()
          ..sort();
    final result = await showNudge(
      context: context,
      backend: widget.backend,
      crewId: crew.id,
      member: day.member,
      state: _nudges[day.member.id],
      today: week.today,
      lastKept: kept.lastOrNull,
    );
    if (!mounted || result == null) return;
    setState(() => _nudges = {..._nudges, day.member.id: result});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nudged ${day.member.displayName.trim().isEmpty ? 'your crewmate' : day.member.displayName.trim()}.',
        ),
      ),
    );
  }

  Future<void> _togglePact(String pactId) async {
    final crew = _crew;
    final week = _week;
    if (_savingPact != null || crew == null || week == null) return;
    ++_request; // Discard older reads while saving this selection.
    final selected = week.checkedToday(widget.userId);
    if (!selected.add(pactId)) selected.remove(pactId);
    var dayChanged = false;
    setState(() {
      _savingPact = pactId;
      _saveError = null;
    });
    try {
      final pact = week.pacts.firstWhere((p) => p.id == pactId);
      if (selected.contains(pactId) && pact.photoRequired) {
        final saved = await showPhotoCheckIn(
          userId: widget.userId,
          context: context,
          backend: widget.backend,
          crewId: crew.id,
          pactId: pactId,
          pactTitle: pact.title,
          daysKept: week.days(pactId, widget.userId),
          daysPerWeek: pact.daysPerWeek,
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
    } catch (error) {
      // Midnight in the crew's timezone is its own failure, not a failed
      // write: the server refuses a check-in dated against the day that just
      // ended, and the week in hand still says yesterday. Reported as a plain
      // save error it skipped the refresh below, so `week.today` stayed stale
      // and every retry was refused in exactly the same way. The photo sheet
      // reads the same sentence — see `photo_check_in_page.dart`.
      dayChanged = error.toString().contains('day changed');
      if (mounted) {
        setState(
          () => _saveError = dayChanged
              ? 'It’s a new day. Your week has been refreshed.'
              : 'Could not save. Tap the pact to retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _savingPact = null);
        if (_saveError == null || dayChanged) await _refresh();
      }
    }
  }

  /// Whether Home knows which crew it is about yet, which is what decides
  /// the header's height. See [_selector].
  bool get _hasSelector => _crews?.isNotEmpty ?? false;

  /// The header's height as the page is drawing it now: the rail alone until
  /// the crews arrive, and the crew's name over it once they have.
  double get _headerHeight =>
      _hasSelector ? HomeHeader.height : HomeHeader.headingHeight;

  /// The bell in the top corner: what the crew has told you, and the way into
  /// the list of it. Home is the page people open to see what the crew has
  /// been doing, and this is the corner notifications live in.
  ///
  /// It counts for itself and does not ride [_refresh]: the count answers to
  /// the crew's notices rather than to this week, and it should not be reread
  /// every time a pact is saved or a crew is switched.
  Widget _bell() => NotificationsBell(
    key: const ValueKey('home-notifications'),
    backend: widget.backend,
    active: widget.active,
  );

  /// The crew's name at the top of Home, as Pacts and Crews carry it: the
  /// same title in the same place, so the page says which crew it is about
  /// and switching is one gesture wherever you are. Null until the crews are
  /// in — the page does not know its own subject yet, and a title guessing at
  /// one is worse than no title.
  Widget? _selector() {
    final crews = _crews;
    if (crews == null || crews.isEmpty) return null;
    return CrewSwitcher(
      key: const ValueKey('home-crew-switcher'),
      crews: crews,
      selectedId: _crew?.id ?? widget.selectedCrewId,
      // A switch mid-save would save the check-in against the crew being
      // left, so the control waits for the write to land.
      onSelected: _savingPact != null ? null : widget.onCrewSelected,
    );
  }

  /// Opens the rail on [day], with the rest of the crew's day behind it.
  ///
  /// Only members who are in are handed over: the viewer walks out of one
  /// member's check-ins and into the next one's, and a member with nothing
  /// kept would be a page in that walk with nothing on it.
  Future<void> _openStories(List<MemberDay> days, MemberDay day) async {
    final open = days.where((d) => d.isIn).toList();
    final index = open.indexOf(day);
    final today = _week?.today;
    if (index < 0 || today == null) return;
    final opened = <String>{};
    await StoryViewer.open(
      context,
      days: open,
      viewerId: widget.userId,
      initial: index,
      backend: widget.backend,
      onSeen: (story) => opened.add(story.id),
    );
    if (opened.isEmpty) return;
    // Marked on the way out rather than as each story is shown: the rail is
    // behind the viewer, so a ring going grey there is a frame nobody sees —
    // and a rebuild of this page in the middle of another route's build.
    unawaited(widget.seenStore.mark(widget.userId, today, opened));
    if (mounted) setState(() => _seen.addAll(opened));
  }

  /// Opens the crew's week, the page the count under the rail is a line of.
  ///
  /// The week is reread on the way back: the page checks nobody in, but it
  /// stands open long enough for the crew to have moved under it.
  Future<void> _openCrewWeek() async {
    final crew = _crew;
    if (crew == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CrewWeekPage(
          crew: crew,
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
                          // Heading and its switcher, today's count, the crew
                          // panel and a usable pact card; shorter viewports
                          // scale down.
                          312 +
                              _headerHeight +
                              CrewTodayBar.height +
                              12 +
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
                                  return TodaySkeleton(
                                    selector: selector,
                                    action: _bell(),
                                  );
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
                                          onPressed: widget.onChooseStart,
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
                                final days = MemberDay.read(
                                  week,
                                  viewerId: widget.userId,
                                  seen: _seen,
                                );
                                return Column(
                                  key: ValueKey(_crew!.id),
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    HomeHeader(
                                      action: _bell(),
                                      rail: StoriesRail(
                                        days: days,
                                        onNudge: _nudge,
                                        // Past the page's own margin, so a
                                        // long crew leaves at the screen's
                                        // edge rather than at the card's.
                                        bleed: 12,
                                        onOpen: (day) =>
                                            _openStories(days, day),
                                      ),
                                      selector: selector,
                                    ),
                                    const SizedBox(height: 12),
                                    CrewTodayBar(
                                      week: week,
                                      onOpenWeek: _openCrewWeek,
                                    ),
                                    const SizedBox(height: 12),
                                    HomeCrewPanel(
                                      key: const ValueKey('home-crew-panel'),
                                      week: week,
                                      userId: widget.userId,
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
                                                mainAxisSize: MainAxisSize.min,
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
