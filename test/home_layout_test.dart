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
          final board = find.byKey(const ValueKey('crew-board'));
          final position = tester.getTopLeft(board);
          final activePact = tester.getRect(
            find.byKey(const ValueKey('move')).hitTestable(),
          );
          final crewBounds = tester.getRect(board);
          expect(activePact.center.dx, lessThan(crewBounds.center.dx));
          expect(
            crewBounds.center.dx - activePact.center.dx,
            lessThanOrEqualTo(13),
          );
          expect(activePact.left, greaterThan(crewBounds.left));
          expect(activePact.right, lessThan(crewBounds.right));
          final titleBottom = tester.getBottomRight(find.byType(HomeHeader)).dy;
          final crewTop = tester.getTopLeft(find.byType(TodayCrewCard)).dy;
          // Home leads with its own name and dot, the crew streak beside it,
          // and the selector underneath — no activity strip.
          expect(find.text('Home'), findsWidgets);
          expect(find.byKey(const ValueKey('latest-check-in')), findsNothing);
          final streak = tester.getRect(
            find.byKey(const ValueKey('crew-header-streak')),
          );
          final heading = tester.getRect(find.text('Home').first);
          expect(streak.left, greaterThan(heading.right));
          expect(
            tester.getTopLeft(find.byType(CrewSwitcher)).dy,
            greaterThanOrEqualTo(heading.bottom),
          );
          final todayTop = tester.getTopLeft(find.byType(TodayPactsCard)).dy;
          expect(crewTop, greaterThanOrEqualTo(titleBottom));
          expect(todayTop, greaterThanOrEqualTo(crewBounds.bottom));
          expect(
            tester.getBottomRight(find.byType(TodayPactsCard)).dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy,
            ),
          );
          await tester.drag(
            find.byKey(const ValueKey('pending-tile')),
            const Offset(0, -180),
          );
          await tester.pumpUi();
          expect(tester.getTopLeft(board), position);
          expect(
            tester.getBottomRight(board).dy,
            lessThanOrEqualTo(
              tester.getTopLeft(find.byKey(const ValueKey('nav-home'))).dy,
            ),
          );
          expect(find.byKey(const ValueKey('crew-streak')), findsNothing);
          final before = find.text('Early Birds');
          expect(before, findsOneWidget);
          await tester.timedDrag(
            find.byType(Swiper),
            Offset(-size.width * .7, 0),
            const Duration(milliseconds: 300),
          );
          await tester.pumpUi();
          expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
          expect(find.text('Your pacts'), findsNothing);
          expect(find.text('1 of 2'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
