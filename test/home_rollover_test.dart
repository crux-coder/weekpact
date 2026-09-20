import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// Represents the authoritative crew-local date advancing on the server.
class RolloverBackend extends DashboardBackend {
  RolloverBackend(this.today) : completedOn = today;
  String today;
  final String completedOn;

  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final original = await super.fetchWeek(crewId);
    final date = DateTime.parse(today);
    final monday = date.subtract(Duration(days: date.weekday - 1));
    final start = monday.toIso8601String().substring(0, 10);
    return CrewWeek(
      today: today,
      weekStart: start,
      timezone: 'Europe/Sarajevo',
      pacts: original.pacts.where((pact) => pact.id == 'move').toList(),
      members: original.members,
      checkIns: completedOn.compareTo(start) >= 0
          ? [PactCheckIn('move', '', completedOn)]
          : [],
    );
  }
}

/// [completed] is the pact's distinct days *this week*, which is not the same
/// question as whether today is checked: rolling 15th → 16th keeps last night's
/// check-in inside the same week, while rolling 13th → 14th starts a new one.
void expectDay(
  WidgetTester tester, {
  required bool checked,
  required int completed,
}) {
  expect(
    find.text('Checked in today').hitTestable(),
    checked ? findsOneWidget : findsNothing,
  );
  expect(
    find.text('Check in').hitTestable(),
    checked ? findsNothing : findsOneWidget,
  );
  // The card splits the count from its denominator for the type scale, so the
  // pair is read through the progress bar's own semantics rather than as text.
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.value == '$completed of 7 days',
    ),
    findsWidgets,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  for (final dates in [
    ['2026-09-15', '2026-09-16'],
    ['2026-09-13', '2026-09-14'],
  ]) {
    testWidgets(
      'minute refresh rolls crew day ${dates.first} to ${dates.last}',
      (tester) async {
        final backend = RolloverBackend(dates.first);
        await pumpHome(tester, backend);
        await tester.pumpUi();
        final sameWeek = dates.first == '2026-09-15';
        expectDay(tester, checked: true, completed: 1);
        final fetches = backend.fetches;
        backend.today = dates.last;
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpUi();
        expect(backend.fetches, greaterThan(fetches));
        // The card counts the week, so the same week keeps last night's day
        // while a new one starts the count over.
        expectDay(tester, checked: false, completed: sameWeek ? 1 : 0);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'resume after midnight refreshes without waiting for the minute timer',
    (tester) async {
      final backend = RolloverBackend('2026-09-15');
      await pumpHome(tester, backend);
      await tester.pumpUi();
      expectDay(tester, checked: true, completed: 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      backend.today = '2026-09-16';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpUi();
      // Still the same week, so yesterday's check-in stays counted.
      expectDay(tester, checked: false, completed: 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('returning to Home refreshes the crew date', (tester) async {
    final backend = RolloverBackend('2026-09-15');
    await pumpHome(tester, backend);
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('nav-pacts')));
    await tester.pumpUi();
    backend.today = '2026-09-16';
    await tester.tap(find.byKey(const ValueKey('nav-home')));
    await tester.pumpUi();
    expectDay(tester, checked: false, completed: 1);
    await tester.pumpWidget(const SizedBox());
  });
}
