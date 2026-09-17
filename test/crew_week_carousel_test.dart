import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_week_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

class _CrewBackend extends DashboardBackend {
  int memberCount = 3;
  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
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
  testWidgets(
    'carousel shows the selected pact’s totals and days, stops at both ends, and refreshes selection',
    (tester) async {
      final backend = _backend();
      await _pump(tester, backend);
      expect(find.text('33%'), findsOneWidget);
      expect(find.byTooltip('Refresh crew activity'), findsNothing);
      expect(find.text('12 / 36'), findsWidgets);
      expect(backend.fetches, 1);
      expect(find.text('6 / 15', findRichText: true), findsOneWidget);
      expect(find.byTooltip('Sep 17 · Completed'), findsWidgets);
      expect(find.textContaining('@'), findsNothing);
      // The dots are the only control; swiping is advertised by the next
      // card peeking in rather than by arrows.
      expect(find.byTooltip('Previous pact'), findsNothing);
      expect(find.byTooltip('Next pact'), findsNothing);
      final carousel = find.byKey(const ValueKey('crew-pact-carousel'));
      // The pact either side of the selected one is on screen, just clipped.
      expect(find.text('Gym'), findsOneWidget);
      await tester.drag(carousel, const Offset(-330, 0));
      await tester.pumpUi();
      expect(find.text('Gym').hitTestable(), findsOneWidget);
      expect(
        find.text('2 / 9', findRichText: true).hitTestable(),
        findsOneWidget,
      );
      await tester.drag(carousel, const Offset(0, 400));
      await tester.pumpUi();
      expect(backend.fetches, 2);
      expect(find.text('Gym').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Show Read'));
      await tester.pumpUi();
      expect(find.text('Read').hitTestable(), findsOneWidget);
      await tester.drag(carousel, const Offset(-330, 0));
      await tester.pumpUi();
      expect(find.text('Read').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Show Hangboard'));
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
          await _pump(
            tester,
            _backend()..memberCount = 20,
            size: size,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          final vertical = tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .where(
                (state) =>
                    axisDirectionToAxis(state.widget.axisDirection) ==
                    Axis.vertical,
              );
          expect(vertical, hasLength(1));
          expect(vertical.single.position.maxScrollExtent, 0);
          expect(vertical.single.position.minScrollExtent, 0);
          expect(find.byTooltip('Back to home').hitTestable(), findsOneWidget);
          final banner = tester.getRect(find.text('1 of 20 checked in today'));
          expect(banner.bottom, lessThanOrEqualTo(size.height - 20));
          for (var page = 1; page < 5; page++) {
            await tester.tap(find.byTooltip('Next members').hitTestable());
            await tester.pumpUi();
          }
          expect(
            find.text('17–20 of 20 members').hitTestable(),
            findsOneWidget,
          );
          expect(
            tester
                .widget<IconButton>(
                  find
                      .byWidgetPredicate(
                        (w) => w is IconButton && w.tooltip == 'Next members',
                      )
                      .hitTestable(),
                )
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final dark in [true, false]) {
    testWidgets('crew overview preview ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
        final fonts = FontLoader('RobotoCondensed')
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/RobotoCondensed-Bold.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await tester.runAsync(() async {
          await fonts.load();
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
