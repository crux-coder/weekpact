import 'home_glass.dart';
import '../onboarding/profile_avatar.dart';
import '../auth/account_actions.dart';
import '../notifications/notification_settings_card.dart';

import 'package:flutter/services.dart';

import '../crew/crew_week_page.dart';

import 'dart:async';

import 'home_backend.dart';

import 'package:flutter/material.dart';

import '../goals/goals_backend.dart';
import '../goals/goals_page.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../auth/auth_backend.dart';
import '../crew/crew_backend.dart';
import '../crew/crew_page.dart';
import '../theme/weekpact_theme.dart';
import '../theme/theme_preference.dart';
import '../widgets/brutal_widgets.dart';
import 'today_widgets.dart';
import '../widgets/page_frame.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.user,
    required this.authBackend,
    required this.crewBackend,
    this.goalsBackend = const MissingGoalsBackend(),
    this.homeBackend = const MissingHomeBackend(),
  });

  final AuthUser user;
  final AuthBackend authBackend;
  final CrewBackend crewBackend;
  final GoalsBackend goalsBackend;
  final HomeBackend homeBackend;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _navigationItems = [
    BrutalNavigationItem(
      label: 'Home',
      icon: HugeIconsStrokeRounded.home01,
      color: WeekPactColors.softYellow,
    ),
    BrutalNavigationItem(
      label: 'Goals',
      icon: HugeIconsStrokeRounded.target02,
      color: WeekPactColors.mintGreen,
    ),
    BrutalNavigationItem(
      label: 'Crews',
      icon: HugeIconsStrokeRounded.userGroup,
      color: WeekPactColors.softYellow,
    ),
    BrutalNavigationItem(
      label: 'Account',
      icon: HugeIconsStrokeRounded.userAccount,
      color: WeekPactColors.softCoral,
    ),
  ];

  late final PageController _pageController;
  int _selectedIndex = 0;
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
            backend: widget.homeBackend,
            goalsBackend: widget.goalsBackend,
            userId: widget.user.id,
            active: _selectedIndex == 0,
            onOpenCrews: () => _selectDestination(2),
            onOpenGoals: () => _selectDestination(1),
          ),
          GoalsPage(
            backend: widget.goalsBackend,
            onOpenCrews: () => _selectDestination(2),
          ),
          CrewPage(
            active: _selectedIndex == 2,
            onInviteAccepted: () => _selectDestination(0),
            onCrewLeft: () => _selectDestination(0),
            backend: widget.crewBackend,
            currentUserEmail: widget.user.email,
          ),
          _AccountDestination(
            user: widget.user,
            backend: widget.authBackend,
            signingOut: _signingOut,
            onSignOut: _signOut,
          ),
        ],
      ),
      bottomNavigationBar: BrutalBottomNavigationBar(
        items: _navigationItems,
        glass: _selectedIndex == 0,
        selectedIndex: _selectedIndex,
        onSelected: _selectDestination,
      ),
    );
    return HomeGlassBackground(child: scaffold);
  }
}

class _HomeDestination extends StatefulWidget {
  const _HomeDestination({
    required this.backend,
    required this.goalsBackend,
    required this.userId,
    required this.active,
    required this.onOpenCrews,
    required this.onOpenGoals,
  });
  final HomeBackend backend;
  final GoalsBackend goalsBackend;
  final String userId;
  final bool active;
  final VoidCallback onOpenCrews;
  final VoidCallback onOpenGoals;
  @override
  State<_HomeDestination> createState() => _HomeDestinationState();
}

