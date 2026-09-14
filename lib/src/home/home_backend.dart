import '../recaps/weekly_recap.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../pacts/pacts_backend.dart';
import 'avatar_url_cache.dart';

class WeekMember {
  const WeekMember(
    this.id,
    this.email, {
    this.displayName = '',
    this.avatarPath,
    this.avatarUrl,
  });
  final String displayName;
  final String? avatarPath;
  final String? avatarUrl;
  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty || displayName == 'Crew member') return '?';
    return (parts.first.characters.first +
            (parts.length > 1 ? parts.last.characters.first : ''))
        .toUpperCase();
  }

  WeekMember withAvatar(String? url) => WeekMember(
    id,
    email,
    displayName: displayName,
    avatarPath: avatarPath,
    avatarUrl: url,
  );
  final String id;
  final String email;
}

class PactCheckIn {
  const PactCheckIn(this.pactId, this.userId, this.day);
  final String pactId;
  final String userId;
  final String day;
}

class CrewActivity {
  const CrewActivity({
    required this.pactId,
    required this.userId,
    required this.createdAt,
    this.completedOn,
    this.pactTitle,
  });

  final String pactId;
  final String userId;
  final DateTime createdAt;
  final String? completedOn;
  final String? pactTitle;

  factory CrewActivity.fromJson(Map<String, dynamic> row) => CrewActivity(
    pactId: row['pact_id'] as String,
    userId: row['user_id'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    completedOn: row['completed_on'] as String?,
    pactTitle: (row['crew_pacts'] as Map?)?['title'] as String?,
  );
}

enum CrewNudgeStatus { ready, sent, cooldown, checkedIn, unavailable }

class CrewNudgeState {
  const CrewNudgeState(this.status, {this.nextAllowedAt});
  final CrewNudgeStatus status;
  final DateTime? nextAllowedAt;

  factory CrewNudgeState.fromJson(Map<String, dynamic> row) => CrewNudgeState(
    switch (row['status']) {
      'ready' => CrewNudgeStatus.ready,
      'sent' => CrewNudgeStatus.sent,
      'cooldown' => CrewNudgeStatus.cooldown,
      'checked_in' => CrewNudgeStatus.checkedIn,
      'unavailable' => CrewNudgeStatus.unavailable,
      _ => throw const FormatException('Unknown nudge status'),
    },
    nextAllowedAt: row['next_allowed_at'] == null
        ? null
        : DateTime.parse(row['next_allowed_at'] as String),
  );
}

class CrewWeek {
  const CrewWeek({
    required this.today,
    required this.weekStart,
    required this.timezone,
    required this.pacts,
    required this.members,
    required this.checkIns,
    this.streakWeeks = 0,
    this.latestActivity,
  });
  final CrewActivity? latestActivity;
  final int streakWeeks;
  final String today;
  final String weekStart;
  final String timezone;
  final List<CrewPact> pacts;
  final List<WeekMember> members;
  final List<PactCheckIn> checkIns;

  factory CrewWeek.fromJson(Map<String, dynamic> row) => CrewWeek(
    streakWeeks: row['streak_weeks'] as int? ?? 0,
    today: row['today'] as String,
    weekStart: row['week_start'] as String,
    timezone: row['timezone'] as String,
    pacts: (row['pacts'] as List)
        .map((g) => CrewPact.fromJson(Map<String, dynamic>.from(g)))
        .toList(),
    members: (row['members'] as List)
        .map(
          (m) => WeekMember(
            m['user_id'] as String,
            m['email'] as String,
            displayName: m['display_name'] as String? ?? '',
            avatarPath: m['avatar_path'] as String?,
          ),
        )
        .toList(),
    checkIns: (row['check_ins'] as List)
        .map(
          (i) => PactCheckIn(
            i['pact_id'] as String,
            i['user_id'] as String,
            i['completed_on'] as String,
          ),
        )
        .toList(),
  );

  int days(String pactId, String userId) => checkIns
      .where(
        (i) =>
            i.pactId == pactId &&
            i.userId == userId &&
            i.day.compareTo(weekStart) >= 0 &&
            i.day.compareTo(today) <= 0,
      )
      .map((i) => i.day)
      .toSet()
      .length;
  Set<String> checkedToday(String userId) => checkIns
      .where((i) => i.userId == userId && i.day == today)
      .map((i) => i.pactId)
      .toSet();
  int get target => pacts.fold(0, (sum, g) => sum + g.daysPerWeek);
  int completed(String userId) => pacts.fold(
    0,
    (sum, g) => sum + math.min(g.daysPerWeek, days(g.id, userId)),
  );
  int percent(String userId) =>
      target == 0 ? 0 : (100 * completed(userId) / target).round();
  int get percentCrew => target == 0 || members.isEmpty
      ? 0
      : (100 *
                members.fold(0, (sum, m) => sum + completed(m.id)) /
                (target * members.length))
            .round();
  int pactCompleted(CrewPact pact) => members.fold(
    0,
    (sum, m) => sum + math.min(pact.daysPerWeek, days(pact.id, m.id)),
  );
  int pactDoneToday(String pactId) =>
      members.where((m) => checkedToday(m.id).contains(pactId)).length;
  bool onTrack(String userId) {
    final daysLeft = 7 - DateTime.parse(today).weekday;
    return pacts.every(
      (g) =>
          days(g.id, userId) +
              daysLeft +
              (checkedToday(userId).contains(g.id) ? 0 : 1) >=
          g.daysPerWeek,
    );
  }
}

abstract interface class HomeBackend {
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId);
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  });
  Future<CrewWeek> fetchWeek(String crewId);
  Future<List<CrewActivity>> fetchActivity(
    String crewId, {
    CrewActivity? before,
    int limit = 20,
  });
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
  });
}

