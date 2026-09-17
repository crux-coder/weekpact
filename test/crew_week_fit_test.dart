import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_pact_week_card.dart';
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

/// The app's real faces. The default test font has square, fixed metrics, so a
/// layout that overflows with RobotoCondensed can still fit in a test.
Future<void> _loadFonts() async {
  for (final family in ['RobotoCondensed', 'Roboto']) {
    final loader = FontLoader(family);
    for (final weight in ['Regular', 'Bold']) {
      final file = File('assets/fonts/$family-$weight.ttf');
      if (file.existsSync()) {
        loader.addFont(
          Future.value(file.readAsBytesSync().buffer.asByteData()),
        );
      }
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

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
        // A neighbouring card peeks in, so measure one card and its own rows.
        final selected = find.byType(CrewPactWeekCard).first;
        final card = tester.getRect(selected);
        final summary = tester.getRect(
          find.text('0 of $members checked in today'),
        );
        // Nothing may sit past the safe area: the page is one viewport.
        expect(card.bottom, lessThanOrEqualTo(size.height - inset));
        expect(summary.bottom, lessThanOrEqualTo(size.height - inset));
        // The carousel runs full bleed: it starts outside the page's own
        // margin, so the neighbouring pacts reach the screen's edges.
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('crew-pact-carousel')))
              .dx,
          lessThan(tester.getTopLeft(find.text('Crew pacts')).dx),
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
