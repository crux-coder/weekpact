import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_icon.dart';
import '../widgets/avatar_shape.dart';
import 'home_backend.dart';
import 'home_surface.dart';

/// The crew's last check-in, under the pact stack: one line of proof that the
/// week is being kept, with the feed a tap away for the rest of it. Built as
/// the crew week's streak panel is — a dark card with a face, a line in the
/// card's own weight and a muted caption under it — on the pact card's corner,
/// so it shares a shape with the stack it sits under.
///
/// The card carries no heading of its own. It says what it is in its own line,
/// and the whole card is the way through to the feed, so a label over it would
/// only repeat what is already there.
class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({
    super.key,
    required this.week,
    required this.userId,
    this.now,
    this.onOpenFeed,
  });

  final CrewWeek week;
  final String userId;

  /// Fixed in tests, so the day a check-in is labelled with never depends on
  /// when the suite runs.
  final DateTime? now;
  final VoidCallback? onOpenFeed;

  /// The card's own inset, top and bottom, as the streak panel takes it.
  static const inset = 14.0;

  /// The card grows with the text, so both of its lines stay whole where the
  /// heading above it can simply scale itself down.
  static double cardHeightOf(BuildContext context) =>
      inset * 2 + math.max(30, 36 * MediaQuery.textScalerOf(context).scale(1));

  /// What the section occupies on Home.
  static double heightOf(BuildContext context) => cardHeightOf(context);

  /// The day a check-in reads as, at the coarseness a one-line entry needs.
  static String day(BuildContext context, DateTime at, DateTime now) {
    if (DateUtils.isSameDay(at, now)) return 'Today';
    if (DateUtils.isSameDay(at, DateUtils.addDaysToDate(now, -1))) {
      return 'Yesterday';
    }
    return MaterialLocalizations.of(context).formatMediumDate(at);
  }

  @override
  Widget build(BuildContext context) {
    final activity = week.latestActivity;
    final member = week.members
        .where((m) => m.id == activity?.userId)
        .firstOrNull;
    final pact = week.pacts.where((p) => p.id == activity?.pactId).firstOrNull;
    return SizedBox(
      height: cardHeightOf(context),
      child: _ActivityCard(
        activity: activity,
        member: member,
        pact: pact,
        isMine: activity?.userId == userId,
        now: now,
        onOpenFeed: onOpenFeed,
      ),
    );
  }
}

/// The streak panel's card, carrying a check-in: the same dark fill, outline
/// and raised edge, an icon-sized face where it puts its flame, and the pair
/// of lines beside it.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.activity,
    required this.member,
    required this.pact,
    required this.isMine,
    required this.now,
    required this.onOpenFeed,
  });

  final CrewActivity? activity;
  final WeekMember? member;
  final CrewPact? pact;
  final bool isMine;
  final DateTime? now;
  final VoidCallback? onOpenFeed;

  @override
  Widget build(BuildContext context) {
    final entry = activity;
    return AppSurface(
      fillColor: WeekPactDarkCard.fill,
      resolveTone: false,
      outlineColor: WeekPactDarkCard.outline,
      // The pact card's corner, so the card sitting under the stack carries
      // the stack's own shape rather than a second one.
      shape: WeekPactMetrics.pactCardShape,
      builder: (context) => InkWell(
        key: const ValueKey('activity-card'),
        onTap: onOpenFeed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RecentActivityCard.inset,
          ),
          child: entry == null
              ? Center(
                  key: const ValueKey('activity-empty'),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'No check-ins yet',
                      style: TextStyle(
                        color: WeekPactDarkCard.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : Row(
                  key: ValueKey('activity-${entry.pactId}-${entry.userId}'),
                  children: [
                    _Avatar(member: member),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Lines(
                        entry: entry,
                        isMine: isMine,
                        member: member,
                        pact: pact,
                        now: now,
                      ),
                    ),
                    if (pact != null) ...[
                      const SizedBox(width: 10),
                      // The pact's own icon, as the feed puts it beside a
                      // check-in: stated, not coloured in.
                      AppIcon(
                        icon: PactIcon.find(pact!.iconKey).data,
                        color: WeekPactDarkCard.muted,
                        size: 24,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({
    required this.entry,
    required this.isMine,
    required this.member,
    required this.pact,
    required this.now,
  });

  final CrewActivity entry;
  final bool isMine;
  final WeekMember? member;
  final CrewPact? pact;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final name = isMine
        ? 'You'
        : member == null || member!.displayName.trim().isEmpty
        ? 'A crew member'
        : member!.displayName.trim().split(RegExp(r'\s+')).first;
    final title = pact?.title ?? entry.pactTitle;
    final at = entry.createdAt.toLocal();
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title == null ? '$name checked in' : '$name checked in to $title',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: WeekPactDarkCard.ink,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${RecentActivityCard.day(context, at, now ?? DateTime.now())}, '
          '$time',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: WeekPactDarkCard.muted,
            fontSize: 12,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The member's face, at the size the streak panel gives its flame.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.member});
  final WeekMember? member;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      member?.initials ?? '?',
      style: const TextStyle(color: homeInk, fontSize: 12),
    );
    final url = member?.avatarUrl;
    return FlatAvatar(
      radius: 15,
      backgroundColor: WeekPactColors.mintGreen,
      child: AvatarClip(
        child: url == null
            ? initials
            : Image.network(
                url,
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => initials,
              ),
      ),
    );
  }
}
