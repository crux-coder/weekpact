import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/your_week.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/pump_ui.dart';

const _pacts = [
  CrewPact(
    id: 'gym',
    crewId: 'crew',
    title: 'Gym',
    frequency: PactFrequency.weekly,
    daysPerWeek: 4,
    iconKey: 'gym',
  ),
  CrewPact(
    id: 'read',
    crewId: 'crew',
    title: 'Read',
    frequency: PactFrequency.weekly,
    daysPerWeek: 6,
    iconKey: 'book',
  ),
  CrewPact(
    id: 'water',
    crewId: 'crew',
    title: 'Water',
    frequency: PactFrequency.weekly,
    daysPerWeek: 2,
    iconKey: 'target',
  ),
];

/// A Thursday: Monday to Wednesday gone, four days left with today.
CrewWeek _week({
  List<PactCheckIn> checkIns = const [],
  String today = '2026-09-17',
  List<WeekMember>? members,
}) => CrewWeek(
  today: today,
  weekStart: '2026-09-14',
  timezone: 'Europe/Sarajevo',
  pacts: _pacts,
  members:
      members ??
      const [
        WeekMember('me', 'me@example.com', displayName: 'Jasmin'),
        WeekMember('amir', 'amir@example.com', displayName: 'Amir Hodžić'),
        WeekMember('sara', 'sara@example.com', displayName: 'Sara'),
      ],
  checkIns: checkIns,
);

/// [counts] check-ins for each member, kept from Monday up to [today] across
/// the pacts, never past what a pact asks, so each is a counted one.
List<PactCheckIn> _kept(
  Map<String, int> counts, {
  String today = '2026-09-17',
}) {
  final days =
      DateTime.parse(today).difference(DateTime(2026, 9, 14)).inDays + 1;
  return [
    for (final MapEntry(key: id, value: n) in counts.entries)
      ...[
        for (final pact in _pacts)
          for (var d = 0; d < pact.daysPerWeek && d < days; d++)
            PactCheckIn(pact.id, id, '2026-09-${14 + d}'),
      ].take(n),
  ];
}

/// The podium's headline for the viewer, with [counts] kept each.
String _headline(
  Map<String, int> counts, {
  String today = '2026-09-17',
  List<WeekMember>? members,
}) => YourWeek(
  _week(
    checkIns: _kept(counts, today: today),
    today: today,
    members: members,
  ),
  'me',
).headline.toString();

const _mine = [
  PactCheckIn('gym', 'me', '2026-09-14', clapCount: 2),
  PactCheckIn('gym', 'me', '2026-09-15', clapCount: 1),
  PactCheckIn('read', 'me', '2026-09-15'),
  PactCheckIn('water', 'me', '2026-09-14'),
  PactCheckIn('water', 'me', '2026-09-17', clapCount: 4),
  // Last week's claps are not this week's.
  PactCheckIn('gym', 'me', '2026-09-10', clapCount: 9),
];

