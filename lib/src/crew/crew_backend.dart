import 'package:supabase_flutter/supabase_flutter.dart';

import '../goals/goals_backend.dart';

class CrewMember {
  const CrewMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final String email;
  final String role;
  final DateTime joinedAt;

  bool get isOwner => role == 'owner';
}

class CrewInvite {
  const CrewInvite({
    required this.id,
    required this.email,
    required this.expiresAt,
  });

  final String id;
  final String email;
  final DateTime expiresAt;
}

class CrewDetails {
  const CrewDetails({
    required this.id,
    required this.name,
    required this.timezone,
    required this.ownerId,
    required this.currentUserRole,
    required this.members,
    required this.pendingInvites,
  });

  final String id;
  final String name;
  final String timezone;
  final String ownerId;
  final String currentUserRole;
  final List<CrewMember> members;
  final List<CrewInvite> pendingInvites;

  bool get isOwner => currentUserRole == 'owner';
}

class ReceivedCrewInvite {
  const ReceivedCrewInvite({
    required this.id,
    required this.crewId,
    required this.name,
    required this.timezone,
    required this.expiresAt,
    required this.members,
    required this.goals,
  });

  final String id;
  final String crewId;
  final String name;
  final String timezone;
  final DateTime expiresAt;
  final List<CrewMember> members;
  final List<CrewGoal> goals;

  factory ReceivedCrewInvite.fromJson(Map<String, dynamic> row) =>
      ReceivedCrewInvite(
        id: row['id'] as String,
        crewId: row['crew_id'] as String,
        name: row['name'] as String,
        timezone: row['timezone'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
        members: (row['members'] as List)
            .map(
              (m) => CrewMember(
                userId: m['user_id'] as String,
                email: m['email'] as String,
                role: m['role'] as String,
                joinedAt: DateTime.parse(m['joined_at'] as String),
              ),
            )
            .toList(growable: false),
        goals: (row['goals'] as List)
            .map((g) => CrewGoal.fromJson(Map<String, dynamic>.from(g as Map)))
            .toList(growable: false),
      );
}

abstract interface class CrewBackend {
  Future<List<ReceivedCrewInvite>> fetchReceivedInvites();
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  });
  Future<CrewDetails?> fetchCrew();
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  });
  Future<CrewDetails> inviteMember({
    required String crewId,
    required String email,
  });
  Future<CrewDetails> revokeInvite({
    required String crewId,
    required String inviteId,
  });
  Future<CrewDetails> acceptInvite(String token);
}

class SupabaseCrewBackend implements CrewBackend {
  const SupabaseCrewBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<CrewDetails?> fetchCrew() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final membership = await _client
        .from('crew_members')
        .select(
          'crew_id,user_id,email,role,joined_at,'
          'crews!inner(id,name,timezone,owner_id)',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (membership == null) return null;

    final crew = membership['crews'] as Map<String, dynamic>;
    final crewId = crew['id'] as String;
    final memberRows = await _client
        .from('crew_members')
        .select('user_id,email,role,joined_at')
        .eq('crew_id', crewId)
        .order('joined_at');

    List<dynamic> inviteRows = const [];
    if (membership['role'] == 'owner') {
      inviteRows = await _client
          .from('crew_invites')
          .select('id,email,expires_at')
          .eq('crew_id', crewId)
          .isFilter('accepted_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
    }

    return CrewDetails(
      id: crewId,
      name: crew['name'] as String,
      timezone: crew['timezone'] as String,
      ownerId: crew['owner_id'] as String,
      currentUserRole: membership['role'] as String,
      members: memberRows
          .map(
            (row) => CrewMember(
              userId: row['user_id'] as String,
              email: row['email'] as String,
              role: row['role'] as String,
              joinedAt: DateTime.parse(row['joined_at'] as String),
            ),
          )
          .toList(growable: false),
      pendingInvites: inviteRows
          .map(
            (row) => CrewInvite(
              id: row['id'] as String,
              email: row['email'] as String,
              expiresAt: DateTime.parse(row['expires_at'] as String),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) async {
    final userId = _requireUserId();
    await _client.from('crews').insert({
      'name': name.trim(),
      'timezone': timezone,
      'owner_id': userId,
    });
    return (await fetchCrew())!;
  }

  @override
  Future<CrewDetails> inviteMember({
    required String crewId,
    required String email,
  }) async {
    await _client.functions.invoke(
      'invite-crew-member',
      body: {'crewId': crewId, 'email': email.trim().toLowerCase()},
    );
    return (await fetchCrew())!;
  }

  @override
  Future<CrewDetails> revokeInvite({
    required String crewId,
    required String inviteId,
  }) async {
    await _client
        .from('crew_invites')
        .delete()
        .eq('id', inviteId)
        .eq('crew_id', crewId);
    return (await fetchCrew())!;
  }

  @override
  Future<CrewDetails> acceptInvite(String token) async {
    await _client.rpc('accept_crew_invite', params: {'p_token': token});
    return (await fetchCrew())!;
  }

  @override
  Future<List<ReceivedCrewInvite>> fetchReceivedInvites() async {
    final rows = await _client.rpc('received_crew_invites') as List;
    return rows
        .map(
          (row) => ReceivedCrewInvite.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  }) async {
    await _client.rpc(
      'respond_to_crew_invite',
      params: {'p_invite_id': inviteId, 'p_accept': accept},
    );
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('You must be signed in.');
    return userId;
  }
}

class MissingCrewBackend implements CrewBackend {
  const MissingCrewBackend();

  @override
  Future<List<ReceivedCrewInvite>> fetchReceivedInvites() async => [];

  @override
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  }) => Future.error(_error);

  static StateError get _error => StateError(
    'Supabase is not configured. Add the URL and publishable key first.',
  );

  @override
  Future<CrewDetails?> fetchCrew() async => null;

  @override
  Future<CrewDetails> acceptInvite(String token) => Future.error(_error);

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
  }) => Future.error(_error);

  @override
  Future<CrewDetails> inviteMember({
    required String crewId,
    required String email,
  }) => Future.error(_error);

  @override
  Future<CrewDetails> revokeInvite({
    required String crewId,
    required String inviteId,
  }) => Future.error(_error);
}
