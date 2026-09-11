import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/goals/goals_overview.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

import 'support/home_fakes.dart';

void main() {
  testWidgets('weekly rhythm sums goal targets, not completed check-ins', (
    tester,
  ) async {
    final goals = DashboardGoals().goals;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(body: WeeklyRhythmCard(goals: goals)),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('weekly-rhythm-target')))
          .data,
      '10',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeekPactTheme.dark,
        home: Scaffold(body: WeeklyRhythmCard(goals: goals.take(1).toList())),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('weekly-rhythm-target')))
          .data,
      '7',
    );
  });

  for (final settings in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('goal cards stay square and editable at $settings', (
      tester,
    ) async {
      tester.view.physicalSize = Size(settings.$1, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? edited;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeekPactTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(settings.$2)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: GoalSquareGrid(
                  goals: DashboardGoals().goals,
                  onEdit: (goal) => edited = goal.id,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final first = tester.getRect(
        find.byKey(const ValueKey('goal-management-move')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('goal-management-read')),
      );
      expect(first.width, first.height);
      expect(second.width, second.height);
      if (settings.$2 == 1) {
        expect(first.top, second.top);
      } else {
        expect(second.top, greaterThan(first.bottom));
      }
      await tester.tap(find.byTooltip('Edit Move for 30 min'));
      expect(edited, 'move');
    });
  }
}
