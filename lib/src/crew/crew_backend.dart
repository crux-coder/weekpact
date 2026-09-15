import 'crew_sharing.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../pacts/pacts_backend.dart';

class CrewMember {
  const CrewMember({
    required this.userId,
    required this.email,
    required this.role,
    required this.joinedAt,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String email;
  final String role;
  final DateTime joinedAt;
  final String? displayName;
  final String? avatarUrl;

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
    required this.pacts,
  });

  final String id;
  final String crewId;
  final String name;
  final String timezone;
  final DateTime expiresAt;
  final List<CrewMember> members;
  final List<CrewPact> pacts;

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
        pacts: (row['pacts'] as List)
            .map((g) => CrewPact.fromJson(Map<String, dynamic>.from(g as Map)))
            .toList(growable: false),
      );
}

abstract interface class CrewBackend {
  Future<void> leaveCrew({required String crewId, String? successorId});
  Future<void> removeMember({required String crewId, required String userId});
  Future<List<ReceivedCrewInvite>> fetchReceivedInvites();
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  });
  Future<List<PactCrew>> fetchCrews();
  Future<CrewDetails?> fetchCrew({String? crewId});
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

class SupabaseCrewBackend implements CrewBackend, CrewSharingBackend {
  @override
  Future<CrewShareLink?> manageShareLink(String crewId, String action) async {
    final row = await _client.rpc(
      'manage_crew_share_link',
      params: {'p_crew': crewId, 'p_action': action},
    );
    return row == null
        ? null
        : CrewShareLink.fromJson(Map<String, dynamic>.from(row as Map));
  }

  const SupabaseCrewBackend(this._client);

  final SupabaseClient _client;

  @override
  Future<List<PactCrew>> fetchCrews() =>
      SupabasePactsBackend(_client).fetchCrews();

  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    var query = _client
        .from('crew_members')
        .select(
          'crew_id,user_id,email,role,joined_at,'
          'crews!inner(id,name,timezone,owner_id)',
        )
        .eq('user_id', userId);
    if (crewId != null) query = query.eq('crew_id', crewId);
    final membership = await query
        .order('joined_at')
        .order('crew_id')
        .limit(1)
        .maybeSingle();
    if (membership == null) return null;

    final crew = membership['crews'] as Map<String, dynamic>;
    final selectedId = crew['id'] as String;
    final memberRows = await _client
        .from('crew_members')
        .select('user_id,email,role,joined_at')
        .eq('crew_id', selectedId)
        .order('joined_at');

    List<dynamic> inviteRows = const [];
    if (membership['role'] == 'owner') {
      inviteRows = await _client
          .from('crew_invites')
          .select('id,email,expires_at')
          .eq('crew_id', selectedId)
          .isFilter('accepted_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
    }

    return CrewDetails(
      id: selectedId,
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
    final row = await _client
        .from('crews')
        .insert({'name': name.trim(), 'timezone': timezone, 'owner_id': userId})
        .select('id')
        .single();
    return (await fetchCrew(crewId: row['id'] as String))!;
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
    return (await fetchCrew(crewId: crewId))!;
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
    return (await fetchCrew(crewId: crewId))!;
  }

  @override
  Future<CrewDetails> acceptInvite(String token) async {
    final crewId = await _client.rpc(
      'accept_crew_invite',
      params: {'p_token': token},
    ) as String;
    return (await fetchCrew(crewId: crewId))!;
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

  @override
  Future<void> leaveCrew({required String crewId, String? successorId}) async {
    await _client.rpc(
      'leave_crew',
      params: {'p_crew_id': crewId, 'p_successor_id': successorId},
    );
  }

  @override
  Future<void> removeMember({
    required String crewId,
    required String userId,
  }) async {
    await _client.rpc(
      'remove_crew_member',
      params: {'p_crew_id': crewId, 'p_user_id': userId},
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
  Future<List<PactCrew>> fetchCrews() async => [];

  @override
  Future<void> leaveCrew({required String crewId, String? successorId}) =>
      Future.error(_error);

  @override
  Future<void> removeMember({required String crewId, required String userId}) =>
      Future.error(_error);

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
  Future<CrewDetails?> fetchCrew({String? crewId}) async => null;

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