class SupabaseHomeBackend implements HomeBackend, RecapBackend {
  @override
  Future<WeeklyRecap?> fetchRecap(String crewId, {String? markSeen}) =>
      SupabaseRecapBackend(client).fetchRecap(crewId, markSeen: markSeen);
  SupabaseHomeBackend(this.client);
  final _avatarUrls = AvatarUrlCache();
  final SupabaseClient client;
  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) async {
    final rows = await client.rpc(
      'crew_nudge_status',
      params: {'target_crew_id': crewId},
    );
    return {
      for (final row in rows as List)
        row['recipient_id'] as String: CrewNudgeState.fromJson(
          Map<String, dynamic>.from(row),
        ),
    };
  }

  @override
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  }) async => CrewNudgeState.fromJson(
    Map<String, dynamic>.from(
      await client.rpc(
        'send_crew_nudge',
        params: {'target_crew_id': crewId, 'target_user_id': recipientId},
      ),
    ),
  );
  @override
  Future<List<CrewActivity>> fetchActivity(
    String crewId, {
    CrewActivity? before,
    int limit = 20,
  }) async {
    var query = client
        .from('pact_check_ins')
        .select(
          'pact_id,user_id,completed_on,created_at,crew_pacts!inner(title,crew_id)',
        )
        .eq('crew_pacts.crew_id', crewId);
    if (before != null) {
      final timestamp = before.createdAt.toUtc().toIso8601String();
      // Include the complete primary key to preserve check-ins with equal
      // timestamps, including several pacts saved in the same transaction.
      query = query.or(
        'created_at.lt.$timestamp,'
        'and(created_at.eq.$timestamp,pact_id.lt.${before.pactId}),'
        'and(created_at.eq.$timestamp,pact_id.eq.${before.pactId},user_id.lt.${before.userId}),'
        'and(created_at.eq.$timestamp,pact_id.eq.${before.pactId},user_id.eq.${before.userId},completed_on.lt.${before.completedOn})',
      );
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('pact_id', ascending: false)
        .order('user_id', ascending: false)
        .order('completed_on', ascending: false)
        .limit(limit);
    return rows.map(CrewActivity.fromJson).toList();
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final row = Map<String, dynamic>.from(
      await client.rpc(
        'crew_week_snapshot',
        params: {'target_crew_id': crewId},
      ),
    );
    final week = CrewWeek.fromJson(row);
    // The snapshot supplies today in the crew timezone. Keep activity on that
    // same date; insertion time only determines which check-in is most recent.
    final activity = week.pacts.isEmpty || week.members.isEmpty
        ? null
        : await client
              .from('pact_check_ins')
              .select('pact_id,user_id,created_at')
              .inFilter('pact_id', week.pacts.map((pact) => pact.id).toList())
              .inFilter(
                'user_id',
                week.members.map((member) => member.id).toList(),
              )
              .eq('completed_on', week.today)
              .order('created_at', ascending: false)
              .order('pact_id')
              .order('user_id')
              .limit(1)
              .maybeSingle();
    final paths = week.members
        .where((m) => m.avatarPath == '${m.id}/avatar.png')
        .map((m) => m.avatarPath!)
        .toList();
    final urls = await _avatarUrls.resolve(
      scope: '${client.auth.currentUser?.id}:$crewId',
      paths: paths,
      sign: (missing, lifetime) async {
        final signed = await client.storage
            .from('avatars')
            .createSignedUrlsResult(missing, lifetime);
        return {
          for (final result in signed)
            if (result is SignedUrlSuccess) result.path: result.signedUrl,
        };
      },
    );
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      members: week.members
          .map((m) => m.withAvatar(urls[m.avatarPath]))
          .toList(),
      checkIns: week.checkIns,
      streakWeeks: week.streakWeeks,
      latestActivity: activity == null ? null : CrewActivity.fromJson(activity),
    );
  }

  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
  }) async {
    await client.rpc(
      'save_pact_check_ins',
      params: {
        'target_crew_id': crewId,
        'expected_today': today,
        'selected_pact_ids': pactIds.toList(),
      },
    );
  }
}

class MissingHomeBackend implements HomeBackend {
  const MissingHomeBackend();
  @override
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<List<CrewActivity>> fetchActivity(
    String crewId, {
    CrewActivity? before,
    int limit = 20,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<CrewWeek> fetchWeek(String crewId) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
  }) => Future.error(StateError('Supabase is not configured.'));
}
