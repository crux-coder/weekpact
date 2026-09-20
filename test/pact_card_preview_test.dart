@Tags(['preview'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/crew/crew_switcher.dart';
import 'package:weekpact/src/home/crew_member_list.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// Writes the pact stack to a PNG so the card can be looked at rather than
/// only asserted on. Not part of the default run — it is tagged `preview` and
/// excluded in `dart_test.yaml`, so it only renders when asked for by name.
///
///     flutter test test/pact_card_preview_test.dart --tags preview --run-skipped
///
/// The file lands next to the other design captures in `design/homepage/`.
void main() {
  setUpAll(loadAppFont);

  testWidgets('render the pact stack', (tester) async {
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = DashboardBackend();
    backend.pacts.pacts = [
      backend.pacts.pacts.first,
      const CrewPact(
        id: 'long',
        crewId: 'crew',
        title: 'Walk the dog around the park before work and again after dinner',
        frequency: PactFrequency.daily,
        daysPerWeek: 5,
        iconKey: 'yoga',
      ),
    ];
    final base = await backend.fetchWeek('crew');
    // A crew with names, and two of the four already in on the first pact.
    final week = CrewWeek(
      today: base.today,
      weekStart: base.weekStart,
      timezone: base.timezone,
      pacts: base.pacts,
      members: const [
        WeekMember('', 'me@example.com', displayName: 'Jasmin Mustafic'),
        WeekMember('ak', 'ak@example.com', displayName: 'Amra Kovac'),
        WeekMember('ts', 'ts@example.com', displayName: 'Tarik Selimovic'),
      ],
      checkIns: [
        PactCheckIn(base.pacts.first.id, 'ak', base.today),
        PactCheckIn(base.pacts.last.id, 'ts', base.today),
      ],
    );

    const capture = ValueKey('capture');
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  HomeCrewPanel(week: week, userId: '', onOpenWeek: () {}),
                  const SizedBox(height: 16),
                  // Home hands the stack whatever the page has left, so the
                  // card is usually taller than its own 248 floor. Render the
                  // roomy case: that is where air collects.
                  TodayPactsCard(
                    height: 360,
                    week: week,
                    userId: '',
                    savingPact: null,
                    onToggle: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();

    Future<void> shoot(String name) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('design/homepage/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(File('design/homepage/$name.png').existsSync(), isTrue);
    }

    await shoot('pact-card-short-title');
    await tester.drag(
      find.byKey(const ValueKey('pact-stack')),
      const Offset(-320, 0),
    );
    await tester.pumpUi();
    await shoot('pact-card-long-title');

    // A crew of one: the faces give way to what the week still wants.
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TodayPactsCard(
                    height: 360,
                    week: CrewWeek(
                      today: week.today,
                      weekStart: week.weekStart,
                      timezone: week.timezone,
                      pacts: [week.pacts.first],
                      members: const [
                        WeekMember('', 'me@example.com', displayName: 'Me'),
                      ],
                      checkIns: [
                        PactCheckIn(week.pacts.first.id, '', week.weekStart),
                      ],
                    ),
                    userId: '',
                    savingPact: null,
                    onToggle: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await shoot('pact-card-solo-crew');

    // The day's row on its own, with a clock: the score at the head, the time
    // left flush with the block's right inset, and the grip still under both.
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  HomeCrewPanel(
                    week: CrewWeek(
                      today: today,
                      weekStart: week.weekStart,
                      timezone: week.timezone,
                      pacts: week.pacts,
                      members: week.members,
                      checkIns: [
                        PactCheckIn(week.pacts.first.id, 'ak', today),
                      ],
                    ),
                    userId: '',
                    onOpenWeek: () {},
                    backend: backend,
                    crewId: 'crew',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await shoot('today-strip');

    // The switcher stacked on the crew panel: the two corners side by side.
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  CrewSwitcher(
                    compact: true,
                    curve: CrewWeekButton.frameCurve,
                    crews: const [
                      PactCrew(
                        id: 'crew',
                        name: 'Early Birds',
                        timezone: 'UTC',
                        isOwner: true,
                      ),
                      PactCrew(
                        id: 'b',
                        name: 'Night Owls',
                        timezone: 'UTC',
                        isOwner: false,
                      ),
                    ],
                    selectedId: 'crew',
                    loadWeek: (_) async => week,
                    onSelected: (_) {},
                  ),
                  const SizedBox(height: 10),
                  HomeCrewPanel(week: week, userId: '', onOpenWeek: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await shoot('crew-switcher-corner');

    // The roster pulled open. The drawer lives in an OverlayPortal, so the
    // capture has to sit above the app rather than inside its body.
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: WeekPactTheme.dark,
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  HomeCrewPanel(
                    week: CrewWeek(
                      today: today,
                      weekStart: week.weekStart,
                      timezone: week.timezone,
                      pacts: week.pacts,
                      members: const [
                        WeekMember(
                          '',
                          'me@example.com',
                          displayName: 'Jasmin Mustafic',
                        ),
                        WeekMember(
                          'mr',
                          'mr@example.com',
                          displayName: 'Mirnes Ramic',
                        ),
                        WeekMember(
                          'ak',
                          'ak@example.com',
                          displayName: 'Amra Kovac',
                        ),
                      ],
                      checkIns: [PactCheckIn(week.pacts.first.id, '', today)],
                    ),
                    userId: '',
                    onOpenWeek: () {},
                    backend: backend,
                    crewId: 'crew',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(find.byType(CrewMemberList), findsOneWidget);
    await shoot('crew-drawer-open');
    expect(tester.takeException(), isNull);
  });
}
