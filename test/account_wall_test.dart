import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/account_page.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/auth/pact_history.dart';
import 'package:weekpact/src/auth/pact_history_card.dart';
import 'package:weekpact/src/auth/profile_history.dart';
import 'package:weekpact/src/auth/profile_scope.dart';
import 'package:weekpact/src/auth/profile_wall.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

/// The dashboard fake with a wall: [total] check-ins, alternating between two
/// pacts, newest first. None carries a photo, so every tile draws its tint.
class WallBackend extends DashboardBackend implements ProfileHistoryBackend {
  WallBackend({this.total = 40});

  final int total;
  final requests = <({String? before, String? pactId})>[];
  final userIds = <String?>[];

  static const wallPacts = [
    ProfilePact(
      id: 'move',
      crewId: 'crew',
      title: 'Move for 30 min',
      iconKey: 'run',
      pactIndex: 0,
    ),
    ProfilePact(
      id: 'read',
      crewId: 'crew',
      title: 'Read 20 pages',
      iconKey: 'book',
      pactIndex: 1,
    ),
  ];

  late final List<ProfileCheckIn> _all = [
    for (var i = 0; i < total; i++)
      ProfileCheckIn(
        ref: CheckInRef(
          crewId: 'crew',
          pactId: wallPacts[i % 2].id,
          userId: 'me',
          day: DateTime.utc(
            2026,
            10,
            26,
          ).subtract(Duration(days: i)).toIso8601String().substring(0, 10),
        ),
        createdAt: DateTime.utc(2026, 10, 26, 18).subtract(Duration(days: i)),
        crewName: 'Early Birds',
        pactTitle: wallPacts[i % 2].title,
        iconKey: wallPacts[i % 2].iconKey,
        pactIndex: wallPacts[i % 2].pactIndex,
        // No real photos in a widget test: every tile draws its tint.
      ),
  ];

  @override
  Future<ProfileSummary> fetchProfileSummary({String? userId}) async =>
      ProfileSummary(
        checkIns: total,
        crews: 1,
        pacts: wallPacts,
        // A crewmate shares only the first crew with the viewer.
        crewIds: userId == null ? null : const ['crew'],
      );

  /// The record the fake tells for each pact; empty by default, so tests
  /// that only care about the wall see no cards.
  List<PactHistory> pactHistory = const [];
  bool failPactHistory = false;

  @override
  Future<List<PactHistory>> fetchPactHistory({String? userId}) async {
    if (failPactHistory) throw StateError('offline');
    return pactHistory;
  }

  @override
  Future<List<ProfileCheckIn>> fetchMyCheckIns({
    ProfileCheckIn? before,
    String? pactId,
    int limit = 30,
    String? userId,
  }) async {
    requests.add((before: before?.day, pactId: pactId));
    userIds.add(userId);
    final matching = _all
        .where((c) => pactId == null || c.ref.pactId == pactId)
        .toList();
    final start = before == null ? 0 : matching.indexOf(before) + 1;
    return matching.skip(start).take(limit).toList();
  }
}

class TwoCrews extends MissingCrewBackend {
  const TwoCrews();

  @override
  Future<List<PactCrew>> fetchCrews() async => const [
    PactCrew(id: 'crew', name: 'Early Birds', timezone: 'UTC', isOwner: true),
    PactCrew(id: 'club', name: 'Book club', timezone: 'UTC', isOwner: false),
  ];
}

