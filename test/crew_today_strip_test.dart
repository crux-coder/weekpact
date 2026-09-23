import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/home/crew_member_list.dart';
import 'package:weekpact/src/home/crew_today_strip.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';
import 'package:weekpact/src/widgets/avatar_shape.dart';

import 'support/home_fakes.dart';
import 'support/pump_ui.dart';

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

/// The strip on its own, at the width and on the face Home's crew block gave
/// it. Home itself stopped building it — the stories rail says who is in, and
/// the crew block is the progress card alone — so its own tests host it.
Future<StripBackend> pumpStrip(
  WidgetTester tester, {
  bool allIn = false,
  bool active = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final backend = StripBackend()..allIn = allIn;
  final week = await backend.fetchWeek('crew');
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.dark,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 80, 12, 0),
            child: CrewTodayStrip(
              week: week,
              userId: '',
              backend: backend,
              crewId: 'crew',
              active: active,
              // The frame the crew block held it in: the drawer comes out at
              // the block's width and finishes on the block's own corner.
              bleed: CrewWeekButton.pad,
              curve: CrewWeekButton.frameCurve,
            ),
          ),
        ),
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
  testWidgets('the strip is a clock and a pull, and says nothing the rail '
      'already says', (tester) async {
    await pumpStrip(tester);
    // The score — so many of the crew in today — moved to the stories rail at
    // the top of the page, in faces. The strip stopped repeating it, as it
    // stopped repeating the faces themselves.
    expect(find.text('/5'), findsNothing);
    expect(find.text('in today'), findsNothing);
    expect(find.byKey(const ValueKey('crew-today-count')), findsNothing);
    expect(find.text('TODAY'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'crew-today-face-',
            ),
      ),
      findsNothing,
    );
    // Where the clock lands is asserted where `now` is controlled — this
    // fixture's day is not the device's, so there is no honest count.
    expect(isOpen(tester), isFalse);
    expect(find.byType(CrewMemberList), findsNothing);
  });

  testWidgets('the day still pulls open when the whole crew is in', (
    tester,
  ) async {
    await pumpStrip(tester, allIn: true);
    // Nothing is left for the time to be left for.
    expect(find.byKey(const ValueKey('crew-today-left')), findsNothing);
    // The grip is still there, so the roster is still a pull away.
    expect(find.byKey(const ValueKey('crew-today-strip')), findsOneWidget);
  });

  testWidgets('a pull runs the drawer open under the finger', (tester) async {
    final backend = await pumpStrip(tester);
    final strip = tester.getRect(
      find.byKey(const ValueKey('crew-today-strip')),
    );
    // Closed, the roster is not on the page at all — it lives inside the
    // drawer, under its clip.
    expect(find.byType(CrewMemberList), findsNothing);
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
    // Scoped to the roster: Home's stories rail is on first-name terms too, so
    // every name in the drawer also has a tile above it.
    final roster = find.byType(CrewMemberList);
    for (final name in ['Jasmin', 'Bea', 'Cai', 'Eli']) {
      expect(
        find.descendant(of: roster, matching: find.text(name)),
        findsOneWidget,
      );
    }
    expect(find.text('Bea Novak'), findsNothing);
    expect(
      find.descendant(of: roster, matching: find.byTooltip('Bea Novak')),
      findsOneWidget,
    );
    // The roster opens straight out of the day's row, with air over its first
    // face and nothing ruled across it.
    final firstFace = tester.getRect(
      find.byKey(const ValueKey('crew-check-in-person-b')),
    );
    expect(firstFace.top, greaterThan(drawer(tester).top));
    expect(firstFace.left, greaterThan(drawer(tester).left));
    expect(firstFace.right, lessThan(drawer(tester).right));
    // The last name is whole: the drawer's run counts the head as well as the
    // rows, so nothing is clipped off the bottom.
    expect(
      tester
          .getRect(find.byKey(const ValueKey('crew-check-in-person-e')))
          .bottom,
      lessThanOrEqualTo(drawer(tester).bottom),
    );
    expect(find.text('Nudge'), findsNWidgets(3));
    expect(find.text('Checked in'), findsOneWidget);
    expect(
      find.descendant(of: roster, matching: find.text('You')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('nudge-c')));
    await tester.pumpUi();
    expect(backend.sent, ['c']);
    expect(find.text('Nudged'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the roster opens with air over its first face, and no rule '
      'across it', (tester) async {
    await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    Rect inDrawer(Finder finder) => tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('crew-today-drawer')),
        matching: finder,
      ),
    );
    expect(find.byKey(const ValueKey('crew-member-list-rule')), findsNothing);
    // The drawer's own head is the gap: the day's row ends, and the first
    // face stands clear of it without a line between them.
    final drawer = tester.getRect(
      find.byKey(const ValueKey('crew-today-drawer')),
    );
    final face = inDrawer(
      find.descendant(
        of: find.byKey(const ValueKey('crew-check-in-person-')),
        matching: find.byType(AvatarClip),
      ),
    );
    expect(face.top - drawer.top, greaterThan(CrewTodayStrip.rowHeight));
    expect(
      face.top - drawer.top,
      lessThan(CrewTodayStrip.rowHeight + CrewTodayStrip.gripHeight + 16),
    );
  });

  testWidgets('every row carries that member\'s week, and the nudge with it', (
    tester,
  ) async {
    await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    // Five members, five bars: the week each of them has kept so far, capped
    // per pact the way `CrewWeek.percent` caps it.
    final bars = find.descendant(
      of: find.byType(CrewMemberList),
      matching: find.byType(LinearProgressIndicator),
    );
    expect(bars, findsNWidgets(5));
    expect(
      tester.widget<LinearProgressIndicator>(bars.first).value,
      inInclusiveRange(0, 1),
    );
    // And the nudge is still on the rows that can take one.
    expect(find.text('Nudge'), findsNWidgets(3));
  });

  testWidgets('the roster says who is in and who the day is waiting on', (
    tester,
  ) async {
    await pumpStrip(tester);
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
    await pumpStrip(tester);
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
    await pumpStrip(tester);
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
    await pumpStrip(tester);
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
    await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isTrue);
    await tester.tapAt(const Offset(195, 800));
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
    expect(find.byType(CrewMemberList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('going inactive shuts an open drawer behind it', (tester) async {
    await pumpStrip(tester);
    await tester.tap(find.byKey(const ValueKey('crew-today-strip')));
    await tester.pumpUi();
    expect(isOpen(tester), isTrue);
    // What the page under it does when it is left: an open drawer belongs to
    // a page you are looking at.
    await pumpStrip(tester, active: false);
    await tester.pumpUi();
    expect(isOpen(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the drawer opens downward and stays on the page', (
    tester,
  ) async {
    await pumpStrip(tester);
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
      // The clock finishes on the row's own right edge, at the strip's inset.
      final row = tester.getRect(find.byType(CrewTodayStrip));
      final left = tester.getRect(find.text('6H LEFT'));
      expect(row.right - left.right, closeTo(CrewTodayStrip.leftInset, 1));
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
    });
  });
}
