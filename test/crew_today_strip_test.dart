import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/auth/auth_backend.dart';
import 'package:weekpact/src/home/crew_member_list.dart';
import 'package:weekpact/src/home/crew_today_strip.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/home_page.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/avatar_shape.dart';

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

/// Every haptic the app asks the platform for while the drawer is worked, in
/// order.
List<String> haptics(WidgetTester tester) {
  final buzzes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        buzzes.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return buzzes;
}

void main() {
  testWidgets('the strip reads the day as a score and a clock', (tester) async {
    await pumpStripHome(tester);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('/5'), findsOneWidget);
    expect(find.text('in today'), findsOneWidget);
    // The faces are gone: the pact cards carry who is in, per pact, and the
    // strip stopped repeating them. What is left is the roll-up and the clock.
    expect(find.text('TODAY'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('crew-today-face-'),
      ),
      findsNothing,
    );
    // The score sits at the head of the row, on the strip's own inset. Where
    // the clock lands at the other end is asserted where `now` is controlled
    // — this fixture's day is not the device's, so there is no honest count.
    expect(
      tester.getRect(find.byKey(const ValueKey('crew-today-count'))).left -
          tester.getRect(find.byType(CrewTodayStrip)).left,
      closeTo(CrewTodayStrip.leftInset, 1),
    );
    // One row: the score and its caption share a line.
    expect(
      tester.getRect(find.text('in today')).center.dy,
      closeTo(tester.getRect(find.text('/5')).center.dy, 6),
    );
    expect(isOpen(tester), isFalse);
    expect(find.byType(CrewMemberList), findsNothing);
  });

  testWidgets('the day still pulls open when the whole crew is in', (
    tester,
  ) async {
    await pumpStripHome(tester, allIn: true);
    expect(find.text('5'), findsOneWidget);
    // Nothing is left for the time to be left for.
    expect(find.byKey(const ValueKey('crew-today-left')), findsNothing);
    // The grip is still there, so the roster is still a pull away.
    expect(find.byKey(const ValueKey('crew-today-strip')), findsOneWidget);
  });

  testWidgets('a pull runs the drawer open under the finger', (tester) async {
    final backend = await pumpStripHome(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    // Closed, the roster's hairline is not on the page at all — it lives
    // inside the drawer, under its clip.
    expect(find.byKey(const ValueKey('crew-member-list-rule')), findsNothing);
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
    // The whole crew, on first-name terms, with a nudge where one can be sent.
    // The surname stays in the tooltip and in what a screen reader reads.
    for (final name in ['Jasmin', 'Bea', 'Cai', 'Eli']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Bea Novak'), findsNothing);
    expect(find.byTooltip('Bea Novak'), findsOneWidget);
    // The roster opens under a hairline, with air between it and the first
    // face — and neither shows until the drawer is out.
    final rule = tester.getRect(
      find.byKey(const ValueKey('crew-member-list-rule')),
    );
    final firstFace = tester.getRect(
      find.byKey(const ValueKey('crew-check-in-person-b')),
    );
    // It sits inside the drawer, at the head of the roster, with air under it
    // so the first face is not pressed against the line.
    expect(rule.top, greaterThan(drawer(tester).top));
    expect(rule.top, lessThan(firstFace.top));
    // Inset to the rows, not run wall to wall: it starts where the faces do.
    expect(rule.left, closeTo(firstFace.left, 1));
    expect(rule.left, greaterThan(drawer(tester).left));
    expect(rule.right, lessThan(drawer(tester).right));
    expect(firstFace.top - rule.bottom, greaterThan(8));
    // The last name is whole: the drawer's run counts the head as well as the
    // rows, so nothing is clipped off the bottom.
    expect(
      tester.getRect(find.byKey(const ValueKey('crew-check-in-person-e'))).bottom,
      lessThanOrEqualTo(drawer(tester).bottom),
    );
    expect(find.text('Nudge'), findsNWidgets(3));
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nudge-c')));
    await tester.pumpUi();
    expect(backend.sent, ['c']);
    expect(find.text('Nudged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the roster opens under a line hung midway between the day and '
      'the first face', (tester) async {
    await pumpStripHome(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    Rect inDrawer(Finder finder) => tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('crew-today-drawer')),
        matching: finder,
      ),
    );
    final rule = inDrawer(find.byKey(const ValueKey('crew-member-list-rule')));
    // The day's last line of type above it, and the first face under it.
    final caption = inDrawer(find.text('in today'));
    final face = inDrawer(
      find.descendant(
        of: find.byKey(const ValueKey('crew-check-in-person-')),
        matching: find.byType(AvatarClip),
      ),
    );
    expect(rule.top - caption.bottom, closeTo(face.top - rule.bottom, 1));
  });

  testWidgets('the roster says who is in and who the day is waiting on', (
    tester,
  ) async {
    await pumpStripHome(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    // Two of the five are in, and every row wears its own state — the drawer
    // holds the whole crew, so a row that says nothing says nothing at all.
    expect(find.byTooltip('Checked in today'), findsNWidgets(2));
    expect(find.byTooltip('Not checked in yet'), findsNWidgets(3));
  });

  testWidgets('the drawer buzzes once it has landed, not as it sets off', (
    tester,
  ) async {
    await pumpStripHome(tester);
    final buzzes = haptics(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    // Under the finger, nothing: the pull can still be handed back, and a
    // drawer on its way out has not arrived anywhere to be felt.
    final pull = await tester.startGesture(strip.center);
    await pull.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(isOpen(tester), isTrue);
    expect(buzzes, isEmpty);
    await pull.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(buzzes, isEmpty);
    await pull.up();
    await tester.pumpUi();
    expect(buzzes, ['HapticFeedbackType.mediumImpact']);

    // Shutting it is not a landing either.
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
    expect(buzzes, ['HapticFeedbackType.mediumImpact']);
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
    expect(find.byKey(const ValueKey('crew-today-count')), findsOneWidget);
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

  group('what the day has left', () {
    CrewWeek weekOn(String today, {required int inToday}) => CrewWeek(
      today: today,
      weekStart: today,
      timezone: 'Europe/Sarajevo',
      pacts: const [
        CrewPact(
          id: 'read',
          crewId: 'crew',
          title: 'Read',
          frequency: PactFrequency.daily,
          daysPerWeek: 7,
          iconKey: 'book',
        ),
      ],
      members: const [
        WeekMember('', 'a@example.com', displayName: 'Jasmin'),
        WeekMember('b', 'b@example.com', displayName: 'Bea'),
      ],
      checkIns: [
        for (final id in const ['', 'b'].take(inToday))
          PactCheckIn('read', id, today),
      ],
    );

    Future<void> pumpStrip(
      WidgetTester tester, {
      required CrewWeek week,
      required DateTime now,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: CrewTodayStrip(week: week, userId: '', now: now),
            ),
          ),
        ),
      ),
    );

    testWidgets('the label says how long the day has to run', (tester) async {
      await pumpStrip(
        tester,
        week: weekOn('2026-09-20', inToday: 1),
        now: DateTime(2026, 9, 20, 17, 12),
      );
      expect(find.text('6H LEFT'), findsOneWidget);
      // The day's two ends sit the same distance off the row's edges: the
      // score at its head, the clock at its tail.
      final row = tester.getRect(find.byType(CrewTodayStrip));
      final count = tester.getRect(
        find.byKey(const ValueKey('crew-today-count')),
      );
      final left = tester.getRect(find.text('6H LEFT'));
      expect(row.right - left.right, closeTo(count.left - row.left, 1));
    });

    testWidgets('it counts in minutes once the day is nearly out', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        week: weekOn('2026-09-20', inToday: 1),
        now: DateTime(2026, 9, 20, 23, 45),
      );
      expect(find.text('15M LEFT'), findsOneWidget);
    });

    testWidgets('a crew that is all in has nothing left to be left', (
      tester,
    ) async {
      await pumpStrip(
        tester,
        week: weekOn('2026-09-20', inToday: 2),
        now: DateTime(2026, 9, 20, 17, 12),
      );
      expect(find.byKey(const ValueKey('crew-today-left')), findsNothing);
    });

    testWidgets('it says nothing when the device and the crew disagree', (
      tester,
    ) async {
      // A member abroad, or the minutes either side of a rollover: the
      // device's midnight is not the crew's, so there is no honest count.
      await pumpStrip(
        tester,
        week: weekOn('2026-09-20', inToday: 1),
        now: DateTime(2026, 9, 21, 0, 30),
      );
      expect(find.byKey(const ValueKey('crew-today-left')), findsNothing);
      expect(find.byKey(const ValueKey('crew-today-count')), findsOneWidget);
    });
  });
}
