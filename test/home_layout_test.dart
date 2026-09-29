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
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

class LargeCrewBackend extends DashboardBackend {
  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
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
  testWidgets('the crew title leads the page and lists your crews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = LargeCrewBackend();
    backend.pacts.crews.add(
      const PactCrew(
        id: 'second',
        name: 'Night Owls',
        timezone: 'UTC',
        isOwner: false,
      ),
    );
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

    // The title is a line of type, not a card: the switcher used to be a
    // raised surface carrying a label and the name at 25pt.
    final switcher = find.byKey(const ValueKey('home-crew-switcher'));
    expect(switcher, findsOneWidget);
    expect(
      find.descendant(of: switcher, matching: find.byType(CrewHeaderSurface)),
      findsNothing,
    );
    expect(tester.getSize(switcher).height, closeTo(CrewSwitcher.height, 1));

    // It leads the page, above the crew's day rather than under it.
    final rail = tester.getRect(find.byKey(const ValueKey('home-stories')));
    final title = tester.getRect(switcher);
    expect(title.bottom, lessThanOrEqualTo(rail.top));
    // And the name and its chevron sit in the middle of the page as one
    // object, rather than the name centring and the mark hanging off it.
    final page = tester.getRect(find.byKey(const ValueKey('home-header')));
    expect(
      tester.getRect(find.byTooltip('Switch crew')).center.dx,
      closeTo(page.center.dx, 1),
    );
    expect(
      tester.getRect(find.text('Early Birds')).center.dx,
      lessThan(page.center.dx),
    );

    // Opening it is a plain list of crews, and picking one switches.
    expect(find.byKey(const ValueKey('crew-switcher-menu')), findsNothing);
    await tester.tap(find.byTooltip('Switch crew'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('crew-switcher-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-option-crew')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-option-second')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('crew-option-second')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('crew-switcher-menu')), findsNothing);
    expect(find.text('Night Owls'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one crew is a title with nothing to open', (tester) async {
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
    // The name still leads the page — it says what the page is about — but a
    // chevron on a list of one is a promise the control cannot keep.
    expect(find.text('Early Birds'), findsOneWidget);
    expect(find.byTooltip('Switch crew'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-crew-switcher')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('crew-switcher-menu')), findsNothing);
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
          // Home leads with the crew's day — the stories rail. The page's own
          // name and the crew streak are gone from here: the navigation bar
          // says which page this is, and the crew week page holds the streak.
          expect(find.byKey(const ValueKey('home-stories')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('crew-header-streak')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('latest-check-in')), findsNothing);
          // The crew's name leads the page, over the rail.
          expect(find.byType(CrewSwitcher), findsOneWidget);
          final rail = tester.getRect(
            find.byKey(const ValueKey('home-stories')),
          );
          final title = tester.getRect(find.byType(CrewSwitcher));
          expect(title.bottom, lessThanOrEqualTo(rail.top));
          expect(rail.bottom, lessThanOrEqualTo(crewBounds.top));
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
