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

class _CrewBackend extends DashboardBackend {
  int memberCount = 3;
  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
    fetches++;
    return CrewWeek(
      today: '2026-09-17',
      weekStart: '2026-09-14',
      timezone: 'Europe/Sarajevo',
      pacts: pacts.pacts,
      members: [
        for (var i = 0; i < memberCount; i++)
          WeekMember(
            '$i',
            'private$i@example.com',
            displayName: i < 3 ? ['Jasmin', 'Mirnes', 'Amar'][i] : 'Member $i',
          ),
      ],
      checkIns: const [
        PactCheckIn('hang', '0', '2026-09-14'),
        PactCheckIn('hang', '0', '2026-09-15'),
        PactCheckIn('hang', '0', '2026-09-17'),
        PactCheckIn('hang', '1', '2026-09-14'),
        PactCheckIn('hang', '1', '2026-09-16'),
        PactCheckIn('hang', '2', '2026-09-15'),
        PactCheckIn('gym', '0', '2026-09-14'),
        PactCheckIn('gym', '1', '2026-09-15'),
        PactCheckIn('read', '0', '2026-09-14'),
        PactCheckIn('read', '0', '2026-09-15'),
        PactCheckIn('read', '1', '2026-09-15'),
        PactCheckIn('read', '2', '2026-09-14'),
      ],
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
      daysPerWeek: 5,
      iconKey: 'target',
    ),
    CrewPact(
      id: 'gym',
      crewId: 'crew',
      title: 'Gym',
      frequency: PactFrequency.weekly,
      daysPerWeek: 3,
      iconKey: 'gym',
    ),
    CrewPact(
      id: 'read',
      crewId: 'crew',
      title: 'Read',
      frequency: PactFrequency.weekly,
      daysPerWeek: 4,
      iconKey: 'book',
    ),
  ];

