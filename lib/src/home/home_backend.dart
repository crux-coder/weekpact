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

  factory PactCheckIn.fromJson(Map<String, dynamic> row) => PactCheckIn(
    row['pact_id'] as String,
    row['user_id'] as String,
    row['completed_on'] as String,
    photoPath: row['photo_path'] as String?,
    keptAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    clapCount: (row['clap_count'] as num?)?.toInt() ?? 0,
    viewerClapped: row['viewer_clapped'] as bool? ?? false,
  );

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

/// What a post outside any pact claims to be: a win, or simply something the
/// member wanted the crew to see. The poster picks as they write the words.
enum PostKind {
  achievement,
  story;

  static PostKind parse(Object? name) =>
      name == 'story' ? PostKind.story : PostKind.achievement;
}

/// A win a member posted to the crew outside any pact — a first 6c, a five
/// mile run — or, as a [PostKind.story], simply a moment from their day. It
/// sits in the stories rail beside the day's check-ins and takes claps the
/// same way, but it keeps no pact: nothing about the week, the streak or a
/// nudge counts it.
class Achievement {
  const Achievement({
    required this.id,
    required this.userId,
    required this.day,
    required this.text,
    this.kind = PostKind.achievement,
    this.photoPath,
    this.photoUrl,
    this.postedAt,
    this.clapCount = 0,
    this.viewerClapped = false,
  });

  final String id;
  final String userId;

  /// The crew's day it was posted on, `yyyy-MM-dd`.
  final String day;
  final String text;
  final PostKind kind;

  /// The photo posted with it, when one was. Stored and signed as a check-in
  /// photo is, in the same bucket.
  final String? photoPath;
  final String? photoUrl;
  final DateTime? postedAt;
  final int clapCount;
  final bool viewerClapped;

  /// The longest an achievement may be, as the server holds it.
  static const maxLength = 160;

  factory Achievement.fromJson(Map<String, dynamic> row) => Achievement(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    day: row['posted_on'] as String,
    text: row['body'] as String,
    kind: PostKind.parse(row['kind']),
    photoPath: row['photo_path'] as String?,
    postedAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    clapCount: (row['clap_count'] as num?)?.toInt() ?? 0,
    viewerClapped: row['viewer_clapped'] as bool? ?? false,
  );

  Achievement withPhotoUrl(String? url) => Achievement(
    id: id,
    userId: userId,
    day: day,
    text: text,
    kind: kind,
    photoPath: photoPath,
    photoUrl: url,
    postedAt: postedAt,
    clapCount: clapCount,
    viewerClapped: viewerClapped,
  );
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
    this.topPacts = const [],
  });

  /// The week's Monday, as `yyyy-MM-dd`.
  final String weekStart;

  /// The crew's progress that week, 0 to 100, figured the way
  /// [CrewWeek.percentCrew] figures the current one.
  final int percent;

  /// Monday to Sunday: the share of the crew that checked in that day.
  final List<double> shareOut;

  /// Monday to Sunday: the pact the crew kept most that day, null where
  /// nobody kept one. Empty from a server that does not send it yet.
  final List<String?> topPacts;

  factory CrewWeekSummary.fromJson(Map<String, dynamic> row) => CrewWeekSummary(
    weekStart: row['week_start'] as String,
    percent: (row['percent'] as num?)?.toInt() ?? 0,
    shareOut: [
      for (final share in (row['days'] as List? ?? const []))
        (share as num?)?.toDouble() ?? 0,
    ],
    topPacts: [
      for (final pact in (row['top_pacts'] as List? ?? const []))
        pact as String?,
    ],
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
    this.achievements = const [],
  });
  final CrewActivity? latestActivity;

  /// Today's achievements, oldest first. Only the current week carries them:
  /// the rail is the one place they show, and it shows today.
  final List<Achievement> achievements;
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
        .map((i) => PactCheckIn.fromJson(Map<String, dynamic>.from(i as Map)))
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

  /// The pact the crew kept most on [day], counted as [shareOut] counts —
  /// current members only. A tie goes to the pact earlier in the list, as
  /// the history the server sends breaks it. Null where nobody kept one.
  String? topPact(String day) {
    final ids = members.map((m) => m.id).toSet();
    final counts = <String, int>{};
    for (final i in checkIns) {
      if (i.day == day && ids.contains(i.userId)) {
        counts[i.pactId] = (counts[i.pactId] ?? 0) + 1;
      }
    }
    String? top;
    for (final pact in pacts) {
      final count = counts[pact.id] ?? 0;
      if (count > 0 && count > (counts[top] ?? 0)) top = pact.id;
    }
    return top;
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
}

