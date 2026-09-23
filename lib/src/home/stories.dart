import 'package:flutter/material.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import 'home_backend.dart';

/// One check-in, read as a story: what was kept, when, and the colour the pact
/// wears everywhere else.
///
/// A story is a check-in and nothing more. A pact that asks for a photo leaves
/// one on the row; a pact that does not leaves a check-in the viewer still
/// opens, drawn in the pact's own tint. The rail never invents a post.
class Story {
  const Story({
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
  final Color tint;
  final Color badge;

  String get id => checkIn.id;
  String? get photoUrl => checkIn.photoUrl;
  bool get hasPhoto => checkIn.photoUrl != null;
  DateTime? get keptAt => checkIn.keptAt;
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

  /// Today's check-ins, oldest first — the order the viewer walks them in.
  final List<Story> stories;

  /// Every story here has been opened on this device. False when there is
  /// nothing to open, which the dashed tile says for itself.
  final bool seen;
  final bool isViewer;

  bool get isIn => stories.isNotEmpty;

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
      final stories =
          week.checkIns
              .where(
                (i) =>
                    i.userId == member.id &&
                    i.day == week.today &&
                    byPact.containsKey(i.pactId),
              )
              .map((i) {
                final (index, pact) = byPact[i.pactId]!;
                return Story(
                  checkIn: i,
                  pact: pact,
                  tint: WeekPactColors.pactTint(index),
                  badge: WeekPactColors.pactBadge(index),
                );
              })
              .toList()
            ..sort((a, b) => _at(a).compareTo(_at(b)));
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
