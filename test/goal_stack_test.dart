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
        findsOneWidget,
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

  testWidgets('coverflow centers the selected card and angles its neighbor', (
    tester,
  ) async {
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
    final first = find.byKey(const ValueKey('goal-coverflow-0'));
    final second = find.byKey(const ValueKey('goal-coverflow-1'));
    expect(
      tester.widget<Transform>(first).transform.storage[2],
      closeTo(0, .001),
    );
    expect(
      tester.widget<Transform>(second).transform.storage[2].abs(),
      greaterThan(.1),
    );
    await tester.tap(find.byTooltip('Goal 2 of 2'));
    await tester.pumpUi();
    expect(
      tester.widget<Transform>(second).transform.storage[2],
      closeTo(0, .001),
    );
    expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    await tester.tap(find.byTooltip('Goal 2 of 2'));
    await tester.pumpUi();
    expect(haptics, hasLength(1));
    expect(tester.takeException(), isNull);
  });

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
