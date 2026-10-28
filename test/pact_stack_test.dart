import 'package:flutter/services.dart';

import 'support/pump_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/home/home_surface.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/fonts.dart';
import 'support/home_fakes.dart';

void main() {
  // The default test font has square, fixed metrics, so a title that wraps in
  // the app can sit on one line here. Anything measuring the fit needs the
  // real face.
  setUpAll(loadAppFont);

  testWidgets('a long pact name shrinks to fit rather than being cut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const long =
        'Walk the dog around the park before work and again after dinner';
    final backend = DashboardBackend();
    backend.pacts.pacts = [
      backend.pacts.pacts.first,
      CrewPact(
        id: 'long',
        crewId: 'crew',
        title: long,
        frequency: PactFrequency.daily,
        daysPerWeek: 7,
        iconKey: 'yoga',
      ),
    ];
    final week = await backend.fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: TodayPactsCard(
              week: week,
              userId: '',
              savingPact: null,
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();

    double sizeOf(String title) =>
        tester.widget<Text>(find.text(title).hitTestable()).style!.fontSize!;

    final short = sizeOf('Move for 30 min');
    await tester.drag(
      find.byKey(const ValueKey('pact-stack')),
      const Offset(-320, 0),
    );
    await tester.pumpUi();
    final shrunk = sizeOf(long);
    // The short name keeps the card's display size; the long one steps down
    // to hold the whole promise, and never past the floor.
    expect(short, 25);
    expect(shrunk, lessThan(short));
    // _FittedTitle.minFontSize: below this a title stops being a headline.
    expect(shrunk, greaterThanOrEqualTo(15.0));
    // Whole points, so two cards in a stack stay on one type scale.
    expect(shrunk, shrunk.roundToDouble());
    // Shrinking is what keeps the name whole: it is not also cut.
    expect(find.text(long).hitTestable(), findsOneWidget);
    // Four lines, and the name is laid out across more than two of them —
    // a two-line cap would have had to shrink much further or ellipsise.
    final title = tester.widget<Text>(find.text(long).hitTestable());
    expect(title.maxLines, 4);
    final painter = TextPainter(
      text: TextSpan(text: long, style: title.style),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: tester.getSize(find.text(long).hitTestable()).width);
    expect(painter.computeLineMetrics().length, greaterThan(2));
    painter.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day that is kept is raised, the rest stay flat', (
    tester,
  ) async {
    final backend = DashboardBackend();
    final week = await backend.fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPactsCard(
            week: week,
            userId: '',
            savingPact: null,
            onToggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpUi();
    // The second pact carries the week's one completed day.
    await tester.drag(
      find.byKey(const ValueKey('pact-stack')),
      const Offset(-650, 0),
    );
    await tester.pumpUi();
    final segments = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('pact-progress-read')),
            matching: find.byType(Container),
          ),
        )
        .toList();
    expect(segments, hasLength(3));
    final faces = segments
        .map((segment) => segment.decoration! as ShapeDecoration)
        .toList();
    // The kept day is raised on the check-in button's own edge.
    expect(faces.first.shadows, isNotNull);
    expect(faces.last.shadows, isNull);
    // A continuous corner that outgrows its box leaves stray ticks at the
    // segment's ends, so it never exceeds half the height.
    final shape = faces.first.shape as ContinuousRectangleBorder;
    expect(
      shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
      lessThanOrEqualTo(segments.first.constraints!.maxHeight / 2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards fill the width and stop at both ends', (tester) async {
    final backend = DashboardBackend();
    backend.pacts.pacts.add(
      const CrewPact(
        id: 'third',
        crewId: 'crew',
        title: 'Stretch',
        frequency: PactFrequency.daily,
        daysPerWeek: 7,
        iconKey: 'yoga',
      ),
    );
    final week = await backend.fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPactsCard(
            week: week,
            userId: '',
            savingPact: null,
            onToggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpUi();
    void expectSelected(int index) {
      final pact = week.pacts[index];
      expect(find.text(pact.title).hitTestable(), findsOneWidget);
      expect(find.text('3 pacts'), findsNothing);
      expect(find.text('YOUR PACTS'), findsNothing);
      // One card at a time, edge to edge: nothing peeks in beside it.
      final card = tester.getRect(find.byKey(ValueKey(pact.id)));
      final stack = tester.getRect(find.byKey(const ValueKey('pact-stack')));
      expect(card.left, closeTo(stack.left, 1));
      expect(card.right, closeTo(stack.right, 1));
      for (final other in week.pacts) {
        if (other == pact) continue;
        expect(find.text(other.title).hitTestable(), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> swipe(double dx, int expectedIndex) async {
      await tester.drag(
        find.byKey(const ValueKey('pact-stack')),
        Offset(dx, 0),
      );
      await tester.pumpUi();
      expectSelected(expectedIndex);
    }

    expectSelected(0);
    await swipe(650, 0);
    await swipe(-650, 1);
    await swipe(-650, 2);
    await swipe(-650, 2);
    await swipe(650, 1);
    await swipe(650, 0);
  });

  testWidgets('the icon and the check-in button sit on the card\'s inset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final week = await DashboardBackend().fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: TodayPactsCard(
              week: week,
              userId: '',
              savingPact: null,
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    final card = tester.getRect(find.byKey(const ValueKey('move')));
    final button = tester.getRect(
      find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
    );
    expect(button.left, closeTo(card.left + homeCardInset.left, 1));
    expect(button.right, closeTo(card.right - homeCardInset.right, 1));
    final dashes = tester.getRect(
      find.byKey(const ValueKey('pact-progress-move')).hitTestable(),
    );
    expect(dashes.left, closeTo(button.left, 1));
    expect(dashes.width, closeTo(button.width, 1));
    final icon = tester.getRect(find.byKey(const ValueKey('pact-icon-move')));
    expect(icon.top, closeTo(card.top + homeCardInset.top, 1));
    expect(icon.right, closeTo(card.right - homeCardInset.right, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('neighbours shrink, and only a sliver shows past the edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final week = await DashboardBackend().fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TodayPactsCard(
                week: week,
                height: 400,
                userId: '',
                savingPact: null,
                onToggle: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    final stack = tester.getRect(find.byKey(const ValueKey('pact-stack')));
    final front = tester.getRect(find.byKey(const ValueKey('move')));
    final next = tester.getRect(find.byKey(const ValueKey('read')));
    // The focused card spans the content; the next one is smaller and
    // starts just past the content's edge, so 8 of the margin's 12 show it.
    expect(front.left, closeTo(stack.left, 1));
    expect(front.right, closeTo(stack.right, 1));
    expect(next.width, closeTo(stack.width * .86, 1));
    expect(next.height, lessThan(front.height));
    expect(next.left, closeTo(stack.right + 4, 1));
    // It can be seen, not used: its check-in is not a target.
    expect(
      find.byKey(const ValueKey('check-in-Read 20 pages')).hitTestable(),
      findsNothing,
    );

    final gesture = await tester.startGesture(stack.center);
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      // Mid-swipe the two cards trade sizes, with the same small gap held
      // between them throughout.
      final out = tester.getRect(find.byKey(const ValueKey('move')));
      final incoming = tester.getRect(find.byKey(const ValueKey('read')));
      expect(incoming.left - out.right, closeTo(4, 1));
      expect(incoming.center.dy, closeTo(out.center.dy, .01));
    }
    await gesture.up();
    await tester.pumpUi();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps pact order and selected card after completing and undoing',
    (tester) async {
      final backend = DashboardBackend();
      backend.pacts.pacts.add(
        const CrewPact(
          id: 'third',
          crewId: 'crew',
          title: 'Stretch',
          frequency: PactFrequency.daily,
          daysPerWeek: 7,
          iconKey: 'run',
        ),
      );
      var week = await backend.fetchWeek('crew');
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return TodayPactsCard(
                  week: week,
                  userId: '',
                  savingPact: null,
                  onToggle: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpUi();
      expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('pact-stack')),
        const Offset(-650, 0),
      );
      await tester.pumpUi();
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('pact-stack')),
        const Offset(-650, 0),
      );
      await tester.pumpUi();
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      backend.selected.add('third');
      final updated = await backend.fetchWeek('crew');
      refresh(() => week = updated);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Completing leaves the card at its size: the celebration is the
      // dialog's, not the card's.
      final before = tester.getRect(find.byKey(const ValueKey('third')));
      await tester.pumpUi();
      final settled = tester.getRect(find.byKey(const ValueKey('third')));
      expect(before.width, settled.width);
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      expect(find.text('Checked in today').hitTestable(), findsOneWidget);
      // The done bar stands exactly where the button stood, so the count
      // and its bar above do not shift by the difference.
      final progress = find.byKey(const ValueKey('pact-progress-third'));
      final progressDone = tester.getRect(progress);
      final actionDone = tester.getRect(
        find.byKey(const ValueKey('check-in-Stretch')),
      );
      backend.selected.remove('third');
      final undone = await backend.fetchWeek('crew');
      refresh(() => week = undone);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('third'))).width,
        settled.width,
      );
      await tester.pumpUi();
      expect(tester.getRect(progress), progressDone);
      expect(
        tester.getRect(find.byKey(const ValueKey('check-in-Stretch'))),
        actionDone,
      );
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      expect(find.text('Check in').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('pact-stack')),
        const Offset(650, 0),
      );
      await tester.pumpUi();
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('moving to another pact gives one haptic tap', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
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
    final week = await DashboardBackend().fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(
          body: TodayPactsCard(
            week: week,
            userId: '',
            savingPact: null,
            onToggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(haptics, isEmpty);
    expect(find.text('Read 20 pages').hitTestable(), findsNothing);
    // A dot per pact under the cards.
    expect(find.byTooltip('Pact 1 of 2'), findsOneWidget);
    expect(find.byTooltip('Pact 2 of 2'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('pact-stack')),
      const Offset(-650, 0),
    );
    await tester.pumpUi();
    expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'many pacts and crew members fit narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = DashboardBackend();
      final original = await backend.fetchWeek('crew');
      final week = CrewWeek(
        today: original.today,
        weekStart: original.weekStart,
        timezone: 'UTC',
        pacts: [
          for (var i = 0; i < 14; i++)
            CrewPact(
              id: '$i',
              crewId: 'crew',
              title: 'Pact $i: Take a long evening walk and stretch after work',
              frequency: PactFrequency.daily,
              daysPerWeek: 7,
              iconKey: 'run',
            ),
        ],
        members: [
          for (var i = 0; i < 18; i++) WeekMember('$i', 'member$i@example.com'),
        ],
        checkIns: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    TodayPactsCard(
                      week: week,
                      userId: '',
                      savingPact: null,
                      onToggle: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpUi();
      expect(find.text('1 of 14'), findsNothing);
      // Fourteen dots still fit a narrow screen, scaled down if they must be.
      expect(find.byTooltip('Pact 1 of 14'), findsOneWidget);
      expect(find.byTooltip('Pact 14 of 14'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the front pact\'s dot is long, and a dot goes to its pact', (
    tester,
  ) async {
    final week = await DashboardBackend().fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPactsCard(
            week: week,
            userId: '',
            savingPact: null,
            onToggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpUi();
    double width(int i) => tester
        .getSize(
          find.descendant(
            of: find.byTooltip('Pact $i of 2'),
            matching: find.byType(Container),
          ),
        )
        .width;
    expect(width(1), greaterThan(width(2)));
    expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip('Pact 2 of 2'));
    await tester.pumpUi();
    expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
    expect(width(2), greaterThan(width(1)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single pact has no dots', (tester) async {
    final backend = DashboardBackend();
    backend.pacts.pacts = [backend.pacts.pacts.first];
    final week = await backend.fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPactsCard(
            week: week,
            userId: '',
            savingPact: null,
            onToggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpUi();
    expect(find.byTooltip('Pact 1 of 1'), findsNothing);
  });
}
