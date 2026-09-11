import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../goals/goals_backend.dart';

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

class GoalCheckIn {
  const GoalCheckIn(this.goalId, this.userId, this.day);
  final String goalId;
  final String userId;
  final String day;
}

class CrewWeek {
  const CrewWeek({
    required this.today,
    required this.weekStart,
    required this.timezone,
    required this.goals,
    required this.members,
    required this.checkIns,
    this.streakWeeks = 0,
  });
  final int streakWeeks;
  final String today;
  final String weekStart;
  final String timezone;
  final List<CrewGoal> goals;
  final List<WeekMember> members;
  final List<GoalCheckIn> checkIns;

  factory CrewWeek.fromJson(Map<String, dynamic> row) => CrewWeek(
    streakWeeks: row['streak_weeks'] as int? ?? 0,
    today: row['today'] as String,
    weekStart: row['week_start'] as String,
    timezone: row['timezone'] as String,
    goals: (row['goals'] as List)
        .map((g) => CrewGoal.fromJson(Map<String, dynamic>.from(g)))
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
          (i) => GoalCheckIn(
            i['goal_id'] as String,
            i['user_id'] as String,
            i['completed_on'] as String,
          ),
        )
        .toList(),
  );

  int days(String goalId, String userId) => checkIns
      .where(
        (i) =>
            i.goalId == goalId &&
            i.userId == userId &&
            i.day.compareTo(weekStart) >= 0 &&
            i.day.compareTo(today) <= 0,
      )
      .map((i) => i.day)
      .toSet()
      .length;
  Set<String> checkedToday(String userId) => checkIns
      .where((i) => i.userId == userId && i.day == today)
      .map((i) => i.goalId)
      .toSet();
  int get target => goals.fold(0, (sum, g) => sum + g.daysPerWeek);
  int completed(String userId) => goals.fold(
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
  int goalCompleted(CrewGoal goal) => members.fold(
    0,
    (sum, m) => sum + math.min(goal.daysPerWeek, days(goal.id, m.id)),
  );
  int goalDoneToday(String goalId) =>
      members.where((m) => checkedToday(m.id).contains(goalId)).length;
  bool onTrack(String userId) {
    final daysLeft = 7 - DateTime.parse(today).weekday;
    return goals.every(
      (g) =>
          days(g.id, userId) +
              daysLeft +
              (checkedToday(userId).contains(g.id) ? 0 : 1) >=
          g.daysPerWeek,
    );
  }
}

abstract interface class HomeBackend {
  Future<CrewWeek> fetchWeek(String crewId);
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> goalIds,
  });
}

class SupabaseHomeBackend implements HomeBackend {
  const SupabaseHomeBackend(this.client);
  final SupabaseClient client;
  @override
  Future<CrewWeek> fetchWeek(String crewId) async {
    final row = Map<String, dynamic>.from(
      await client.rpc(
        'crew_week_snapshot',
        params: {'target_crew_id': crewId},
      ),
    );
    final week = CrewWeek.fromJson(row);
    final paths = week.members
        .where((m) => m.avatarPath == '${m.id}/avatar.png')
        .map((m) => m.avatarPath!)
        .toList();
    final urls = <String, String>{};
    if (paths.isNotEmpty) {
      try {
        final signed = await client.storage
            .from('avatars')
            .createSignedUrlsResult(paths, 300);
        for (final result in signed) {
          if (result is SignedUrlSuccess) urls[result.path] = result.signedUrl;
        }
      } catch (_) {
        /* Profile images must not prevent loading check-ins. */
      }
    }
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      goals: week.goals,
      members: week.members
          .map((m) => m.withAvatar(urls[m.avatarPath]))
          .toList(),
      checkIns: week.checkIns,
      streakWeeks: week.streakWeeks,
    );
  }

  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> goalIds,
  }) async {
    await client.rpc(
      'save_goal_check_ins',
      params: {
        'target_crew_id': crewId,
        'expected_today': today,
        'selected_goal_ids': goalIds.toList(),
      },
    );
  }
}

class MissingHomeBackend implements HomeBackend {
  const MissingHomeBackend();
  @override
  Future<CrewWeek> fetchWeek(String crewId) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> goalIds,
  }) => Future.error(StateError('Supabase is not configured.'));
}
