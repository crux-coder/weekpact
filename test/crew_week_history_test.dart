import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_pact_week_card.dart';
import 'package:weekpact/src/crew/crew_week_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// A crew three weeks in: this week half kept, and two finished weeks behind
/// it that come back with their own check-ins when asked for by their Monday.
class _CrewBackend extends DashboardBackend {
  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
    fetches++;
    requestedWeeks.add(weekStart);
    if (failLoad) throw StateError('offline');
    final start = weekStart ?? '2026-09-14';
    return CrewWeek(
      today: '2026-09-17',
      weekStart: start,
      timezone: 'Europe/Sarajevo',
      pacts: pacts.pacts,
      members: const [
        WeekMember('0', 'me@example.com', displayName: 'Jasmin'),
        WeekMember('1', 'friend@example.com', displayName: 'Mirnes'),
      ],
      checkIns: switch (start) {
        '2026-09-07' => const [
          PactCheckIn('hang', '0', '2026-09-07'),
          PactCheckIn('hang', '0', '2026-09-09'),
          PactCheckIn('hang', '1', '2026-09-08'),
          PactCheckIn('hang', '1', '2026-09-13'),
        ],
        '2026-08-31' => const [PactCheckIn('hang', '0', '2026-09-01')],
        _ => const [
          PactCheckIn('hang', '0', '2026-09-15'),
          PactCheckIn('hang', '1', '2026-09-16'),
        ],
      },
    );
  }
}

_CrewBackend _backend() => _CrewBackend()
  ..pacts.pacts = const [
    CrewPact(
      id: 'hang',
      crewId: 'crew',
      title: 'Hangboard',
      frequency: PactFrequency.weekly,
      daysPerWeek: 2,
      iconKey: 'target',
    ),
  ]
  ..history = const [
    CrewWeekSummary(
      weekStart: '2026-09-07',
      percent: 100,
      shareOut: [.5, .5, .5, 0, 0, 0, .5],
    ),
    CrewWeekSummary(
      weekStart: '2026-08-31',
      percent: 25,
      shareOut: [0, .5, 0, 0, 0, 0, 0],
    ),
  ];