Future<void> _pump(
  WidgetTester tester,
  _CrewBackend backend, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? WeekPactTheme.dark : WeekPactTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 24, bottom: 20),
        ),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const ValueKey('crew-preview'),
        child: CrewWeekPage(
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

void main() {
  testWidgets('a pull brings the page down with it, and refreshes the week', (
    tester,
  ) async {
    final backend = _backend();
    await _pump(tester, backend);
    final podium = find.byKey(const ValueKey('crew-week-podium'));
    final rest = tester.getTopLeft(podium).dy;
    final pull = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('crew-week-podium'))),
    );
    await pull.moveBy(const Offset(0, 60));
    await pull.moveBy(const Offset(0, 60));
    await tester.pump();
    // The content follows the finger, rather than only the spinner moving.
    expect(tester.getTopLeft(podium).dy, greaterThan(rest + 20));
    final before = backend.fetches;
    for (var i = 0; i < 6; i++) {
      await pull.moveBy(const Offset(0, 50));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pull.up();
    await tester.pumpUi();
    expect(backend.fetches, before + 1);
    // And it springs back home.
    expect(tester.getTopLeft(podium).dy, moreOrLessEquals(rest, epsilon: 1));
  });

  testWidgets(
    'carousel shows the selected pact’s totals and days, stops at both ends, and refreshes selection',
    (tester) async {
      final backend = _backend();
      await _pump(tester, backend);
      expect(find.byKey(const ValueKey('crew-week-podium')), findsOneWidget);
      expect(find.byTooltip('Refresh crew activity'), findsNothing);
      expect(find.text('12 / 36'), findsWidgets);
      expect(backend.fetches, 1);
      // The card leads with the calendar: no per-pact check-in count.
      expect(find.text('6 / 15', findRichText: true), findsNothing);
      expect(find.byTooltip('Sep 17 · Completed'), findsWidgets);
      expect(find.textContaining('@'), findsNothing);
      // Swiping is the only control, advertised by the next card peeking in
      // rather than by arrows or dots.
      expect(find.byTooltip('Previous pact'), findsNothing);
      expect(find.byTooltip('Next pact'), findsNothing);
      final carousel = find.byKey(const ValueKey('crew-pact-carousel'));
      // The pact either side of the selected one is on screen, just clipped.
      expect(find.text('Gym'), findsOneWidget);
      await tester.drag(carousel, const Offset(-330, 0));
      await tester.pumpUi();
      expect(find.text('Gym').hitTestable(), findsOneWidget);
      await tester.drag(carousel, const Offset(0, 400));
      await tester.pumpUi();
      expect(backend.fetches, 2);
      expect(find.text('Gym').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Show Read'), findsNothing);
      await tester.drag(carousel, const Offset(-330, 0));
      await tester.pumpUi();
      expect(find.text('Read').hitTestable(), findsOneWidget);
      await tester.drag(carousel, const Offset(-330, 0));
      await tester.pumpUi();
      expect(find.text('Read').hitTestable(), findsOneWidget);
      await tester.drag(carousel, const Offset(330, 0));
      await tester.pumpUi();
      await tester.drag(carousel, const Offset(330, 0));
      await tester.pumpUi();
      expect(find.text('Hangboard').hitTestable(), findsOneWidget);
      backend.pacts.pacts = [];
      await tester.drag(carousel, const Offset(0, 400));
      await tester.pumpUi();
      expect(
        find.text(
          'No pacts yet. Your crew’s weekly activity will appear here.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'crew carousel fits $size at text scale $scale with 20 members',
        (tester) async {
          await loadAppFont();
          await _pump(
            tester,
            _backend()..memberCount = 20,
            size: size,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          // Four and a half people are on the card at once, at their full
          // height; the rest scroll inside it.
          expect(find.byTooltip('Next members'), findsNothing);
          final card = find.byType(CrewPactWeekCard).first;
          final mondays = find.descendant(
            of: card,
            matching: find.byWidgetPredicate(
              (w) => w is Tooltip && w.message!.startsWith('Sep 14 ·'),
            ),
          );
          final list = tester
              .stateList<ScrollableState>(
                find.descendant(of: card, matching: find.byType(Scrollable)),
              )
              .single
              .position;
          if (scale == 1) expect(list.viewportDimension, 4.5 * 54);
          expect(list.maxScrollExtent, 15.5 * 54);
          if (scale == 1) {
            expect(tester.getSize(mondays.first).height, 54);
          }
          double arrow(String label) => tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.descendant(
                        of: card,
                        matching: find.byWidgetPredicate(
                          (w) => w is Semantics && w.properties.label == label,
                        ),
                      ),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity;
          expect(arrow('Show earlier members'), 0);
          expect(arrow('Show more members'), 1);
          expect(find.byTooltip('Back to home').hitTestable(), findsOneWidget);
          await tester.ensureVisible(mondays.first);
          await tester.pumpUi();
          await tester.drag(mondays.first, const Offset(0, -6000));
          await tester.pumpUi();
          // Scrolled to the end, the last member is in the card, and only
          // the arrow back up shows.
          expect(list.pixels, list.maxScrollExtent);
          expect(arrow('Show earlier members'), 1);
          expect(arrow('Show more members'), 0);
          expect(
            tester.getRect(mondays.last).bottom,
            lessThanOrEqualTo(tester.getRect(card).bottom),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final members in [3, 6]) {
    testWidgets('the card has no empty room under $members members', (
      tester,
    ) async {
      await loadAppFont();
      await _pump(
        tester,
        _backend()..memberCount = members,
        size: const Size(430, 932),
      );
      final card = find.byType(CrewPactWeekCard).first;
      Rect rect(Finder finder) =>
          tester.getRect(find.descendant(of: card, matching: finder).first);
      expect(tester.getSize(card).height, CrewPactWeekCard.heightFor(members));
      // Under the rows: the down arrow's room when the list scrolls, then
      // the gap over the divider, and nothing more.
      expect(
        rect(find.byType(Divider)).top - rect(find.byType(ListView)).bottom,
        closeTo(members > 4 ? 28 : 8, 1),
      );
    });
  }

  for (final dark in [true, false]) {
    testWidgets('crew overview preview ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(() async {
          await loadAppFont();
          await icons.load();
        });
      }
      await _pump(tester, _backend(), dark: dark);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('crew-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/weekpact-crew-carousel-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
