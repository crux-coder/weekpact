import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/pump_ui.dart';

const _pact = CrewPact(
  id: 'move',
  crewId: 'crew',
  title: 'Gym',
  frequency: PactFrequency.daily,
  daysPerWeek: 5,
  iconKey: 'yoga',
);

CrewWeek _week({
  required List<WeekMember> members,
  required List<String> inToday,
  int mine = 0,
}) => CrewWeek(
  today: '2026-09-11',
  weekStart: '2026-09-07',
  timezone: 'UTC',
  pacts: const [_pact],
  members: members,
  checkIns: [
    for (final id in inToday) PactCheckIn(_pact.id, id, '2026-09-11'),
    for (var day = 0; day < mine; day++)
      PactCheckIn(_pact.id, 'me', '2026-09-0${7 + day}'),
  ],
);

Future<void> _pump(WidgetTester tester, CrewWeek week) async {
  tester.view.physicalSize = const Size(390, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: TodayPactsCard(
            height: 400,
            week: week,
            userId: 'me',
            savingPact: null,
            onToggle: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('the count reads as one line, with nothing beside it', (
    tester,
  ) async {
    // The box right of the count carried the crew's faces, then a days-to-go
    // figure. Both repeated what the rail and the bar already say, so the
    // count now stands alone with its caption on the same line.
    await _pump(
      tester,
      _week(
        members: const [
          WeekMember('me', 'me@example.com', displayName: 'Me'),
          WeekMember('ak', 'ak@example.com', displayName: 'Amra Kovac'),
        ],
        inToday: ['ak'],
        mine: 2,
      ),
    );
    expect(find.textContaining('in today'), findsNothing);
    expect(find.text('to go'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('/ 5'), findsOneWidget);
    expect(find.text('days this week'), findsOneWidget);
    final count = tester.getRect(find.text('2'));
    final caption = tester.getRect(find.text('days this week'));
    // Inline: the caption starts right of the count and sits inside the
    // count's own line rather than under it. Baselines are shared; boxes are
    // not, since the big number has no descender space and the caption does.
    expect(caption.left, greaterThan(count.right));
    expect(caption.center.dy, greaterThan(count.top));
    expect(caption.center.dy, lessThan(count.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crew of one reads the same way', (tester) async {
    await _pump(
      tester,
      _week(
        members: const [WeekMember('me', 'me@example.com', displayName: 'Me')],
        inToday: [],
        mine: 2,
      ),
    );
    expect(find.text('to go'), findsNothing);
    expect(find.text('days this week'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
