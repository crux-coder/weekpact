import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/goals/goals_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';
import 'package:weekpact/src/home/today_widgets.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets(
    'swipes unfinished goals first and moves saved goals behind them',
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
      await tester.pumpAndSettle();
      expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('goal-stack')),
        const Offset(-650, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stretch').hitTestable(), findsOneWidget);
      backend.selected.add('third');
      final updated = await backend.fetchWeek('crew');
      refresh(() => week = updated);
      await tester.pumpAndSettle();
      expect(find.text('Move for 30 min').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('goal-stack')),
        const Offset(-650, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read 20 pages').hitTestable(), findsOneWidget);
      expect(find.text('Undo check-in').hitTestable(), findsOneWidget);
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
      await tester.pumpAndSettle();
      expect(find.text('1 of 14'), findsNothing);
      expect(find.byTooltip('Goal 5 of 14'), findsOneWidget);
      expect(find.byTooltip('Goal 6 of 14'), findsNothing);
      expect(find.text('+13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
