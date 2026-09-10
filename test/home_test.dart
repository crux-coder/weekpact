import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepup/src/auth/auth_backend.dart';
import 'package:keepup/src/crew/crew_backend.dart';
import 'package:keepup/src/home/home_backend.dart';
import 'package:keepup/src/home/home_page.dart';
import 'package:keepup/src/theme/keepup_theme.dart';

import 'support/home_fakes.dart';

import 'package:keepup/src/crew/crew_week_page.dart';

Future<void> pumpHome(WidgetTester tester, DashboardBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: KeepUpTheme.light,
      home: HomePage(
        user: const AuthUser(email: 'person@example.com'),
        authBackend: const MissingConfigurationAuthBackend(),
        crewBackend: const MissingCrewBackend(),
        goalsBackend: backend.goals,
        homeBackend: backend,
      ),
    ),
  );
}

void main() {
  test('weekly progress caps each goal, excludes old days and ignores former members', () {
    final goals = DashboardGoals().goals;
    final week = CrewWeek(
      today: '2026-09-13',
      weekStart: '2026-09-07',
      timezone: 'UTC',
      goals: goals,
      members: const [
        WeekMember('me', 'me@example.com'),
        WeekMember('other', 'other@example.com'),
      ],
      checkIns: [
        for (var day = 7; day <= 13; day++)
          GoalCheckIn(
            'read',
            'me',
            '2026-09-${day.toString().padLeft(2, '0')}',
          ),
        const GoalCheckIn('move', 'me', '2026-09-06'),
        const GoalCheckIn('move', 'me', '2026-09-13'),
        const GoalCheckIn('move', 'me', '2026-09-13'),
        const GoalCheckIn('move', 'former', '2026-09-13'),
      ],
    );
    expect(week.completed('me'), 4);
    expect(week.percent('me'), 40);
    expect(week.percentCrew, 20);
    expect(week.goalDoneToday('move'), 1);
    expect(week.onTrack('me'), isFalse);
  });

  testWidgets(
    'shows skeleton, real data, save retry and reload persistence on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = DashboardBackend();
      final week = await backend.fetchWeek('crew');
      backend.loading = Completer<CrewWeek>();
      await pumpHome(tester, backend);
      await tester.pump();
      expect(find.text('EARLY BIRDS'), findsOneWidget);
      expect(find.text('CHECK IN'), findsNothing);
      backend.loading!.complete(week);
      backend.loading = null;
      await tester.pumpAndSettle();
      expect(find.text('EARLY BIRDS'), findsOneWidget);
      expect(find.text('1 OF 2 DONE'), findsOneWidget);
      backend.failSave = true;
      await tester.tap(find.byKey(const ValueKey('check-in-Move for 30 min')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save.'), findsOneWidget);
      expect(backend.selected, {'read'});
      backend.failSave = false;
      await tester.tap(find.byKey(const ValueKey('check-in-Move for 30 min')));
      await tester.pumpAndSettle();
      expect(backend.selected, {'move', 'read'});
      expect(find.text('2 OF 2 DONE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, backend);
      await tester.pumpAndSettle();
      expect(find.text('2 OF 2 DONE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('load errors retry and goal edits refresh when returning home', (
    tester,
  ) async {
    final backend = DashboardBackend()..failLoad = true;
    await pumpHome(tester, backend);
    await tester.pumpAndSettle();
    expect(find.text('TRY AGAIN'), findsOneWidget);
    backend.failLoad = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpAndSettle();
    expect(find.text('Move for 30 min'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-goals')));
    await tester.pumpAndSettle();
    backend.goals.goals = [];
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpAndSettle();
    expect(find.text('No goals yet.'), findsOneWidget);
    expect(find.text('CHECK IN'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('opens current crew week, shows member days and returns home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = DashboardBackend();
    await pumpHome(tester, backend);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('View week'));
    await tester.tap(find.byTooltip('View week'));
    await tester.pumpAndSettle();
    expect(find.byType(CrewWeekPage), findsOneWidget);
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('Sep 7 – Sep 13'), findsOneWidget);
    expect(find.text('1 / 10 WEEKLY CHECK-INS'), findsOneWidget);
    expect(find.text('0 / 10 WEEKLY CHECK-INS'), findsOneWidget);
    expect(find.byTooltip('Sep 9 · Completed'), findsOneWidget);
    expect(find.byTooltip('Sep 10 · Upcoming'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back to home'));
    await tester.pumpAndSettle();
    expect(find.byType(CrewWeekPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('crew week retries loading errors', (tester) async {
    final backend = DashboardBackend()..failLoad = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeepUpTheme.dark,
        home: CrewWeekPage(
          crew: backend.goals.crews.first,
          backend: backend,
          userId: '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load crew activity. Try again.'),
      findsOneWidget,
    );
    backend.failLoad = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 10 WEEKLY CHECK-INS'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('haptics only fire for successful completed check-ins', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final backend = DashboardBackend();
    await pumpHome(tester, backend);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    final goal = find.byKey(const ValueKey('check-in-Move for 30 min'));
    backend.failSave = true;
    await tester.tap(goal);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    backend.failSave = false;
    await tester.tap(goal);
    await tester.pumpAndSettle();
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
    await tester.tap(goal);
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no crews shows a useful empty state with no fake progress', (
    tester,
  ) async {
    final backend = DashboardBackend();
    backend.goals.crews = [];
    await pumpHome(tester, backend);
    await tester.pumpAndSettle();
    expect(find.text('GO TO CREWS'), findsOneWidget);
    expect(find.text('CREW THIS WEEK'), findsNothing);
    expect(backend.fetches, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