class _HomeDestinationState extends State<_HomeDestination>
    with WidgetsBindingObserver {
  List<GoalCrew>? _crews;
  GoalCrew? _crew;
  CrewWeek? _week;
  String? _error;
  int _request = 0;
  Timer? _timer;
  String? _savingGoal;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.active && _savingGoal == null) _refresh();
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
        _savingGoal == null) {
      _refresh();
    }
  }

  Future<void> _refresh({String? crewId}) async {
    if (_savingGoal != null) return;
    final request = ++_request;
    try {
      final crews = await widget.goalsBackend.fetchCrews();
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
      if (mounted && request == _request) setState(() => _week = week);
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Could not load your week. Please try again.');
      }
    }
  }

  Future<void> _toggleGoal(String goalId) async {
    final crew = _crew;
    final week = _week;
    if (_savingGoal != null || crew == null || week == null) return;
    ++_request; // Discard older reads while saving this selection.
    final selected = week.checkedToday(widget.userId);
    if (!selected.add(goalId)) selected.remove(goalId);
    setState(() {
      _savingGoal = goalId;
      _saveError = null;
    });
    try {
      await widget.backend.saveCheckIns(
        crewId: crew.id,
        today: week.today,
        goalIds: selected,
      );
      if (!mounted) return;
      if (selected.contains(goalId)) {
        // Haptics are best-effort and must never turn a saved check-in into an error.
        unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
      }
      setState(() {
        _week = CrewWeek(
          today: week.today,
          streakWeeks: week.streakWeeks,
          weekStart: week.weekStart,
          timezone: week.timezone,
          goals: week.goals,
          members: week.members,
          checkIns: [
            ...week.checkIns.where(
              (i) => i.userId != widget.userId || i.day != week.today,
            ),
            ...selected.map((id) => GoalCheckIn(id, widget.userId, week.today)),
          ],
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = 'Could not save. Tap the goal to retry.');
      }
    } finally {
      if (mounted) setState(() => _savingGoal = null);
    }
    if (mounted && _saveError == null) await _refresh();
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
                if (loading) return const TodaySkeleton();
                if (_error != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
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
                        const Text(
                          'Your week starts with a crew.',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 20),
                        BrutalButton(
                          label: 'GO TO CREWS',
                          color: context.mint,
                          onPressed: widget.onOpenCrews,
                        ),
                      ],
                    ),
                  );
                }
                if (week == null) return const SizedBox.shrink();
                const crewHeight = 180.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CrewTitleBanner(name: _crew!.name),
                    const SizedBox(height: 8),
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
                      child: week.goals.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'No goals yet.',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  BrutalButton(
                                    label: 'VIEW GOALS',
                                    color: context.yellow,
                                    onPressed: widget.onOpenGoals,
                                  ),
                                ],
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, space) => TodayGoalsCard(
                                horizontalBleed: 12,
                                height: space.maxHeight,
                                week: week,
                                userId: widget.userId,
                                savingGoal: _savingGoal,
                                onToggle: _toggleGoal,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    TodayCrewCard(
                      animate: widget.active,
                      height: crewHeight,
                      crewName: _crew!.name,
                      week: week,
                      userId: widget.userId,
                      onOpen: () async {
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
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountDestination extends StatelessWidget {
  const _AccountDestination({
    required this.user,
    required this.backend,
    required this.signingOut,
    required this.onSignOut,
  });
  final AuthUser user;
  final AuthBackend backend;
  final bool signingOut;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _DestinationFrame(
      title: 'ACCOUNT.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalShadow(
            fillColor: context.coral,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(backend: backend),
                  if (user.firstName.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '${user.firstName} ${user.lastName}',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'SIGNED IN AS',
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.email,
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          BrutalTabbedCard(
            title: 'APPEARANCE',
            tabColor: context.mint,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Device'),
                      ),
                    ],
                    selected: {ThemePreference.of(context).mode},
                    onSelectionChanged: (selection) =>
                        ThemePreference.of(context).onChanged(selection.single),
                    style: ButtonStyle(
                      foregroundColor: WidgetStatePropertyAll(context.ink),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? context.yellow
                            : context.surface,
                      ),
                      side: WidgetStatePropertyAll(
                        BorderSide(
                          color: context.border,
                          width: WeekPactMetrics.border,
                        ),
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontWeight: FontWeight.w800),
                      ),
                      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Device follows your system appearance.',
                    style: TextStyle(color: context.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const NotificationSettingsCard(),
          AccountActions(backend: backend, enabled: !signingOut),
          const SizedBox(height: 30),
          BrutalButton(
            label: 'LOG OUT',
            color: context.pink,
            isLoading: signingOut,
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _DestinationFrame extends StatelessWidget {
  const _DestinationFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PageFrame(header: PageHeading(title), child: child);
  }
}
