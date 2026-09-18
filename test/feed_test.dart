import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/feed/feed_page.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'home_test.dart' show pumpHome;
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

FeedEntry entry(
  int index, {
  String day = '2026-09-09',
  String crew = 'Early Birds',
  String? photoPath = 'photo.png',
  String name = 'Mirnes Halilovic',
  int claps = 0,
  bool clapped = false,
}) => FeedEntry(
  pactId: 'pact-$index',
  userId: 'member-$index',
  crewId: 'crew',
  crewName: crew,
  pactTitle: 'Pact $index',
  iconKey: 'run',
  day: day,
  createdAt: DateTime.parse(
    '${day}T${(9 + index % 9).toString().padLeft(2, '0')}:00:00Z',
  ),
  displayName: name,
  photoPath: photoPath,
  clapCount: claps,
  clapped: clapped,
);

class FeedBackend extends DashboardBackend {
  FeedBackend({int entries = 30})
    : feed = List.generate(entries, (index) => entry(index));

  final List<FeedEntry> feed;
  final cursors = <FeedEntry?>[];
  final claps = <String, int>{};

  /// Every clap write asked for, as the post's id and the state requested.
  final clapWrites = <(String, bool)>[];
  bool fail = false;
  bool failClap = false;
  Completer<List<FeedEntry>>? pending;

  @override
  Future<List<FeedEntry>> fetchFeed({FeedEntry? before, int limit = 20}) async {
    cursors.add(before);
    if (fail) throw StateError('offline');
    if (pending != null) return pending!.future;
    return feed
        .skip(
          before == null ? 0 : feed.indexWhere((e) => e.id == before.id) + 1,
        )
        .take(limit)
        .toList();
  }

  @override
  Future<int> setClap({
    required String pactId,
    required String userId,
    required String day,
    required bool clapped,
  }) async {
    final id = '$pactId/$userId/$day';
    clapWrites.add((id, clapped));
    if (failClap) throw StateError('offline');
    final before =
        claps[id] ?? feed.firstWhere((entry) => entry.id == id).clapCount;
    return claps[id] = math.max(0, before + (clapped ? 1 : -1));
  }
}

Future<void> pumpFeed(
  WidgetTester tester,
  FeedBackend backend, {
  // Posts are photo-sized, so a phone-width but tall viewport keeps several
  // of them on screen at once.
  Size size = const Size(390, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: FeedPage(backend: backend, userId: 'member-0'),
      ),
    ),
  );
  await tester.pumpUi();
}

void main() {
  testWidgets('shows check-ins from every crew, newest first', (tester) async {
    final backend = FeedBackend(entries: 3);
    backend.feed[1] = entry(1, crew: 'Climbers');
    await pumpFeed(tester, backend);

    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Pact 0'), findsOneWidget);
    expect(find.text('Pact 1'), findsOneWidget);
    expect(find.text('Climbers'), findsOneWidget);
    // The viewer's own check-in is attributed to them, others by name. The
    // name heads the card and the crew sits under the pact it kept.
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Early Birds'), findsNWidgets(2));
    expect(find.text('Mirnes Halilovic'), findsNWidgets(2));
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('groups entries under one heading per day', (tester) async {
    final backend = FeedBackend(entries: 4);
    for (var index = 0; index < 4; index++) {
      backend.feed[index] = entry(
        index,
        day: index < 2 ? '2026-09-09' : '2026-09-08',
      );
    }
    await pumpFeed(tester, backend);

    expect(
      find.byKey(const ValueKey('feed-date-2026-09-09T00:00:00.000')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('feed-date-2026-09-08T00:00:00.000')),
      findsOneWidget,
    );
  });

  testWidgets('pages with a cursor as the feed is scrolled', (tester) async {
    final backend = FeedBackend(entries: 30);
    await pumpFeed(tester, backend, size: const Size(390, 844));

    expect(backend.cursors.first, isNull);
    expect(find.text('Pact 0'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('feed-list')),
      const Offset(0, -4000),
    );
    await tester.pumpUi();

    expect(backend.cursors.length, greaterThan(1));
    expect(backend.cursors[1]?.id, backend.feed[11].id);
    await tester.scrollUntilVisible(
      find.text('Pact 12'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pact 12'), findsOneWidget);
  });

  testWidgets('offers a retry after a failed read', (tester) async {
    final backend = FeedBackend(entries: 3)..fail = true;
    await pumpFeed(tester, backend);

    expect(find.text('Could not load the feed.'), findsOneWidget);
    backend.fail = false;
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pumpUi();

    expect(find.text('Pact 0'), findsOneWidget);
    expect(find.text('Could not load the feed.'), findsNothing);
  });

  testWidgets('keeps an honest empty state and shows photoless check-ins', (
    tester,
  ) async {
    final backend = FeedBackend(entries: 0);
    // A phone-height viewport keeps the pull-to-refresh threshold reachable.
    await pumpFeed(tester, backend, size: const Size(390, 844));
    expect(find.text('No check-ins yet.'), findsOneWidget);

    backend.feed.add(entry(0, photoPath: null));
    // Pull to refresh picks up check-ins posted since the feed was opened.
    final pull = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('feed-list'))),
    );
    for (var step = 0; step < 12; step++) {
      await pull.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await pull.up();
    await tester.pumpUi();
    await tester.pumpUi();
    expect(find.text('Pact 0'), findsOneWidget);
    expect(find.text('No check-ins yet.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home no longer carries the crew history panel', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHome(tester, DashboardBackend());
    await tester.pumpUi();

    expect(find.byKey(const ValueKey('crew-history-button')), findsNothing);
    expect(find.text('RECENT CHECK-INS'), findsNothing);
    // The feed replaces it as its own destination.
    expect(find.byKey(const ValueKey('nav-feed')), findsOneWidget);
  });
}
