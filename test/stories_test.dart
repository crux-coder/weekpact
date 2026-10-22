import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/achievement_composer.dart';
import 'package:weekpact/src/home/clap_control.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/home/photo_check_in_page.dart';
import 'package:weekpact/src/home/stories.dart';
import 'package:weekpact/src/home/story_seen_store.dart';
import 'package:weekpact/src/home/story_viewer.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/status_bar_blur.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/photo_fakes.dart';
import 'support/pump_ui.dart';

const _today = '2026-09-09';

/// A crew of four with a day between them: you have kept one pact, two others
/// are in — one with a photo, one without — and the fourth has not checked in.
class StoriesBackend extends DashboardBackend {
  StoriesBackend({
    this.yourCheckIns = const ['read'],
    this.beaClaps = 0,
    this.beaClappedByYou = false,
  }) : _beaCount = beaClaps;

  final List<String> yourCheckIns;

  /// The claps Bea's check-in already carries in the week, and whether the
  /// viewer gave one of them. Everything a story opens on comes from here.
  final int beaClaps;
  final bool beaClappedByYou;
  int _beaCount;
  bool failClap = false;

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
    if (failClap) throw StateError('offline');
    // Bea's is the only check-in these tests clap, so one tally answers for
    // the crew, and it answers from where the week left it rather than from
    // zero.
    _beaCount = (_beaCount + (clapped ? 1 : -1)).clamp(0, 999);
    return _beaCount;
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
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
          clapCount: beaClaps,
          viewerClapped: beaClappedByYou,
        ),
        PactCheckIn('read', 'cai', _today, keptAt: DateTime.utc(2026, 9, 9, 8)),
      ],
      achievements: achievements,
    );
  }
}

