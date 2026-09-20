import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/recent_activity.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

CrewWeek _weekWith(CrewWeek week, {CrewActivity? activity}) => CrewWeek(
  today: week.today,
  weekStart: week.weekStart,
  timezone: week.timezone,
  pacts: week.pacts,
  members: [
    const WeekMember('me', 'me@example.com', displayName: 'Sam Reed'),
    const WeekMember('al', 'al@example.com', displayName: 'Alex Fox'),
  ],
  checkIns: week.checkIns,
  streakWeeks: week.streakWeeks,
  latestActivity: activity,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required CrewWeek week,
  VoidCallback? onOpenFeed,
}) => tester.pumpWidget(
  MaterialApp(
    theme: WeekPactTheme.dark,
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(alwaysUse24HourFormat: true),
        child: RecentActivityCard(
          week: week,
          userId: 'me',
          now: DateTime(2026, 9, 18, 20),
          onOpenFeed: onOpenFeed,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('names the pact and the day of the crew\'s last check-in', (
    tester,
  ) async {
    final backend = DashboardBackend();
    final week = _weekWith(
      await backend.fetchWeek('crew'),
      activity: CrewActivity(
        pactId: 'move',
        userId: 'me',
        createdAt: DateTime(2026, 9, 18, 18, 24),
      ),
    );
    var opened = 0;
    await _pumpCard(tester, week: week, onOpenFeed: () => opened++);
    await tester.pumpUi();
    // No heading over it: the card says what it is and is its own way in.
    expect(find.text('RECENT ACTIVITY'), findsNothing);
    expect(find.text('View all'), findsNothing);
    expect(find.text('You checked in to Move for 30 min'), findsOneWidget);
    expect(find.text('Today, 18:24'), findsOneWidget);
    // The pact's own tint and icon place the entry against its card.
    expect(find.byKey(const ValueKey('activity-move-me')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-card')));
    await tester.pumpUi();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crew mate is named, and an older check-in dated', (
    tester,
  ) async {
    final backend = DashboardBackend();
    final week = _weekWith(
      await backend.fetchWeek('crew'),
      activity: CrewActivity(
        pactId: 'read',
        userId: 'al',
        createdAt: DateTime(2026, 9, 17, 7, 5),
      ),
    );
    await _pumpCard(tester, week: week);
    await tester.pumpUi();
    expect(find.text('Alex checked in to Read 20 pages'), findsOneWidget);
    expect(find.text('Yesterday, 07:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('both lines stay whole at large text', (tester) async {
    final backend = DashboardBackend();
    final week = _weekWith(
      await backend.fetchWeek('crew'),
      activity: CrewActivity(
        pactId: 'read',
        userId: 'me',
        createdAt: DateTime(2026, 9, 18, 18, 24),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              alwaysUse24HourFormat: true,
              textScaler: TextScaler.linear(2),
            ),
            child: RecentActivityCard(
              week: week,
              userId: 'me',
              now: DateTime(2026, 9, 18, 20),
              onOpenFeed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.text('Today, 18:24'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('says so when nobody has checked in', (tester) async {
    final backend = DashboardBackend();
    await _pumpCard(tester, week: _weekWith(await backend.fetchWeek('crew')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('activity-empty')), findsOneWidget);
    expect(find.text('LATEST ACTIVITY'), findsOneWidget);
    expect(find.text('No check-ins yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