void main() {
  Future<void> pumpAccount(
    WidgetTester tester,
    WallBackend backend, {
    CrewBackend? crews,
    Key? capture,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) =>
            RepaintBoundary(key: capture, child: child!),
        home: Scaffold(
          body: AccountPage(
            user: const AuthUser(
              email: 'alex.morgan@example.com',
              firstName: 'Alex',
              lastName: 'Morgan',
            ),
            backend: const MissingConfigurationAuthBackend(),
            signingOut: false,
            onSignOut: () {},
            homeBackend: backend,
            crewBackend: crews,
          ),
        ),
      ),
    );
    await tester.pumpUi();
  }

  testWidgets('the wall shows the figures and pages on as it scrolls', (
    tester,
  ) async {
    final backend = WallBackend();
    await pumpAccount(tester, backend);

    expect(find.text('40'), findsOneWidget);
    expect(find.text('check-ins'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byType(ProfileWallTile), findsNWidgets(30));
    expect(backend.requests, [(before: null, pactId: null)]);

    await tester.scrollUntilVisible(
      find.byType(ProfileWallTile).last,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpUi();
    expect(backend.requests.length, 2);
    expect(backend.requests.last.before, isNotNull);
    expect(find.byType(ProfileWallTile), findsNWidgets(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pact chip narrows the wall to that pact', (tester) async {
    final backend = WallBackend(total: 10);
    await pumpAccount(tester, backend);

    expect(find.byType(ProfileWallTile), findsNWidgets(10));
    await tester.tap(find.byKey(const ValueKey('account-filter-read')));
    await tester.pumpUi();

    expect(backend.requests.last.pactId, 'read');
    expect(find.byType(ProfileWallTile), findsNWidgets(5));
    for (final tile in tester.widgetList<ProfileWallTile>(
      find.byType(ProfileWallTile),
    )) {
      expect(tile.checkIn.ref.pactId, 'read');
    }

    await tester.tap(find.text('All'));
    await tester.pumpUi();
    expect(find.byType(ProfileWallTile), findsNWidgets(10));
  });

  testWidgets('each pact’s record heads the wall, and opens it on that pact', (
    tester,
  ) async {
    final backend = WallBackend(total: 10)
      ..pactHistory = const [
        PactHistory(
          pactId: 'move',
          crewId: 'crew',
          crewName: 'Early Birds',
          title: 'Move for 30 min',
          iconKey: 'run',
          pactIndex: 0,
          daysPerWeek: 3,
          today: '2026-10-28',
          firstDay: '2026-10-06',
          weeks: [
            PactWeek(start: '2026-10-05', kept: 3),
            PactWeek(start: '2026-10-12', kept: 3),
            PactWeek(start: '2026-10-19', kept: 3),
            PactWeek(start: '2026-10-26', kept: 1),
          ],
          days: ['2026-10-19', '2026-10-21', '2026-10-23', '2026-10-27'],
        ),
        PactHistory(
          pactId: 'read',
          crewId: 'crew',
          crewName: 'Early Birds',
          title: 'Read 20 pages',
          iconKey: 'book',
          pactIndex: 1,
          daysPerWeek: 7,
          today: '2026-10-28',
        ),
      ];
    await pumpAccount(tester, backend);

    expect(find.byType(PactHistoryCard), findsNWidgets(2));
    expect(
      find.text('4 weeks in · 10 days · on target 3 of 4'),
      findsOneWidget,
    );
    expect(find.text('3 wks running'), findsOneWidget);
    expect(find.text('Not kept yet'), findsOneWidget);
    expect(find.byType(PactCalendar), findsNWidgets(2));

    final read = find.byKey(const ValueKey('account-history-read'));
    await tester.ensureVisible(read);
    await tester.pumpUi();
    await tester.tap(read);
    await tester.pumpUi();
    expect(backend.requests.last.pactId, 'read');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a record that will not load leaves the wall standing', (
    tester,
  ) async {
    final backend = WallBackend(total: 4)..failPactHistory = true;
    await pumpAccount(tester, backend);
    expect(find.byType(PactHistoryCard), findsNothing);
    expect(find.byType(ProfileWallTile), findsNWidgets(4));
  });

  testWidgets('an empty wall says where check-ins come from', (tester) async {
    await pumpAccount(tester, WallBackend(total: 0));
    expect(find.byType(ProfileWallTile), findsNothing);
    expect(find.textContaining('Every check-in you keep'), findsOneWidget);
  });

  testWidgets('the crews you are in sit in a strip of pills', (tester) async {
    const capture = ValueKey('capture');
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
      await tester.runAsync(loadAppFont);
    }
    await pumpAccount(
      tester,
      WallBackend(total: 14),
      crews: const TwoCrews(),
      capture: capture,
    );

    expect(find.byKey(const ValueKey('account-crew-crew')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-crew-club')), findsOneWidget);
    // The dashboard's week lends each pill its faces.
    expect(
      tester
          .widget<ProfileCrewPill>(
            find.byKey(const ValueKey('account-crew-crew')),
          )
          .members,
      isNotEmpty,
    );
    expect(tester.takeException(), isNull);

    if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/weekpact-dark-account-wall.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  memberProfileTests();
}

class SignedIn extends MissingConfigurationAuthBackend {
  const SignedIn();

  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'me', email: 'alex.morgan@example.com');
}

void memberProfileTests() {
  const sam = WeekMember('sam', '', displayName: 'Sam Rivera');

  testWidgets('a face opens the crewmate\'s profile, read-only', (
    tester,
  ) async {
    final backend = WallBackend(total: 5);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        builder: (context, child) => ProfileScope(
          authBackend: const SignedIn(),
          homeBackend: backend,
          crewBackend: const TwoCrews(),
          pactsBackend: const MissingPactsBackend(),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: ProfileScope.opener(context, sam),
              child: const Text('Sam'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sam'));
    await tester.pumpUi();

    expect(find.text('Sam Rivera'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.byType(ProfileWallTile), findsNWidgets(5));
    expect(backend.userIds, everyElement('sam'));
    // Nothing of yours to change on somebody else's page.
    expect(find.text('Edit profile'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.text('alex.morgan@example.com'), findsNothing);
    // The nudge comes with the profile wherever it was opened from, in the
    // first crew the two of you share when the face came with none.
    expect(find.byKey(const ValueKey('profile-nudge')), findsOneWidget);
    // Only the crew the two of you share.
    expect(find.byKey(const ValueKey('account-crew-crew')), findsOneWidget);
    expect(find.byKey(const ValueKey('account-crew-club')), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpUi();
    expect(find.text('Sam Rivera'), findsNothing);
  });

  testWidgets('without a scope a face opens nothing', (tester) async {
    late VoidCallback? opener;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            opener = ProfileScope.opener(context, sam);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(opener, isNull);
  });
}
