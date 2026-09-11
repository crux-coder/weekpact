import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weekpact/src/goals/goals_backend.dart';
import 'package:weekpact/src/goals/goals_page.dart';
import 'package:weekpact/src/goals/goal_icons.dart';
import 'package:weekpact/src/theme/weekpact_theme.dart';

const ownerCrew = GoalCrew(
  id: 'a',
  name: 'Early Birds',
  timezone: 'Europe/Sarajevo',
  isOwner: true,
);
const memberCrew = GoalCrew(
  id: 'b',
  name: 'Weekend Crew',
  timezone: 'UTC',
  isOwner: false,
);

class FakeGoals implements GoalsBackend {
  List<GoalCrew> crews = [ownerCrew, memberCrew];
  final goals = <CrewGoal>[];
  Completer<List<GoalCrew>>? loading;
  bool failSave = false;
  @override
  Future<CrewGoal> updateGoal({
    required String goalId,
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  }) async {
    if (failSave) throw Exception('offline');
    final index = goals.indexWhere(
      (goal) => goal.id == goalId && goal.crewId == crewId,
    );
    return goals[index] = CrewGoal(
      id: goalId,
      crewId: crewId,
      title: title,
      frequency: frequency,
      daysPerWeek: daysPerWeek,
      iconKey: iconKey,
    );
  }

  @override
  Future<List<GoalCrew>> fetchCrews() => loading?.future ?? Future.value(crews);
  @override
  Future<List<CrewGoal>> fetchGoals(String crewId) async =>
      goals.where((goal) => goal.crewId == crewId).toList();
  @override
  Future<CrewGoal> addGoal({
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  }) async {
    if (failSave) throw Exception('offline');
    final goal = CrewGoal(
      id: '${goals.length}',
      crewId: crewId,
      title: title,
      frequency: frequency,
      daysPerWeek: daysPerWeek,
      iconKey: iconKey,
    );
    goals.add(goal);
    return goal;
  }
}

Future<void> pumpGoals(WidgetTester tester, FakeGoals backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: WeekPactTheme.light,
      home: Scaffold(
        body: GoalsPage(backend: backend, onOpenCrews: () {}),
      ),
    ),
  );
}

void main() {
  test('unknown and legacy icons fall back to target', () {
    expect(GoalIcon.find('unknown').key, 'target');
    expect(
      CrewGoal.fromJson({
        'id': '1',
        'crew_id': 'a',
        'title': 'Read',
        'frequency': 'daily',
        'days_per_week': 7,
      }).iconKey,
      'target',
    );
  });
  testWidgets(
    'owner edits an existing goal and retries without losing changes',
    (tester) async {
      final backend = FakeGoals();
      backend.goals.add(
        const CrewGoal(
          id: 'g',
          crewId: 'a',
          title: 'Read',
          frequency: GoalFrequency.weekly,
          daysPerWeek: 3,
          iconKey: 'book',
        ),
      );
      await pumpGoals(tester, backend);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Read'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT GOAL'), findsOneWidget);
      expect(find.byTooltip('Change icon: Reading'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Read',
      );
      await tester.enterText(
        find.byType(TextFormField).first,
        'Read every day',
      );
      await tester.tap(find.text('Every day'));
      backend.failSave = true;
      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load or save'), findsOneWidget);
      expect(backend.goals.single.title, 'Read');
      backend.failSave = false;
      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      expect(backend.goals.single.id, 'g');
      expect(backend.goals.single.title, 'Read every day');
      expect(backend.goals.single.daysPerWeek, 7);
      expect(backend.goals.single.iconKey, 'book');
      expect(find.text('Read every day'), findsOneWidget);
    },
  );

  testWidgets('members cannot see edit actions', (tester) async {
    final backend = FakeGoals()..crews = [memberCrew];
    backend.goals.add(
      const CrewGoal(
        id: 'g',
        crewId: 'b',
        title: 'Read',
        frequency: GoalFrequency.daily,
        daysPerWeek: 7,
      ),
    );
    await pumpGoals(tester, backend);
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
    expect(find.byTooltip('Edit Read'), findsNothing);
  });

  testWidgets('shows skeleton while loading and a crew-specific empty state', (
    tester,
  ) async {
    final backend = FakeGoals()..loading = Completer<List<GoalCrew>>();
    await pumpGoals(tester, backend);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Your goals'), findsOneWidget);
    expect(find.text('ADD GOAL'), findsNothing);
    backend.loading!.complete([ownerCrew]);
    await tester.pumpAndSettle();
    expect(find.text('Small steps start here.'), findsOneWidget);
    expect(find.text('ADD GOAL'), findsOneWidget);
  });

  testWidgets('owner saves daily and weekly goals to the selected crew', (
    tester,
  ) async {
    final backend = FakeGoals();
    await pumpGoals(tester, backend);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ADD GOAL'));
    await tester.tap(find.text('ADD GOAL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE GOAL'));
    await tester.pumpAndSettle();
    expect(find.text('Use 2–100 characters'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Read 20 pages');
    await tester.ensureVisible(find.byTooltip('Change icon: Target'));
    await tester.tap(find.byTooltip('Change icon: Target'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'read');
    await tester.pumpAndSettle();
    expect(find.text('Strength'), findsNothing);
    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change icon: Reading'), findsOneWidget);
    await tester.ensureVisible(find.text('SAVE GOAL'));
    await tester.tap(find.text('SAVE GOAL'));
    await tester.pumpAndSettle();
    expect(backend.goals.single.iconKey, 'book');
    expect(backend.goals.single.daysPerWeek, 7);
    expect(backend.goals.single.frequency, GoalFrequency.daily);
    expect(backend.goals.single.crewId, 'a');
    expect(find.text('Read 20 pages'), findsOneWidget);

    await tester.ensureVisible(find.text('ADD GOAL'));
    await tester.tap(find.text('ADD GOAL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Go for a run');
    await tester.tap(find.text('Days per week'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SAVE GOAL'));
    await tester.tap(find.text('SAVE GOAL'));
    await tester.pumpAndSettle();
    expect(backend.goals.last.frequency, GoalFrequency.weekly);
    expect(backend.goals.last.daysPerWeek, 3);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '3 days / week',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byType(DropdownButton<String>));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekend Crew').last);
    await tester.pumpAndSettle();
    expect(find.text('Read 20 pages'), findsNothing);
    expect(find.text('ADD GOAL'), findsNothing);
    expect(
      find.text('Your crew owner hasn’t added any goals yet.'),
      findsOneWidget,
    );
  });

  testWidgets('failed save retains form and supports retry', (tester) async {
    final backend = FakeGoals()..failSave = true;
    await pumpGoals(tester, backend);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ADD GOAL'));
    await tester.tap(find.text('ADD GOAL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Walk outside');
    await tester.ensureVisible(find.text('SAVE GOAL'));
    await tester.tap(find.text('SAVE GOAL'));
    await tester.pumpAndSettle();
    expect(find.text('Walk outside'), findsOneWidget);
    expect(
      find.text(
        'Could not load or save goals. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    backend.failSave = false;
    await tester.ensureVisible(find.text('SAVE GOAL'));
    await tester.tap(find.text('SAVE GOAL'));
    await tester.pumpAndSettle();
    expect(backend.goals.length, 1);
    expect(find.text('ADD A GOAL'), findsNothing);
  });

  testWidgets('users without crews get a crews action', (tester) async {
    await pumpGoals(tester, FakeGoals()..crews = []);
    await tester.pumpAndSettle();
    expect(find.text('GO TO CREWS'), findsOneWidget);
    expect(find.text('ADD GOAL'), findsNothing);
  });
}
