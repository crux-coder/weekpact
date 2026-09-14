import 'package:flutter/services.dart';

import 'support/pump_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets('cards stay centered and stop at both ends', (tester) async {
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
      expect(find.text('0${index + 1} / 03'), findsOneWidget);
      final card = tester.getRect(find.byKey(ValueKey(pact.id)).hitTestable());
      final stack = tester.getRect(find.byKey(const ValueKey('pact-stack')));
      expect(
        tester
            .widget<Opacity>(
              find.byKey(ValueKey('pact-content-opacity-${pact.id}')),
            )
            .opacity,
        1,
      );
      expect(card.center.dx, closeTo(stack.center.dx, 1));
      expect(card.left, greaterThan(stack.left));
      expect(card.right, lessThan(stack.right));
      if (index > 0) {
        final previousPact = week.pacts[index - 1];
        final previous = tester.getRect(find.byKey(ValueKey(previousPact.id)));
        expect(
          tester
              .widget<Opacity>(
                find.byKey(ValueKey('pact-content-opacity-${previousPact.id}')),
              )
              .opacity,
          closeTo(.2, .001),
        );
        expect(previous.left, lessThan(stack.left));
        expect(previous.right, greaterThan(stack.left + 10));
        expect(previous.right, lessThan(card.left));
        expect(previous.top, closeTo(card.top, 1));
        expect(previous.bottom, closeTo(card.bottom, 1));
        expect(
          find.byKey(ValueKey('check-in-${previousPact.title}')).hitTestable(),
          findsNothing,
        );
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
    await swipe(-650, 2);
    expect(
      find.byKey(const ValueKey('pact-icon-move')).hitTestable(),
      findsNothing,
    );
    final returningContent = find.byKey(
      const ValueKey('pact-content-opacity-read'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('pact-stack'))),
    );
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    var previousOpacity = tester.widget<Opacity>(returningContent).opacity;
    for (var frame = 0; frame < 5; frame++) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final opacity = tester.widget<Opacity>(returningContent).opacity;
      expect(opacity, greaterThan(previousOpacity));
      expect(opacity, lessThan(1));
      previousOpacity = opacity;
    }
    await gesture.moveBy(const Offset(450, 0));
    await gesture.up();
    await tester.pumpUi();
    expectSelected(1);
    await swipe(650, 0);
    await swipe(650, 0);
  });

  testWidgets(
    'icons grow at the top-right anchor and active content fills the card',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final card = tester.getRect(nearestCopy(tester, const ValueKey('move')));
      final button = tester.getRect(
        find.byKey(const ValueKey('check-in-Move for 30 min')).hitTestable(),
      );
      final dashes = tester.getRect(
        find.byKey(const ValueKey('pact-progress-move')).hitTestable(),
      );
      expect(button.left, closeTo(card.left + 12, 1));
      expect(button.right, closeTo(card.right - 12, 1));
      expect(dashes.width, closeTo(button.width, 1));
      final fullIcon = tester
          .getRect(nearestCopy(tester, const ValueKey('pact-icon-move')))
          .width;
      final icon = nearestCopy(tester, const ValueKey('pact-icon-read'));
      final initialIcon = tester.getRect(icon).width;
      final incomingCard = nearestCopy(tester, const ValueKey('read'));
      final incomingBounds = tester.getRect(incomingCard);
      final rightInset =
          (incomingBounds.right - tester.getRect(icon).right) /
          incomingBounds.width;
      final topInset =
          (tester.getRect(icon).top - incomingBounds.top) /
          incomingBounds.height;
      expect(initialIcon, lessThan(fullIcon));
      final activeIconBounds = tester.getRect(
        nearestCopy(tester, const ValueKey('pact-icon-move')),
      );
      expect(activeIconBounds.top, closeTo(card.top + 12, 1));
      expect(activeIconBounds.right, closeTo(card.right - 12, 1));
      expect(find.text('Read 20 pages').hitTestable(), findsNothing);
      expect(find.text('Stretch').hitTestable(), findsNothing);
      final gesture = await tester.startGesture(card.center);
      await gesture.moveBy(const Offset(-24, 0));
      await tester.pump();
      var previous = initialIcon;
      for (var frame = 0; frame < 5; frame++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 16));
        final iconBounds = tester.getRect(icon);
        final cardBounds = tester.getRect(incomingCard);
        expect(
          (cardBounds.right - iconBounds.right) / cardBounds.width,
          closeTo(rightInset, .001),
        );
        expect(
          (iconBounds.top - cardBounds.top) / cardBounds.height,
          closeTo(topInset, .001),
        );
        final size = iconBounds.width;
        expect(size, greaterThanOrEqualTo(previous - .01));
        previous = size;
      }
      expect(previous, greaterThan(initialIcon));
      expect(previous, lessThan(fullIcon));
      await gesture.moveBy(const Offset(-180, 0));
      await gesture.up();
      await tester.pumpUi();
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      expect(
        tester
            .getRect(nearestCopy(tester, const ValueKey('pact-icon-read')))
            .width,
        closeTo(fullIcon, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('swiping card stays within the vertical clipping bounds', (
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
            child: TodayPactsCard(
              week: week,
              height: 400,
              horizontalBleed: 12,
              userId: '',
              savingPact: null,
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    Finder pactCopy() => nearestCopy(tester, const ValueKey('move'));
    final pact = pactCopy();
    Rect paintedBounds(Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
    }

    final restingBottom = paintedBounds(pact).bottom;
    void checkFrame() {
      if (pact.evaluate().isEmpty) return;
      final box = tester.renderObject<RenderBox>(pact);
      // A slide must remain upright even while the pointer is moving.
      expect(box.getTransformTo(null).storage[1], closeTo(0, .001));
      final bounds = paintedBounds(pact);
      final clips = find.ancestor(of: pact, matching: find.byType(ClipRect));
      expect(clips, findsWidgets);
      for (final clip in clips.evaluate()) {
        final clipBox = clip.renderObject! as RenderBox;
        final viewport = MatrixUtils.transformRect(
          clipBox.getTransformTo(null),
          Offset.zero & clipBox.size,
        );
        expect(bounds.top, greaterThanOrEqualTo(viewport.top - 1));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      }
      final incoming = paintedBounds(
        nearestCopy(tester, const ValueKey('read')),
      );
      expect(incoming.bottom, lessThanOrEqualTo(restingBottom + 1));
      expect(
        incoming.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('pact-stack'))).top,
        ),
      );
    }

    final gesture = await tester.startGesture(tester.getCenter(pact));
    for (var step = 0; step < 13; step++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
      checkFrame();
    }
    await gesture.up();
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      checkFrame();
    }
    await tester.pumpUi();
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
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.byKey(const ValueKey('pact-completion-effect')),
        findsWidgets,
      );
      await tester.pumpUi();
      expect(
        find.byKey(const ValueKey('pact-completion-effect')),
        findsNothing,
      );
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      expect(find.text('Checked in today').hitTestable(), findsOneWidget);
      backend.selected.remove('third');
      final undone = await backend.fetchWeek('crew');
      refresh(() => week = undone);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('pact-completion-effect')),
        findsNothing,
      );
      await tester.pumpUi();
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      expect(find.text('Mark done').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('pact-stack')),
        const Offset(650, 0),
      );
      await tester.pumpUi();
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'slide and stack keeps the selected card upright and provides haptics',
    (tester) async {
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
              horizontalBleed: 12,
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
      final first = nearestCopy(tester, const ValueKey('pact-slide-stack-0'));
      expect(
        tester.widget<Transform>(first).transform.storage[1],
        closeTo(0, .001),
      );
      final front = tester.getRect(nearestCopy(tester, const ValueKey('move')));
      final behind = tester.getRect(
        nearestCopy(tester, const ValueKey('read')),
      );
      expect(behind.right, greaterThan(front.right));
      expect(behind.top, greaterThan(front.top));
      expect(behind.bottom, lessThan(front.bottom));
      final previewIcon = tester.getRect(
        nearestCopy(tester, const ValueKey('pact-icon-read')),
      );
      expect(previewIcon.left, greaterThan(front.right));
      expect(previewIcon.right, lessThan(behind.right));
      expect(find.text('Read 20 pages').hitTestable(), findsNothing);
      final activeIcon = tester.getRect(
        nearestCopy(tester, const ValueKey('pact-icon-move')),
      );
      expect(previewIcon.width, lessThan(activeIcon.width));
      expect(behind.width, lessThan(front.width));
      await tester.tap(find.byTooltip('Pact 2 of 2'));
      await tester.pumpUi();
      expect(
        tester
            .widget<Transform>(
              nearestCopy(tester, const ValueKey('pact-slide-stack-1')),
            )
            .transform
            .storage[1],
        closeTo(0, .001),
      );
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      expect(
        tester
            .getRect(nearestCopy(tester, const ValueKey('pact-icon-read')))
            .width,
        greaterThan(previewIcon.width),
      );
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      await tester.tap(find.byTooltip('Pact 2 of 2'));
      await tester.pumpUi();
      expect(haptics, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

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
              title: 'Pact $i',
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
                    TodayCrewCard(
                      week: week,
                      userId: '',
                      crewName: 'Early Birds',
                      onOpen: () {},
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
      expect(find.byTooltip('Pact 5 of 14'), findsOneWidget);
      expect(find.byTooltip('Pact 6 of 14'), findsNothing);
      expect(find.textContaining(RegExp(r'^\+\d+$')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

// Looping renders extra copies; inspect the largest copy nearest the viewport.
Finder nearestCopy(WidgetTester tester, Key key) {
  final candidates = find.byKey(key).evaluate().toList();
  final center = tester.getCenter(find.byKey(const ValueKey('pact-stack')));
  double score(Element element) {
    final box = element.renderObject! as RenderBox;
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return bounds.width - (bounds.center.dx - center.dx).abs() * 10;
  }

  candidates.sort((a, b) => score(b).compareTo(score(a)));
  return find.byElementPredicate(
    (element) => identical(element, candidates.first),
  );
}