void main() {
  test('each pact says how far along it is and what it still needs', () {
    final mine = YourWeek(_week(checkIns: _mine), 'me');
    expect(mine.daysLeft, 4);
    expect(mine.keptDays, [true, true, false, true, false, false, false]);
    expect(mine.completed, 5);
    expect(mine.target, 12);

    final [gym, read, water] = mine.pacts;
    // Gym: 2 of 4, today open, so five days to keep two in.
    expect((gym.kept, gym.toGo, gym.openDays), (2, 2, 4));
    expect(gym.state, PactPaceState.onTrack);
    // Read: 1 of 6 with four days to go is out of reach.
    expect(read.state, PactPaceState.outOfReach);
    // Water: kept twice, done; today's check-in closes today for it.
    expect((water.kept, water.openDays), (2, 3));
    expect(water.state, PactPaceState.done);

    expect(mine.claps, 7);
  });

  test('a pact that needs every day left says so', () {
    final mine = YourWeek(
      _week(
        checkIns: const [
          PactCheckIn('read', 'me', '2026-09-14'),
          PactCheckIn('read', 'me', '2026-09-15'),
        ],
      ),
      'me',
    );
    expect(mine.pacts[1].toGo, 4);
    expect(mine.pacts[1].state, PactPaceState.everyDay);
  });

  test('the place line names who to pass next, or the lead', () {
    final behind = YourWeek(
      _week(
        checkIns: [
          ..._mine,
          for (final day in ['2026-09-14', '2026-09-15', '2026-09-16'])
            PactCheckIn('gym', 'amir', day),
          for (final day in ['2026-09-14', '2026-09-15', '2026-09-16'])
            PactCheckIn('read', 'amir', day),
          for (final day in ['2026-09-14', '2026-09-15', '2026-09-16'])
            PactCheckIn('read', 'sara', day),
          const PactCheckIn('gym', 'sara', '2026-09-14'),
          const PactCheckIn('gym', 'sara', '2026-09-15'),
          const PactCheckIn('gym', 'sara', '2026-09-16'),
        ],
      ),
      'me',
    );
    // Amir and Sara share first on 6, so the viewer is third, and either is
    // the one to pass, by 2.
    expect(behind.standing!.place, 3);
    expect(
      behind.placeNote,
      matches(RegExp(r'^2 check-ins to pass (Amir|Sara)$')),
    );

    final ahead = YourWeek(_week(checkIns: _mine), 'me');
    expect(ahead.standing!.place, 1);
    // Amir and Sara share second on nothing: the lead is over both.
    expect(ahead.placeNote, '5 check-ins ahead of Amir and Sara');

    List<PactCheckIn> amirOn(int days) => [
      for (final day in [
        '2026-09-14',
        '2026-09-15',
        '2026-09-16',
        '2026-09-17',
      ].take(days))
        PactCheckIn('gym', 'amir', day),
      if (days > 4) const PactCheckIn('water', 'amir', '2026-09-14'),
    ];
    expect(
      YourWeek(_week(checkIns: [..._mine, ...amirOn(4)]), 'me').placeNote,
      '1 check-in ahead of Amir',
    );
    expect(
      YourWeek(_week(checkIns: [..._mine, ...amirOn(5)]), 'me').placeNote,
      'Tied with Amir',
    );

    final tied = YourWeek(_week(), 'me');
    expect(tied.placeNote, 'Tied with Amir and Sara');
  });

  test('the podium headline says one thing for each place', () {
    const monday = '2026-09-14';
    const sunday = '2026-09-20';
    expect(
      _headline({}, today: monday),
      'Fresh week · The first check-in takes the lead',
    );
    expect(
      _headline({}),
      'Nobody’s on the board yet · The first check-in takes the lead',
    );
    expect(
      _headline({'me': 12, 'amir': 3}, today: sunday),
      'Week done · Every pact kept. Cheer the rest on',
    );
    expect(
      _headline({'me': 2, 'amir': 2, 'sara': 2}),
      'All square · The whole crew is on 17%',
    );
    expect(
      _headline({'me': 3, 'amir': 3, 'sara': 1}),
      'Neck and neck · You and Amir share the top',
    );
    expect(
      _headline({'me': 5, 'amir': 3, 'sara': 3}),
      'You’re out in front · 2 check-ins ahead of Amir and Sara',
    );
    expect(
      _headline({'me': 4, 'amir': 5}, today: sunday),
      'Last day, 1 behind · One check-in ties it with Amir',
    );
    expect(
      _headline({'me': 4, 'amir': 5}),
      'Right on Amir’s heels · One check-in ties the lead',
    );
    expect(
      _headline({'me': 1, 'amir': 5, 'sara': 3}),
      'Plenty of week left · 3 check-ins to pass Sara',
    );
    expect(
      _headline({'me': 3, 'amir': 6, 'sara': 1}),
      'You’re 2nd of 3 · 4 check-ins to pass Amir',
    );
  });

  test('a crew of one hears about its own week', () {
    const solo = [WeekMember('me', 'me@example.com', displayName: 'Jasmin')];
    expect(
      _headline({}, members: solo),
      'Fresh week · Your first check-in starts it',
    );
    expect(
      _headline({'me': 3}, members: solo),
      '25% of your week · 9 check-ins to go',
    );
  });

  testWidgets('your card opens the viewer’s week', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: Center(
            child: YourWeekPanel(
              week: _week(checkIns: _mine),
              userId: 'me',
            ),
          ),
        ),
      ),
    );
    // One card: your headline over your days and count.
    expect(find.text('You’re out in front'), findsOneWidget);
    expect(find.text('5 check-ins ahead of Amir and Sara'), findsOneWidget);
    expect(find.text('5 / 12'), findsOneWidget);
    expect(
      tester.getRect(find.byType(YourWeekPanel)).height,
      YourWeekPanel.height,
    );
    await tester.tap(find.byKey(const ValueKey('your-week-row')));
    await tester.pumpUi();

    final sheet = find.byKey(const ValueKey('your-week-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.text('Thursday · 4 days left · 5 of 12 check-ins'),
      findsOneWidget,
    );
    expect(find.text('2 to go'), findsOneWidget);
    expect(find.text('Out of reach this week'), findsOneWidget);
    expect(find.text('Done for the week'), findsOneWidget);
    expect(find.text('1st place'), findsOneWidget);
    expect(find.text('7 this week'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
