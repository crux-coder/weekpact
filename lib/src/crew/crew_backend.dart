import 'crew_sharing.dart';

import 'dart:typed_data';

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

class CrewDetails {
  const CrewDetails({
    required this.id,
    required this.name,
    required this.timezone,
    required this.ownerId,
    required this.currentUserRole,
    required this.members,
    this.createdAt,
    this.description,
    this.avatarUrl,
  });

  final String id;
  final String name;

  /// A line about what the crew is for, set by its owner. Null when unset.
  final String? description;

  /// A signed URL for the crew's photo, or null when it has none or the URL
  /// could not be made. Each upload has its own path, so this changes with it.
  final String? avatarUrl;
  final String timezone;
  final String ownerId;
  final String currentUserRole;
  final List<CrewMember> members;

  /// When the crew was started, for the line the crew card opens with.
  ///
  /// Nullable rather than required: `crews.created_at` has always been there,
  /// but nothing read it until the card did, and a crew summary is not worth
  /// making every fake and fixture in the suite restate a date they do not
  /// care about. The card simply drops the clause when it is absent.
  final DateTime? createdAt;

  bool get isOwner => currentUserRole == 'owner';
}

/// What a crew's invite may say about it before anyone has joined: its name,
/// who is in it, who sent the invite, and what they keep. Readable without an
/// account, so nothing here identifies anyone beyond a first name.
class CrewInvitePreview {
  const CrewInvitePreview({
    required this.crewName,
    required this.memberCount,
    required this.ownerName,
    String? inviterName,
    this.inviterInitials = '',
    this.memberInitials = const [],
    this.pacts = const [],
    this.isMember = false,
  }) : inviterName = inviterName ?? ownerName;

  final String crewName;
  final int memberCount;
  final String ownerName;

  /// Whoever shared the link, or the owner when the code was typed.
  final String inviterName;
  final String inviterInitials;
  final List<String> memberInitials;
  final List<InvitePact> pacts;

  /// The signed-in account is already in this crew.
  final bool isMember;

  static CrewInvitePreview fromJson(Map<String, dynamic> row) =>
      CrewInvitePreview(
        crewName: row['crew_name'] as String,
        memberCount: (row['member_count'] as num).toInt(),
        ownerName: row['owner_name'] as String,
        inviterName: row['inviter_name'] as String?,
        inviterInitials: row['inviter_initials'] as String? ?? '',
        memberInitials: [
          for (final initials in row['member_initials'] as List? ?? const [])
            initials as String,
        ],
        pacts: [
          for (final pact in row['pacts'] as List? ?? const [])
            InvitePact.fromJson(Map<String, dynamic>.from(pact as Map)),
        ],
        isMember: row['is_member'] as bool? ?? false,
      );
}

/// A pact as an invite shows it.
class InvitePact {
  const InvitePact({
    required this.title,
    required this.iconKey,
    required this.daysPerWeek,
  });

  final String title;
  final String iconKey;
  final int daysPerWeek;

  static InvitePact fromJson(Map<String, dynamic> row) => InvitePact(
    title: row['title'] as String,
    iconKey: row['icon_key'] as String? ?? 'target',
    daysPerWeek: (row['days_per_week'] as num?)?.toInt() ?? 7,
  );
}

/// Thrown when the join itself succeeded and only the crew that followed could
/// not be read. The person is a member either way, so the page that catches
/// this sends them on rather than telling them the invitation failed.
class CrewJoinedWithoutDetails implements Exception {
  const CrewJoinedWithoutDetails(this.crewId);

  final String crewId;

  @override
  String toString() => 'Joined crew $crewId, but its details could not load.';
}

abstract interface class CrewBackend {
  Future<void> leaveCrew({required String crewId, String? successorId});
  Future<void> removeMember({required String crewId, required String userId});
  Future<List<PactCrew>> fetchCrews();
  Future<CrewDetails?> fetchCrew({String? crewId});
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
    String? description,
    Uint8List? avatar,
  });

  /// Joins the crew behind [code] (or a legacy link token). Joining a crew
  /// you are already in is not an error.
  Future<CrewDetails> acceptInvite(String code);

  /// What the invite is for, or null when the code is unknown or was reset.
  /// [from] is the member who shared the link, when it said.
  Future<CrewInvitePreview?> previewInvite(String code, {String? from});
}

