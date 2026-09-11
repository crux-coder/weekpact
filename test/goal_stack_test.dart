import 'package:flutter/services.dart';

import 'support/pump_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/goals/goals_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets('carousel wraps repeatedly in both directions', (tester) async {
    final week = await DashboardBackend().fetchWeek('crew');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayGoalsCard(
            week: week,
            userId: '',
            savingGoal: null,
            onToggle: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpUi();
    for (final direction in [-1, 1]) {
      for (var step = 0; step < 6; step++) {
        await tester.drag(
          find.byKey(const ValueKey('goal-stack')),
          Offset(direction * 650.0, 0),
        );
        await tester.pumpUi();
        expect(
          find
              .text(step.isEven ? 'Read 20 pages' : 'Move for 30 min')
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

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
            child: TodayGoalsCard(
              week: week,
              height: 400,
              horizontalBleed: 12,
              userId: '',
              savingGoal: null,
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpUi();
    Finder goalCopy() => nearestCopy(tester, const ValueKey('move'));
    final goal = goalCopy();
    Rect paintedBounds(Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
    }

    final restingBottom = paintedBounds(goal).bottom;
    void checkFrame() {
      if (goal.evaluate().isEmpty) return;
      final box = tester.renderObject<RenderBox>(goal);
      // A slide must remain upright even while the pointer is moving.
      expect(box.getTransformTo(null).storage[1], closeTo(0, .001));
      final bounds = paintedBounds(goal);
      final clips = find.ancestor(of: goal, matching: find.byType(ClipRect));
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
      expect(incoming.bottom, lessThanOrEqualTo(restingBottom + 8));
      expect(incoming.bottom, greaterThanOrEqualTo(restingBottom - 1));
    }

    final gesture = await tester.startGesture(tester.getCenter(goal));
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
    'keeps goal order and selected card after completing and undoing',
    (tester) async {
      final backend = DashboardBackend();
      backend.goals.goals.add(
        const CrewGoal(
          id: 'third',
          crewId: 'crew',
          title: 'Stretch',
          frequency: GoalFrequency.daily,
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
                return TodayGoalsCard(
                  week: week,
                  userId: '',
                  savingGoal: null,
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
        find.byKey(const ValueKey('goal-stack')),
        const Offset(-650, 0),
      );
      await tester.pumpUi();
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('goal-stack')),
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
        find.byKey(const ValueKey('goal-completion-effect')),
        findsWidgets,
      );
      await tester.pumpUi();
      expect(
        find.byKey(const ValueKey('goal-completion-effect')),
        findsNothing,
      );
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      expect(find.text('Undo check-in').hitTestable(), findsOneWidget);
      backend.selected.remove('third');
      final undone = await backend.fetchWeek('crew');
      refresh(() => week = undone);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('goal-completion-effect')),
        findsNothing,
      );
      await tester.pumpUi();
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      expect(find.text('Mark done').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('goal-stack')),
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
            body: TodayGoalsCard(
              horizontalBleed: 12,
              week: week,
              userId: '',
              savingGoal: null,
              onToggle: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpUi();
      expect(haptics, isEmpty);
      final first = nearestCopy(tester, const ValueKey('goal-slide-stack-0'));
      expect(
        tester.widget<Transform>(first).transform.storage[1],
        closeTo(0, .001),
      );
      final front = tester.getRect(nearestCopy(tester, const ValueKey('move')));
      final behind = tester.getRect(
        nearestCopy(tester, const ValueKey('read')),
      );
      expect(behind.bottom, greaterThan(front.bottom));
      expect(behind.bottom - front.bottom, lessThan(12));
      expect(behind.width, lessThan(front.width));
      await tester.tap(find.byTooltip('Goal 2 of 2'));
      await tester.pumpUi();
      expect(
        tester
            .widget<Transform>(
              nearestCopy(tester, const ValueKey('goal-slide-stack-1')),
            )
            .transform
            .storage[1],
        closeTo(0, .001),
      );
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      await tester.tap(find.byTooltip('Goal 2 of 2'));
      await tester.pumpUi();
      expect(haptics, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'many goals and crew members fit narrow screens with large text',
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
        goals: [
          for (var i = 0; i < 14; i++)
            CrewGoal(
              id: '$i',
              crewId: 'crew',
              title: 'Goal $i',
              frequency: GoalFrequency.daily,
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
                    TodayGoalsCard(
                      week: week,
                      userId: '',
                      savingGoal: null,
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
      expect(find.byTooltip('Goal 5 of 14'), findsOneWidget);
      expect(find.byTooltip('Goal 6 of 14'), findsNothing);
      expect(find.textContaining(RegExp(r'^\+\d+$')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

// Looping renders extra copies; inspect the largest copy nearest the viewport.
Finder nearestCopy(WidgetTester tester, Key key) {
  final candidates = find.byKey(key).evaluate().toList();
  final center = tester.getCenter(find.byKey(const ValueKey('goal-stack')));
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
