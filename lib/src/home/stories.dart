import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import 'home_backend.dart';

/// The one glyph an achievement is drawn with, wherever it appears.
const achievementIcon = HugeIconsStrokeRounded.champion;

/// How each kind of post is drawn, wherever it appears: the rail, the viewer,
/// and the toggle that picks between them. Gold and a trophy for a win,
/// lavender and a camera for a plain story.
extension PostKindLook on PostKind {
  List<List<dynamic>> get icon => switch (this) {
    PostKind.achievement => achievementIcon,
    PostKind.story => HugeIconsStrokeRounded.camera02,
  };

  Color get tint => switch (this) {
    PostKind.achievement => WeekPactColors.achievement,
    PostKind.story => WeekPactColors.story,
  };

  Color get badge => switch (this) {
    PostKind.achievement => WeekPactColors.achievementBadge,
    PostKind.story => WeekPactColors.storyBadge,
  };

  String get label => switch (this) {
    PostKind.achievement => 'Achievement',
    PostKind.story => 'Story',
  };
}

/// One thing a member did today, as the rail and the viewer draw it: a pact
/// check-in, or an achievement or story posted outside any pact.
///
/// The two are mixed in one member's day, in the order they happened, and
/// told apart by colour and by the chip the viewer pins to each: a check-in
/// wears its pact's sorbet and badge, an achievement gold and a trophy, a
/// plain story lavender and a camera.
sealed class Story {
  const Story();

  /// The one name a story goes by: a clap and a seen mark mean it by this.
  String get id;
  String get userId;
  String? get photoUrl;
  bool get hasPhoto => photoUrl != null;
  DateTime? get keptAt;

  /// The story's wash colour, and the deeper hue its ring and badge take.
  Color get tint;
  Color get badge;

  /// The claps this story already has, and whether the viewer gave one.
  /// The viewer opens on these rather than on zero — a clap is the one thing
  /// a story asks for, and a page that forgets the ones already given asks
  /// for it again every time.
  int get clapCount;
  bool get viewerClapped;
}

/// One check-in, read as a story: what was kept, when, and the colour the pact
/// wears everywhere else.
///
/// A pact that asks for a photo leaves one on the row; a pact that does not
/// leaves a check-in the viewer still opens, drawn in the pact's own tint.
class PactStory extends Story {
  const PactStory({
    required this.checkIn,
    required this.pact,
    required this.tint,
    required this.badge,
    this.week,
  });

  final PactCheckIn checkIn;
  final CrewPact pact;

  /// The member's week on this pact, which a check-in without a photo shows
  /// in place of one. Null where the week is not to hand, as in a month of
  /// photos, which never needs it.
  final StoryWeek? week;

  /// The pact's card colour, and the deeper hue its badge and ring take. Both
  /// come from the pact's place in the crew's list, so a story is the same
  /// colour as the card the check-in was made on.
  @override
  final Color tint;
  @override
  final Color badge;

  @override
  String get id => checkIn.id;
  @override
  String get userId => checkIn.userId;
  @override
  String? get photoUrl => checkIn.photoUrl;
  @override
  DateTime? get keptAt => checkIn.keptAt;
  @override
  int get clapCount => checkIn.clapCount;
  @override
  bool get viewerClapped => checkIn.viewerClapped;
}

/// One member's week on one pact, Monday first: the days they kept it, which
/// of them is today, and how many the pact asks for.
///
/// A check-in without a photo has nothing to show but the fact of itself, so
/// it shows where it leaves the week instead — the one thing about it that is
/// news, and different every day.
class StoryWeek {
  const StoryWeek({
    required this.kept,
    required this.today,
    required this.target,
  });

  /// Reads [userId]'s week on [pact] out of the crew's.
  factory StoryWeek.read(CrewWeek week, CrewPact pact, String userId) {
    final start = _date(week.weekStart);
    int index(String day) => _date(day).difference(start).inDays;
    final kept = List.filled(DateTime.daysPerWeek, false);
    for (final i in week.checkIns) {
      if (i.pactId != pact.id || i.userId != userId) continue;
      final at = index(i.day);
      if (at >= 0 && at < kept.length) kept[at] = true;
    }
    return StoryWeek(
      kept: kept,
      today: index(week.today).clamp(0, kept.length - 1),
      target: pact.frequency == PactFrequency.daily
          ? DateTime.daysPerWeek
          : pact.daysPerWeek,
    );
  }

  final List<bool> kept;
  final int today;
  final int target;

  int get count => kept.where((day) => day).length;
  int get left => target - count;

