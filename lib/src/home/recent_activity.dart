import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../crew/crew_switcher.dart';
import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/page_frame.dart';
import 'home_backend.dart';
import 'home_surface.dart';
import 'today_widgets.dart';

/// The crew's last check-in, between the heading and the crew block: one line
/// of proof that the week is being kept, with the feed a tap away for the rest
/// of it. It leads because it is the page's news — what the crew block and the
/// stack under it carry is the week's standing state, which does not change
/// between glances.
///
/// It is the crew block's own surface, not a card of its own: the same
/// recessed face, outline, raised edge and frame corner (`CrewHeaderSurface`
/// on [CrewWeekButton.frameCurve]), so the two blocks under the heading read
/// as one pair rather than as two different card languages stacked up. It
/// carries a face, a line in the page's ink and a muted caption under it, as
/// the crew week's streak panel does.
///
/// It is labelled as the crew block labels its own rows — `LATEST ACTIVITY` in
/// the same `CrewControlLabel`, at the same height and gap — so the two blocks
/// name their contents the same way. The whole card is still the way through
/// to the feed; the label names what is in it rather than standing over it as
/// a section heading.
class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({
    super.key,
    required this.week,
    required this.userId,
    this.now,
    this.onOpenFeed,
  });

  /// The loading state: the same card at the same height with its lines not
  /// yet filled in, so nothing under it moves when the week arrives.
  const RecentActivityCard.loading({super.key})
    : week = null,
      userId = '',
      now = null,
      onOpenFeed = null;

  final CrewWeek? week;
  final String userId;

  /// Fixed in tests, so the day a check-in is labelled with never depends on
  /// when the suite runs.
  final DateTime? now;
  final VoidCallback? onOpenFeed;

  /// The card's own inset, top and bottom, as the streak panel takes it.
  static const inset = 14.0;

  /// The label over the check-in, and the gap under it. These used to alias
  /// the crew strip's own, back when it carried a `TODAY` eyebrow at the same
  /// height — the pair read as one block labelled twice. The strip has since
  /// collapsed to a single unlabelled row, so this card owns the measurements
  /// it is the last user of.
  static const labelHeight = 12.0;
  static const labelGap = 8.0;

  /// The check-in's own line: the face, and the pair of lines beside it.
  static double lineHeightOf(BuildContext context) =>
      math.max(30, 36 * MediaQuery.textScalerOf(context).scale(1));

  /// The card grows with the text, so both of its lines stay whole where the
  /// heading above it can simply scale itself down.
  static double cardHeightOf(BuildContext context) =>
      inset * 2 + labelHeight + labelGap + lineHeightOf(context);

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
    final crew = week;
    final activity = crew?.latestActivity;
    final member = crew?.members
        .where((m) => m.id == activity?.userId)
        .firstOrNull;
    final pact = crew?.pacts.where((p) => p.id == activity?.pactId).firstOrNull;
    return SizedBox(
      height: cardHeightOf(context),
      child: _ActivityCard(
        loading: crew == null,
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

/// The crew block's surface, carrying a check-in: the same recessed face,
/// outline, raised edge and frame corner, an icon-sized face where the streak
/// panel puts its flame, and the pair of lines beside it.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.loading,
    required this.activity,
    required this.member,
    required this.pact,
    required this.isMine,
    required this.now,
    required this.onOpenFeed,
  });

  final bool loading;
  final CrewActivity? activity;
  final WeekMember? member;
  final CrewPact? pact;
  final bool isMine;
  final DateTime? now;
  final VoidCallback? onOpenFeed;

  @override
  Widget build(BuildContext context) {
    final entry = activity;
    return CrewHeaderSurface(
      // The crew block's own frame corner, so the block above it and the
      // block below carry one shape between them.
      curve: CrewWeekButton.frameCurve,
      child: InkWell(
        key: const ValueKey('activity-card'),
        onTap: onOpenFeed,
        child: Padding(
          padding: const EdgeInsets.all(RecentActivityCard.inset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                height: RecentActivityCard.labelHeight,
                child: CrewControlLabel('LATEST ACTIVITY'),
              ),
              const SizedBox(height: RecentActivityCard.labelGap),
              Expanded(
                child: loading
                    ? const _LoadingLines()
                    : entry == null
                    ? Center(
                        key: const ValueKey('activity-empty'),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'No check-ins yet',
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        key: ValueKey(
                          'activity-${entry.pactId}-${entry.userId}',
                        ),
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
                              color: context.muted,
                              size: 24,
                            ),
                          ],
                        ],
                      ),
              ),
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
          style: TextStyle(
            color: context.ink,
            fontSize: 16,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${RecentActivityCard.day(context, at, now ?? DateTime.now())}, '
          '$time',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.muted, fontSize: 12, height: 1.2),
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

/// The card before the week arrives: the face, the line and the caption as
/// bars, laid out where the check-in's own will land, so the card is the same
/// height and the same shape either way.
class _LoadingLines extends StatelessWidget {
  const _LoadingLines();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SkeletonBar(width: 30, height: 30, radius: 15),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            SkeletonBar(width: 168, height: 13),
            SizedBox(height: 7),
            SkeletonBar(width: 92, height: 10),
          ],
        ),
      ),
    ],
  );
}
