import 'dart:typed_data';
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
  const PactCheckIn(
    this.pactId,
    this.userId,
    this.day, {
    this.photoPath,
    this.photoUrl,
    this.keptAt,
    this.clapCount = 0,
    this.viewerClapped = false,
  });
  final String pactId;
  final String userId;
  final String day;

  /// How many people have clapped this check-in, and whether the viewer is
  /// one of them. The week carries both so a story opens on the claps it
  /// already has rather than on a tally of this session's own tap. They
  /// default to none, which is what an optimistic check-in the page has just
  /// written honestly knows.
  final int clapCount;
  final bool viewerClapped;

  /// The photo kept with this check-in, when the pact asked for one. Null for
  /// a pact that does not, which is most of them.
  final String? photoPath;

  /// [photoPath] signed for reading. Carried for today's check-ins only — the
  /// rest of the week is counted, never shown, and a signed URL for each of
  /// them would be a page of links nothing opens.
  final String? photoUrl;

  /// When it was kept. The stories rail orders by it and the viewer prints it.
  final DateTime? keptAt;

  PactCheckIn withPhotoUrl(String? url) => PactCheckIn(
    pactId,
    userId,
    day,
    photoPath: photoPath,
    photoUrl: url,
    keptAt: keptAt,
    clapCount: clapCount,
    viewerClapped: viewerClapped,
  );

  /// The one name a check-in goes by: a clap, a seen mark and a story all
  /// mean the same check-in by it.
  String get id => '$pactId/$userId/$day';
}

class CrewActivity {
  const CrewActivity({
    required this.pactId,
    required this.userId,
    required this.createdAt,
    this.completedOn,
    this.pactTitle,
    this.photoPath,
  });

  final String pactId;
  final String userId;
  final DateTime createdAt;
  final String? completedOn;
  final String? pactTitle;
  final String? photoPath;