/// Ending a crew, for the one person who can.
///
/// It sits beside [CrewBackend] rather than in it, the way [CrewSharingBackend]
/// does: a backend that cannot reach the database can still answer every other
/// question on that interface from what it holds, and a page asks for this one
/// before it offers the door.
abstract interface class CrewDeletionBackend {
  /// Deletes the crew itself. Row-level security lets only its owner through,
  /// and the database takes the members, pacts, check-ins, share links and
  /// finalized weeks with it.
  Future<void> deleteCrew(String crewId);
}

/// Changing a crew's name, description and photo, for its owner.
///
/// Beside [CrewBackend] for the same reason as [CrewDeletionBackend]: the
/// crew page offers the editor only when its backend can save one.
abstract interface class CrewEditingBackend {
  /// Saves [name] and [description] (blank clears it). A null [avatar] keeps
  /// the photo the crew has. Row-level security lets only the owner through.
  Future<CrewDetails> updateCrew({
    required String crewId,
    required String name,
    String? description,
    Uint8List? avatar,
  });
}

/// Where crew photos live, and how long a signed link to one lasts.
const crewAvatarBucket = 'crew-avatars';
const _crewAvatarLifetime = 3600;

/// The longest description a crew may carry, as the database checks it.
const crewDescriptionMaxLength = 280;