/// One check-in, by what names it: the crew, the pact, whose it is and the
/// day it was kept. Notifications about a check-in carry one, so a tap can
/// open that check-in's story.
class CheckInRef {
  const CheckInRef({
    required this.crewId,
    required this.pactId,
    required this.userId,
    required this.day,
  });

  final String crewId;
  final String pactId;
  final String userId;

  /// `yyyy-MM-dd`, in the crew's own calendar.
  final String day;

  /// Reads one out of [row], or null when any part of it is missing.
  static CheckInRef? tryRead(Map<String, dynamic> row) {
    final crewId = row['crew_id'];
    final pactId = row['pact_id'];
    final userId = row['check_in_user_id'];
    final day = row['check_in_day'];
    if (crewId is! String || crewId.isEmpty) return null;
    if (pactId is! String || pactId.isEmpty) return null;
    if (userId is! String || userId.isEmpty) return null;
    if (day is! String || day.isEmpty) return null;
    return CheckInRef(crewId: crewId, pactId: pactId, userId: userId, day: day);
  }

  bool matches(PactCheckIn checkIn) =>
      checkIn.pactId == pactId &&
      checkIn.userId == userId &&
      checkIn.day == day;
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
    this.pactIndex,
    this.clapCount = 0,
    this.avatarPath,
    this.avatarUrl,
    this.checkIn,
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

  /// The pact's place in its crew's list, which its colour is read from (see
  /// `WeekPactColors.pactTint`). Null for a notice about no pact, or from a
  /// server too old to say.
  final int? pactIndex;

  /// How many people the clap notification stands for, the first of them named
  /// by [displayName]. Zero for every other type.
  final int clapCount;
  final String? avatarPath;
  final String? avatarUrl;

  /// The check-in the notification is about, which a tap opens. Null for a
  /// notice about no check-in, or from a server too old to say.
  final CheckInRef? checkIn;

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
    'achievement_clapped' => 'clapped your achievement',
    'story_clapped' => 'clapped your story',
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
        pactIndex: pactIndex,
        clapCount: clapCount,
        avatarPath: avatarPath,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        checkIn: checkIn,
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
        pactIndex: (row['pact_index'] as num?)?.toInt(),
        clapCount: (row['clap_count'] as num?)?.toInt() ?? 0,
        avatarPath: row['avatar_path'] as String?,
        checkIn: CheckInRef.tryRead(row),
      );
}

abstract interface class HomeBackend {
  Future<Map<String, CrewNudgeState>> fetchNudgeStates(String crewId);
  Future<CrewNudgeState> sendNudge({
    required String crewId,
    required String recipientId,
  });

  /// The crew's week: this one, or the finished week that began on
  /// [weekStart] (a Monday, `yyyy-MM-dd`). A past week comes back with the
  /// real [CrewWeek.today], so nothing in it reads as still open.
  Future<CrewWeek> fetchWeek(String crewId, {String? weekStart});

  /// The crew's week around [checkIn], with that check-in's photo signed
  /// whatever day it was kept on, for opening it as a story.
  Future<CrewWeek> fetchCheckInWeek(CheckInRef checkIn);

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

