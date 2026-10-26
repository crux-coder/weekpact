import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/account_page.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/auth/profile_history.dart';
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
  Future<ProfileSummary> fetchProfileSummary() async =>
      ProfileSummary(checkIns: total, crews: 1, pacts: wallPacts);

  @override
  Future<List<ProfileCheckIn>> fetchMyCheckIns({
    ProfileCheckIn? before,
    String? pactId,
    int limit = 30,
  }) async {
    requests.add((before: before?.day, pactId: pactId));
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
}
