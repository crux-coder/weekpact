import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/home/stories.dart';
import 'package:weekpact/src/home/story_seen_store.dart';
import 'package:weekpact/src/home/story_viewer.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

const _today = '2026-09-09';

/// A crew of four with a day between them: you have kept one pact, two others
/// are in — one with a photo, one without — and the fourth has not checked in.
class StoriesBackend extends DashboardBackend {
  StoriesBackend({this.yourCheckIns = const ['read']});

  final List<String> yourCheckIns;

  /// The claps this backend was asked to write, newest last.
  final claps = <({String pactId, String userId, bool clapped})>[];

  @override
  Future<int> setClap({
    required String pactId,
    required String userId,
    required String day,
    required bool clapped,
  }) async {
    claps.add((pactId: pactId, userId: userId, clapped: clapped));
    return clapped ? 1 : 0;
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    fetches++;
    return CrewWeek(
      today: _today,
      weekStart: '2026-09-07',
      timezone: 'UTC',
      pacts: pacts.pacts,
      members: const [
        WeekMember('', 'person@example.com', displayName: 'Jasmin Mustafic'),
        WeekMember('bea', 'bea@example.com', displayName: 'Bea Novak'),
        WeekMember('cai', 'cai@example.com', displayName: 'Cai Mensah'),
        WeekMember('eli', 'eli@example.com', displayName: 'Eli Fisher'),
      ],
      checkIns: [
        for (final pact in yourCheckIns)
          PactCheckIn(pact, '', _today, keptAt: DateTime.utc(2026, 9, 9, 7)),
        PactCheckIn(
          'move',
          'bea',
          _today,
          photoPath: 'bea/move.jpg',
          photoUrl: 'https://example.test/bea-move.jpg',
          keptAt: DateTime.utc(2026, 9, 9, 9),
        ),
        PactCheckIn('read', 'cai', _today, keptAt: DateTime.utc(2026, 9, 9, 8)),
      ],
    );
  }
}

Future<void> pumpStoriesHome(
  WidgetTester tester, {
  DashboardBackend? backend,
  StorySeenStore? seen,
  ThemeData? theme,
}) async {
  final home = backend ?? StoriesBackend();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? WeekPactTheme.light,
      home: HomePage(
        user: const AuthUser(email: 'person@example.com'),
        authBackend: const MissingConfigurationAuthBackend(),
        crewBackend: const MissingCrewBackend(),
        pactsBackend: home.pacts,
        homeBackend: home,
        storySeenStore: seen,
      ),
    ),
  );
  await tester.pumpUi();
}

CrewWeek weekWith(List<PactCheckIn> checkIns) => CrewWeek(
  today: _today,
  weekStart: '2026-09-07',
  timezone: 'UTC',
  pacts: const [
    CrewPact(
      id: 'move',
      crewId: 'crew',
      title: 'Move for 30 min',
      frequency: PactFrequency.daily,
      daysPerWeek: 7,
    ),
  ],
  members: const [
    WeekMember('', 'person@example.com', displayName: 'Jasmin Mustafic'),
    WeekMember('bea', 'bea@example.com', displayName: 'Bea Novak'),
    WeekMember('cai', 'cai@example.com', displayName: 'Cai Mensah'),
  ],
  checkIns: checkIns,
);

