import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/crew_today_strip.dart';
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

/// The card's own fill, past the frame the panel holds it in.
Color _cardFill(WidgetTester tester) => tester
    .widgetList<AppSurface>(find.byType(AppSurface))
    .firstWhere((surface) => surface.fillColor != null)
    .fillColor!;

/// Every face currently drawn on the track.
final _raceFaces = find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('race-face-'),
);

/// Where a member's face sits on the track, in the track's own pixels.
double _faceX(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('race-face-$id'))).dx -
    tester.getTopLeft(find.byKey(const ValueKey('crew-race-track'))).dx;

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

  testWidgets('the crew week is a race, not an average', (tester) async {
    // 'me' has kept three of the five days they owe; 'other' has kept none.
    // The card used to fold both into "30%", which is a figure neither of
    // them can move on their own.
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 2, read: 1),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(find.text('CREW PROGRESS · THIS WEEK'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('crew-race-track')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-week-finish')), findsOneWidget);
    // Wednesday, so Thursday to Sunday plus today are still to run.
    expect(find.text('THIS WEEK · 5 DAYS LEFT'), findsOneWidget);
    expect(find.textContaining("YOU'RE"), findsOneWidget);
    expect(find.textContaining('1st'), findsOneWidget);
    // Everyone on the track, each at their own standing.
    expect(find.byKey(const ValueKey('race-face-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('race-face-other')), findsOneWidget);
    expect(_faceX(tester, 'me'), greaterThan(_faceX(tester, 'other')));
    expect(_cardFill(tester), WeekPactColors.crewProgress);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crew that is level is level, not first and second', (
    tester,
  ) async {
    // Two members on the same figure are not a first and a second decided by
    // whatever order the roster arrived in.
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 1, read: 0),
        }),
      ),
    );
    expect(find.text('LEVEL'), findsOneWidget);
    expect(find.textContaining("YOU'RE"), findsNothing);
    // And level members stand together on the track rather than one of them
    // standing in for both.
    expect(find.byKey(const ValueKey('race-face-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('race-face-other')), findsOneWidget);
    // 26 is the drawn face inside its ring: level members overlap rather
    // than spreading out across the card.
    expect(
      (_faceX(tester, 'me') - _faceX(tester, 'other')).abs(),
      lessThan(26),
    );
  });

  testWidgets('a kept week turns the card mint', (tester) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 3, read: 2),
          'other': (move: 3, read: 2),
        }),
      ),
    );
    expect(_cardFill(tester), WeekPactColors.mintGreen);
    expect(find.text('LEVEL'), findsOneWidget);
  });

  testWidgets('a crew of one keeps the bar, and has no place to be in', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(userId: 'me', week: _weekWith({'me': (move: 2, read: 1)})),
    );
    // There is nobody to race, so the card says what it always said: how much
    // of your own week is kept — on the same lane, at the same flag, so the
    // card does not change shape when a second member joins.
    expect(find.byKey(const ValueKey('crew-race-track')), findsNothing);
    expect(find.byKey(const ValueKey('crew-solo-track')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-week-finish')), findsOneWidget);
    expect(find.textContaining("YOU'RE"), findsNothing);
    expect(find.text('YOUR WEEK · 5 DAYS LEFT'), findsOneWidget);
    expect(find.textContaining('60'), findsOneWidget);
  });

  testWidgets('the last day of the week says so', (tester) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        // 2026-09-13 is a Sunday.
        week: _weekWith({'me': (move: 1, read: 0)}, today: '2026-09-13'),
      ),
    );
    expect(find.text('YOUR WEEK · LAST DAY'), findsOneWidget);
  });

  testWidgets('a running streak is the one loud thing on the card', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(find.byKey(const ValueKey('crew-week-streak')), findsNothing);
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }, streakWeeks: 4),
      ),
    );
    final streak = find.byKey(const ValueKey('crew-week-streak'));
    expect(streak, findsOneWidget);
    expect(
      find.descendant(of: streak, matching: find.text('4')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: streak, matching: find.byType(Text)),
          )
          .style
          ?.color,
      WeekPactColors.streak,
    );
  });

  testWidgets('the loading panel stands in the card\'s place', (tester) async {
    await _pump(tester, const HomeCrewPanel.loading());
    final loading = tester.getRect(find.byType(HomeCrewPanel));
    expect(find.byKey(const ValueKey('crew-race-track')), findsNothing);
    expect(find.textContaining('DAYS LEFT'), findsNothing);
    // The empty lane and its flag are already standing, so the line above
    // them does not move once the week lands.
    expect(find.byKey(const ValueKey('crew-week-finish')), findsOneWidget);
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 1, read: 0),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    expect(tester.getRect(find.byType(HomeCrewPanel)), loading);
    expect(loading.height, HomeCrewPanel.height);
  });

  testWidgets('the block is the card, with no day under it', (tester) async {
    await _pump(
      tester,
      HomeCrewPanel(
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
    expect(find.byType(CrewTodayStrip), findsNothing);
    expect(find.text('in today'), findsNothing);
    // What is left is the card, at the card's own height.
    expect(
      tester.getRect(find.byType(HomeCrewPanel)).height,
      HomeCrewPanel.height,
    );
    expect(HomeCrewPanel.height, HomeCrewPanel.cardHeight);
  });

  testWidgets('the block is one height, whatever the crew', (tester) async {
    for (final size in [1, 2, 9, 20]) {
      await _pump(
        tester,
        HomeCrewPanel(
          userId: 'member0',
          week: _weekWith({
            for (var i = 0; i < size; i++) 'member$i': (move: 1, read: 0),
          }),
        ),
      );
      expect(
        tester.getRect(find.byType(HomeCrewPanel)).height,
        HomeCrewPanel.height,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a crew too big for the track keeps you and the leader', (
    tester,
  ) async {
    // Nine members cannot all stand on one track: a place has a position, so
    // the row cannot end in a "+4" the way a row of faces can.
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'member8',
        week: _weekWith({
          for (var i = 0; i < 9; i++)
            'member$i': (move: i > 5 ? 0 : 3, read: 0),
        }),
      ),
    );
    expect(find.byKey(const ValueKey('crew-race-track')), findsOneWidget);
    // The viewer is trailing and still on the track, and so is the leader.
    expect(find.byKey(const ValueKey('race-face-member8')), findsOneWidget);
    expect(find.byKey(const ValueKey('race-face-member0')), findsOneWidget);
    // But not all nine of them: the track holds six and says so by holding
    // six, rather than by stacking nine faces on one mark.
    expect(tester.widgetList(_raceFaces).length, 6);
  });

  testWidgets('the card goes nowhere, and the track spends the whole width', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 3, read: 2),
          'other': (move: 0, read: 0),
        }),
      ),
    );
    // The card still goes nowhere: the handle it wears opens it where it
    // stands rather than pushing the crew week, which has its own door on the
    // line above.
    expect(find.byKey(const ValueKey('open-crew-week')), findsNothing);
    expect(find.byTooltip('View week'), findsNothing);
    // And the track really does run the card's own width, less its inset.
    final card = tester.getRect(find.byType(HomeCrewPanel));
    final track = tester.getRect(find.byKey(const ValueKey('crew-race-track')));
    expect(track.left - card.left, closeTo(WeekPactMetrics.pageInset, 1));
    expect(card.right - track.right, closeTo(WeekPactMetrics.pageInset, 1));
  });

  testWidgets('the lane is filled to the front runner, and ends at a flag', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 0, read: 0),
          'leader': (move: 3, read: 2),
        }),
      ),
    );
    final flag = find.byKey(const ValueKey('crew-week-finish'));
    expect(flag, findsOneWidget);
    final track = tester.getRect(find.byKey(const ValueKey('crew-race-track')));
    // The flag stands at the end of the lane, past every face.
    expect(tester.getRect(flag).right, closeTo(track.right, 1));
    expect(
      tester.getRect(find.byKey(const ValueKey('race-face-leader'))).right,
      lessThanOrEqualTo(tester.getRect(flag).left + 1),
    );
    // A kept week puts the leader against the flag rather than back with the
    // member who has kept nothing.
    expect(
      _faceX(tester, 'leader'),
      greaterThan(_faceX(tester, 'me') + track.width / 2),
    );
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
                child: HomeCrewPanel(
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
        tester.getRect(find.byType(HomeCrewPanel)).height,
        HomeCrewPanel.height,
      );
    },
  );

  /// Every member lane currently drawn in the open card.
  testWidgets('the card opens into a lane a member, and shuts again', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 3, read: 1),
          'ahead': (move: 3, read: 2),
          'behind': (move: 1, read: 0),
        }),
      ),
    );
    // Shut: one track carrying everybody, and no lanes.
    expect(find.byKey(const ValueKey('crew-race-track')), findsOneWidget);
    expect(_lanes, findsNothing);
    final shut = tester.getRect(find.byType(HomeCrewPanel)).height;
    expect(shut, HomeCrewPanel.height);

    await tester.tap(find.byKey(const ValueKey('crew-panel-toggle')));
    await tester.pumpUi();
    // Open: the track's riders unstacked, one lane each, and the card taller.
    expect(find.byKey(const ValueKey('crew-race-track')), findsNothing);
    expect(_lanes, findsNWidgets(3));
    expect(
      tester.getRect(find.byType(HomeCrewPanel)).height,
      greaterThan(shut),
    );
    // Each lane carries the figure the track had no room for.
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('20%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('crew-panel-toggle')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('crew-race-track')), findsOneWidget);
    expect(_lanes, findsNothing);
    expect(tester.getRect(find.byType(HomeCrewPanel)).height, shut);
  });

  testWidgets('the lanes hold the same crew the track was showing', (
    tester,
  ) async {
    // Eight members is past the track's cap, so it keeps the leader, the
    // viewer and the viewer's neighbours. Opening the card must not introduce
    // anyone the track in front of it never drew.
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          for (var i = 0; i < 7; i++) 'm$i': (move: 3 - (i % 3), read: 0),
          'me': (move: 1, read: 1),
        }),
      ),
    );
    final faces = tester
        .widgetList(_raceFaces)
        .map((w) => (w.key! as ValueKey<String>).value.substring(10))
        .toSet();
    expect(faces.length, _raceFaceCap);
    await tester.tap(find.byKey(const ValueKey('crew-panel-toggle')));
    await tester.pumpUi();
    final laned = tester
        .widgetList(_lanes)
        .map((w) => (w.key! as ValueKey<String>).value.substring(10))
        .toSet();
    expect(laned, faces);
  });

  testWidgets('the lanes run in from the start, and settle where they stand', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 3, read: 1),
          'ahead': (move: 3, read: 2),
          'behind': (move: 1, read: 0),
        }),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('crew-panel-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Part way through, nobody is standing at their answer yet: the leader's
    // face is still on the way and their figure is still counting.
    expect(find.text('100%'), findsNothing);
    final leader = _laneOf(tester, 'ahead');
    expect(leader.run, greaterThan(0));
    expect(leader.run, lessThan(1));
    // The lanes leave together and arrive apart, so a rider further down the
    // order is behind the one above it while the field is running.
    expect(_laneOf(tester, 'behind').run, lessThan(leader.run));

    await tester.pumpUi();
    expect(find.text('100%'), findsOneWidget);
    expect(_laneOf(tester, 'ahead').run, 1);
    expect(_laneOf(tester, 'behind').run, 1);
  });

  testWidgets('less motion gets the field where it finished, not the run', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 366,
                child: HomeCrewPanel(
                  userId: 'me',
                  week: _weekWith({
                    'me': (move: 3, read: 1),
                    'ahead': (move: 3, read: 2),
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('crew-panel-toggle')));
    await tester.pump();
    expect(_laneOf(tester, 'ahead').run, 1);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('a crew of one has no handle and does not open', (tester) async {
    await _pump(
      tester,
      HomeCrewPanel(userId: 'me', week: _weekWith({'me': (move: 3, read: 1)})),
    );
    expect(find.byKey(const ValueKey('crew-solo-track')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-panel-mark')), findsNothing);
    final inkwell = tester.widget<InkWell>(
      find.byKey(const ValueKey('crew-panel-toggle')),
    );
    expect(inkwell.onTap, isNull);
    await tester.tap(
      find.byKey(const ValueKey('crew-panel-toggle')),
      warnIfMissed: false,
    );
    await tester.pumpUi();
    expect(_lanes, findsNothing);
    expect(tester.getRect(find.byType(HomeCrewPanel)).height, HomeCrewPanel.height);
  });

  testWidgets('a crew that shrinks to one shuts the card behind it', (
    tester,
  ) async {
    await _pump(
      tester,
      HomeCrewPanel(
        userId: 'me',
        week: _weekWith({
          'me': (move: 3, read: 1),
          'other': (move: 1, read: 0),
        }),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('crew-panel-toggle')));
    await tester.pumpUi();
    expect(_lanes, findsNWidgets(2));
    await _pump(
      tester,
      HomeCrewPanel(userId: 'me', week: _weekWith({'me': (move: 3, read: 1)})),
    );
    expect(_lanes, findsNothing);
    expect(tester.getRect(find.byType(HomeCrewPanel)).height, HomeCrewPanel.height);
  });
}

/// The most faces the track draws before it starts keeping only the leader
/// and the viewer's neighbourhood.
const _raceFaceCap = 6;

/// One member's drawn lane, by their id.
_MemberLaneProbe _laneOf(WidgetTester tester, String id) =>
    _MemberLaneProbe(tester.widget(find.byKey(ValueKey('crew-lane-$id'))));

/// Reads the private lane widget's run without naming its type.
extension type _MemberLaneProbe(Widget lane) {
  double get run => (lane as dynamic).run as double;
}

/// Every member lane currently drawn.
final _lanes = find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('crew-lane-'),
);