Future<void> _pump(
  WidgetTester tester,
  DashboardBackend backend, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    // The boundary wraps the app, not the route, so a sheet over the page is
    // in the capture too.
    RepaintBoundary(
      key: const ValueKey('crew-preview'),
      child: MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(top: 24, bottom: 20)),
          child: child!,
        ),
        home: CrewWeekPage(
          crew: const PactCrew(
            id: 'crew',
            name: 'Hangboardasi',
            timezone: 'Europe/Sarajevo',
            isOwner: true,
          ),
          backend: backend,
          userId: '0',
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

/// Writes the page to `/tmp` when the suite runs with `CAPTURE_DESIGN`, the
/// way the carousel preview does, so the design can be looked at rather than
/// only asserted about.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('crew-preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/weekpact-crew-history-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await loadAppFont();
    if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  const sep7 = 'Week of Sep 7 to Sep 13: 100% crew progress';
  const aug31 = 'Week of Aug 31 to Sep 6: 25% crew progress';

  Future<void> scrollDown(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey('crew-refresh-viewport')),
      const Offset(0, -600),
    );
    await tester.pumpUi();
  }

  testWidgets('finished weeks sit in a month calendar under the week', (
    tester,
  ) async {
    await _pump(tester, _backend());
    expect(tester.takeException(), isNull);
    await _capture(tester, 'this-week');
    // The page no longer counts who checked in today.
    expect(find.textContaining('checked in today'), findsNothing);
    // This week is still one viewport, with only the month's header showing
    // under it to say the page goes on.
    final size = tester.view.physicalSize;
    final heading = find.text('September');
    expect(heading, findsOneWidget);
    expect(tester.getRect(heading).bottom, lessThanOrEqualTo(size.height));
    expect(find.bySemanticsLabel(sep7).hitTestable(), findsNothing);

    await scrollDown(tester);
    await _capture(tester, 'scrolled');
    expect(find.byKey(const ValueKey('crew-month-calendar')), findsOneWidget);
    final first = tester.getTopLeft(find.bySemanticsLabel(aug31));
    final second = tester.getTopLeft(find.bySemanticsLabel(sep7));
    expect(first.dy, lessThan(second.dy));
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    // The live week has its own row, but it is the page above, not a button.
    expect(find.bySemanticsLabel(RegExp('^Week of Sep 14')), findsNothing);
    // September is this month, and Aug 31 starts before it: back, not on.
    expect(find.byTooltip('Previous month'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Next month'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('tapping a finished week opens it as a sheet over this week', (
    tester,
  ) async {
    final backend = _backend();
    await _pump(tester, backend);
    await scrollDown(tester);
    await tester.tap(find.bySemanticsLabel(sep7));
    await tester.pumpUi();

    // The week was asked for by its Monday.
    expect(backend.requestedWeeks.last, '2026-09-07');
    await _capture(tester, 'past-week');
    final sheet = find.byKey(const ValueKey('past-week-sheet'));
    expect(sheet, findsOneWidget);
    // The sheet leads with when, not with the crew's name: that is still on
    // the page behind it.
    expect(find.text('LAST WEEK'), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Sep 7 – 13')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Hangboardasi')),
      findsNothing,
    );
    // No dial and no streak: one closed line, and the card as it ended.
    expect(find.text('Week closed'), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('100%')),
      findsOneWidget,
    );
    expect(find.text('All 2 hit their target'), findsOneWidget);
    expect(find.text('Crew progress').hitTestable(), findsNothing);
    expect(
      find.descendant(of: sheet, matching: find.byType(CrewPactWeekCard)),
      findsOneWidget,
    );
    expect(find.textContaining('per person'), findsNothing);
    // Every day has gone, so none is marked as today or still to come.
    expect(find.byTooltip('Sep 13 · Completed'), findsWidgets);
    expect(find.byTooltip('Sep 13 · Upcoming'), findsNothing);
    expect(find.byTooltip('Sep 7 · Not checked in yet'), findsNothing);

    await tester.tap(find.byTooltip('Back to this week'));
    await tester.pumpUi();
    expect(sheet, findsNothing);
    expect(find.byKey(const ValueKey('crew-week-podium')), findsOneWidget);
  });

  testWidgets('a week further back is a past week, not last week', (
    tester,
  ) async {
    await _pump(tester, _backend());
    await scrollDown(tester);
    await tester.tap(find.bySemanticsLabel(aug31));
    await tester.pumpUi();
    expect(find.text('PAST WEEK'), findsOneWidget);
    expect(find.text('Aug 31 – Sep 6'), findsOneWidget);
    expect(find.text('No one hit their target'), findsOneWidget);
  });

  testWidgets('a week that cannot load says so inside the sheet', (
    tester,
  ) async {
    final backend = _backend();
    await _pump(tester, backend);
    await scrollDown(tester);
    backend.failLoad = true;
    await tester.tap(find.bySemanticsLabel(sep7));
    await tester.pumpUi();
    expect(find.text('Could not load that week. Try again.'), findsOneWidget);

    backend.failLoad = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    expect(find.text('Week closed'), findsOneWidget);
  });

  testWidgets(
    'a crew in its first week has no calendar and stays one viewport',
    (tester) async {
      await _pump(tester, _backend()..history = const []);
      expect(find.byKey(const ValueKey('crew-month-calendar')), findsNothing);
      // The page's own scroll, not the member list inside each pact card.
      final cards = find.byType(CrewPactWeekCard);
      final inCards = tester
          .stateList<ScrollableState>(
            find.descendant(of: cards, matching: find.byType(Scrollable)),
          )
          .toSet();
      final vertical = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .where(
            (state) =>
                axisDirectionToAxis(state.widget.axisDirection) ==
                    Axis.vertical &&
                !inCards.contains(state),
          );
      expect(vertical.single.position.maxScrollExtent, 0);
    },
  );

  testWidgets('a history that cannot load says so without taking the week', (
    tester,
  ) async {
    final backend = _backend()..failHistory = true;
    await _pump(tester, backend);
    expect(find.byKey(const ValueKey('crew-week-podium')), findsOneWidget);
    await scrollDown(tester);
    expect(find.text('Could not load past weeks.'), findsOneWidget);

    backend.failHistory = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    await scrollDown(tester);
    expect(find.text('Could not load past weeks.'), findsNothing);
    expect(find.bySemanticsLabel(sep7), findsOneWidget);
  });

  testWidgets('stepping back a month fetches the weeks it needs', (
    tester,
  ) async {
    final backend = _backend()
      ..history = [
        for (var i = 1; i <= 15; i++)
          CrewWeekSummary(
            weekStart: DateTime.utc(2026, 9, 14)
                .subtract(Duration(days: 7 * i))
                .toIso8601String()
                .substring(0, 10),
            percent: 50,
            shareOut: const [.5, 0, 0, 0, 0, 0, 0],
          ),
      ];
    await _pump(tester, backend, size: const Size(390, 2400));
    await scrollDown(tester);
    // Twelve weeks reach back to Jun 22; June starts in the week of Jun 1.
    for (final month in ['August', 'July', 'June']) {
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpUi();
      expect(find.text(month), findsOneWidget);
    }
    expect(
      find.bySemanticsLabel('Week of Jun 1 to Jun 7: 50% crew progress'),
      findsOneWidget,
    );
    // The fifteenth week is the crew's first, so there is no month before.
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Previous month'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpUi();
    expect(find.text('July'), findsOneWidget);
  });

  testWidgets(
    'the sheet springs back from a short drag and closes past the line',
    (tester) async {
      await _pump(tester, _backend());
      await scrollDown(tester);
      await tester.tap(find.bySemanticsLabel(sep7));
      await tester.pumpUi();
      final sheet = find.byKey(const ValueKey('past-week-sheet'));
      final handle = find.text('Sep 7 – 13').last;
      final top = tester.getTopLeft(sheet).dy;

      // A short, slow pull is not a close: the sheet comes back to where it was.
      await tester.timedDrag(
        handle,
        const Offset(0, 80),
        const Duration(seconds: 1),
      );
      await tester.pumpUi();
      expect(sheet, findsOneWidget);
      expect(tester.getTopLeft(sheet).dy, moreOrLessEquals(top, epsilon: .5));

      // Past a quarter of its height, letting go closes it.
      await tester.timedDrag(
        handle,
        const Offset(0, 320),
        const Duration(seconds: 1),
      );
      await tester.pumpUi();
      expect(sheet, findsNothing);
    },
  );

  testWidgets('a swipe across the calendar steps the month', (tester) async {
    await _pump(tester, _backend());
    await scrollDown(tester);
    await tester.fling(
      find.byKey(const ValueKey('crew-month-calendar')),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpUi();
    expect(find.text('August'), findsOneWidget);
    expect(find.text('September'), findsNothing);
    await tester.fling(
      find.byKey(const ValueKey('crew-month-calendar')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpUi();
    expect(find.text('September'), findsOneWidget);
  });

  testWidgets('the title is the crew switcher, and switching loads that crew', (
    tester,
  ) async {
    const home = PactCrew(
      id: 'crew',
      name: 'Hangboardasi',
      timezone: 'Europe/Sarajevo',
      isOwner: true,
    );
    const other = PactCrew(
      id: 'other',
      name: 'Runners',
      timezone: 'Europe/Sarajevo',
      isOwner: false,
    );
    final backend = _backend();
    final picked = <String>[];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: CrewWeekPage(
          crew: home,
          backend: backend,
          userId: '0',
          crews: const [home, other],
          onCrewSelected: picked.add,
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('crew-week-switcher')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-week-podium')), findsOneWidget);
    final before = backend.fetches;

    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    await tester.tap(find.text('Runners').last);
    await tester.pumpUi();
    expect(picked, ['other']);
    expect(backend.fetches, greaterThan(before));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('crew-week-switcher')),
        matching: find.text('Runners'),
      ),
      findsOneWidget,
    );
  });
}
