import 'package:flutter/material.dart';
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
        PactCheckIn('hang', '0', '2026-09-15'),
        PactCheckIn('hang', '1', '2026-09-16'),
        PactCheckIn('hang', '2', '2026-09-15'),
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

void main() {
  setUpAll(loadAppFont);

  for (final (size, inset, scale, members) in [
    (const Size(558, 603), 0.0, 1.0, 3),
    (const Size(700, 600), 0.0, 1.0, 3),
    (const Size(900, 500), 0.0, 1.0, 3),
    (const Size(393, 660), 34.0, 1.0, 3),
    (const Size(393, 852), 59.0, 2.0, 3),
    (const Size(565, 945), 34.0, 1.0, 3),
    (const Size(565, 945), 0.0, 1.0, 3),
    (const Size(390, 844), 20.0, 1.0, 3),
    (const Size(393, 852), 34.0, 1.0, 3),
    (const Size(393, 852), 34.0, 1.3, 3),
    (const Size(430, 932), 34.0, 1.0, 5),
    (const Size(375, 812), 34.0, 1.0, 6),
    (const Size(320, 568), 20.0, 1.0, 3),
  ]) {
    testWidgets(
      'the whole crew week fits $size inset $inset scale $scale members $members',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: WeekPactTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                padding: EdgeInsets.only(top: 24, bottom: inset),
              ),
              child: child!,
            ),
            home: CrewWeekPage(
              crew: const PactCrew(
                id: 'crew',
                name: 'Hangboardasi',
                timezone: 'Europe/Sarajevo',
                isOwner: true,
              ),
              backend: _backend()..memberCount = members,
              userId: '0',
            ),
          ),
        );
        await tester.pumpUi();
        expect(tester.takeException(), isNull);
        // The card never shrinks its crew to fit: where it is taller than
        // the screen, the page scrolls. Scrolled to its end, the whole card
        // clears the safe area.
        await tester.drag(
          find.byKey(const ValueKey('crew-refresh-viewport')),
          const Offset(0, -3000),
        );
        await tester.pumpUi();
        // A neighbouring card peeks in, so measure one card and its own rows.
        final selected = find.byType(CrewPactWeekCard).first;
        final card = tester.getRect(selected);
        expect(card.bottom, lessThanOrEqualTo(size.height - inset));
        // The deck is Home's: the card in front is as wide as the page's
        // column, with only a sliver of its neighbours in the margin.
        expect(
          card.left,
          moreOrLessEquals(tester.getTopLeft(find.text('Crew pacts')).dx),
        );
        // The carousel clips its pages, so it has to leave the card's raised
        // edge room below the card or the card reads as cut off.
        final carousel = tester.getRect(
          find.byKey(const ValueKey('crew-pact-carousel')),
        );
        // A very short viewport scales the whole page down, the edge with it,
        // so the gap is checked as present rather than as an exact 2px.
        expect(carousel.bottom - card.bottom, greaterThan(1.5));
        // The card's own bottom row has to sit inside the card's padding, not
        // flush against an edge that clips it.
        final total = tester.getRect(
          find.descendant(of: selected, matching: find.text('Crew total')),
        );
        expect(total.bottom, lessThanOrEqualTo(card.bottom - 10));
      },
    );
  }
}
