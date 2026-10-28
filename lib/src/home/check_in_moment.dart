import 'package:flutter/material.dart';

import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import 'home_backend.dart';

/// What Home says the moment a check-in lands: where that puts you in the
/// crew's day, and how far along the pact's week it takes you.
///
/// The reward for keeping a pact used to arrive later, as a clap, or not at
/// all; a habit is wired by what happens at the moment of the behaviour, so
/// this is said at once, before the week is refetched.
class CheckInMoment {
  const CheckInMoment({required this.headline, required this.detail});

  /// Who else is in today, or for a crew of one, where the week stands.
  final String headline;

  /// The pact's count for the week, and what is left of today.
  final String detail;

  /// Read off [week] as it stands with the check-in on [pactId] applied.
  static CheckInMoment read(
    CrewWeek week, {
    required String userId,
    required String pactId,
  }) {
    final pact = week.pacts.firstWhere((p) => p.id == pactId);
    final days = week.days(pactId, userId);
    final target = pact.daysPerWeek;
    final weekDone = days >= target;
    final left = week.pacts.length - week.checkedToday(userId).length;
    final members = week.members.map((m) => m.id).toSet();
    final inToday = week.checkIns
        .where((i) => i.day == week.today && members.contains(i.userId))
        .map((i) => i.userId)
        .toSet()
        .length;
    final headline = switch (members.length) {
      <= 1 =>
        weekDone
            ? '${pact.title} done for the week.'
            : 'Day $days of $target for ${pact.title}.',
      _ when inToday <= 1 => 'First in the crew today.',
      final crew when inToday >= crew => 'The whole crew is in today.',
      _ =>
        'You and ${inToday - 1} ${inToday == 2 ? 'crewmate' : 'crewmates'} '
            'are in today.',
    };
    final rest = left > 0
        ? '$left more ${left == 1 ? 'pact' : 'pacts'} today'
        : 'today done';
    final detail = members.length <= 1
        ? left > 0
              ? '${rest[0].toUpperCase()}${rest.substring(1)}.'
              : 'That’s everything for today.'
        : '${pact.title}: ${weekDone ? 'week done' : '$days of $target this week'}'
              ' · $rest';
    return CheckInMoment(headline: headline, detail: detail);
  }
}

/// The moment, put up as the app's own dialog in the pact's badge colour:
/// the pact's icon, the headline, the detail, and one button. It stays until
/// it is read and sent off, by the button or a tap outside it.
Future<void> showCheckInMoment(
  BuildContext context, {
  required CheckInMoment moment,
  required int pactIndex,
  required String iconKey,
}) => showDialog<void>(
  context: context,
  builder: (context) => AppDialog(
    key: const ValueKey('check-in-moment'),
    centered: true,
    icon: PactIcon.find(iconKey).data,
    iconColor: WeekPactColors.pactBadge(pactIndex),
    title: moment.headline,
    message: moment.detail,
    actions: [
      AppButton(label: 'NICE', onPressed: () => Navigator.pop(context)),
    ],
  ),
);