void main() {
  test('the rail reads you first, then what is new, then what is not in', () {
    final week = weekWith([
      PactCheckIn('move', 'bea', _today, keptAt: DateTime.utc(2026, 9, 9, 7)),
      PactCheckIn('move', 'cai', _today, keptAt: DateTime.utc(2026, 9, 9, 9)),
    ]);
    final days = MemberDay.read(week, viewerId: '', seen: const {});
    expect(days.map((d) => d.member.id), ['', 'cai', 'bea']);
    expect(days.first.isViewer, isTrue);
    // You come first with nothing kept; the newest check-in leads the rest.
    expect(days.first.isIn, isFalse);
    expect(days.last.isIn, isTrue);

    // A story that has been opened falls behind one that has not.
    final seen = MemberDay.read(week, viewerId: '', seen: {'move/cai/$_today'});
    expect(seen.map((d) => d.member.id), ['', 'bea', 'cai']);
    expect(seen.last.seen, isTrue);
  });

  test('a member with nothing kept today is in the rail, with no stories', () {
    final days = MemberDay.read(weekWith([]), viewerId: 'bea');
    expect(days, hasLength(3));
    expect(days.every((d) => !d.isIn), isTrue);
    expect(days.first.member.id, 'bea');
    // Nothing kept is not the same as nothing left to see.
    expect(days.first.seen, isFalse);
  });

  test('yesterday cannot leave today looking read', () async {
    final store = StorySeenStore.memory();
    await store.mark('person', '2026-09-08', ['move/bea/2026-09-08']);
    expect(store.read('person', '2026-09-08'), {'move/bea/2026-09-08'});
    expect(store.read('person', _today), isEmpty);
    await store.mark('person', _today, ['move/bea/$_today']);
    expect(store.read('person', _today), {'move/bea/$_today'});
    expect(store.read('person', '2026-09-08'), isEmpty);
  });

  testWidgets('home leads with the crew, on first-name terms', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStoriesHome(tester);
    // One tile a member, whatever they have done, and you are the first.
    for (final id in ['', 'bea', 'cai', 'eli']) {
      expect(find.byKey(ValueKey('story-tile-$id')), findsOneWidget);
    }
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
    expect(find.text('Bea Novak'), findsNothing);
    final rail = tester.getRect(find.byKey(const ValueKey('home-stories')));
    expect(
      tester.getRect(find.byKey(const ValueKey('story-tile-'))).left,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('story-tile-bea'))).left,
      ),
    );
    // It stands where the page's name did, above everything else on Home.
    expect(
      rail.top,
      lessThan(
        tester.getRect(find.byKey(const ValueKey('home-crew-panel'))).top,
      ),
    );
  });

  testWidgets('names read on the canvas they stand on, in either theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The labels sit on the page itself rather than on a card, so they take
    // the canvas's ink. Card ink here is near-black on a near-black canvas.
    await pumpStoriesHome(tester);
    expect(
      tester.widget<Text>(find.text('Bea')).style?.color,
      WeekPactColors.black,
    );
    expect(
      tester.widget<Text>(find.text('Eli')).style?.color,
      WeekPactColors.mutedLight,
    );

    await pumpStoriesHome(tester, theme: WeekPactTheme.dark);
    expect(
      tester.widget<Text>(find.text('Bea')).style?.color,
      WeekPactColors.darkInk,
    );
    expect(
      tester.widget<Text>(find.text('Eli')).style?.color,
      WeekPactColors.darkMuted,
    );
  });

  testWidgets('a tile opens the day, and the ring goes grey behind it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seen = StorySeenStore.memory();
    await pumpStoriesHome(tester, seen: seen);
    await tester.tap(find.byKey(const ValueKey('story-tile-bea')));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsOneWidget);
    expect(find.text('Bea Novak'), findsOneWidget);
    expect(find.byKey(const ValueKey('story-photo')), findsOneWidget);
    // The shot says which pact it is of, in the corner, and nothing on the
    // page says "kept": a story is a check-in, and today is a given.
    final chip = find.byKey(const ValueKey('story-pact'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Move for 30 min')),
      findsOneWidget,
    );
    final shot = tester.getRect(find.byKey(const ValueKey('story-photo')));
    final corner = tester.getRect(chip);
    expect(corner.left - shot.left, closeTo(12, 1));
    expect(shot.bottom - corner.bottom, closeTo(12, 1));
    expect(find.textContaining('kept'), findsNothing);

    // Tapping on past Bea's one check-in moves to the next member in the rail.
    // Cai kept a pact that asks for no photo, so that check-in opens as the
    // pact's own card rather than as an empty frame.
    await tester.tapAt(const Offset(340, 400));
    await tester.pumpUi();
    expect(find.text('Cai Mensah'), findsOneWidget);
    // No photo, so the frame is filled by a wash mixed from the pact's own
    // colours — the page is the same page either way, and the chip in the
    // corner always sits on something.
    expect(find.byKey(const ValueKey('story-wash')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-photo')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-pact')),
        matching: find.text('Read 20 pages'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('kept'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('close-stories')));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsNothing);
    // Both were opened, and the marks are the check-ins' own names.
    expect(seen.read('', _today), {'move/bea/$_today', 'read/cai/$_today'});
  });

  testWidgets('a story takes a clap, and only then shows a tally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend();
    await pumpStoriesHome(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('story-tile-bea')));
    await tester.pumpUi();
    // Home's week does not carry claps, so the pill opens on the word rather
    // than on a number it would have to invent.
    expect(find.text('Clap'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-clap')));
    await tester.pumpUi();
    expect(backend.claps, [(pactId: 'move', userId: 'bea', clapped: true)]);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Clap'), findsNothing);

    // And it comes back: the same pill takes the clap away again.
    await tester.tap(find.byKey(const ValueKey('story-clap')));
    await tester.pumpUi();
    expect(backend.claps.last, (pactId: 'move', userId: 'bea', clapped: false));
    expect(find.text('Clap'), findsOneWidget);
  });

  testWidgets('your own tile opens your own day', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStoriesHome(tester);
    await tester.tap(find.byKey(const ValueKey('story-tile-')));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsOneWidget);
    expect(find.text('You'), findsWidgets);
    expect(find.textContaining('Read 20 pages'), findsWidgets);
  });

  testWidgets('with nothing kept, your tile opens nothing and offers no '
      'camera', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStoriesHome(tester, backend: StoriesBackend(yourCheckIns: []));
    // The pact card below is where a check-in is made, so the rail has no
    // "+" and your own empty tile does not take a tap.
    await tester.tap(
      find.byKey(const ValueKey('story-tile-')),
      warnIfMissed: false,
    );
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
