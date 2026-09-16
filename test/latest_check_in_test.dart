import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

final _now = DateTime.utc(2026, 9, 9, 12);

CrewWeek week({CrewActivity? latest, Set<String> checkedBy = const {}}) =>
    CrewWeek(
      today: '2026-09-09',
      weekStart: '2026-09-07',
      timezone: 'UTC',
      pacts: const [CrewPactStub.move],
      members: const [
        WeekMember('me', 'me@example.com', displayName: 'Jasmin Mustafic'),
        WeekMember('mate', 'mate@example.com', displayName: 'Mirnes Halilovic'),
      ],
      checkIns: [
        for (final id in checkedBy) PactCheckIn('move', id, '2026-09-09'),
      ],
      latestActivity: latest,
    );

Future<void> pumpStrip(
  WidgetTester tester,
  CrewWeek data, {
  VoidCallback? onOpenFeed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: LatestCheckInStrip(
          week: data,
          userId: 'me',
          now: _now,
          onOpenFeed: onOpenFeed,
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  for (final entry in {
    const Duration(seconds: 20): 'just now',
    const Duration(minutes: 8): '8m ago',
    const Duration(hours: 5): '5h ago',
  }.entries) {
    testWidgets('names the latest check-in and its age (${entry.value})', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        week(
          latest: CrewActivity(
            pactId: 'move',
            userId: 'mate',
            createdAt: _now.subtract(entry.key),
          ),
        ),
      );

      expect(
        find.textContaining('Mirnes checked in', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Move for 30 min · ${entry.value}',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('attributes your own check-in to you', (tester) async {
    await pumpStrip(
      tester,
      week(
        latest: CrewActivity(
          pactId: 'move',
          userId: 'me',
          createdAt: _now.subtract(const Duration(minutes: 3)),
        ),
      ),
    );

    expect(
      find.textContaining('You checked in', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('says so honestly when nothing has happened yet', (tester) async {
    await pumpStrip(tester, week());

    expect(
      find.textContaining(
        'Nobody has checked in yet today',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('ago', findRichText: true), findsNothing);
  });

  testWidgets('opens the feed when tapped', (tester) async {
    var opened = 0;
    await pumpStrip(
      tester,
      week(
        latest: CrewActivity(
          pactId: 'move',
          userId: 'mate',
          createdAt: _now.subtract(const Duration(minutes: 3)),
        ),
      ),
      onOpenFeed: () => opened++,
    );

    await tester.tap(find.byKey(const ValueKey('latest-check-in')));
    await tester.pumpUi();
    expect(opened, 1);
  });

  testWidgets('home shows the strip and reaches the feed through it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHome(tester, DashboardBackend());
    await tester.pumpUi();

    expect(find.text('TODAY’S CHECK-INS'), findsNothing);
    expect(find.byKey(const ValueKey('latest-check-in')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('latest-check-in')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('feed-list')), findsOneWidget);
  });
}

/// The fake crew's pact, kept here so the strip's copy is checked against a
/// real pact title rather than a placeholder.
abstract final class CrewPactStub {
  static const move = CrewPact(
    id: 'move',
    crewId: 'crew',
    title: 'Move for 30 min',
    frequency: PactFrequency.daily,
    daysPerWeek: 7,
    iconKey: 'run',
  );
}
