import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_page.dart';
import 'package:weekpact/src/crew/crews_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/invites/invite_links.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'multiple_crews_test.dart' show MultipleCrews;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// Weeks for the list: a streak on every crew, and the crews named in
/// [failing] refused.
class ListWeeks extends DashboardBackend {
  ListWeeks() : super(viewerId: 'me');
  final failing = <String>{};
  final asked = <String>[];

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
    asked.add(crewId);
    if (failing.contains(crewId)) throw StateError('offline');
    final week = await super.fetchWeek(crewId);
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      members: week.members,
      checkIns: week.checkIns,
      streakWeeks: 6,
    );
  }
}

Future<void> showList(
  WidgetTester tester,
  MultipleCrews crews, {
  HomeBackend? weeks,
  ValueChanged<String>? onSelected,
  ValueChanged<InviteRef>? onInviteCode,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: CrewsPage(
          backend: crews,
          weekBackend: weeks,
          userId: 'me',
          currentUserEmail: 'owner@example.com',
          onCrewSelected: onSelected,
          onInviteCode: onInviteCode,
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  testWidgets('every crew gets a card with its week at a glance', (
    tester,
  ) async {
    final weeks = ListWeeks();
    await showList(tester, MultipleCrews(), weeks: weeks);

    expect(find.byType(CrewListCard), findsNWidgets(2));
    expect(find.text('Early Birds'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    // Read 20 pages kept once, of a week of 7 + 3.
    expect(find.text('You: 1 of 10 this week'), findsNWidgets(2));
    expect(find.text('2 pacts'), findsNWidgets(2));
    expect(find.text('Crew 5%'), findsNWidgets(2));
    expect(find.text('6 wk'), findsNWidgets(2));
    expect(weeks.asked, unorderedEquals(['crew', 'second']));
  });

  testWidgets('one week failing leaves the rest of the list alone', (
    tester,
  ) async {
    final weeks = ListWeeks()..failing.add('second');
    await showList(tester, MultipleCrews(), weeks: weeks);

    expect(
      find.byKey(const ValueKey('crew-card-progress-crew')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('crew-card-progress-second')),
      findsNothing,
    );
    expect(find.text('This week could not load.'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no crews yet offers the form and the code', (tester) async {
    final crews = MultipleCrews()..entries.clear();
    await showList(tester, crews, onInviteCode: (_) {});

    expect(find.byType(CrewListCard), findsNothing);
    expect(find.text('Start your crew'), findsOneWidget);
    expect(find.text('CREATE CREW'), findsOneWidget);
    // Nothing to make another of yet, so no "another crew" control.
    expect(find.byTooltip('Create another crew'), findsNothing);
    expect(find.byTooltip('Join with a code'), findsOneWidget);
  });

  testWidgets('a card opens its crew, and coming back reloads the list', (
    tester,
  ) async {
    final crews = MultipleCrews();
    final weeks = ListWeeks();
    final selected = <String>[];
    await showList(tester, crews, weeks: weeks, onSelected: selected.add);

    await tester.tap(find.text('Night Owls'));
    await tester.pumpUi();
    expect(find.byType(CrewPage), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-page-title')), findsOneWidget);
    expect(crews.fetched.last, 'second');
    expect(selected, ['second']);

    crews.entries.removeLast();
    await tester.tap(find.byTooltip('Back to crews'));
    await tester.pumpUi();
    expect(find.byType(CrewPage), findsNothing);
    expect(find.text('Night Owls'), findsNothing);
    expect(find.byType(CrewListCard), findsOneWidget);
  });
}
