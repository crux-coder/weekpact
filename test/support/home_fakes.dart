import 'dart:async';

import 'package:weekpact/src/goals/goals_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';

class DashboardGoals extends MissingGoalsBackend {
  List<GoalCrew> crews = [
    const GoalCrew(
      id: 'crew',
      name: 'Early Birds',
      timezone: 'UTC',
      isOwner: true,
    ),
  ];
  List<CrewGoal> goals = [
    const CrewGoal(
      id: 'move',
      crewId: 'crew',
      title: 'Move for 30 min',
      frequency: GoalFrequency.daily,
      daysPerWeek: 7,
      iconKey: 'run',
    ),
    const CrewGoal(
      id: 'read',
      crewId: 'crew',
      title: 'Read 20 pages',
      frequency: GoalFrequency.weekly,
      daysPerWeek: 3,
      iconKey: 'book',
    ),
  ];
  @override
  Future<List<GoalCrew>> fetchCrews() async => crews;
  @override
  Future<List<CrewGoal>> fetchGoals(String crewId) async => goals;
}

class DashboardBackend implements HomeBackend {
  DashboardBackend({DashboardGoals? goals}) : goals = goals ?? DashboardGoals();
  final DashboardGoals goals;
  final selected = <String>{'read'};
  bool failSave = false;
  bool failLoad = false;
  int fetches = 0;
  Completer<CrewWeek>? loading;
  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    fetches++;
    if (failLoad) throw StateError('offline');
    if (loading != null) return loading!.future;
    return CrewWeek(
      today: '2026-09-09',
      weekStart: '2026-09-07',
      timezone: 'UTC',
      goals: goals.goals,
      members: const [
        WeekMember('', 'person@example.com'),
        WeekMember('other', 'friend@example.com'),
      ],
      checkIns: selected
          .map((id) => GoalCheckIn(id, '', '2026-09-09'))
          .toList(),
    );
  }

  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> goalIds,
  }) async {
    if (failSave) throw StateError('offline');
    selected
      ..clear()
      ..addAll(goalIds);
  }
}
