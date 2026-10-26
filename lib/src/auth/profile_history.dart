import '../home/home_backend.dart';

/// One of the viewer's own check-ins as Account's photo wall shows it: with
/// the crew and pact it was kept for, so a tile can be drawn and opened
/// without the crew's week.
class ProfileCheckIn {
  const ProfileCheckIn({
    required this.ref,
    required this.createdAt,
    required this.crewName,
    required this.pactTitle,
    required this.iconKey,
    required this.pactIndex,
    this.clapCount = 0,
    this.photoPath,
    this.photoUrl,
  });

  /// The check-in itself, as a tap opens it in the story viewer.
  final CheckInRef ref;
  final DateTime createdAt;
  final String crewName;
  final String pactTitle;
  final String iconKey;

  /// The pact's place in its crew's list, which its colours are read from.
  final int pactIndex;
  final int clapCount;

  /// Null for a check-in kept without a photo; its tile is the pact's tint.
  final String? photoPath;
  final String? photoUrl;

  /// `yyyy-MM-dd`, in the crew's own calendar.
  String get day => ref.day;

  factory ProfileCheckIn.fromJson(Map<String, dynamic> row) => ProfileCheckIn(
    ref: CheckInRef(
      crewId: row['crew_id'] as String,
      pactId: row['pact_id'] as String,
      userId: row['user_id'] as String,
      day: row['completed_on'] as String,
    ),
    createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    crewName: row['crew_name'] as String? ?? '',
    pactTitle: row['pact_title'] as String? ?? '',
    iconKey: row['icon_key'] as String? ?? 'target',
    pactIndex: (row['pact_index'] as num?)?.toInt() ?? 0,
    clapCount: (row['clap_count'] as num?)?.toInt() ?? 0,
    photoPath: row['photo_path'] as String?,
  );

  ProfileCheckIn withPhotoUrl(String? url) => ProfileCheckIn(
    ref: ref,
    createdAt: createdAt,
    crewName: crewName,
    pactTitle: pactTitle,
    iconKey: iconKey,
    pactIndex: pactIndex,
    clapCount: clapCount,
    photoPath: photoPath,
    photoUrl: url,
  );
}

/// A pact in one of the viewer's crews, as a filter over the wall.
class ProfilePact {
  const ProfilePact({
    required this.id,
    required this.crewId,
    required this.title,
    required this.iconKey,
    required this.pactIndex,
  });

  final String id;
  final String crewId;
  final String title;
  final String iconKey;
  final int pactIndex;

  factory ProfilePact.fromJson(Map<String, dynamic> row) => ProfilePact(
    id: row['id'] as String,
    crewId: row['crew_id'] as String,
    title: row['title'] as String? ?? '',
    iconKey: row['icon_key'] as String? ?? 'target',
    pactIndex: (row['pact_index'] as num?)?.toInt() ?? 0,
  );
}

/// What heads the wall: the three figures and the pacts to filter by.
class ProfileSummary {
  const ProfileSummary({
    required this.checkIns,
    required this.crews,
    this.pacts = const [],
  });

  final int checkIns;
  final int crews;
  final List<ProfilePact> pacts;

  factory ProfileSummary.fromJson(Map<String, dynamic> row) => ProfileSummary(
    checkIns: (row['check_ins'] as num?)?.toInt() ?? 0,
    crews: (row['crews'] as num?)?.toInt() ?? 0,
    pacts: [
      for (final pact in row['pacts'] as List? ?? const [])
        ProfilePact.fromJson(Map<String, dynamic>.from(pact as Map)),
    ],
  );
}

/// The viewer's own record across every crew they are in. Kept apart from
/// [HomeBackend] so the fakes that stand in for it need not grow a wall.
abstract interface class ProfileHistoryBackend {
  Future<ProfileSummary> fetchProfileSummary();

  /// The viewer's check-ins, newest first, after [before] when given and of
  /// [pactId] alone when given, each with its photo signed.
  Future<List<ProfileCheckIn>> fetchMyCheckIns({
    ProfileCheckIn? before,
    String? pactId,
    int limit = 30,
  });
}