  /// A `yyyy-MM-dd` day as a UTC midnight, so the days between two of them
  /// are whole days whatever the clocks did in between.
  static DateTime _date(String day) {
    final parsed = DateTime.parse(day);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
}

/// A post outside any pact, read as a story: the member's own words over
/// their photo, in the colours of its [PostKind].
///
/// Neither kind's colour is one of the pact sorbets, so a post never reads as
/// one more pact in the rail.
class AchievementStory extends Story {
  const AchievementStory(this.achievement);

  final Achievement achievement;

  @override
  String get id => achievement.id;
  @override
  String get userId => achievement.userId;
  @override
  String? get photoUrl => achievement.photoUrl;
  @override
  DateTime? get keptAt => achievement.postedAt;
  @override
  Color get tint => kind.tint;
  @override
  Color get badge => kind.badge;
  @override
  int get clapCount => achievement.clapCount;
  @override
  bool get viewerClapped => achievement.viewerClapped;
  String get text => achievement.text;
  PostKind get kind => achievement.kind;
}

/// One member's day, as the rail draws it: their stories, whether they have
/// all been seen, and whether this is the person holding the phone.
class MemberDay {
  const MemberDay({
    required this.member,
    required this.stories,
    required this.seen,
    required this.isViewer,
  });

  final WeekMember member;

  /// Today's check-ins and achievements, oldest first — the order the viewer
  /// walks them in.
  final List<Story> stories;

  /// Every story here has been opened on this device. False when there is
  /// nothing to open, which the dashed tile says for itself.
  final bool seen;
  final bool isViewer;

  bool get isIn => stories.isNotEmpty;

  /// Whether any of today's stories is an achievement, which the rail marks
  /// with a trophy on the tile. A plain story earns no mark: its ring says it.
  bool get hasAchievement => stories.any(
    (s) => s is AchievementStory && s.kind == PostKind.achievement,
  );

  /// The crew's day, in the order the rail shows it: you first, then whoever
  /// has something unseen, then the seen ones, then whoever is not in yet.
  ///
  /// You stay first whether or not you have checked in, because the left-most
  /// tile is where a rail is read from and your own day is the one you came to
  /// see. Everyone else appears whatever they have done: a crew of six is six
  /// tiles all day, so the rail reads as the crew rather than as a list that
  /// grows and reshuffles under the thumb.
  static List<MemberDay> read(
    CrewWeek week, {
    required String viewerId,
    Set<String> seen = const {},
  }) {
    final byPact = <String, (int, CrewPact)>{
      for (var i = 0; i < week.pacts.length; i++)
        week.pacts[i].id: (i, week.pacts[i]),
    };
    final days = <MemberDay>[];
    for (final member in week.members) {
      final stories = <Story>[
        for (final i in week.checkIns)
          if (i.userId == member.id &&
              i.day == week.today &&
              byPact.containsKey(i.pactId))
            PactStory(
              checkIn: i,
              pact: byPact[i.pactId]!.$2,
              tint: WeekPactColors.pactTint(byPact[i.pactId]!.$1),
              badge: WeekPactColors.pactBadge(byPact[i.pactId]!.$1),
              week: StoryWeek.read(week, byPact[i.pactId]!.$2, member.id),
            ),
        for (final a in week.achievements)
          if (a.userId == member.id && a.day == week.today) AchievementStory(a),
      ]..sort((a, b) => _at(a).compareTo(_at(b)));
      days.add(
        MemberDay(
          member: member,
          stories: stories,
          seen: stories.isNotEmpty && stories.every((s) => seen.contains(s.id)),
          isViewer: member.id == viewerId,
        ),
      );
    }
    // Rank and position together, so members who tie on rank keep the crew's
    // own order rather than whatever an unstable sort leaves them in.
    final order = <MemberDay, (int, DateTime, int)>{
      for (var i = 0; i < days.length; i++)
        days[i]: (_rank(days[i]), _latest(days[i]), i),
    };
    days.sort((a, b) {
      final first = order[a]!;
      final second = order[b]!;
      if (first.$1 != second.$1) return first.$1.compareTo(second.$1);
      // Newest first among people who are in; the crew's order decides the
      // rest, and any tie.
      final recency = second.$2.compareTo(first.$2);
      if (first.$1 != 3 && recency != 0) return recency;
      return first.$3.compareTo(second.$3);
    });
    return days;
  }

  static int _rank(MemberDay day) => day.isViewer
      ? 0
      : !day.isIn
      ? 3
      : day.seen
      ? 2
      : 1;

  static DateTime _at(Story story) =>
      story.keptAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime _latest(MemberDay day) => day.stories.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : _at(day.stories.last);
}
