import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../home/home_backend.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'pact_icons.dart';
import '../widgets/app_icon.dart';
import '../widgets/pact_icon_badge.dart';
import 'pacts_backend.dart';

class YourWeekCard extends StatelessWidget {
  const YourWeekCard({super.key, required this.week, required this.userId});

  final CrewWeek week;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final completed = week.completed(userId);
    final target = week.target;
    final remaining = target - completed;
    final today = DateTime.parse('${week.today}T00:00:00Z');
    final start = DateTime.parse('${week.weekStart}T00:00:00Z');
    final daysLeft = (7 - today.difference(start).inDays).clamp(1, 7);
    return AppSurface(
      fillColor: WeekPactColors.stone,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your week so far',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (target == 0)
              Text(
                'Add a pact to start your week.',
                style: TextStyle(color: context.muted),
              )
            else ...[
              Text(
                '$completed of $target check-ins done',
                key: const ValueKey('weekly-progress-total'),
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: completed / target,
                minHeight: 10,
                borderRadius: WeekPactMetrics.pill,
                color: context.ink,
                backgroundColor: context.ink.withValues(alpha: .12),
                semanticsLabel:
                    'Your weekly check-ins: $completed of $target completed',
              ),
              const SizedBox(height: 10),
              Text(
                remaining == 0
                    ? 'All weekly targets met. Nice work!'
                    : '$remaining left · ${daysLeft == 1 ? 'Today is the last day' : '$daysLeft days remaining, including today'}',
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: context.border),
              const SizedBox(height: 6),
              for (final pact in week.pacts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      AppIcon(
                        icon: PactIcon.find(pact.iconKey).data,
                        color: context.ink,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pact.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${week.days(pact.id, userId).clamp(0, pact.daysPerWeek)} / ${pact.daysPerWeek}',
                        key: ValueKey('weekly-progress-${pact.id}'),
                        semanticsLabel:
                            '${pact.title}: ${week.days(pact.id, userId).clamp(0, pact.daysPerWeek)} of ${pact.daysPerWeek} check-ins',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The pact list: one full-width card per pact, each in its own colour, so a
/// pact is recognised by the same tint here that it wears on Home and on the
/// crew week.
class PactBarList extends StatelessWidget {
  const PactBarList({
    super.key,
    required this.pacts,
    this.onEdit,
    this.onDelete,
  });
  final List<CrewPact> pacts;
  final ValueChanged<CrewPact>? onEdit;
  final ValueChanged<CrewPact>? onDelete;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, pact) in pacts.indexed) ...[
        if (index > 0) const SizedBox(height: 8),
        PactBar(
          key: ValueKey('pact-management-${pact.id}'),
          pact: pact,
          tint: WeekPactColors.pactTint(index),
          badge: WeekPactColors.pactBadge(index),
          onEdit: onEdit == null ? null : () => onEdit!(pact),
          onDelete: onDelete == null ? null : () => onDelete!(pact),
        ),
      ],
    ],
  );
}

/// One pact card, in the pact's own tint.
///
/// The tint used to run only part way across — a fill measuring the pact
/// against a seven day week, on a bare cream track. The card says it plainly
/// now: the count under the title is the number, and the colour is only which
/// pact this is. A card in one colour is also one object rather than two, so a
/// title crossing what used to be the fill's edge no longer sat half on the
/// tint and half off it.
class PactBar extends StatelessWidget {
  const PactBar({
    super.key,
    required this.pact,
    this.tint,
    this.badge,
    this.onEdit,
    this.onDelete,
  });
  final CrewPact pact;

  /// The track's fill, and the deeper companion the icon badge is drawn in.
  final Color? tint;
  final Color? badge;

