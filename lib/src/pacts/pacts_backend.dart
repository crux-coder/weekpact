import 'package:supabase_flutter/supabase_flutter.dart';

enum PactFrequency { daily, weekly }

class PactCrew {
  const PactCrew({
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

class CrewPact {
  const CrewPact({
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
  final PactFrequency frequency;
  final int daysPerWeek;
  final String iconKey;

  String get schedule => frequency == PactFrequency.daily
      ? 'Every day · 7 days / week'
      : '$daysPerWeek ${daysPerWeek == 1 ? 'day' : 'days'} / week';

  factory CrewPact.fromJson(Map<String, dynamic> row) => CrewPact(
    id: row['id'] as String,
    crewId: row['crew_id'] as String,
    title: row['title'] as String,
    iconKey: row['icon_key'] as String? ?? 'target',
    frequency: PactFrequency.values.byName(row['frequency'] as String),
    daysPerWeek: row['days_per_week'] as int,
  );
}

abstract interface class PactsBackend {
  Future<CrewPact> updatePact({
    required String pactId,
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  });
  Future<List<PactCrew>> fetchCrews();
  Future<List<CrewPact>> fetchPacts(String crewId);
  Future<CrewPact> addPact({
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  });
}

class SupabasePactsBackend implements PactsBackend {
  const SupabasePactsBackend(this._client);
  final SupabaseClient _client;

  @override
  Future<List<PactCrew>> fetchCrews() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to view your pacts.');
    final rows = await _client
        .from('crew_members')
        .select('role,crews!inner(id,name,timezone)')
        .eq('user_id', user.id)
        .order('joined_at')
        .order('crew_id');
    return rows
        .map((row) {
          final crew = row['crews'] as Map<String, dynamic>;
          return PactCrew(
            id: crew['id'] as String,
            name: crew['name'] as String,
            timezone: crew['timezone'] as String,
            isOwner: row['role'] == 'owner',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<CrewPact>> fetchPacts(String crewId) async {
    final rows = await _client
        .from('crew_pacts')
        .select()
        .eq('crew_id', crewId)
        .order('created_at');
    return rows.map(CrewPact.fromJson).toList(growable: false);
  }

  @override
  Future<CrewPact> addPact({
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.length < 2 || cleanTitle.length > 100) {
      throw ArgumentError('Use 2–100 characters for the pact.');
    }
    if (daysPerWeek < 1 ||
        daysPerWeek > 7 ||
        (frequency == PactFrequency.daily && daysPerWeek != 7)) {
      throw ArgumentError('Choose a valid weekly target.');
    }
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to add a pact.');
    final row = await _client
        .from('crew_pacts')
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
    return CrewPact.fromJson(row);
  }

  @override
  Future<CrewPact> updatePact({
    required String pactId,
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.length < 2 ||
        cleanTitle.length > 100 ||
        daysPerWeek < 1 ||
        daysPerWeek > 7 ||
        (frequency == PactFrequency.daily && daysPerWeek != 7)) {
      throw ArgumentError('Choose a valid pact name and weekly target.');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in to edit a pact.');
    }
    final row = await _client
        .from('crew_pacts')
        .update({
          'title': cleanTitle,
          'frequency': frequency.name,
          'days_per_week': daysPerWeek,
          'icon_key': iconKey,
        })
        .eq('id', pactId)
        .eq('crew_id', crewId)
        .select()
        .single();
    return CrewPact.fromJson(row);
  }
}

class MissingPactsBackend implements PactsBackend {
  const MissingPactsBackend();
  @override
  Future<List<PactCrew>> fetchCrews() async => [];
  @override
  Future<List<CrewPact>> fetchPacts(String crewId) async => [];
  @override
  Future<CrewPact> addPact({
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    String iconKey = 'target',
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<CrewPact> updatePact({
    required String pactId,
    required String crewId,
    required String title,
    required PactFrequency frequency,
    required int daysPerWeek,
    required String iconKey,
  }) => Future.error(StateError('Supabase is not configured.'));
}
