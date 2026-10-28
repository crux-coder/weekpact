import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/dashed_border.dart';
import 'package:weekpact/src/crew/crew_switcher.dart';

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
  int streakWeeks = 0,
  String today = '2026-09-09',
}) => CrewWeek(
  today: today,
  weekStart: '2026-09-07',
  timezone: 'UTC',
  streakWeeks: streakWeeks,
  pacts: _pacts,
  members: [for (final id in progress.keys) WeekMember(id, '$id@example.com')],
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

/// Every step currently on the podium.
final _podiumSteps = find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('podium-step-'),
);

/// A member's bar on the podium.
Rect _bar(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('podium-bar-$id')));

/// A member's bar colour.
Color _barColour(WidgetTester tester, String id) =>
    ((tester
                .widget<Container>(find.byKey(ValueKey('podium-bar-$id')))
                .decoration!
            as ShapeDecoration)
        .color!);

void main() {
  test(
    'places are read as places: ties share one, and the next is skipped',
    () {
      final week = _weekWith({
        'leader': (move: 3, read: 2),
        'me': (move: 1, read: 0),
        'level': (move: 1, read: 0),
        'last': (move: 0, read: 0),
      });
      final standings = week.standings('me');
      expect(
        [for (final s in standings) s.member.id],
        ['leader', 'me', 'level', 'last'],
      );
      // Two members on the same figure share second, and nobody is third.
      expect([for (final s in standings) s.place], [1, 2, 2, 4]);
      expect(
        [for (final s in standings) s.isViewer],
        [false, true, false, false],
      );
      expect(standings.first.percent, 100);
      expect(standings.last.percent, 0);
    },
  );

  testWidgets('the crew week is a podium, not an average', (tester) async {
    // 'me' has kept three of the five days they owe; 'other' has kept none.
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 2, read: 1),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('crew-podium')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-face-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-face-other')), findsOneWidget);
    // The leader is crowned, stands taller, and stands to the right of second.
    expect(find.byKey(const ValueKey('podium-crown-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-crown-other')), findsNothing);
    expect(
      _bar(tester, 'me').height,
      greaterThan(_bar(tester, 'other').height),
    );
    expect(_bar(tester, 'me').left, greaterThan(_bar(tester, 'other').left));
    // Further along is a different colour on the scale.
    expect(_barColour(tester, 'me'), isNot(_barColour(tester, 'other')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the card names what it shows, and leaves your headline to its own card',
    (tester) async {
      await _pump(
        tester,
        CrewPodiumPanel(
          userId: 'me',
          week: _weekWith({
            'me': (move: 2, read: 1),
            'other': (move: 0, read: 0),
          }, streakWeeks: 4),
        ),
      );
      // The podium says what it is, a crew of two's top two, and nothing
      // about you: that is the headline card's.
      expect(find.text('Top 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('podium-headline')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('podium-bar-me')),
          matching: find.text('60%'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          // Under half a week the figure stands on the bar rather than in it.
          of: find.byKey(const ValueKey('podium-step-other')),
          matching: find.text('0%'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('crew-week-streak')), findsNothing);
      // The standing is still said, to a screen reader.
      final semantics = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Crew week',
        ),
      );
      expect(semantics.properties.value, contains('You are 1st of 2'));
    },
  );

  testWidgets('the card stands on the crew week bar\'s surface', (
    tester,
  ) async {
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(CrewPodiumPanel),
        matching: find.byType(CrewHeaderSurface),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a week fully kept is gold, and only that week', (tester) async {
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'done': (move: 3, read: 2),
          'also': (move: 3, read: 2),
          'me': (move: 2, read: 1),
        }),
      ),
    );
    expect(_barColour(tester, 'done'), WeekPactColors.gold);
    expect(_barColour(tester, 'also'), WeekPactColors.gold);
    expect(_barColour(tester, 'me'), isNot(WeekPactColors.gold));
  });

  testWidgets('a bar is its share of the full height, and a face moves in at '
      'half', (tester) async {
    // Five check-ins owed: 'done' has all five, 'half' three, 'none' none.
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'done',
        week: _weekWith({
          'done': (move: 3, read: 2),
          'half': (move: 2, read: 1),
          'none': (move: 0, read: 0),
        }),
      ),
    );
    final full = _bar(tester, 'done').height;
    expect(_bar(tester, 'half').height, closeTo(full * .6, 1));
    // An empty week is still a sliver, so it can be seen.
    expect(_bar(tester, 'none').height, greaterThan(0));
    expect(_bar(tester, 'none').height, lessThan(full * .1));
    bool inBar(String id) => find
        .descendant(
          of: find.byKey(ValueKey('podium-bar-$id')),
          matching: find.byKey(ValueKey('podium-face-$id')),
        )
        .evaluate()
        .isNotEmpty;
    expect(inBar('done'), isTrue);
    expect(inBar('half'), isTrue);
    // 'none' is under half: its face stands on its bar, not in it.
    expect(inBar('none'), isFalse);
    expect(
      tester.getRect(find.byKey(const ValueKey('podium-face-none'))).bottom,
      lessThanOrEqualTo(_bar(tester, 'none').top),
    );
  });

  testWidgets('a crew that is level shows no place, not first and second', (
    tester,
  ) async {
    // Two members on the same figure are not a first and a second decided by
    // whatever order the roster arrived in: no crown, and one height of bar.
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 1, read: 0),
        }),
      ),
    );
    expect(find.byKey(const ValueKey('podium-crown-me')), findsNothing);
    expect(find.byKey(const ValueKey('podium-crown-other')), findsNothing);
    expect(_bar(tester, 'me').height, _bar(tester, 'other').height);
    // The colour is the progress's, not the person's: level is one colour.
    expect(_barColour(tester, 'me'), _barColour(tester, 'other'));
  });

  testWidgets('a crew of one stands on its own bar', (tester) async {
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({'me': (move: 2, read: 1)}),
      ),
    );
    expect(find.byKey(const ValueKey('podium-bar-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-crown-me')), findsNothing);
    // One member is one bar, across the card's width less its inset.
    final card = tester.getRect(find.byType(CrewPodiumPanel));
    expect(
      _bar(tester, 'me').width,
      closeTo(card.width - WeekPactMetrics.pageInset * 2, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the loading panel stands in the card\'s place', (tester) async {
    await _pump(tester, const CrewPodiumPanel.loading());
    final loading = tester.getRect(find.byType(CrewPodiumPanel));
    expect(_podiumSteps, findsNothing);
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(tester.getRect(find.byType(CrewPodiumPanel)), loading);
    expect(loading.height, CrewPodiumPanel.height);
  });

  testWidgets('the block is the card, with no day under it', (tester) async {
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith(
          {'me': (move: 1, read: 0), 'other': (move: 0, read: 0)},
          checkedToday: const {'other'},
        ),
      ),
    );
    // The day's pull-down went with the score before it: the stories rail at
    // the top of the page says who is in, and a frame around a single card is
    // a box drawn round one object.
    expect(find.text('in today'), findsNothing);
    // What is left is the card, at the card's own height, and the gold tab
    // standing half over its top edge.
    expect(
      tester.getRect(find.byType(CrewPodiumPanel)).height,
      CrewPodiumPanel.height,
    );
    expect(
      tester.getRect(find.byType(CrewHeaderSurface)).height,
      CrewPodiumPanel.cardHeight,
    );
    final tab = tester.getRect(find.byKey(const ValueKey('podium-top-tab')));
    final card = tester.getRect(find.byType(CrewHeaderSurface));
    expect(tab.top, lessThan(card.top));
    expect(tab.bottom, greaterThan(card.top));
    expect(tab.center.dx, closeTo(card.center.dx, 1));
  });

  testWidgets('the block is one height, whatever the crew', (tester) async {
    for (final size in [1, 2, 9, 20]) {
      await _pump(
        tester,
        CrewPodiumPanel(
          userId: 'member0',
          week: _weekWith({
            for (var i = 0; i < size; i++) 'member$i': (move: 1, read: 0),
          }),
        ),
      );
      expect(
        tester.getRect(find.byType(CrewPodiumPanel)).height,
        CrewPodiumPanel.height,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a viewer off the podium stands beside it', (tester) async {
    // Nine members, and the viewer trailing: the podium holds three places,
    // and you, so the card is still about where you are.
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'member8',
        week: _weekWith({
          for (var i = 0; i < 9; i++)
            'member$i': (move: i > 5 ? 0 : 3 - i ~/ 2, read: 0),
        }),
      ),
    );
    expect(find.byKey(const ValueKey('crew-podium')), findsOneWidget);
    // Three places on the podium, and the viewer's own bar beside it.
    expect(tester.widgetList(_podiumSteps).length, 4);
    expect(find.byKey(const ValueKey('podium-viewer')), findsOneWidget);
    // Beside it, a dashed box with your place and your figure.
    final viewer = find.byKey(const ValueKey('podium-viewer'));
    expect(
      find.descendant(of: viewer, matching: find.byType(DashedBorder)),
      findsOneWidget,
    );
    expect(find.descendant(of: viewer, matching: find.text('7th')), findsOne);
    expect(find.descendant(of: viewer, matching: find.text('0%')), findsOne);
    expect(find.byKey(const ValueKey('podium-face-member8')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-face-member0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a viewer tied with third stands on the podium', (tester) async {
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'leader': (move: 1, read: 0),
          'b': (move: 0, read: 0),
          'c': (move: 0, read: 0),
          'me': (move: 0, read: 0),
        }),
      ),
    );
    expect(find.byKey(const ValueKey('podium-viewer')), findsNothing);
    expect(find.byKey(const ValueKey('podium-bar-me')), findsOneWidget);
    expect(tester.widgetList(_podiumSteps).length, 3);
  });

  testWidgets('a viewer on the podium is not drawn twice', (tester) async {
    await _pump(
      tester,
      CrewPodiumPanel(
        userId: 'me',
        week: _weekWith({
          'leader': (move: 3, read: 2),
          'me': (move: 2, read: 0),
          'third': (move: 1, read: 0),
          'last': (move: 0, read: 0),
        }),
      ),
    );
    expect(find.byKey(const ValueKey('podium-viewer')), findsNothing);
    expect(find.byKey(const ValueKey('podium-face-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-face-last')), findsNothing);
    // The card no longer opens: everything it had to say is on its face.
    expect(find.byKey(const ValueKey('crew-panel-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('open-crew-week')), findsNothing);
  });

  testWidgets(
    'larger system text scales into the panel rather than out of it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 366,
                child: CrewPodiumPanel(
                  userId: 'me',
                  week: _weekWith({
                    'me': (move: 3, read: 1),
                    'other': (move: 1, read: 0),
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpUi();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(CrewPodiumPanel)).height,
        CrewPodiumPanel.height,
      );
    },
  );
}
