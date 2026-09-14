import 'support/pump_ui.dart';

import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

import 'package:weekpact/src/crew/crew_week_page.dart';

Future<void> pumpHome(WidgetTester tester, DashboardBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: HomePage(
        user: const AuthUser(email: 'person@example.com'),
        authBackend: const MissingConfigurationAuthBackend(),
        crewBackend: const MissingCrewBackend(),
        pactsBackend: backend.pacts,
        homeBackend: backend,
      ),
    ),
  );
}

void main() {
  test('weekly progress caps each pact, excludes old days and ignores former members', () {
    final pacts = DashboardPacts().pacts;
    final week = CrewWeek(
      today: '2026-09-13',
      weekStart: '2026-09-07',
      timezone: 'UTC',
      pacts: pacts,
      members: const [
        WeekMember('me', 'me@example.com'),
        WeekMember('other', 'other@example.com'),
      ],
      checkIns: [
        for (var day = 7; day <= 13; day++)
          PactCheckIn(
            'read',
            'me',
            '2026-09-${day.toString().padLeft(2, '0')}',
          ),
        const PactCheckIn('move', 'me', '2026-09-06'),
        const PactCheckIn('move', 'me', '2026-09-13'),
        const PactCheckIn('move', 'me', '2026-09-13'),
        const PactCheckIn('move', 'former', '2026-09-13'),
      ],
    );
    expect(week.completed('me'), 4);
    expect(week.percent('me'), 40);
    expect(week.percentCrew, 20);
    expect(week.pactDoneToday('move'), 1);
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
      expect(find.text('WeekPact'), findsNothing);
      expect(find.text('CHECK IN'), findsNothing);
      expect(find.byKey(const ValueKey('skeleton-pact-card')), findsOneWidget);
      final loadingCrew = tester.getRect(
        find.byKey(const ValueKey('skeleton-crew-board')),
      );
      backend.loading!.complete(week);
      backend.loading = null;
      await tester.pumpUi();
      expect(find.text('Early Birds'), findsOneWidget);
      expect(find.byKey(const ValueKey('skeleton-pact-card')), findsNothing);
      expect(
        tester.getRect(find.byKey(const ValueKey('crew-board'))),
        loadingCrew,
      );
      expect(find.text('Mark done').hitTestable(), findsOneWidget);
      backend.failSave = true;
      await tester.tap(
        find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
      );
      await tester.pumpUi();
      expect(find.textContaining('Could not save.'), findsOneWidget);
      expect(backend.selected, {'read'});
      backend.failSave = false;
      await tester.tap(
        find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
      );
      await tester.pumpUi();
      expect(backend.selected, {'move', 'read'});
      expect(find.text('Checked in today'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester, backend);
      await tester.pumpUi();
      expect(find.text('Checked in today'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('load errors retry and pact edits refresh when returning home', (
    tester,
  ) async {
    final backend = DashboardBackend()..failLoad = true;
    await pumpHome(tester, backend);
    await tester.pumpUi();
    expect(find.text('TRY AGAIN'), findsOneWidget);
    backend.failLoad = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-pacts')));
    await tester.pumpUi();
    backend.pacts.pacts = [];
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpUi();
    expect(find.text('No pacts yet.'), findsOneWidget);
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
    await tester.pumpUi();
    await tester.ensureVisible(find.byTooltip('View week'));
    await tester.tap(find.byTooltip('View week'));
    await tester.pumpUi();
    expect(find.byType(CrewWeekPage), findsOneWidget);
    expect(find.text('This week · Sep 7 – Sep 13'), findsOneWidget);
    expect(find.text('Crew progress'), findsOneWidget);
    expect(find.text('1 of 2 checked in today'), findsOneWidget);
    await tester.tap(find.byTooltip('Next pact'));
    await tester.pumpUi();
    expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Sep 9 · Completed'), findsOneWidget);
    expect(find.byTooltip('Sep 10 · Upcoming').hitTestable(), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back to home'));
    await tester.pumpUi();
    expect(find.byType(CrewWeekPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('crew week retries loading errors', (tester) async {
    final backend = DashboardBackend()..failLoad = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: CrewWeekPage(
          crew: backend.pacts.crews.first,
          backend: backend,
          userId: '',
        ),
      ),
    );
    await tester.pumpUi();
    expect(
      find.text('Could not load crew activity. Try again.'),
      findsOneWidget,
    );
    backend.failLoad = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    expect(find.text('Crew progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-pact-carousel')), findsOneWidget);
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
    await tester.pumpUi();
    expect(calls, isEmpty);
    final pact = find
        .byKey(const ValueKey('check-in-Move for 30 min'))
        .hitTestable();
    backend.failSave = true;
    await tester.tap(pact);
    await tester.pumpUi();
    expect(calls, isEmpty);
    backend.failSave = false;
    await tester.tap(pact);
    await tester.pumpUi();
    expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
    await tester.tap(pact);
    await tester.pumpUi();
    expect(calls.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no crews shows a useful empty state with no fake progress', (
    tester,
  ) async {
    final backend = DashboardBackend();
    backend.pacts.crews = [];
    await pumpHome(tester, backend);
    await tester.pumpUi();
    expect(find.text('GO TO CREWS'), findsOneWidget);
    expect(find.text('CREW THIS WEEK'), findsNothing);
    expect(backend.fetches, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