  factory CrewActivity.fromJson(Map<String, dynamic> row) => CrewActivity(
    photoPath: row['photo_path'] as String?,
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

/// Where one member stands in the crew's week: how far along they are, and
/// what place that puts them in. See [CrewWeek.standings].
class CrewStanding {
  const CrewStanding({
    required this.member,
    required this.percent,
    required this.place,
    required this.isViewer,
  });

  final WeekMember member;

  /// How much of this member's own week is kept, 0 to 100.
  final int percent;

  /// One-based. Members on the same [percent] share a place.
  final int place;
  final bool isViewer;
}

/// One finished week as the crew week page lists it: when it was, how much
/// of the crew's week was kept, and how much of the crew was out each day.
class CrewWeekSummary {
  const CrewWeekSummary({
    required this.weekStart,
    required this.percent,
    required this.shareOut,
  });

  /// The week's Monday, as `yyyy-MM-dd`.
  final String weekStart;

  /// The crew's progress that week, 0 to 100, figured the way
  /// [CrewWeek.percentCrew] figures the current one.
  final int percent;

  /// Monday to Sunday: the share of the crew that checked in that day.
  final List<double> shareOut;

  factory CrewWeekSummary.fromJson(Map<String, dynamic> row) => CrewWeekSummary(
    weekStart: row['week_start'] as String,
    percent: (row['percent'] as num?)?.toInt() ?? 0,
    shareOut: [
      for (final share in (row['days'] as List? ?? const []))
        (share as num?)?.toDouble() ?? 0,
    ],
  );

  /// The week's last day, as `yyyy-MM-dd`.
  String get weekEnd =>
      DateTime.parse(weekStart)
          .add(const Duration(days: 6))
          .toIso8601String()
          .substring(0, 10);
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
            photoPath: i['photo_path'] as String?,
            keptAt: DateTime.tryParse(i['created_at'] as String? ?? ''),
            clapCount: (i['clap_count'] as num?)?.toInt() ?? 0,
            viewerClapped: i['viewer_clapped'] as bool? ?? false,
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

  /// Everyone who has kept [pactId] today, the crew included.
  ///
  /// The week already carries every check-in it has, each naming its pact, its
  /// person and its day — [days] and [checkedToday] just fold that list two
  /// other ways. Nothing is fetched for this.
  Set<String> keptToday(String pactId) => checkIns
      .where((i) => i.pactId == pactId && i.day == today)
      .map((i) => i.userId)
      .toSet();

  Set<String> checkedToday(String userId) => checkIns
      .where((i) => i.userId == userId && i.day == today)
      .map((i) => i.pactId)
      .toSet();

  /// How much of the crew was out on [day], as a share of its members.
  ///
  /// A person counts once however many pacts they kept that day: the figure
  /// answers "how much of the crew was in", which is what the row of days
  /// under Home's rail draws, and a member with three pacts would otherwise
  /// fill a day on their own.
  double shareOut(String day) {
    if (members.isEmpty) return 0;
    final ids = members.map((m) => m.id).toSet();
    final out = checkIns
        .where((i) => i.day == day && ids.contains(i.userId))
        .map((i) => i.userId)
        .toSet()
        .length;
    return out / members.length;
  }

  /// The week's seven days as `yyyy-MM-dd`, Monday first.
  ///
  /// Built off [weekStart] rather than off the check-ins, so a day nobody kept
  /// still has a column and the row keeps its shape all week.
  List<String> get weekDays {
    final start = DateTime.parse(weekStart);
    return [
      for (var i = 0; i < 7; i++)
        start.add(Duration(days: i)).toIso8601String().substring(0, 10),
    ];
  }

  /// Whether the week has run its course: its Sunday is behind [today]. A
  /// week reached from the past-weeks list is; the live week never is.
  bool get isOver => weekDays.last.compareTo(today) < 0;

  int get target => pacts.fold(0, (sum, g) => sum + g.daysPerWeek);
  int completed(String userId) => pacts.fold(
    0,
    (sum, g) => sum + math.min(g.daysPerWeek, days(g.id, userId)),
  );
  int percent(String userId) =>
      target == 0 ? 0 : (100 * completed(userId) / target).round();

  /// The crew this week, furthest along first.
  ///
  /// [percentCrew] folds the same numbers into one figure, which is the one
  /// thing about a crew's week nobody can act on: a percentage of four people
  /// is not a number you can move. This keeps them apart, so Home can say
  /// where each member stands and where the viewer stands among them.
  ///
  /// Ties share a place, as places do — four members all on nothing are four
  /// firsts, not a first, a second, a third and a fourth decided by whatever
  /// order the roster arrived in.
  List<CrewStanding> standings(String viewerId) {
    final ordered = [...members]
      ..sort((a, b) => percent(b.id).compareTo(percent(a.id)));
    final places = <CrewStanding>[];
    var place = 0;
    int? previous;
    for (var i = 0; i < ordered.length; i++) {
      final share = percent(ordered[i].id);
      if (share != previous) {
        place = i + 1;
        previous = share;
      }
      places.add(
        CrewStanding(
          member: ordered[i],
          percent: share,
          place: place,
          isViewer: ordered[i].id == viewerId,
        ),
      );
    }
    return places;
  }

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

/// One notification as the reader sees it: what happened, who did it, and
/// whether this person has already read it.
///
/// The wording is built here rather than carried from the server, because the
/// push template lives in the notification worker and a list has room the
/// notification tray does not. What the payload contributes is the facts.
class NotificationEntry {
  const NotificationEntry({
    required this.eventId,
    required this.type,
    required this.createdAt,
    required this.read,
    required this.crewId,
    required this.crewName,
    required this.actorId,
    required this.displayName,
    this.pactTitle,
    this.iconKey,
    this.clapCount = 0,
    this.avatarPath,
    this.avatarUrl,
  });

  final String eventId;
  final String type;
  final DateTime createdAt;
  final bool read;
  final String crewId;
  final String crewName;
  final String actorId;
  final String displayName;
  final String? pactTitle;
  final String? iconKey;

  /// How many people the clap notification stands for, the first of them named
  /// by [displayName]. Zero for every other type.
  final int clapCount;
  final String? avatarPath;
  final String? avatarUrl;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty || displayName == 'Crew member') return '?';
    return (parts.first.characters.first +
            (parts.length > 1 ? parts.last.characters.first : ''))
        .toUpperCase();
  }

  /// Everyone the notification is about, the way it would be said aloud.
  String get subject {
    final others = clapCount - 1;
    if (type != 'check_in_clapped' || others <= 0) return displayName;
    return others == 1
        ? '$displayName and 1 other'
        : '$displayName and $others others';
  }

  /// What they did, with [subject] already said.
  String get action => switch (type) {
    'check_in_clapped' => 'clapped your ${pactTitle ?? 'pact'} check-in',
    'pact_completed' => 'completed ${pactTitle ?? 'a pact'}',
    'crew_nudge' => 'is cheering you on',
    _ => 'sent you a notification',
  };

  NotificationEntry copyWith({String? avatarUrl, bool? read}) =>
      NotificationEntry(
        eventId: eventId,
        type: type,
        createdAt: createdAt,
        read: read ?? this.read,
        crewId: crewId,
        crewName: crewName,
        actorId: actorId,
        displayName: displayName,
        pactTitle: pactTitle,
        iconKey: iconKey,
        clapCount: clapCount,
        avatarPath: avatarPath,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  static NotificationEntry fromJson(Map<String, dynamic> row) =>
      NotificationEntry(
        eventId: row['event_id'] as String,
        type: row['type'] as String,
        createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
        read: row['read'] as bool? ?? false,
        crewId: row['crew_id'] as String,
        crewName: row['crew_name'] as String? ?? '',
        actorId: row['actor_id'] as String,
        displayName: row['display_name'] as String? ?? 'Crew member',
        pactTitle: row['pact_title'] as String?,
        iconKey: row['icon_key'] as String?,
        clapCount: (row['clap_count'] as num?)?.toInt() ?? 0,
        avatarPath: row['avatar_path'] as String?,
      );
}

abstract interface class HomeBackend {
  Future<Uint8List> fetchCheckInPhoto(String path);
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId);
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  });

  /// The crew's week: this one, or the finished week that began on
  /// [weekStart] (a Monday, `yyyy-MM-dd`). A past week comes back with the
  /// real [CrewWeek.today], so nothing in it reads as still open.
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart});

  /// Finished weeks before [before] (a Monday; this week when null), newest
  /// first, at most [limit] of them and never earlier than the crew's first.
  Future<List<CrewWeekSummary>> fetchWeekHistory(
    String crewId, {
    String? before,
    int limit = 12,
  });
  Future<List<CrewActivity>> fetchActivity(
    String crewId, {
    CrewActivity? before,
    int limit = 20,
  });

  Future<List<NotificationEntry>> fetchNotifications({
    NotificationEntry? before,
    int limit = 20,
  });
  Future<int> fetchUnreadNotificationCount();
  Future<void> markNotificationsRead({DateTime? upTo});

  /// Adds or removes the viewer's clap on one check-in and returns the check-in's
  /// clap count afterwards. Both directions are idempotent, so a repeated tap
  /// settles on the state asked for rather than toggling twice.
  Future<int> setClap({
    required String pactId,
    required String userId,
    required String day,
    required bool clapped,
  });
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
    Map<String, Uint8List> photos = const {},
  });
}

