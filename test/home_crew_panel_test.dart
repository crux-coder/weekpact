import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';

import 'support/pump_ui.dart';

/// Two members owing five days a week each: ten check-ins to the week.
const _pacts = [
  CrewPact(
    id: 'move',
    crewId: 'crew',
    title: 'Move',
    frequency: PactFrequency.weekly,
    daysPerWeek: 3,
    iconKey: 'run',
  ),
  CrewPact(
    id: 'read',
    crewId: 'crew',
    title: 'Read',
    frequency: PactFrequency.weekly,
    daysPerWeek: 2,
    iconKey: 'book',
  ),
];

const _days = ['2026-09-07', '2026-09-08', '2026-09-09'];

CrewWeek _weekWith(
  Map<String, ({int move, int read})> progress, {
  Set<String> checkedToday = const {},
}) => CrewWeek(
  today: '2026-09-09',
  weekStart: '2026-09-07',
  timezone: 'UTC',
  pacts: _pacts,
  members: [
    for (final id in progress.keys) WeekMember(id, '$id@example.com'),
  ],
  checkIns: [
    for (final entry in progress.entries) ...[
      for (var day = 0; day < entry.value.move; day++)
        PactCheckIn('move', entry.key, _days[day]),
      for (var day = 0; day < entry.value.read; day++)
        PactCheckIn('read', entry.key, _days[day]),
    ],
    // Today's own check-ins, on top of whatever the week already holds.
    for (final id in checkedToday) PactCheckIn('move', id, _days.last),
  ],
);

Future<void> _pump(WidgetTester tester, Widget panel) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Center(child: SizedBox(width: 366, child: panel)),
      ),
    ),
  );
  await tester.pumpUi();
}

/// The card's own fill, past the frame the panel holds it in.
Color _cardFill(WidgetTester tester) => tester
    .widgetList<AppSurface>(find.byType(AppSurface))
    .firstWhere((surface) => surface.fillColor != null)
    .fillColor!;

void main() {
  testWidgets('the panel reads the crew week as one percentage', (
    tester,
  ) async {
    // Three of the ten the two of them owe, capped at each pact's own target.
    await _pump(
      tester,
      HomeCrewPanel(
        week: _weekWith({
          'me': (move: 2, read: 1),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(find.text('CREW PROGRESS · THIS WEEK'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('crew-progress-percent')),
      findsOneWidget,
    );
    expect(find.textContaining('30'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(.3, .001));
    expect(_cardFill(tester), WeekPactColors.crewProgress);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a kept week turns the card mint and fills the bar', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        week: _weekWith({
          'me': (move: 3, read: 2),
          'other': (move: 3, read: 2),
        }),
      ),
    );
    expect(find.textContaining('100'), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      ).value,
      1,
    );
    expect(_cardFill(tester), WeekPactColors.mintGreen);
  });

  testWidgets('the loading panel stands in a two-person block\'s place', (
    tester,
  ) async {
    await _pump(tester, const HomeCrewPanel.loading());
    final loading = tester.getRect(find.byType(HomeCrewPanel));
    expect(find.text('CREW PROGRESS · THIS WEEK'), findsNothing);
    expect(find.text('in today'), findsNothing);
    await _pump(
      tester,
      HomeCrewPanel(
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(tester.getRect(find.byType(HomeCrewPanel)), loading);
    expect(loading.height, HomeCrewPanel.height);
  });

  testWidgets('the block carries the day under the card', (tester) async {
    // The strip's own reading of the day is covered in
    // crew_today_strip_test; here it only has to be in its place.
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }, checkedToday: const {'other'}),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('/2'), findsOneWidget);
    expect(find.text('in today'), findsOneWidget);
    expect(
      tester.getRect(find.text('in today')).top,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('open-crew-week'))).top,
      ),
    );
  });

  testWidgets('the block is one height, whatever the crew', (tester) async {
    for (final size in [1, 2, 9]) {
      await _pump(
        tester,
        HomeCrewPanel(
          week: _weekWith({
            for (var i = 0; i < size; i++) 'member$i': (move: 1, read: 0),
          }),
        ),
      );
      expect(
        tester.getRect(find.byType(HomeCrewPanel)).height,
        HomeCrewPanel.height,
      );
    }
  });

  testWidgets('the progress card is the way into the crew week', (
    tester,
  ) async {
    var opened = 0;
    await _pump(
      tester,
      HomeCrewPanel(
        week: _weekWith({'me': (move: 1, read: 0)}),
        onOpenWeek: () => opened++,
      ),
    );
    expect(find.byTooltip('View week'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-crew-week')));
    await tester.pumpUi();
    expect(opened, 1);
    // The week is what the page shows, so the card that reads it is the door
    // rather than the day's rows under it.
    expect(
      tester.getRect(find.byKey(const ValueKey('open-crew-week'))).bottom,
      lessThan(tester.getRect(find.text('in today')).top),
    );
    // Nothing to open before the week has arrived.
    await _pump(tester, const HomeCrewPanel.loading());
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('open-crew-week')))
          .onTap,
      isNull,
    );
  });

  testWidgets('larger system text scales into the panel rather than out of it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 366,
              child: HomeCrewPanel(
                week: _weekWith({'me': (move: 3, read: 1)}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(HomeCrewPanel)).height,
      HomeCrewPanel.height,
    );
  });
}
