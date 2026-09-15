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

void expectDay(WidgetTester tester, String day, {required bool checked}) {
  final label = '$day, today: ${checked ? 'completed' : 'not completed'}';
  expect(
    find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    ),
    findsWidgets,
  );
  expect(
    find.text('Checked in today').hitTestable(),
    checked ? findsOneWidget : findsNothing,
  );
  expect(
    find.text('Check in').hitTestable(),
    checked ? findsNothing : findsOneWidget,
  );
  expect(find.text(checked ? '1/2' : '0/2'), findsOneWidget);
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
        expectDay(tester, dates.first, checked: true);
        final fetches = backend.fetches;
        backend.today = dates.last;
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpUi();
        expect(backend.fetches, greaterThan(fetches));
        expectDay(tester, dates.last, checked: false);
        expect(
          find.bySemanticsLabel('${dates.first}, today: completed'),
          findsNothing,
        );
        if (dates.first == '2026-09-15') {
          // Yesterday stays completed in the same week, but cannot be undone as today.
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == '${dates.first}: completed',
            ),
            findsWidgets,
          );
        } else {
          expect(
            find.byKey(ValueKey('pact-day-move-${dates.first}')),
            findsNothing,
          );
        }
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
      expectDay(tester, backend.today, checked: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      backend.today = '2026-09-16';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpUi();
      expectDay(tester, backend.today, checked: false);
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
    expectDay(tester, backend.today, checked: false);
    await tester.pumpWidget(const SizedBox());
  });
}