String? _cleanDescription(String? description) {
  final trimmed = description?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class SupabaseCrewBackend
    implements
        CrewBackend,
        CrewSharingBackend,
        CrewDeletionBackend,
        CrewEditingBackend {
  @override
  Future<String> inviteCode(String crewId) async =>
      await _client.rpc('crew_invite_code', params: {'p_crew': crewId})
          as String;

  @override
  Future<String> resetInviteCode(String crewId) async =>
      await _client.rpc('reset_crew_invite_code', params: {'p_crew': crewId})
          as String;

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
          'crews!inner(id,name,description,avatar_path,timezone,owner_id,'
          'created_at)',
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

    return CrewDetails(
      id: selectedId,
      name: crew['name'] as String,
      description: crew['description'] as String?,
      avatarUrl: await _signAvatar(crew['avatar_path'] as String?),
      timezone: crew['timezone'] as String,
      ownerId: crew['owner_id'] as String,
      createdAt: DateTime.tryParse(crew['created_at'] as String? ?? ''),
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
    );
  }

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
    String? description,
    Uint8List? avatar,
  }) async {
    final userId = _requireUserId();
    final row = await _client
        .from('crews')
        .insert({
          'name': name.trim(),
          'description': _cleanDescription(description),
          'timezone': timezone,
          'owner_id': userId,
        })
        .select('id')
        .single();
    final crewId = row['id'] as String;
    if (avatar != null) {
      // The photo needs the crew's id, so it follows the insert. By then the
      // crew exists: failing here would send the owner back to make a second
      // one, so the crew goes ahead without a photo they can add from Edit.
      try {
        await _saveAvatar(crewId, avatar);
      } catch (_) {}
    }
    return (await fetchCrew(crewId: crewId))!;
  }

  @override
  Future<CrewDetails> updateCrew({
    required String crewId,
    required String name,
    String? description,
    Uint8List? avatar,
  }) async {
    _requireUserId();
    final updated = await _client
        .from('crews')
        .update({
          'name': name.trim(),
          'description': _cleanDescription(description),
        })
        .eq('id', crewId)
        .select('id');
    // As with deleting, a member's update matches no row rather than raising.
    if (updated.isEmpty) throw StateError('Only the owner can edit a crew.');
    if (avatar != null) await _saveAvatar(crewId, avatar);
    final crew = await fetchCrew(crewId: crewId);
    if (crew == null) throw StateError('This crew is no longer available.');
    return crew;
  }

  /// Uploads [avatar] under a fresh name, points the crew at it, then clears
  /// out the photos it replaced.
  Future<void> _saveAvatar(String crewId, Uint8List avatar) async {
    if (avatar.isEmpty || avatar.length > 5 * 1024 * 1024) {
      throw ArgumentError('Choose a photo smaller than 5 MB.');
    }
    final path = '$crewId/${DateTime.now().millisecondsSinceEpoch}.png';
    final bucket = _client.storage.from(crewAvatarBucket);
    await bucket.uploadBinary(
      path,
      avatar,
      fileOptions: const FileOptions(contentType: 'image/png'),
    );
    await _client.from('crews').update({'avatar_path': path}).eq('id', crewId);
    try {
      final stale = [
        for (final file in await bucket.list(path: crewId))
          if ('$crewId/${file.name}' != path) '$crewId/${file.name}',
      ];
      if (stale.isNotEmpty) await bucket.remove(stale);
    } catch (_) {
      // Leftovers cost storage, not correctness; the next save retries.
    }
  }

  Future<String?> _signAvatar(String? path) async {
    if (path == null) return null;
    try {
      return await _client.storage
          .from(crewAvatarBucket)
          .createSignedUrl(path, _crewAvatarLifetime);
    } catch (_) {
      // The crew still reads without its photo; the face falls back to
      // initials.
      return null;
    }
  }

  @override
  Future<CrewDetails> acceptInvite(String code) async {
    final crewId = await _client.rpc(
      'accept_crew_invite',
      params: {'p_code': code},
    ) as String;
    // Past this line the membership exists. A crew that will not load is a
    // reading problem, and reporting it as a refused invitation would leave
    // someone who is already in the crew asking for a fresh link.
    CrewDetails? crew;
    try {
      crew = await fetchCrew(crewId: crewId);
    } catch (_) {
      crew = null;
    }
    if (crew == null) throw CrewJoinedWithoutDetails(crewId);
    return crew;
  }

  @override
  Future<CrewInvitePreview?> previewInvite(String code, {String? from}) async {
    final row = await _client.rpc(
      'preview_crew_invite',
      params: {'p_code': code, 'p_from': from},
    );
    return row == null
        ? null
        : CrewInvitePreview.fromJson(Map<String, dynamic>.from(row as Map));
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

  @override
  Future<void> deleteCrew(String crewId) async {
    // Storage does not cascade, and once the row is gone nobody owns the
    // folder any more, so the photos go first. Only the owner may remove them,
    // which is also the only person whose delete below goes through.
    try {
      final bucket = _client.storage.from(crewAvatarBucket);
      final files = await bucket.list(path: crewId);
      if (files.isNotEmpty) {
        await bucket.remove([for (final file in files) '$crewId/${file.name}']);
      }
    } catch (_) {}
    // The row and nothing else: every table hanging off a crew cascades, and
    // `crews_delete_for_owner` is what decides whether this deletes anything
    // at all. A member's attempt matches no row rather than raising, so the
    // deleted row is asked for back and its absence is the refusal.
    final deleted = await _client
        .from('crews')
        .delete()
        .eq('id', crewId)
        .select('id');
    if (deleted.isEmpty) throw StateError('Only the owner can delete a crew.');
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('You must be signed in.');
    return userId;
  }
}

class MissingCrewBackend implements CrewBackend, CrewDeletionBackend {
  const MissingCrewBackend();

  @override
  Future<void> deleteCrew(String crewId) => Future.error(_error);

  @override
  Future<List<PactCrew>> fetchCrews() async => [];

  @override
  Future<void> leaveCrew({required String crewId, String? successorId}) =>
      Future.error(_error);

  @override
  Future<void> removeMember({required String crewId, required String userId}) =>
      Future.error(_error);

  static StateError get _error => StateError(
    'Supabase is not configured. Add the URL and publishable key first.',
  );

  @override
  Future<CrewDetails?> fetchCrew({String? crewId}) async => null;

  @override
  Future<CrewDetails> acceptInvite(String code) => Future.error(_error);

  @override
  Future<CrewInvitePreview?> previewInvite(String code, {String? from}) async =>
      null;

  @override
  Future<CrewDetails> createCrew({
    required String name,
    required String timezone,
    String? description,
    Uint8List? avatar,
  }) => Future.error(_error);
}