  /// What the bar's menu offers. Both are the owner's alone, so a member sees
  /// no menu at all rather than one whose every entry is greyed out.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      // The whole card is the tint, so [AppSurface] mixes its outline and its
      // raised edge from that rather than from the cream it used to sit on —
      // the same pairing Home's pact card makes from the same colour.
      fillColor: tint ?? context.yellow,
      borderRadius: WeekPactMetrics.cardCorner,
      builder: (context) => Semantics(
        label:
            '${pact.title}. ${pact.schedule}.'
            '${pact.photoRequired ? ' Photo check-in' : ' No photo needed'}',
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                10,
                onEdit == null && onDelete == null ? 14 : 4,
                10,
              ),
              child: Row(
                children: [
                  PactIconBadge(
                    icon: PactIcon.find(pact.iconKey).data,
                    tint: badge ?? WeekPactColors.pactBadge(0),
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  // The count sits under the name as its caption rather
                  // than beside it as a column of its own. Set beside the
                  // name it took a fixed bite out of every row — enough to
                  // ellipsize a title that would otherwise have fit. Here
                  // it costs the title nothing, and with the card in one
                  // flat colour it is the only thing that says how much of
                  // the week the pact claims.
                  Expanded(
                    child: Tooltip(
                      message: pact.schedule,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pact.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.ink,
                              fontSize: 19,
                              height: 1.1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${pact.daysPerWeek}/week',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              // `.74` clears 4.5:1 on the deepest of the
                              // ten tints and 7:1 on the lightest, so the
                              // caption reads as secondary on every card
                              // rather than vanishing on some of them.
                              color: context.ink.withValues(alpha: .74),
                              fontSize: 13,
                              height: 1.1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    _PactMenu(
                      key: ValueKey('pact-menu-${pact.id}'),
                      pact: pact,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a bar's owner can do to it, behind the one button the bar has room
/// for. Editing and deleting are both whole-pact actions and neither is the
/// obvious default, so they share a menu rather than one of them taking the
/// bar's only slot and the other going somewhere else on the page.
class _PactMenu extends StatelessWidget {
  const _PactMenu({super.key, required this.pact, this.onEdit, this.onDelete});

  final CrewPact pact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: '${pact.title} options',
    // The menu is a small card, cut to the same corner and sat on the same
    // fill as the surfaces around it, rather than Material's flat rectangle.
    color: context.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeekPactMetrics.cardCorner),
      side: BorderSide(color: context.border),
    ),
    position: PopupMenuPosition.under,
    onSelected: (action) => action(),
    itemBuilder: (context) => [
      if (onEdit != null)
        PopupMenuItem(
          value: onEdit,
          child: _PactMenuEntry(
            icon: HugeIconsStrokeRounded.pencilEdit02,
            label: 'Edit pact',
            color: context.ink,
          ),
        ),
      if (onDelete != null)
        PopupMenuItem(
          value: onDelete,
          child: _PactMenuEntry(
            icon: HugeIconsStrokeRounded.delete02,
            label: 'Delete pact',
            color: context.errorInk,
          ),
        ),
    ],
    icon: AppIcon(
      icon: HugeIconsStrokeRounded.moreHorizontal,
      color: context.ink,
      size: 22,
    ),
  );
}

class _PactMenuEntry extends StatelessWidget {
  const _PactMenuEntry({
    required this.icon,
    required this.label,
    required this.color,
  });

  final List<List<dynamic>> icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppIcon(icon: icon, color: color, size: 20),
      const SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

/// The pacts page's own loading shapes: the week card, the list heading and a
/// few bars, so the page does not rearrange itself the moment it loads.
class PactsSkeletonBody extends StatelessWidget {
  const PactsSkeletonBody({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSurface(
        fillColor: WeekPactColors.stone,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SkeletonBar(width: 150, height: 18),
              const SizedBox(height: 16),
              const SkeletonBar(width: 210, height: 26),
              const SizedBox(height: 14),
              const SkeletonBar(height: 10, radius: 999),
              const SizedBox(height: 10),
              const SkeletonBar(width: 170, height: 12),
              const SizedBox(height: 18),
              Divider(height: 1, color: context.border),
              const SizedBox(height: 6),
              for (var i = 0; i < 2; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SkeletonBar(width: 22, height: 22),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBar(height: 14)),
                      SizedBox(width: 12),
                      SkeletonBar(width: 40, height: 14),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Row(
        children: [
          SkeletonBar(width: 120, height: 20),
          Spacer(),
          SkeletonBar(width: 84, height: 10),
        ],
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        AppSurface(
          borderRadius: WeekPactMetrics.cardCorner,
          builder: (context) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  SkeletonBar(width: 40, height: 40),
                  SizedBox(width: 12),
                  SkeletonBar(width: 22, height: 28),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonBar(height: 16)),
                  SizedBox(width: 12),
                  SkeletonBar(width: 22, height: 22),
                ],
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const SkeletonBar(height: 48, radius: WeekPactMetrics.controlRadius),
    ],
  );
}
