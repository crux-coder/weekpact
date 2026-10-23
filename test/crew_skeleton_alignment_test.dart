import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/crew/crew_pact_week_card.dart';
import 'package:weekpact/src/crew/crew_week_page.dart';
import 'package:weekpact/src/crew/past_week_sheet.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/app_components.dart';
import 'package:weekpact/src/widgets/page_frame.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';

/// Holds the week open so the skeleton can be measured, then lets it in.
class _SlowBackend extends DashboardBackend {
  final week = Completer<CrewWeek>();

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) {
    fetches++;
    return week.future;
  }
}

const _crew = PactCrew(
  id: 'crew',
  name: 'Hangboardasi',
  timezone: 'Europe/Sarajevo',
  isOwner: true,
);

const _pacts = [
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

CrewWeek _week(String weekStart) => CrewWeek(
  today: '2026-09-17',
  weekStart: weekStart,
  timezone: 'Europe/Sarajevo',
  pacts: _pacts,
  members: const [
    WeekMember('0', 'a@example.com', displayName: 'Jasmin'),
    WeekMember('1', 'b@example.com', displayName: 'Mirnes'),
    WeekMember('2', 'c@example.com', displayName: 'Amar'),
  ],
  checkIns: const [
    PactCheckIn('hang', '0', '2026-09-15'),
    PactCheckIn('hang', '1', '2026-09-16'),
  ],
);

/// Where [finder]'s box is drawn on screen, after every transform above it:
/// the deck shrinks the cards either side of the front one.
Rect _drawn(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Matcher _at(Rect expected) => isA<Rect>()
    .having((r) => r.left, 'left', closeTo(expected.left, 1))
    .having((r) => r.top, 'top', closeTo(expected.top, 1))
    .having((r) => r.right, 'right', closeTo(expected.right, 1))
    .having((r) => r.bottom, 'bottom', closeTo(expected.bottom, 1));

/// A bar standing in for a line of words: level with the words' left edge,
/// as wide as they are, and centred on their line.
Matcher _onLine(Rect line, {required double width}) => isA<Rect>()
    .having((r) => r.left, 'left', closeTo(line.left, 1))
    .having((r) => r.width, 'width', closeTo(width, 1))
    .having((r) => r.center.dy, 'centre', closeTo(line.center.dy, 1));

double _wordsWidth(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text))
    .getMaxIntrinsicWidth(double.infinity);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home) => MaterialApp(
  theme: WeekPactTheme.dark,
  builder: (context, child) => RepaintBoundary(
    key: const ValueKey('capture'),
    child: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(padding: const EdgeInsets.only(top: 47, bottom: 34)),
      child: child!,
    ),
  ),
  home: home,
);

/// Lets the week in and waits out the swap.
Future<void> _arrive(
  WidgetTester tester,
  _SlowBackend backend,
  CrewWeek week,
) async {
  backend.week.complete(week);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 800));
  }
}

/// Run with --dart-define=CAPTURE_DESIGN=true to see both states.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${Directory.systemTemp.path}/weekpact-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// What the deck's skeleton draws, in the order the loaded deck is read.
typedef _Deck = ({Rect heading, Rect counter, Rect card, Rect next, Rect dot});

_Deck _skeletonDeck(WidgetTester tester, Finder skeleton) {
  final bars = find.descendant(
    of: skeleton,
    matching: find.byType(SkeletonBar),
  );
  return (
    heading: _drawn(tester, bars.at(0)),
    counter: _drawn(tester, bars.at(1)),
    card: _drawn(
      tester,
      find.byKey(const ValueKey('crew-pact-carousel-skeleton-card')),
    ),
    next: _drawn(
      tester,
      find.byKey(const ValueKey('crew-pact-carousel-skeleton-next')),
    ),
    dot: _drawn(tester, bars.at(2)),
  );
}

void _expectDeck(WidgetTester tester, _Deck skeleton) {
  expect(
    skeleton.heading,
    _onLine(
      _drawn(tester, find.text('Crew pacts')),
      width: _wordsWidth(tester, 'Crew pacts'),
    ),
  );
  expect(
    skeleton.counter,
    _onLine(
      _drawn(tester, find.text('1 / 3')),
      width: _wordsWidth(tester, '1 / 3'),
    ),
  );
  final cards = find.byType(CrewPactWeekCard);
  expect(skeleton.card, _at(_drawn(tester, cards.at(0))));
  expect(skeleton.next, _at(_drawn(tester, cards.at(1))));
  expect(skeleton.dot, _at(_drawn(tester, find.byTooltip('Pact 1 of 3'))));
}

void main() {
  setUpAll(loadAppFont);

  testWidgets('the crew week skeleton stands where the week arrives', (
    tester,
  ) async {
    _phone(tester);
    final backend = _SlowBackend()..pacts.pacts = _pacts;
    await tester.pumpWidget(
      _app(CrewWeekPage(crew: _crew, backend: backend, userId: '0')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _capture(tester, 'crew-week-loading');

    final skeleton = find.byKey(const ValueKey('crew-week-skeleton'));
    final podium = _drawn(
      tester,
      find.descendant(of: skeleton, matching: find.byType(CrewPodiumPanel)),
    );
    final deck = _skeletonDeck(tester, skeleton);

    await _arrive(tester, backend, _week('2026-09-14'));
    await _capture(tester, 'crew-week-loaded');
    expect(skeleton, findsNothing);

    expect(podium, _at(_drawn(tester, find.byType(CrewPodiumPanel))));
    _expectDeck(tester, deck);
  });

  testWidgets('the past-week skeleton stands where the week arrives', (
    tester,
  ) async {
    _phone(tester);
    final backend = _SlowBackend()..pacts.pacts = _pacts;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PastWeekSheet(
              crew: _crew,
              backend: backend,
              userId: '0',
              weekStart: '2026-09-07',
              currentWeekStart: '2026-09-14',
              crewSize: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _capture(tester, 'past-week-loading');

    final skeleton = find.byKey(const ValueKey('past-week-skeleton'));
    final banner = _drawn(
      tester,
      find.descendant(of: skeleton, matching: find.byType(AppSurface)).first,
    );
    final deck = _skeletonDeck(tester, skeleton);

    await _arrive(tester, backend, _week('2026-09-07'));
    await _capture(tester, 'past-week-loaded');
    expect(skeleton, findsNothing);

    expect(
      banner,
      _at(
        _drawn(
          tester,
          find
              .ancestor(
                of: find.text('Week closed'),
                matching: find.byType(AppSurface),
              )
              .first,
        ),
      ),
    );
    _expectDeck(tester, deck);
  });
}
