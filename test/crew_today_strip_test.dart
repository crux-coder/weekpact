import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/home/crew_member_list.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';
import 'widget_test.dart' show FakeAuthBackend, FakeCrewBackend;

/// A crew of five, two of them in today, and a nudge waiting for the rest.
class StripBackend extends DashboardBackend {
  final sent = <String>[];

  /// True when the whole crew has checked in today.
  bool allIn = false;

  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async => {
    for (final id in ['', 'b', 'c', 'd', 'e'])
      id: id == '' || id == 'b'
          ? const CrewNudgeState(CrewNudgeStatus.checkedIn)
          : const CrewNudgeState(CrewNudgeStatus.ready),
  };

  @override
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  }) async {
    sent.add(recipientId);
    return const CrewNudgeState(CrewNudgeStatus.sent);
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final week = await super.fetchWeek(crewId);
    const names = ['Jasmin', 'Bea Novak', 'Cai Ruiz', 'Dara Bell', 'Eli Shaw'];
    const ids = ['', 'b', 'c', 'd', 'e'];
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      members: [
        for (var i = 0; i < ids.length; i++)
          WeekMember(ids[i], '$i@example.com', displayName: names[i]),
      ],
      checkIns: [
        for (final id in allIn ? ids : const ['', 'b'])
          PactCheckIn('read', id, week.today),
      ],
    );
  }
}

Future<StripBackend> pumpStripHome(
  WidgetTester tester, {
  bool allIn = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = FakeAuthBackend();
  addTearDown(auth.dispose);
  final backend = StripBackend()..allIn = allIn;
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: HomePage(
        user: const AuthUser(email: 'person@example.com'),
        authBackend: auth,
        crewBackend: FakeCrewBackend(),
        pactsBackend: backend.pacts,
        homeBackend: backend,
      ),
    ),
  );
  await tester.pumpUi();
  return backend;
}

/// The drawer's box on screen, however far it has been pulled out.
Rect drawer(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('crew-today-drawer')));

bool isOpen(WidgetTester tester) =>
    find.byKey(const ValueKey('crew-today-drawer')).evaluate().isNotEmpty;

void main() {
  testWidgets('the strip reads the day and caps its faces', (tester) async {
    await pumpStripHome(tester);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('/5'), findsOneWidget);
    // Only the crew who are in wear a face; the score counts the rest.
    expect(find.byKey(const ValueKey('crew-today-face-me')), findsNothing);
    expect(find.byKey(const ValueKey('crew-today-face-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-today-face-c')), findsNothing);
    expect(find.byKey(const ValueKey('crew-today-face-e')), findsNothing);
    expect(find.byKey(const ValueKey('crew-today-more')), findsNothing);
    // They sit to the right, past the score.
    final faces = tester.getRect(
      find.byKey(const ValueKey('crew-today-face-b')),
    );
    expect(faces.left, greaterThan(tester.getRect(find.text('/5')).right));
    expect(isOpen(tester), isFalse);
    expect(find.byType(CrewMemberList), findsNothing);
  });

  testWidgets('more check-ins than the strip holds become a count', (
    tester,
  ) async {
    await pumpStripHome(tester, allIn: true);
    // Five in, three faces, and the two it could not show as one more.
    expect(find.text('5'), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-today-more')), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('a pull runs the drawer open under the finger', (tester) async {
    final backend = await pumpStripHome(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    final pull = await tester.startGesture(strip.center);
    // The drawer comes out on the same update the pull passes the threshold,
    // and then keeps pace with the finger pixel for pixel.
    await pull.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(isOpen(tester), isTrue);
    final part = drawer(tester);
    expect(part.top, strip.top);
    expect(part.height, greaterThan(strip.height));
    await pull.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(drawer(tester).height - part.height, closeTo(60, 0.5));

    await pull.up();
    await tester.pumpUi();
    expect(isOpen(tester), isTrue);
    expect(find.byType(CrewMemberList), findsOneWidget);
    // The whole crew, with a nudge where one can be sent.
    for (final name in ['Jasmin', 'Bea Novak', 'Cai Ruiz', 'Eli Shaw']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Nudge'), findsNWidgets(3));
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nudge-c')));
    await tester.pumpUi();
    expect(backend.sent, ['c']);
    expect(find.text('Nudged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pull that stops short hands the drawer back', (tester) async {
    await pumpStripHome(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    final pull = await tester.startGesture(strip.center);
    await pull.moveBy(const Offset(0, 24));
    await tester.pump();
    expect(isOpen(tester), isTrue);
    await pull.up();
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
    // An upward drag is not a pull at all, and leaves the strip alone.
    final up = await tester.startGesture(strip.center);
    await up.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(isOpen(tester), isFalse);
    await up.up();
    await tester.pumpUi();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap runs the pull through, and a second one shuts it', (
    tester,
  ) async {
    await pumpStripHome(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isTrue);
    expect(drawer(tester).height, greaterThan(strip.height));
    // The barrier behind the drawer only catches the tap that shuts it — it
    // paints nothing, so the page underneath is not dimmed. The drawer is the
    // block carried further down, not a card laid over the page.
    final barrier = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('crew-today-barrier')),
    );
    expect(barrier.child, isA<SizedBox>());

    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
  });

  testWidgets('a tap outside shuts the drawer', (tester) async {
    await pumpStripHome(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isTrue);
    await tester.tapAt(const Offset(195, 800));
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
    expect(find.text('TODAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving Home shuts an open drawer behind it', (tester) async {
    await pumpStripHome(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isTrue);
    await tester.tap(find.byKey(const ValueKey('nav-pacts')));
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the drawer opens downward and stays on the page', (
    tester,
  ) async {
    await pumpStripHome(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    final open = drawer(tester);
    expect(open.top, strip.top);
    // It comes out at the block's width rather than the strip's, so it reads
    // as the block itself growing.
    expect(open.left, lessThan(strip.left));
    expect(open.width, greaterThan(strip.width));
    expect(open.center.dx, closeTo(strip.center.dx, 0.5));
    expect(open.bottom, lessThanOrEqualTo(844));
  });
}
