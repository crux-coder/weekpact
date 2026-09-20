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

  testWidgets('the card counts the whole crew, the viewer included', (
    tester,
  ) async {
    await _pump(
      tester,
      _week(
        members: const [
          WeekMember('me', 'me@example.com', displayName: 'Jasmin Mustafic'),
          WeekMember('ak', 'ak@example.com', displayName: 'Amra Kovac'),
          WeekMember('ts', 'ts@example.com', displayName: 'Tarik Selimovic'),
        ],
        inToday: ['ak'],
      ),
    );
    // Three in the crew, so the card says three. Counting only the others
    // made a crew of three read "0 of 2", which is the crew strip higher up
    // Home saying one thing and this card saying another about one crew.
    expect(find.text('1 of 3 in today'), findsOneWidget);
    expect(find.text('JM'), findsOneWidget);
    expect(find.text('AK'), findsOneWidget);
    expect(find.text('TS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the viewer leads their group, as in the crew strip', (
    tester,
  ) async {
    await _pump(
      tester,
      _week(
        members: const [
          WeekMember('ak', 'ak@example.com', displayName: 'Amra Kovac'),
          WeekMember('me', 'me@example.com', displayName: 'Jasmin Mustafic'),
          WeekMember('ts', 'ts@example.com', displayName: 'Tarik Selimovic'),
        ],
        inToday: ['ak', 'me'],
      ),
    );
    // Kept-today first, and the viewer first within that group, however the
    // roster happens to arrive.
    double x(String initials) => tester.getRect(find.text(initials)).left;
    expect(x('JM'), lessThan(x('AK')));
    expect(x('AK'), lessThan(x('TS')));
    expect(find.text('2 of 3 in today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crew of one gets what the week still wants instead', (
    tester,
  ) async {
    await _pump(
      tester,
      _week(
        members: const [WeekMember('me', 'me@example.com', displayName: 'Me')],
        inToday: [],
        mine: 2,
      ),
    );
    // "1 of 1 in today" would be worse than saying nothing.
    expect(find.byKey(const ValueKey('pact-crew-move')), findsNothing);
    expect(find.textContaining('in today'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('to go'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crew too big for the row ends in a count, not a lie', (
    tester,
  ) async {
    await _pump(
      tester,
      _week(
        members: const [
          WeekMember('me', 'me@example.com', displayName: 'Me Myself'),
          WeekMember('a', 'a@example.com', displayName: 'Ann Able'),
          WeekMember('b', 'b@example.com', displayName: 'Bo Brown'),
          WeekMember('c', 'c@example.com', displayName: 'Cy Clark'),
          WeekMember('d', 'd@example.com', displayName: 'Dee Dunn'),
          WeekMember('e', 'e@example.com', displayName: 'Ed Ellis'),
        ],
        inToday: ['a', 'b'],
      ),
    );
    // Three faces and "+3" — never four faces standing for six people.
    expect(find.text('AA'), findsOneWidget);
    expect(find.text('BB'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('2 of 6 in today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the faces sit inside the card and clear the bar', (
    tester,
  ) async {
    await _pump(
      tester,
      _week(
        members: const [
          WeekMember('me', 'me@example.com', displayName: 'Me Myself'),
          WeekMember('ak', 'ak@example.com', displayName: 'Amra Kovac'),
        ],
        inToday: ['ak'],
      ),
    );
    final card = tester.getRect(find.byKey(const ValueKey('move')).hitTestable());
    final faces = tester.getRect(find.byKey(const ValueKey('pact-crew-move')));
    final bar = tester.getRect(
      find.byKey(const ValueKey('pact-progress-move')).hitTestable(),
    );
    // Flush with the card's own inset, and clear of the bar under it.
    expect(faces.right, closeTo(bar.right, 1));
    expect(faces.left, greaterThan(card.left));
    expect(faces.bottom, lessThanOrEqualTo(bar.top));
    expect(tester.takeException(), isNull);
  });
}
