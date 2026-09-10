import 'package:supabase_flutter/supabase_flutter.dart';

enum GoalFrequency { daily, weekly }

class GoalCrew {
  const GoalCrew({
    required this.id,
    required this.name,
    required this.timezone,
    required this.isOwner,
  });
  final String id;
  final String name;
  final String timezone;
  final bool isOwner;
}

class CrewGoal {
  const CrewGoal({
    required this.id,
    required this.crewId,
    required this.title,
    required this.frequency,
    required this.daysPerWeek,
    this.iconKey = 'target',
  });
  final String id;
  final String crewId;
  final String title;
  final GoalFrequency frequency;
  final int daysPerWeek;
  final String iconKey;

  String get schedule => frequency == GoalFrequency.daily
      ? 'Every day · 7 days / week'
      : '$daysPerWeek ${daysPerWeek == 1 ? 'day' : 'days'} / week';

  factory CrewGoal.fromJson(Map<String, dynamic> row) => CrewGoal(
    id: row['id'] as String,
    crewId: row['crew_id'] as String,
    title: row['title'] as String,
    iconKey: row['icon_key'] as String? ?? 'target',
    frequency: GoalFrequency.values.byName(row['frequency'] as String),
    daysPerWeek: row['days_per_week'] as int,
  );
}

abstract interface class GoalsBackend {
  Future<CrewGoal> updateGoal({
    required String goalId,
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  });
  Future<List<GoalCrew>> fetchCrews();
  Future<List<CrewGoal>> fetchGoals(String crewId);
  Future<CrewGoal> addGoal({
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  });
}

class SupabaseGoalsBackend implements GoalsBackend {
  const SupabaseGoalsBackend(this._client);
  final SupabaseClient _client;

  @override
  Future<List<GoalCrew>> fetchCrews() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to view your goals.');
    final rows = await _client
        .from('crew_members')
        .select('role,crews!inner(id,name,timezone)')
        .eq('user_id', user.id)
        .order('joined_at');
    return rows
        .map((row) {
          final crew = row['crews'] as Map<String, dynamic>;
          return GoalCrew(
            id: crew['id'] as String,
            name: crew['name'] as String,
            timezone: crew['timezone'] as String,
            isOwner: row['role'] == 'owner',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<CrewGoal>> fetchGoals(String crewId) async {
    final rows = await _client
        .from('crew_goals')
        .select()
        .eq('crew_id', crewId)
        .order('created_at');
    return rows.map(CrewGoal.fromJson).toList(growable: false);
  }

  @override
  Future<CrewGoal> addGoal({
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.length < 2 || cleanTitle.length > 100) {
      throw ArgumentError('Use 2–100 characters for the goal.');
    }
    if (daysPerWeek < 1 ||
        daysPerWeek > 7 ||
        (frequency == GoalFrequency.daily && daysPerWeek != 7)) {
      throw ArgumentError('Choose a valid weekly target.');
    }
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to add a goal.');
    final row = await _client
        .from('crew_goals')
        .insert({
          'crew_id': crewId,
          'title': cleanTitle,
          'icon_key': iconKey,
          'frequency': frequency.name,
          'days_per_week': daysPerWeek,
          'created_by': user.id,
        })
        .select()
        .single();
    return CrewGoal.fromJson(row);
  }

  @override
  Future<CrewGoal> updateGoal({
    required String goalId,
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.length < 2 ||
        cleanTitle.length > 100 ||
        daysPerWeek < 1 ||
        daysPerWeek > 7 ||
        (frequency == GoalFrequency.daily && daysPerWeek != 7)) {
      throw ArgumentError('Choose a valid goal name and weekly target.');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in to edit a goal.');
    }
    final row = await _client
        .from('crew_goals')
        .update({
          'title': cleanTitle,
          'frequency': frequency.name,
          'days_per_week': daysPerWeek,
          'icon_key': iconKey,
        })
        .eq('id', goalId)
        .eq('crew_id', crewId)
        .select()
        .single();
    return CrewGoal.fromJson(row);
  }
}

class MissingGoalsBackend implements GoalsBackend {
  const MissingGoalsBackend();
  @override
  Future<List<GoalCrew>> fetchCrews() async => [];
  @override
  Future<List<CrewGoal>> fetchGoals(String crewId) async => [];
  @override
  Future<CrewGoal> addGoal({
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<CrewGoal> updateGoal({
    required String goalId,
    required String crewId,
    required String title,
    required GoalFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}
