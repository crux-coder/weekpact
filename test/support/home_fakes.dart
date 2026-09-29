import 'dart:typed_data';
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
  /// The member the fake treats as the person holding the phone. It has to
  /// match the signed-in user's id, or a check-in lands on a stranger and the
  /// page keeps offering "Check in".
  final String viewerId;

  @override
  Future<Uint8List> fetchCheckInPhoto(String path) =>
      Future.error(StateError('Photo unavailable'));
  DashboardBackend({DashboardPacts? pacts, this.viewerId = ''})
    : pacts = pacts ?? DashboardPacts();
  final DashboardPacts pacts;
  final selected = <String>{'read'};
  Map<String, Uint8List> lastPhotos = {};
  bool failSave = false;
  bool failLoad = false;
  int fetches = 0;
  Completer<CrewWeek>? loading;
  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async =>
      {};
  @override
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  }) async => const CrewNudgeState(CrewNudgeStatus.unavailable);
  @override
  Future<List<CrewActivity>> fetchActivity(
    String crewId, {
    CrewActivity? before,
    int limit = 20,
  }) async => [];

  /// Notifications the fake hands back, newest first. Tests that care set it;
  /// everything else gets an empty list and a quiet badge.
  List<NotificationEntry> notifications = const [];
  int unreadNotifications = 0;
  DateTime? markedReadUpTo;
  int notificationPages = 0;
  bool failNotifications = false;
  @override
  Future<List<NotificationEntry>> fetchNotifications({
    NotificationEntry? before,
    int limit = 20,
  }) async {
    notificationPages++;
    if (failNotifications) throw StateError('Notifications unavailable');
    final start = before == null
        ? 0
        : notifications.indexWhere((entry) => entry.eventId == before.eventId) +
              1;
    if (start <= 0 && before != null) return [];
    return notifications.skip(start).take(limit).toList();
  }

  @override
  Future<int> fetchUnreadNotificationCount() async => unreadNotifications;

  @override
  Future<void> markNotificationsRead({DateTime? upTo}) async {
    markedReadUpTo = upTo;
    unreadNotifications = 0;
  }

  @override
  Future<int> setClap({
    required String pactId,
    required String userId,
    required String day,
    required bool clapped,
  }) async => clapped ? 1 : 0;
  /// Finished weeks the fake hands back, newest first, and the week the page
  /// last asked for, so a test can tell which week was opened.
  List<CrewWeekSummary> history = const [];
  bool failHistory = false;
  final requestedWeeks = <String?>[];
  @override
  Future<List<CrewWeekSummary>> fetchWeekHistory(
    String crewId, {
    String? before,
    int limit = 12,
  }) async {
    if (failHistory) throw StateError('offline');
    final start = before == null
        ? 0
        : history.indexWhere((week) => week.weekStart == before) + 1;
    return history.skip(start).take(limit).toList();
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
    fetches++;
    requestedWeeks.add(weekStart);
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
              userId: viewerId,
              createdAt: DateTime.utc(2026, 9, 9, 10),
            ),
      members: [
        WeekMember(viewerId, 'person@example.com'),
        const WeekMember('other', 'friend@example.com'),
      ],
      checkIns: selected
          .map((id) => PactCheckIn(id, viewerId, '2026-09-09'))
          .toList(),
    );
  }

  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
    Map<String, Uint8List> photos = const {},
  }) async {
    if (failSave) throw StateError('offline');
    for (final id in pactIds.difference(selected)) {
      final pact = pacts.pacts.firstWhere((pact) => pact.id == id);
      if (pact.photoRequired && photos[id]?.isNotEmpty != true) {
        throw StateError('Take a photo to check in.');
      }
    }
    lastPhotos = Map.of(photos);
    selected
      ..clear()
      ..addAll(pactIds);
  }
}