  /// Every check-in that kept a photo in the calendar month beginning on
  /// [monthStart] (`yyyy-MM-01`), oldest first, each with its photo signed
  /// and the claps it has.
  Future<List<PactCheckIn>> fetchMonthPhotos(
    String crewId, {
    required String monthStart,
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

  /// Posts [text] to the crew as one of today's achievements, with the
  /// [photo] every achievement carries, and returns it as the server dated
  /// it. [today] is
  /// the crew's day the photo is filed under, as a check-in photo's is.
  Future<Achievement> postAchievement({
    required String crewId,
    required String text,
    required String today,
    required Uint8List photo,
    PostKind kind = PostKind.achievement,
  });

  /// Takes down one of the viewer's own achievements, claps and all.
  Future<void> deleteAchievement(String achievementId);

  /// The achievement counterpart of [setClap]: idempotent both ways, and
  /// answers with the achievement's clap count afterwards.
  Future<int> setAchievementClap({
    required String achievementId,
    required bool clapped,
  });
}

class SupabaseHomeBackend implements HomeBackend {
  SupabaseHomeBackend(this.client);
  final _avatarUrls = AvatarUrlCache();
  final _notificationAvatars = AvatarUrlCache();
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
  Future<List<PactCheckIn>> fetchMonthPhotos(
    String crewId, {
    required String monthStart,
  }) async {
    final rows = await client.rpc(
      'crew_month_photos',
      params: {'target_crew_id': crewId, 'month_start': monthStart},
    );
    final checkIns = [
      for (final row in rows as List)
        PactCheckIn.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    // One batch of signed URLs for the month, rather than one per tile.
    final urls = await _signed(
      'check-in-photos',
      checkIns.map((i) => i.photoPath).nonNulls.toSet().toList(),
    );
    return [
      for (final checkIn in checkIns)
        if (urls[checkIn.photoPath] case final url?) checkIn.withPhotoUrl(url),
    ];
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

  @override
  Future<int> setAchievementClap({
    required String achievementId,
    required bool clapped,
  }) async {
    final row = Map<String, dynamic>.from(
      await client.rpc(
        'set_achievement_clap',
        params: {'target_achievement_id': achievementId, 'clapped': clapped},
      ),
    );
    return (row['clap_count'] as num).toInt();
  }

  @override
  Future<Achievement> postAchievement({
    required String crewId,
    required String text,
    required String today,
    required Uint8List photo,
    PostKind kind = PostKind.achievement,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to post.');
    if (photo.isEmpty || photo.length > 5 * 1024 * 1024) {
      throw StateError('Invalid achievement photo.');
    }
    final path = '$userId/$crewId/achievements/$today/${_nonce()}.png';
    try {
      await client.storage
          .from('check-in-photos')
          .uploadBinary(
            path,
            photo,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
      final posted = Achievement.fromJson(
        Map<String, dynamic>.from(
          await client.rpc(
            'post_crew_achievement',
            params: {
              'target_crew_id': crewId,
              'achievement_body': text.trim(),
              'photo': path,
              'post_kind': kind.name,
            },
          ),
        ),
      );
      final urls = await _signed('check-in-photos', [path]);
      return posted.withPhotoUrl(urls[path]);
    } finally {
      // As a check-in's: queued only when nothing ended up naming it.
      try {
        await client.rpc(
          'discard_unused_check_in_photos',
          params: {
            'paths': [path],
          },
        );
      } catch (_) {
        /* Orphan sweeper retries. */
      }
    }
  }

  static String _nonce() {
    final random = math.Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  Future<void> deleteAchievement(String achievementId) => client.rpc(
    'delete_crew_achievement',
    params: {'target_achievement_id': achievementId},
  );

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
  Future<CrewWeek> fetchCheckInWeek(CheckInRef checkIn) async {
    // Any day of a week names it, this week's included.
    final week = await fetchWeek(checkIn.crewId, weekStart: checkIn.day);
    // Only today's photos come signed; an older one is signed here.
    final missing = week.checkIns
        .where((i) => checkIn.matches(i) && i.photoUrl == null)
        .map((i) => i.photoPath)
        .nonNulls
        .toList();
    final urls = await _signed('check-in-photos', missing);
    if (urls.isEmpty) return week;
    return CrewWeek(
      today: week.today,
      weekStart: week.weekStart,
      timezone: week.timezone,
      pacts: week.pacts,
      members: week.members,
      checkIns: [
        for (final i in week.checkIns)
          if (urls[i.photoPath] case final url? when checkIn.matches(i))
            i.withPhotoUrl(url)
          else
            i,
      ],
      streakWeeks: week.streakWeeks,
      latestActivity: week.latestActivity,
      achievements: week.achievements,
    );
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
    // Today's achievements, for the rail beside today's check-ins. A past
    // week has no rail, so it goes without. A failure here is its own: the
    // week is the page, and an achievement is one thing on it.
    final achievements = weekStart != null
        ? const <Achievement>[]
        : await client
              .rpc(
                'crew_achievements',
                params: {'target_crew_id': crewId, 'on_day': week.today},
              )
              .then(
                (rows) => [
                  for (final row in rows as List)
                    Achievement.fromJson(Map<String, dynamic>.from(row as Map)),
                ],
              )
              .catchError((Object _) => const <Achievement>[]);
    // Today's photos, signed for the stories rail. Only today's: the rail
    // shows the day, and the week's older check-ins are counted rather than
    // opened.
    final stories = await _signed('check-in-photos', [
      ...{
        ...week.checkIns
            .where((i) => i.day == week.today)
            .map((i) => i.photoPath)
            .nonNulls,
        ...achievements.map((a) => a.photoPath).nonNulls,
      },
    ]);
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
      achievements: [
        for (final a in achievements) a.withPhotoUrl(stories[a.photoPath]),
      ],
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
  Future<List<PactCheckIn>> fetchMonthPhotos(
    String crewId, {
    required String monthStart,
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
  Future<CrewWeek> fetchCheckInWeek(CheckInRef checkIn) =>
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
  @override
  Future<Achievement> postAchievement({
    required String crewId,
    required String text,
    required String today,
    required Uint8List photo,
    PostKind kind = PostKind.achievement,
  }) => Future.error(StateError('Supabase is not configured.'));
  @override
  Future<void> deleteAchievement(String achievementId) =>
      Future.error(StateError('Supabase is not configured.'));
  @override
  Future<int> setAchievementClap({
    required String achievementId,
    required bool clapped,
  }) => Future.error(StateError('Supabase is not configured.'));
}
