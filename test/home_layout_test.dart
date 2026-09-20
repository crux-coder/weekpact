import 'package:weekpact/src/home/today_widgets.dart';

import 'support/pump_ui.dart';

import 'package:card_swiper/card_swiper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/crew/crew_switcher.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

class LargeCrewBackend extends DashboardBackend {
  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final week = await super.fetchWeek(crewId);
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      members: [
        for (var i = 0; i < 20; i++) WeekMember('$i', 'member$i@example.com'),
      ],
      checkIns: week.checkIns,
    );
  }
}

void main() {
  testWidgets('the switcher is cut to the same corner as the blocks under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = LargeCrewBackend();
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: HomePage(
          user: const AuthUser(email: 'person@example.com'),
          authBackend: const MissingConfigurationAuthBackend(),
          crewBackend: const MissingCrewBackend(),
          pactsBackend: backend.pacts,
          homeBackend: backend,
        ),
      ),
    );
    await tester.pumpUi();

    /// The corner a block actually paints, not the one it was handed.
    double cornerOf(Key key) {
      final surface = tester.widget<CrewHeaderSurface>(
        find
            .descendant(
              of: find.byKey(key),
              matching: find.byType(CrewHeaderSurface),
            )
            .first,
      );
      return surface.curve;
    }

    final switcher = cornerOf(const ValueKey('home-crew-switcher'));
    final panel = cornerOf(const ValueKey('home-crew-panel'));
    // Two blocks of one width, stacked, sharing an edge: they share a corner
    // or the pair reads as a mistake. The switcher used to keep the
    // standalone control's `panelCurve` while the panel took the column's,
    // which is half the radius at the same width.
    expect(switcher, panel);
    expect(switcher, CrewWeekButton.frameCurve);
    expect(CrewWeekButton.frameCurve, greaterThan(WeekPactMetrics.panelCurve));
    // And they really are the same width, which is what makes it show.
    expect(
      tester.getSize(find.byKey(const ValueKey('home-crew-switcher'))).width,
      closeTo(
        tester.getSize(find.byKey(const ValueKey('home-crew-panel'))).width,
        1,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(320, 568),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'home stays fixed at $size with text scale $scale and a large crew',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final backend = LargeCrewBackend();
          await tester.pumpWidget(
            MaterialApp(
              theme: WeekPactTheme.dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  padding: const EdgeInsets.only(top: 24, bottom: 20),
                ),
                child: child!,
              ),
              home: HomePage(
                user: const AuthUser(email: 'person@example.com'),
                authBackend: const MissingConfigurationAuthBackend(),
                crewBackend: const MissingCrewBackend(),
                pactsBackend: backend.pacts,
                homeBackend: backend,
              ),
            ),
          );
          await tester.pumpUi();
          expect(tester.takeException(), isNull);
          expect(find.text('WeekPact'), findsNothing);
          expect(find.byType(Swiper), findsOneWidget);
          final verticalScrolls = tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .where(
                (s) =>
                    s.widget.axisDirection == AxisDirection.down ||
                    s.widget.axisDirection == AxisDirection.up,
              );
          expect(verticalScrolls, hasLength(1));
          expect(verticalScrolls.single.position.maxScrollExtent, 0);
          expect(verticalScrolls.single.position.minScrollExtent, 0);
          final board = find.byKey(const ValueKey('home-crew-panel'));
          final position = tester.getTopLeft(board);
          final activePact = tester.getRect(
            find.byKey(const ValueKey('move')).hitTestable(),
          );
          final crewBounds = tester.getRect(board);
          expect(activePact.center.dx, closeTo(crewBounds.center.dx, 1));
          expect(activePact.left, greaterThan(crewBounds.left));
          expect(activePact.right, lessThan(crewBounds.right));
          final titleBottom = tester.getBottomRight(find.byType(HomeHeader)).dy;
          final crewTop = crewBounds.top;
          // Home leads with its own name and dot and the crew streak beside
          // it, and carries the crew switcher under them as Pacts and Crews
          // do — no activity strip.
          expect(find.text('Home'), findsWidgets);
          expect(find.byKey(const ValueKey('latest-check-in')), findsNothing);
          expect(find.byType(CrewSwitcher), findsOneWidget);
          final streak = tester.getRect(
            find.byKey(const ValueKey('crew-header-streak')),
          );
          final heading = tester.getRect(find.text('Home').first);
          expect(streak.left, greaterThan(heading.right));
          final todayTop = tester.getTopLeft(find.byType(TodayPactsCard)).dy;
          expect(crewTop, greaterThanOrEqualTo(titleBottom));
          expect(todayTop, greaterThanOrEqualTo(crewBounds.bottom));
          expect(
            tester.getBottomRight(find.byType(TodayPactsCard)).dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy,
            ),
          );
          await tester.drag(board, const Offset(0, -180));
          await tester.pumpUi();
          expect(tester.getTopLeft(board), position);
          expect(
            tester.getBottomRight(board).dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy,
            ),
          );
          expect(find.byKey(const ValueKey('crew-streak')), findsNothing);
          expect(board, findsOneWidget);
          await tester.timedDrag(
            find.byType(Swiper),
            Offset(-size.width * .7, 0),
            const Duration(milliseconds: 300),
          );
          await tester.pumpUi();
          expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
          expect(find.byKey(const ValueKey('pacts-heading')), findsNothing);
          expect(find.text('1 of 2'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
