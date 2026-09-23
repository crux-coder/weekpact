import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/dashed_border.dart';

/// A crew of four, on a week starting Monday 7 September 2026 with Wednesday
/// as today: two days behind, today, and four still ahead.
CrewWeek week({
  Map<String, List<String>> out = const {},
  int members = 4,
  String today = '2026-09-09',
}) => CrewWeek(
  today: today,
  weekStart: '2026-09-07',
  timezone: 'UTC',
  pacts: const [
    CrewPact(
      id: 'move',
      crewId: 'crew',
      title: 'Move for 30 min',
      frequency: PactFrequency.weekly,
      daysPerWeek: 5,
      iconKey: 'run',
    ),
    CrewPact(
      id: 'read',
      crewId: 'crew',
      title: 'Read 20 pages',
      frequency: PactFrequency.weekly,
      daysPerWeek: 5,
      iconKey: 'book',
    ),
  ],
  members: [
    for (var i = 0; i < members; i++)
      WeekMember('member-$i', 'member$i@example.com'),
  ],
  checkIns: [
    for (final day in out.entries)
      for (final who in day.value) PactCheckIn('move', who, day.key),
  ],
);

Future<void> pumpBar(
  WidgetTester tester,
  CrewWeek? crew, {
  VoidCallback? onOpenWeek,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 366,
            child: crew == null
                ? const CrewTodayBar.loading()
                : CrewTodayBar(week: crew, onOpenWeek: onOpenWeek),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The filled part of one day's column, or null when the day took nobody.
SizedBox? fill(WidgetTester tester, String day) {
  final boxes = tester.widgetList<SizedBox>(
    find.descendant(
      of: find.byKey(ValueKey('crew-week-day-$day')),
      matching: find.byType(SizedBox),
    ),
  );
  // The column's own box is the track; the one inside it is the fill.
  final inner = boxes.where((box) => (box.height ?? 0) > 0).skip(1);
  return inner.isEmpty ? null : inner.first;
}

bool isAhead(WidgetTester tester, String day) => find
    .descendant(
      of: find.byKey(ValueKey('crew-week-day-$day')),
      matching: find.byType(DashedBorder),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  testWidgets('the week keeps all seven days, however little was kept', (
    tester,
  ) async {
    await pumpBar(tester, week());
    for (final day in [
      '2026-09-07',
      '2026-09-08',
      '2026-09-09',
      '2026-09-10',
      '2026-09-11',
      '2026-09-12',
      '2026-09-13',
    ]) {
      expect(find.byKey(ValueKey('crew-week-day-$day')), findsOneWidget);
    }
    // Monday first, and the two pairs that share a letter kept in order.
    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(2));
    expect(find.text('S'), findsNWidgets(2));
  });

  testWidgets('a column is filled to the share of the crew that was out', (
    tester,
  ) async {
    await pumpBar(
      tester,
      week(
        out: {
          '2026-09-07': ['member-0', 'member-1', 'member-2', 'member-3'],
          '2026-09-08': ['member-0', 'member-1'],
          '2026-09-09': ['member-0'],
        },
      ),
    );
    // A full crew fills the track, less the points the block's edge stands on;
    // half of it fills half of that.
    expect(fill(tester, '2026-09-07')!.height, 36);
    expect(fill(tester, '2026-09-08')!.height, 18);
    // One of four is 9 points, which clears the four-point floor on its own.
    expect(fill(tester, '2026-09-09')!.height, 9);
    // The columns are the count. Nothing beside them says it again in figures.
    expect(find.text('1/4'), findsNothing);
    expect(find.text('Crew week'), findsOneWidget);
  });

  testWidgets('one person out of a large crew is never drawn as nobody', (
    tester,
  ) async {
    await pumpBar(
      tester,
      week(
        members: 20,
        out: {
          '2026-09-08': ['member-0'],
        },
      ),
    );
    // 1/20 of 36 points is 1.8 — a hairline nobody reads as a mark.
    expect(fill(tester, '2026-09-08')!.height, 4);
  });

  testWidgets('a member counts once a day, however many pacts they kept', (
    tester,
  ) async {
    final crew = week(members: 2);
    final doubled = CrewWeek(
      today: crew.today,
      weekStart: crew.weekStart,
      timezone: crew.timezone,
      pacts: crew.pacts,
      members: crew.members,
      checkIns: const [
        PactCheckIn('move', 'member-0', '2026-09-08'),
        PactCheckIn('read', 'member-0', '2026-09-08'),
      ],
    );
    await pumpBar(tester, doubled);
    // Half the crew, not all of it.
    expect(fill(tester, '2026-09-08')!.height, 18);
  });

  testWidgets('days still to come are outlines, and days behind are not', (
    tester,
  ) async {
    await pumpBar(tester, week());
    expect(isAhead(tester, '2026-09-07'), isFalse);
    expect(isAhead(tester, '2026-09-09'), isFalse, reason: 'today has been');
    expect(isAhead(tester, '2026-09-10'), isTrue);
    expect(isAhead(tester, '2026-09-13'), isTrue);
  });

  testWidgets('the count is said in full for a screen reader, and the handle '
      'only appears when there is something to open', (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await pumpBar(
      tester,
      week(
        out: {
          '2026-09-09': ['member-0', 'member-1'],
        },
      ),
      onOpenWeek: () => opened++,
    );
    expect(
      find.bySemanticsLabel('2 of 4 checked in today, open the crew week'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('open-crew-week')));
    expect(opened, 1);

    // The same week with nowhere to go says the count and stops there.
    await pumpBar(
      tester,
      week(
        out: {
          '2026-09-09': ['member-0', 'member-1'],
        },
      ),
    );
    expect(find.bySemanticsLabel('2 of 4 checked in today'), findsOneWidget);
    expect(find.text('Crew week'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the loading row holds the same height, and opens nothing', (
    tester,
  ) async {
    await pumpBar(tester, null);
    expect(
      tester.getSize(find.byKey(const ValueKey('crew-today-bar'))).height,
      CrewTodayBar.height,
    );
    // No handle while there is nothing to open, and no label promising one.
    expect(find.text('Crew week'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
