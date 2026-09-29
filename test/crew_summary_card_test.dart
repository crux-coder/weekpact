import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_roster.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/page_frame.dart';

Future<void> pumpCard(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Center(child: SizedBox(width: 366, child: card)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the card counts the crew, its pacts and its streak', (
    tester,
  ) async {
    await pumpCard(
      tester,
      CrewSummaryCard(
        people: 4,
        pacts: 3,
        streakWeeks: 6,
        startedAt: DateTime(2026, 9, 7),
      ),
    );
    expect(find.text('4'), findsOneWidget);
    expect(find.text('PEOPLE'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('PACTS'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    // The label names the measure rather than agreeing with the count, so a
    // crew with no streak does not read as one that has something running.
    expect(find.text('WEEK STREAK'), findsOneWidget);
    expect(find.text('SINCE SEP 7'), findsOneWidget);
  });

  testWidgets('a crew of one, one pact and no streak says so in singular', (
    tester,
  ) async {
    await pumpCard(
      tester,
      const CrewSummaryCard(people: 1, pacts: 1, streakWeeks: 0),
    );
    expect(find.text('PERSON'), findsOneWidget);
    expect(find.text('PACT'), findsOneWidget);
    expect(find.text('WEEK STREAK'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    // No date on this crew, so the line is left empty rather than stood in
    // for — and the crew's timezone is not what fills it.
    expect(find.textContaining('SINCE'), findsNothing);
    expect(find.textContaining('UTC'), findsNothing);
  });

  testWidgets('figures still coming are bars, never a nought standing in', (
    tester,
  ) async {
    await pumpCard(tester, const CrewSummaryCard(people: 3));
    expect(find.text('3'), findsOneWidget);
    // A pact count of null is not a crew with no pacts.
    expect(find.text('0'), findsNothing);
    expect(find.text('PACTS'), findsOneWidget);
    expect(find.text('WEEK STREAK'), findsOneWidget);
  });

  testWidgets('a crew started in another year is dated with its year', (
    tester,
  ) async {
    await pumpCard(
      tester,
      CrewSummaryCard(
        people: 4,
        pacts: 3,
        streakWeeks: 6,
        startedAt: DateTime(2025, 9, 7),
        now: DateTime(2026, 9, 28),
      ),
    );
    expect(find.text('SINCE SEP 7, 2025'), findsOneWidget);
  });

  testWidgets('this year needs no year on it', (tester) async {
    await pumpCard(
      tester,
      CrewSummaryCard(
        people: 4,
        startedAt: DateTime(2026, 9, 7),
        now: DateTime(2026, 9, 28),
      ),
    );
    expect(find.text('SINCE SEP 7'), findsOneWidget);
  });

  testWidgets('a week that did not arrive says so and offers the way back', (
    tester,
  ) async {
    var retries = 0;
    await pumpCard(
      tester,
      CrewSummaryCard(people: 4, weekFailed: true, onRetry: () => retries++),
    );
    // The crew's own figure is still an answer; the two that come with the
    // week are dashes rather than bars nobody is filling in.
    expect(find.text('4'), findsOneWidget);
    expect(find.byType(SkeletonBar), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('Couldn’t load'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('a week still coming says nothing about failing', (tester) async {
    await pumpCard(tester, const CrewSummaryCard(people: 4));
    expect(find.text('Couldn’t load'), findsNothing);
    expect(find.text('—'), findsNothing);
    expect(find.byType(SkeletonBar), findsNWidgets(2));
  });

  testWidgets('the loading card holds the roster in place', (tester) async {
    await pumpCard(tester, const CrewSummaryCard.loading());
    expect(
      tester.getSize(find.byKey(const ValueKey('crew-summary-card'))).height,
      CrewSummaryCard.height,
    );
    expect(find.textContaining('SINCE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger type grows the card rather than clipping it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 366,
                child: CrewSummaryCard(
                  people: 4,
                  pacts: 3,
                  streakWeeks: 6,
                  startedAt: DateTime(2026, 9, 7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('crew-summary-card'))).height,
      greaterThan(CrewSummaryCard.height),
    );
  });
}
