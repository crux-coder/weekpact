import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/chat/chat_backend.dart';
import 'package:weekpact/src/crew/crew_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/chat_fakes.dart';
import 'support/fonts.dart';
import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend, FakeCrewBackend;

/// The website's phone screens, rendered from the real pages with a
/// fictional crew. Run with `--dart-define=CAPTURE_WEBSITE=true` to write
/// them to `website/public/screenshots/` at an iPhone's 3x density.
const _viewer = 'ana';

const _members = [
  WeekMember(_viewer, 'ana@example.com', displayName: 'Ana Horvat'),
  WeekMember('mirnes', 'mirnes@example.com', displayName: 'Mirnes Begić'),
  WeekMember('lejla', 'lejla@example.com', displayName: 'Lejla Kurt'),
  WeekMember('sam', 'sam@example.com', displayName: 'Sam Price'),
];

/// Who kept what, Monday the 7th to today, Wednesday the 9th.
const _kept = {
  'move': {
    _viewer: ['07', '08'],
    'mirnes': ['07', '08', '09'],
    'lejla': ['07', '09'],
    'sam': ['08'],
  },
  'read': {
    _viewer: ['07'],
    'mirnes': ['08'],
    'lejla': ['07', '08', '09'],
  },
  'stretch': {
    _viewer: ['07', '08'],
    'mirnes': ['07', '09'],
    'lejla': ['07', '08', '09'],
    'sam': ['07', '08'],
  },
};

class _ExampleWeek extends DashboardBackend {
  _ExampleWeek() : super(viewerId: _viewer) {
    selected.clear();
    pacts.crews = const [
      PactCrew(id: 'crew', name: 'Early Birds', timezone: 'UTC', isOwner: true),
    ];
    pacts.pacts = const [
      CrewPact(
        id: 'move',
        crewId: 'crew',
        title: 'Move for 30 min',
        frequency: PactFrequency.daily,
        daysPerWeek: 7,
        iconKey: 'run',
      ),
      CrewPact(
        id: 'read',
        crewId: 'crew',
        title: 'Read 20 pages',
        frequency: PactFrequency.weekly,
        daysPerWeek: 3,
        iconKey: 'book',
      ),
      CrewPact(
        id: 'stretch',
        crewId: 'crew',
        title: 'Stretch for 10 min',
        frequency: PactFrequency.weekly,
        daysPerWeek: 5,
        iconKey: 'yoga',
      ),
    ];
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async =>
      CrewWeek(
        today: '2026-09-09',
        weekStart: '2026-09-07',
        timezone: 'UTC',
        streakWeeks: 3,
        pacts: pacts.pacts,
        members: _members,
        checkIns: [
          for (final pact in _kept.entries)
            for (final member in pact.value.entries)
              for (final day in member.value)
                PactCheckIn(
                  pact.key,
                  member.key,
                  '2026-09-$day',
                  keptAt: DateTime.utc(2026, 9, int.parse(day), 8),
                  clapCount: day == '09' ? 2 : 0,
                ),
        ],
      );
}

FakeChatServer _chat() {
  final server = FakeChatServer(
    crews: {
      'crew': {for (final member in _members) member.id},
    },
  );
  const lines = [
    ('mirnes', 'Run done before work. Legs are not happy'),
    ('lejla', 'Same, 5k by the river. Who is still out today?'),
    ('sam', 'Me. Going at lunch, promise'),
    (_viewer, 'Holding you to it Sam'),
    ('lejla', 'Also finished the book — 3 for 3 this week'),
    ('mirnes', 'Show-off. Clapped anyway'),
  ];
  var at = DateTime.utc(2026, 9, 9, 7, 40);
  for (final (index, (sender, body)) in lines.indexed) {
    at = at.add(const Duration(minutes: 6));
    server.messages['m$index'] = ChatMessageRecord(
      id: 'm$index',
      crewId: 'crew',
      senderId: sender,
      body: body,
      createdAt: at,
    );
  }
  server.reads['crew'] = {_viewer: at};
  return server;
}

void main() {
  testWidgets('website screenshots', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    // An iPhone's status bar and home indicator, so the handset the site
    // draws round the screen does not sit on the page's title.
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadAppFont);
    final auth = FakeAuthBackend();
    addTearDown(auth.dispose);
    final home = _ExampleWeek();
    const capture = ValueKey('website-capture');
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: WeekPactTheme.dark,
        builder: (context, child) =>
            RepaintBoundary(key: capture, child: child!),
        home: HomePage(
          user: const AuthUser(email: 'ana@example.com', id: _viewer),
          authBackend: auth,
          crewBackend: FakeCrewBackend()
            ..crew = CrewDetails(
              id: 'crew',
              name: 'Early Birds',
              timezone: 'UTC',
              createdAt: DateTime.utc(2026, 6, 2),
              ownerId: _viewer,
              currentUserRole: 'owner',
              members: [
                for (final member in _members)
                  CrewMember(
                    userId: member.id,
                    email: member.email,
                    displayName: member.displayName,
                    role: member.id == _viewer ? 'owner' : 'member',
                    joinedAt: DateTime(2026),
                  ),
              ],
            ),
          pactsBackend: home.pacts,
          homeBackend: home,
          chatBackend: FakeChatBackend(_chat(), _viewer),
        ),
      ),
    );
    await tester.pumpUi();

    Future<void> save(String name) async {
      expect(tester.takeException(), isNull);
      if (!const bool.fromEnvironment('CAPTURE_WEBSITE')) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('website/public/screenshots/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await save('home');
    await tester.tap(find.byKey(const ValueKey('nav-chat')));
    await tester.pumpUi();
    await save('chat');
    await tester.tap(find.byKey(const ValueKey('nav-crews')));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('crew-card-crew')));
    await tester.pumpUi();
    await tester.tap(find.byKey(const ValueKey('crew-tab-1')));
    await tester.pumpUi();
    await save('crew');
    await tester.pumpWidget(const SizedBox());
  });
}