class SupabaseHomeBackend implements HomeBackend {
  SupabaseHomeBackend(this.client);
  final _avatarUrls = AvatarUrlCache();
  final _notificationAvatars = AvatarUrlCache();
  final SupabaseClient client;
  @override
  Future<Uint8List> fetchCheckInPhoto(String path) =>
      client.storage.from('check-in-photos').download(path);

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
          'pact_id,user_id,completed_on,created_at,photo_path,crew_pacts!inner(title,crew_id)',
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
  Future<List<NotificationEntry>> fetchNotifications({
    NotificationEntry? before,
    int limit = 20,
  }) async {
    final rows = await client.rpc(
      'notification_inbox',
      params: {
        'before_created_at': before?.createdAt.toUtc().toIso8601String(),
        'before_event': before?.eventId,
        'page_limit': limit,
      },
    );
    final entries = (rows as List)
        .map(
          (row) =>
              NotificationEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    // One batch of signed URLs for the page, rather than one per row.
    final avatars = await _notificationAvatars.resolve(
      account: client.auth.currentUser?.id,
      key: 'notifications',
      paths: entries.map((entry) => entry.avatarPath).nonNulls.toSet().toList(),
      sign: (missing, lifetime) => _signed('avatars', missing, lifetime),
    );
    return entries
        .map((entry) => entry.copyWith(avatarUrl: avatars[entry.avatarPath]))
        .toList();
  }

  @override
  Future<int> fetchUnreadNotificationCount() async =>
      (await client.rpc('unread_notification_count') as num).toInt();

  @override
  Future<void> markNotificationsRead({DateTime? upTo}) => client.rpc(
    'mark_notifications_read',
    params: {'up_to': upTo?.toUtc().toIso8601String()},
  );

  @override
  Future<int> setClap({
    required String pactId,
    required String userId,
    required String day,
    required bool clapped,
  }) async {
    final row = Map<String, dynamic>.from(
      await client.rpc(
        'set_check_in_clap',
        params: {
          'target_pact_id': pactId,
          'target_check_in_user': userId,
          'target_day': day,
          'clapped': clapped,
        },
      ),
    );
    return (row['clap_count'] as num).toInt();
  }

  Future<Map<String, String>> _signed(
    String bucket,
    List<String> paths, [
    int lifetime = AvatarUrlCache.lifetimeSeconds,
  ]) async {
    if (paths.isEmpty) return {};
    final signed = await client.storage
        .from(bucket)
        .createSignedUrlsResult(paths, lifetime);
    return {
      for (final result in signed)
        if (result is SignedUrlSuccess) result.path: result.signedUrl,
    };
  }

  @override
  Future<List<CrewWeekSummary>> fetchWeekHistory(
    String crewId, {
    String? before,
    int limit = 12,
  }) async {
    final rows = await client.rpc(
      'crew_week_history',
      params: {
        'target_crew_id': crewId,
        'before_week': ?before,
        'week_count': limit,
      },
    );
    return [
      for (final row in rows as List)
        CrewWeekSummary.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) async {
    final row = Map<String, dynamic>.from(
      await client.rpc(
        'crew_week_snapshot',
        params: {'target_crew_id': crewId, 'target_week_start': ?weekStart},
      ),
    );
    final week = CrewWeek.fromJson(row);
    // The crew's last check-in, whenever it was: the card reads as the latest
    // thing that happened rather than a second account of today, and it dates
    // what it shows. Bounded by the week's own pacts and members.
    final activity = week.pacts.isEmpty || week.members.isEmpty
        ? null
        : await client
              .from('pact_check_ins')
              .select('pact_id,user_id,created_at,photo_path')
              .inFilter('pact_id', week.pacts.map((pact) => pact.id).toList())
              .inFilter(
                'user_id',
                week.members.map((member) => member.id).toList(),
              )
              .order('created_at', ascending: false)
              .order('pact_id')
              .order('user_id')
              .limit(1)
              .maybeSingle();
    // Today's photos, signed for the stories rail. Only today's: the rail
    // shows the day, and the week's older check-ins are counted rather than
    // opened.
    final stories = await _signed(
      'check-in-photos',
      week.checkIns
          .where((i) => i.day == week.today)
          .map((i) => i.photoPath)
          .nonNulls
          .toSet()
          .toList(),
    );
    final paths = week.members
        .where((m) => m.avatarPath == '${m.id}/avatar.png')
        .map((m) => m.avatarPath!)
        .toList();
    final urls = await _avatarUrls.resolve(
      account: client.auth.currentUser?.id,
      key: crewId,
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
      checkIns: week.checkIns
          .map(
            (i) => i.photoPath == null || stories[i.photoPath] == null
                ? i
                : i.withPhotoUrl(stories[i.photoPath]),
          )
          .toList(),
      streakWeeks: week.streakWeeks,
      latestActivity: activity == null ? null : CrewActivity.fromJson(activity),
    );
  }

  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
    Map<String, Uint8List> photos = const {},
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to check in.');
    final paths = <String, String>{};
    final bucket = client.storage.from('check-in-photos');
    try {
      for (final entry in photos.entries) {
        if (!pactIds.contains(entry.key) ||
            entry.value.isEmpty ||
            entry.value.length > 5 * 1024 * 1024) {
          throw StateError('Invalid check-in photo.');
        }
        final random = math.Random.secure();
        final nonce = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final path = '$userId/$crewId/${entry.key}/$today/$nonce.png';
        paths[entry.key] = path;
        await bucket.uploadBinary(
          path,
          entry.value,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: false,
          ),
        );
      }
      await client.rpc(
        'save_pact_check_ins_with_photos',
        params: {
          'target_crew_id': crewId,
          'expected_today': today,
          'selected_pact_ids': pactIds.toList(),
          'photos': paths,
        },
      );
    } finally {
      if (paths.isNotEmpty) {
        // Queue only unused uploads, including when a save committed but its
        // response was lost. The server preserves every referenced photo.
        try {
          await client.rpc(
            'discard_unused_check_in_photos',
            params: {'paths': paths.values.toList()},
          );
        } catch (_) {
          /* Orphan sweeper retries. */
        }
      }
    }
  }
}

class MissingHomeBackend implements HomeBackend {
  const MissingHomeBackend();
  @override
  Future<Uint8List> fetchCheckInPhoto(String path) =>
      Future.error(StateError('Supabase is not configured.'));
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
  Future<int> setClap({
    required String pactId,
    required String userId,
    required String day,
    required bool clapped,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<List<NotificationEntry>> fetchNotifications({
    NotificationEntry? before,
    int limit = 20,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> fetchUnreadNotificationCount() =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> markNotificationsRead({DateTime? upTo}) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart}) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<List<CrewWeekSummary>> fetchWeekHistory(
    String crewId, {
    String? before,
    int limit = 12,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> saveCheckIns({
    required String crewId,
    required String today,
    required Set<String> pactIds,
    Map<String, Uint8List> photos = const {},
  }) => Future.error(StateError('Supabase is not configured.'));
}
