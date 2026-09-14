import 'dart:async';

import 'package:weekpact/src/pacts/pacts_backend.dart';
import 'package:weekpact/src/home/home_backend.dart';

class DashboardPacts extends MissingPactsBackend {
  List<PactCrew> crews = [
    const PactCrew(
      id: 'crew',
      name: 'Early Birds',
      timezone: 'UTC',
      isOwner: true,
    ),
  ];
  List<CrewPact> pacts = [
    const CrewPact(
      id: 'move',
      crewId: 'crew',
      title: 'Move for 30 min',
      frequency: PactFrequency.daily,
      daysPerWeek: 7,
      iconKey: 'run',
    ),
    const CrewPact(
      id: 'read',
      crewId: 'crew',
      title: 'Read 20 pages',
      frequency: PactFrequency.weekly,
      daysPerWeek: 3,
      iconKey: 'book',
    ),
  ];
  @override
  Future<List<PactCrew>> fetchCrews() async => crews;
  @override
  Future<List<CrewPact>> fetchPacts(String crewId) async => pacts;
}

class DashboardBackend implements HomeBackend {
  DashboardBackend({DashboardPacts? pacts}) : pacts = pacts ?? DashboardPacts();
  final DashboardPacts pacts;
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
      pacts: pacts.pacts,
      latestActivity: selected.isEmpty
          ? null
          : CrewActivity(
              pactId: selected.last,
              userId: '',
              createdAt: DateTime.utc(2026, 9, 9, 10),
            ),
      members: const [
        WeekMember('', 'person@example.com'),
        WeekMember('other', 'friend@example.com'),
      ],
      checkIns: selected
          .map((id) => PactCheckIn(id, '', '2026-09-09'))
          .toList(),
    );
  }

  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
  }) async {
    if (failSave) throw StateError('offline');
    selected
      ..clear()
      ..addAll(pactIds);
  }
}
