import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_week_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// Holds the week open so the page can be read while it is still loading.
class _SlowBackend extends DashboardBackend {
  final week = Completer<CrewWeek>();

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) {
    fetches++;
    return week.future;
  }
}

/// Refuses the week, so the page can be read in its failed state.
class _FailingBackend extends DashboardBackend {
  final week = Completer<CrewWeek>();
  bool recovered = false;

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) {
    fetches++;
    if (recovered) return super.fetchWeek(crewId);
    return Future.error(StateError('offline'));
  }
}

void main() {
  testWidgets('the crew week shows its skeleton until the week arrives', (
    tester,
  ) async {
    final backend = _SlowBackend()
      ..pacts.pacts = const [
        CrewPact(
          id: 'hang',
          crewId: 'crew',
          title: 'Hangboard',
          frequency: PactFrequency.weekly,
          daysPerWeek: 5,
          iconKey: 'target',
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: CrewWeekPage(
          crew: const PactCrew(
            id: 'crew',
            name: 'Hangboardasi',
            timezone: 'Europe/Sarajevo',
            isOwner: true,
          ),
          backend: backend,
          userId: '0',
        ),
      ),
    );
    await tester.pumpUi();

    expect(find.byKey(const ValueKey('crew-week-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The page's own frame is already in place behind it.
    expect(find.text('Hangboardasi'), findsOneWidget);

    backend.week.complete(
      CrewWeek(
        today: '2026-09-17',
        weekStart: '2026-09-14',
        timezone: 'Europe/Sarajevo',
        pacts: backend.pacts.pacts,
        members: const [WeekMember('0', 'private@example.com')],
        checkIns: const [PactCheckIn('hang', '0', '2026-09-14')],
      ),
    );
    await tester.pumpUi();

    expect(find.byKey(const ValueKey('crew-week-skeleton')), findsNothing);
    expect(find.text('Crew pacts'), findsOneWidget);
  });

  testWidgets('a week that failed says so instead of standing a filler line '
      'under the error', (tester) async {
    final backend = _FailingBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: CrewWeekPage(
          crew: const PactCrew(
            id: 'crew',
            name: 'Hangboardasi',
            timezone: 'Europe/Sarajevo',
            isOwner: true,
          ),
          backend: backend,
          userId: '0',
        ),
      ),
    );
    await tester.pumpUi();

    expect(
      find.text('Could not load crew activity. Try again.'),
      findsOneWidget,
    );
    expect(find.text('TRY AGAIN'), findsOneWidget);
    // The filler is what the page says when it has nothing yet and nothing
    // went wrong; here something did, and the error has already said it.
    expect(find.text('Your crew\u2019s week'), findsNothing);

    backend.recovered = true;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    expect(find.text('Crew pacts'), findsOneWidget);
    expect(find.text('Could not load crew activity. Try again.'), findsNothing);
  });
}
