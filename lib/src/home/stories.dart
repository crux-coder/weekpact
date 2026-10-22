import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import 'home_backend.dart';

/// The one glyph an achievement is drawn with, wherever it appears.
const achievementIcon = HugeIconsStrokeRounded.champion;

/// One thing a member did today, as the rail and the viewer draw it: a pact
/// check-in, or an achievement posted outside any pact.
///
/// The two are mixed in one member's day, in the order they happened, and
/// told apart by colour and by the chip the viewer pins to each: a check-in
/// wears its pact's sorbet and badge, an achievement wears gold and a trophy.
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
  });

  final PactCheckIn checkIn;
  final CrewPact pact;

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

/// An achievement, read as a story: the member's own words over a gold wash.
///
/// Gold is the podium's colour for a week fully kept, and none of the pact
/// sorbets, so an achievement never reads as one more pact in the rail.
class AchievementStory extends Story {
  const AchievementStory(this.achievement);

  final Achievement achievement;

  @override
  String get id => achievement.id;
  @override
  String get userId => achievement.userId;
  @override
  String? get photoUrl => null;
  @override
  DateTime? get keptAt => achievement.postedAt;
  @override
  Color get tint => WeekPactColors.achievement;
  @override
  Color get badge => WeekPactColors.achievementBadge;
  @override
  int get clapCount => achievement.clapCount;
  @override
  bool get viewerClapped => achievement.viewerClapped;
  String get text => achievement.text;
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
  /// with a trophy on the tile.
  bool get hasAchievement => stories.any((s) => s is AchievementStory);

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
