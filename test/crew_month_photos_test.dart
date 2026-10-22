import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_month_photos_sheet.dart';
import 'package:weekpact/src/crew/crew_streak_card.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/story_viewer.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// A crew of two in mid-September, with photos on three days this month and
/// one in August.
class _CrewBackend extends DashboardBackend {
  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async =>
      CrewWeek(
        today: '2026-09-17',
        weekStart: '2026-09-14',
        timezone: 'Europe/Sarajevo',
        pacts: pacts.pacts,
        members: const [
          WeekMember('0', 'me@example.com', displayName: 'Jasmin'),
          WeekMember('1', 'friend@example.com', displayName: 'Mirnes'),
        ],
        checkIns: const [PactCheckIn('hang', '0', '2026-09-15')],
      );
}

PactCheckIn _photo(String user, String day, {int claps = 0, int hour = 9}) =>
    PactCheckIn(
      'hang',
      user,
      day,
      photoPath: '$user/$day.jpg',
      photoUrl: 'https://example.test/$user/$day.jpg',
      keptAt: DateTime.parse('${day}T${'$hour'.padLeft(2, '0')}:00:00Z'),
      clapCount: claps,
    );

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
  ..monthPhotos = [
    _photo('0', '2026-08-30'),
    _photo('0', '2026-09-03', claps: 1),
    _photo('1', '2026-09-03', hour: 10),
    _photo('1', '2026-09-10', claps: 4),
    _photo('0', '2026-09-15'),
  ];

Future<void> _pump(WidgetTester tester, DashboardBackend backend) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      // The streak card as Home carries it: its View month opens the drawer.
      home: Scaffold(
        body: FutureBuilder(
          future: backend.fetchWeek('crew'),
          builder: (context, week) => week.data == null
              ? const SizedBox.shrink()
              : CrewStreakCard(
                  week: week.data!,
                  history: const [],
                  onViewMonth: () => showCrewMonthPhotosSheet(
                    context: context,
                    crewId: 'crew',
                    backend: backend,
                    userId: '0',
                    week: week.data!,
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpUi();
}

Future<void> _openMonth(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('streak-view-month')));
  await tester.pumpUi();
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('View month opens the month in photos', (tester) async {
    final backend = _backend();
    await _pump(tester, backend);
    expect(find.text('View month'), findsOneWidget);

    await _openMonth(tester);
    expect(
      find.byKey(const ValueKey('crew-month-photos-sheet')),
      findsOneWidget,
    );
    expect(backend.requestedMonths, ['2026-09-01']);
    expect(find.text('4 photos · 3 days'), findsOneWidget);
    // Days with photos are buttons that say how many; the rest are not.
    expect(find.bySemanticsLabel('September 3: 2 photos'), findsOneWidget);
    expect(find.bySemanticsLabel('September 4: no photos'), findsOneWidget);
    // The month's most-clapped check-in sits under the calendar.
    expect(find.text('Mirnes · Hangboard'), findsOneWidget);
    expect(find.text('Sep 10 · 4 claps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day opens its photos in the story viewer', (tester) async {
    await _pump(tester, _backend());
    await _openMonth(tester);

    await tester.tap(find.byKey(const ValueKey('month-photo-2026-09-03')));
    await tester.pumpUi();
    final viewer = tester.widget<StoryViewer>(find.byType(StoryViewer));
    // The viewer first, then the rest of the crew, each with their own photos.
    expect(viewer.days.map((d) => d.member.id), ['0', '1']);
    expect(viewer.days.every((d) => d.stories.length == 1), isTrue);
    expect(viewer.initial, 0);
  });

  testWidgets('the chevrons step months and stop at this one', (tester) async {
    final backend = _backend();
    await _pump(tester, backend);
    await _openMonth(tester);

    final next = find.ancestor(
      of: find.byTooltip('Next month').last,
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(next).onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month').last);
    await tester.pumpUi();
    expect(backend.requestedMonths, ['2026-09-01', '2026-08-01']);
    expect(find.text('1 photo · 1 day'), findsOneWidget);
    // No claps in August, so nothing is called most clapped.
    expect(find.byKey(const ValueKey('month-most-clapped')), findsNothing);

    // Back to September comes from what was already loaded.
    await tester.tap(find.byTooltip('Next month').last);
    await tester.pumpUi();
    expect(backend.requestedMonths, hasLength(2));
    expect(find.text('4 photos · 3 days'), findsOneWidget);
  });

  testWidgets('a month that fails to load can be tried again', (tester) async {
    final backend = _backend()..failMonthPhotos = true;
    await _pump(tester, backend);
    await _openMonth(tester);
    expect(find.text('Could not load photos'), findsOneWidget);

    backend.failMonthPhotos = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();
    expect(find.text('4 photos · 3 days'), findsOneWidget);
  });
}