Future<void> pumpStoriesHome(
  WidgetTester tester, {
  DashboardBackend? backend,
  StorySeenStore? seen,
  ThemeData? theme,
  CheckInPhotoCapture? capturePhoto,
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
        captureCheckInPhoto: capturePhoto,
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

  test('a check-in carries its member\'s week on its pact, Monday first', () {
    final week = weekWith([
      // Last week's Sunday is not this week's.
      const PactCheckIn('move', 'bea', '2026-09-06'),
      const PactCheckIn('move', 'bea', '2026-09-07'),
      PactCheckIn('move', 'bea', _today, keptAt: DateTime.utc(2026, 9, 9, 9)),
      // Someone else's day is not Bea's.
      const PactCheckIn('move', 'cai', '2026-09-08'),
    ]);
    final bea = MemberDay.read(
      week,
      viewerId: '',
    ).firstWhere((d) => d.member.id == 'bea');
    final story = bea.stories.single as PactStory;
    expect(story.week?.kept, [true, false, true, false, false, false, false]);
    expect(story.week?.today, 2);
    // A daily pact asks for all seven.
    expect(story.week?.target, 7);
    expect(story.week?.left, 5);
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
        tester.getRect(find.byKey(const ValueKey('home-streak-card'))).top,
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

  testWidgets('Home\'s title row sits clear of the status bar\'s frost', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62);
    addTearDown(tester.view.reset);
    await pumpStoriesHome(tester);
    // The bell is the highest thing on Home, and its badge sits higher
    // still: the blur has to be done before either begins.
    final bell = tester.getRect(
      find.byKey(const ValueKey('notifications-badge')),
    );
    expect(bell.top, greaterThanOrEqualTo(62 + StatusBarBlur.fade));
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
    // With no photo to show, the shot shows where the check-in leaves Cai's
    // week instead: one of the pact's three, two to go.
    expect(
      find.byKey(const ValueKey('story-week-read/cai/$_today')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('story-week-count')))
          .textSpan
          ?.toPlainText(),
      '1 / 3',
    );
    expect(find.text('2 more this week'), findsOneWidget);
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

  testWidgets('a story opens on the claps the check-in already has', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend(beaClaps: 5, beaClappedByYou: true);
    await pumpStoriesHome(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('story-tile-bea')));
    await tester.pumpUi();
    // Five claps read as five, and the clap the viewer gave reads as given —
    // both come off the week rather than off this session's own writes.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Clap'), findsNothing);
    expect(backend.claps, isEmpty);
    final pill = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey('story-clap')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(pill.color, clapInk);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a story opened already clapped does not pop', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStoriesHome(
      tester,
      backend: StoriesBackend(beaClaps: 2, beaClappedByYou: true),
    );
    await tester.tap(find.byKey(const ValueKey('story-tile-bea')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The squeeze answers a clap landing. A clap given yesterday is not one
    // landing now, so the glyph stands still the whole way in.
    final pop = find.descendant(
      of: find.byKey(const ValueKey('story-clap')),
      matching: find.byType(ScaleTransition),
    );
    for (var i = 0; i < 4; i++) {
      expect(tester.widget<ScaleTransition>(pop).scale.value, 1.0);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a clap moves the count the week gave it, and comes back on a '
      'failure', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend(beaClaps: 5);
    await pumpStoriesHome(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('story-tile-bea')));
    await tester.pumpUi();
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-clap')));
    await tester.pumpUi();
    expect(find.text('6'), findsOneWidget);
    // Taking it back puts the crew's own count back, not a nought.
    await tester.tap(find.byKey(const ValueKey('story-clap')));
    await tester.pumpUi();
    expect(find.text('5'), findsOneWidget);

    backend.failClap = true;
    await tester.tap(find.byKey(const ValueKey('story-clap')));
    await tester.pumpUi();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Could not clap.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a story nobody has clapped takes a clap, and only then shows a '
      'tally', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend();
    await pumpStoriesHome(tester, backend: backend);
    await tester.tap(find.byKey(const ValueKey('story-tile-bea')));
    await tester.pumpUi();
    // A check-in nobody has clapped opens on the word rather than standing a
    // nought there.
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

  testWidgets('with nothing kept, your tile opens the achievement camera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpStoriesHome(
      tester,
      backend: StoriesBackend(yourCheckIns: []),
      capturePhoto: captureTestCheckInPhoto,
    );
    // The pact card below is where a check-in is made, so an empty tile of
    // your own opens nothing to view — only the camera for an achievement.
    await tester.tap(find.byKey(const ValueKey('story-tile-')));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsNothing);
    expect(find.byType(CameraStep<Achievement>), findsOneWidget);
    // And it is not a nudge either: you cannot nudge yourself out of bed.
    expect(find.byKey(const ValueKey('nudge-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('achievements walk with the day\'s check-ins, in the order they '
      'happened', () {
    final week = CrewWeek(
      today: _today,
      weekStart: '2026-09-07',
      timezone: 'UTC',
      pacts: weekWith([]).pacts,
      members: weekWith([]).members,
      checkIns: [
        PactCheckIn('move', 'bea', _today, keptAt: DateTime.utc(2026, 9, 9, 7)),
        PactCheckIn('move', 'bea', _today, keptAt: DateTime.utc(2026, 9, 9, 9)),
      ],
      achievements: [
        Achievement(
          id: 'six-c',
          userId: 'bea',
          day: _today,
          text: 'Climbed my first 6c',
          postedAt: DateTime.utc(2026, 9, 9, 8),
        ),
        // Yesterday's is not today's story.
        Achievement(
          id: 'old',
          userId: 'cai',
          day: '2026-09-08',
          text: 'Ran 5 miles',
          postedAt: DateTime.utc(2026, 9, 8, 8),
        ),
      ],
    );
    final days = MemberDay.read(week, viewerId: '');
    final bea = days.firstWhere((d) => d.member.id == 'bea');
    expect(bea.stories.map((s) => s.runtimeType), [
      PactStory,
      AchievementStory,
      PactStory,
    ]);
    expect(bea.hasAchievement, isTrue);
    expect(bea.stories[1].badge, WeekPactColors.achievementBadge);
    final cai = days.firstWhere((d) => d.member.id == 'cai');
    expect(cai.isIn, isFalse);
    expect(cai.hasAchievement, isFalse);
  });

  testWidgets('an achievement wears a trophy in the rail and reads as one in '
      'the viewer, and takes a clap of its own', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend()
      ..achievements = [
        Achievement(
          id: 'six-c',
          userId: 'eli',
          day: _today,
          text: 'Climbed my first 6c',
          postedAt: DateTime.utc(2026, 9, 9, 10),
          clapCount: 2,
        ),
      ];
    await pumpStoriesHome(tester, backend: backend);
    // Eli kept no pact, but posted a win: in, with a trophy on the tile.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-tile-eli')),
        matching: find.byKey(const ValueKey('story-tile-achievement')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-tile-bea')),
        matching: find.byKey(const ValueKey('story-tile-achievement')),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('story-tile-eli')));
    await tester.pumpUi();
    expect(find.byType(StoryViewer), findsOneWidget);
    expect(find.text('Climbed my first 6c'), findsOneWidget);
    // The corner says achievement, never a pact.
    expect(find.byKey(const ValueKey('story-achievement')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-pact')), findsNothing);
    // Nobody deletes a crewmate's.
    expect(find.byKey(const ValueKey('delete-achievement')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-clap')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('story-clap')));
    await tester.pumpUi();
    expect(backend.achievementClaps, [(id: 'six-c', clapped: true)]);
    expect(backend.claps, isEmpty);
  });

  testWidgets('the + opens the camera first, then the words, and posts to '
      'today\'s rail', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend();
    await pumpStoriesHome(
      tester,
      backend: backend,
      capturePhoto: captureTestCheckInPhoto,
    );
    // Only your own tile carries the +.
    expect(find.byKey(const ValueKey('story-tile-compose')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('story-tile-compose')));
    await tester.pumpUi();
    // The same camera a photo check-in opens, as a page of its own, and no
    // way past it.
    expect(find.byType(CameraStep<Achievement>), findsOneWidget);
    expect(find.text('Post a story'), findsOneWidget);
    expect(find.byKey(const ValueKey('achievement-composer')), findsNothing);
    // The picture goes straight on to the next page, the words.
    await takeTestPhoto(tester);
    expect(find.byKey(const ValueKey('achievement-composer')), findsOneWidget);
    // Back is the camera again: that is how a picture is retaken.
    await tester.tap(find.byTooltip('Back to camera'));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('achievement-composer')), findsNothing);
    expect(find.byType(CameraStep<Achievement>), findsOneWidget);
    await takeTestPhoto(tester);
    expect(find.byType(CameraStep<Achievement>), findsNothing);
    // Then the words, under the picture just taken.
    expect(find.byKey(const ValueKey('achievement-composer')), findsOneWidget);
    expect(find.byKey(const ValueKey('achievement-photo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remove-achievement-photo')),
      findsNothing,
    );
    expect(backend.achievements, isEmpty);
    // A plain story until the toggle says otherwise, and it is the left side.
    expect(
      tester.widget<PostKindToggle>(find.byType(PostKindToggle)).value,
      PostKind.story,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('post-kind-story'))).dx,
      lessThan(
        tester
            .getCenter(find.byKey(const ValueKey('post-kind-achievement')))
            .dx,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('post-kind-achievement')));
    await tester.pumpUi();
    expect(
      tester.widget<PostKindToggle>(find.byType(PostKindToggle)).value,
      PostKind.achievement,
    );
    expect(find.text('What did you achieve?'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('achievement-text')),
        matching: find.byType(EditableText),
      ),
      '  Climbed my first 6c  ',
    );
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('post-achievement')));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('achievement-composer')), findsNothing);
    expect(backend.achievements.single.text, 'Climbed my first 6c');
    expect(backend.achievements.single.kind, PostKind.achievement);
    expect(backend.lastAchievementPhoto, testCheckInPhoto);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('story-tile-')),
        matching: find.byKey(const ValueKey('story-tile-achievement')),
      ),
      findsOneWidget,
    );

    // In the viewer: the photo, the words as its caption, the gold chip — and
    // a way for its author to take it down.
    await tester.tap(find.byKey(const ValueKey('story-tile-')));
    await tester.pumpUi();
    // Your check-in came first; the achievement is the next story.
    await tester.tapAt(const Offset(340, 400));
    await tester.pumpUi();
    expect(find.byKey(const ValueKey('story-photo')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('story-achievement-caption')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('story-achievement')), findsOneWidget);
    expect(find.text('Climbed my first 6c'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-achievement')));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-achievement')));
    await tester.pumpUi();
    expect(backend.deletedAchievements, ['achievement-1']);
    expect(find.byType(StoryViewer), findsNothing);
    expect(find.byKey(const ValueKey('story-tile-achievement')), findsNothing);
  });

  testWidgets('putting the camera away starts nothing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend();
    await pumpStoriesHome(
      tester,
      backend: backend,
      capturePhoto: captureTestCheckInPhoto,
    );
    await tester.tap(find.byKey(const ValueKey('story-tile-compose')));
    await tester.pumpUi();
    await tester.tap(find.byTooltip('Close camera'));
    await tester.pumpUi();
    expect(find.byType(CameraStep<Achievement>), findsNothing);
    expect(find.byKey(const ValueKey('achievement-composer')), findsNothing);
    expect(backend.achievements, isEmpty);
  });

  testWidgets('left alone, it is a plain story: lavender, a camera, and no '
      'trophy in the rail', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = StoriesBackend();
    await pumpStoriesHome(
      tester,
      backend: backend,
      capturePhoto: captureTestCheckInPhoto,
    );
    await tester.tap(find.byKey(const ValueKey('story-tile-compose')));
    await tester.pumpUi();
    await takeTestPhoto(tester);
    expect(
      tester.widget<PostKindToggle>(find.byType(PostKindToggle)).value,
      PostKind.story,
    );
    // The preview's chip follows the toggle, as do the words asked for.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('achievement-photo')),
        matching: find.text('Story'),
      ),
      findsOneWidget,
    );
    expect(find.text('What’s the story?'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('achievement-text')),
        matching: find.byType(EditableText),
      ),
      'Sunrise on the morning run',
    );
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('post-achievement')));
    await tester.pumpUi();
    expect(backend.achievements.single.kind, PostKind.story);
    // A plain story is in the rail, but earns no trophy.
    expect(find.byKey(const ValueKey('story-tile-achievement')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-tile-')));
    await tester.pumpUi();
    await tester.tapAt(const Offset(340, 400));
    await tester.pumpUi();
    final chip = find.byKey(const ValueKey('story-achievement'));
    expect(
      find.descendant(of: chip, matching: find.text('Story')),
      findsOneWidget,
    );
    expect(
      (tester
                  .widget<Container>(
                    find
                        .descendant(of: chip, matching: find.byType(Container))
                        .first,
                  )
                  .decoration!
              as ShapeDecoration)
          .color,
      WeekPactColors.story,
    );
  });
}
