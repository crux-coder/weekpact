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
  Future<CrewWeek> fetchWeek(String crewId) {
    fetches++;
    return week.future;
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
}
