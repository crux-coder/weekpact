import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_streak_card.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';

/// A crew of two with one pact kept twice a week, a quarter of the way into
/// it: one check-in of the four the week asks for.
const _week = CrewWeek(
  today: '2026-09-16',
  weekStart: '2026-09-14',
  timezone: 'Europe/Sarajevo',
  pacts: [
    CrewPact(
      id: 'hang',
      crewId: 'crew',
      title: 'Hangboard',
      frequency: PactFrequency.weekly,
      daysPerWeek: 2,
    ),
  ],
  members: [
    WeekMember('0', 'me@example.com', displayName: 'Jasmin'),
    WeekMember('1', 'friend@example.com', displayName: 'Mirnes'),
  ],
  checkIns: [PactCheckIn('hang', '0', '2026-09-15')],
);

CrewWeekSummary _summary(String weekStart, int percent) => CrewWeekSummary(
  weekStart: weekStart,
  percent: percent,
  shareOut: const [0, 0, 0, 0, 0, 0, 0],
);

/// The crew's finished weeks, newest first, the way the backend hands them
/// back: six of them, one more than the bars have room for.
final _history = [
  _summary('2026-09-07', 100),
  _summary('2026-08-31', 72),
  _summary('2026-08-24', 100),
  _summary('2026-08-17', 40),
  _summary('2026-08-10', 100),
  _summary('2026-08-03', 100),
];

Finder _bar(String weekStart) =>
    find.byKey(ValueKey('streak-week-bar-$weekStart'));

Color? _colourOf(WidgetTester tester, String weekStart) =>
    ((tester.widget<Container>(_bar(weekStart)).decoration!) as ShapeDecoration)
        .color;

Future<void> _pump(
  WidgetTester tester, {
  required List<CrewWeekSummary>? history,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: CrewStreakCard(
            week: _week,
            history: history,
            onViewMonth: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('the bars run oldest to newest, this week at the right', (
    tester,
  ) async {
    await _pump(tester, history: _history);
    // The five most recent finished weeks and this one; the oldest week the
    // history carried has no room left.
    const shown = [
      '2026-08-10',
      '2026-08-17',
      '2026-08-24',
      '2026-08-31',
      '2026-09-07',
      '2026-09-14',
    ];
    for (final weekStart in shown) {
      expect(_bar(weekStart), findsOneWidget);
    }
    expect(_bar('2026-08-03'), findsNothing);
    final lefts = [for (final w in shown) tester.getTopLeft(_bar(w)).dx];
    for (var i = 1; i < lefts.length; i++) {
      expect(lefts[i], greaterThan(lefts[i - 1]));
    }
    // A full history leaves no empty places.
    expect(find.byKey(const ValueKey('streak-week-empty-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a week kept in full takes the flame colour and the full line', (
    tester,
  ) async {
    await _pump(tester, history: _history);
    // A week joins the streak only when it is kept in full, so those take the
    // flame's colour and stand as tall as the dashed line over them.
    final full = tester.getSize(_bar('2026-09-07')).height;
    for (final kept in ['2026-08-10', '2026-08-24', '2026-09-07']) {
      expect(_colourOf(tester, kept), WeekPactColors.streak);
      expect(tester.getSize(_bar(kept)).height, full);
    }
    // Short of it is grey, at its share of the line.
    for (final short in ['2026-08-17', '2026-08-31']) {
      expect(_colourOf(tester, short), isNot(WeekPactColors.streak));
    }
    expect(tester.getSize(_bar('2026-08-31')).height, closeTo(full * .72, .01));
    // This week, a quarter kept, is neither the flame's colour nor the grey
    // of a finished week short of it: it is where the crew is standing.
    expect(_colourOf(tester, '2026-09-14'), isNot(WeekPactColors.streak));
    expect(
      _colourOf(tester, '2026-09-14'),
      isNot(_colourOf(tester, '2026-08-31')),
    );
    expect(tester.getSize(_bar('2026-09-14')).height, closeTo(full * .25, .01));
  });

  testWidgets('a short history leaves the oldest places empty', (tester) async {
    await _pump(tester, history: _history);
    final fullRight = tester.getTopRight(_bar('2026-09-14')).dx;

    // Two finished weeks: three places stand empty at the left, and this week
    // still ends the row where it did with a full history.
    await _pump(tester, history: _history.take(2).toList());
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(ValueKey('streak-week-empty-$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('streak-week-empty-3')), findsNothing);
    final oldest = tester.getTopLeft(_bar('2026-08-31')).dx;
    for (var i = 0; i < 3; i++) {
      expect(
        tester.getTopRight(find.byKey(ValueKey('streak-week-empty-$i'))).dx,
        lessThan(oldest),
      );
    }
    expect(tester.getTopRight(_bar('2026-09-14')).dx, fullRight);

    // No history yet: this week alone, at the right, after five empty places.
    await _pump(tester, history: null);
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('streak-week-empty-$i')), findsOneWidget);
    }
    expect(tester.getTopRight(_bar('2026-09-14')).dx, fullRight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day the crew was out wears its most-kept pact\'s colour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const week = CrewWeek(
      today: '2026-09-16',
      weekStart: '2026-09-14',
      timezone: 'UTC',
      pacts: [
        CrewPact(
          id: 'hang',
          crewId: 'crew',
          title: 'Hangboard',
          frequency: PactFrequency.weekly,
          daysPerWeek: 2,
        ),
        CrewPact(
          id: 'read',
          crewId: 'crew',
          title: 'Read',
          frequency: PactFrequency.daily,
          daysPerWeek: 7,
        ),
      ],
      members: [
        WeekMember('0', 'me@example.com'),
        WeekMember('1', 'friend@example.com'),
      ],
      checkIns: [
        // Monday: Read twice, Hangboard once — Read wins.
        PactCheckIn('read', '0', '2026-09-14'),
        PactCheckIn('read', '1', '2026-09-14'),
        PactCheckIn('hang', '0', '2026-09-14'),
        // Tuesday: one each — the tie goes to Hangboard, first in the list.
        PactCheckIn('read', '0', '2026-09-15'),
        PactCheckIn('hang', '1', '2026-09-15'),
      ],
    );
    final history = [
      CrewWeekSummary(
        weekStart: '2026-09-07',
        percent: 50,
        shareOut: const [.5, .5, 0, 0, 0, 0, 0],
        // Monday from the server; Tuesday from a server too old to say.
        topPacts: const ['read'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: CrewStreakCard(
              week: week,
              history: history,
              onViewMonth: () {},
            ),
          ),
        ),
      ),
    );
    Color? day(String iso) =>
        ((tester
                    .widget<Container>(find.byKey(ValueKey('streak-day-$iso')))
                    .decoration!)
                as ShapeDecoration)
            .color;
    expect(day('2026-09-14'), WeekPactColors.pactBadge(1));
    expect(day('2026-09-15'), WeekPactColors.pactBadge(0));
    expect(day('2026-09-07'), WeekPactColors.pactBadge(1));
    // Out, but with no pact to go on: the plain ink it always had.
    expect(day('2026-09-08'), WeekPactColors.darkInk);
    // Not out at all: no pact colour.
    expect(day('2026-09-09'), isNot(WeekPactColors.pactBadge(0)));
    expect(day('2026-09-09'), isNot(WeekPactColors.pactBadge(1)));
  });
}
