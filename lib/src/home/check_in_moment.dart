import 'package:flutter/material.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/pact_icon_badge.dart';
import 'home_backend.dart';
import 'home_surface.dart';

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

/// The moment, shown over Home as a raised card in the pact's tint that drops
/// in under the status bar, holds for a breath, and lifts away. A tap sends
/// it off early.
///
/// Its whole life is one animation rather than a timer, so a page torn down
/// under it (a crew switched, a test ended) takes it along with nothing left
/// ticking.
class CheckInMomentBanner extends StatefulWidget {
  const CheckInMomentBanner({
    super.key,
    required this.moment,
    required this.tint,
    required this.badge,
    required this.iconKey,
    required this.onDone,
  });

  final CheckInMoment moment;
  final Color tint;
  final Color badge;
  final String iconKey;
  final VoidCallback onDone;

  /// The one banner on screen. A second check-in replaces the first rather
  /// than stacking under it.
  static OverlayEntry? _showing;

  /// Puts the banner up over [context]'s nearest overlay.
  static void show(
    BuildContext context, {
    required CheckInMoment moment,
    required int pactIndex,
    required String iconKey,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _showing?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => CheckInMomentBanner(
        key: const ValueKey('check-in-moment'),
        moment: moment,
        tint: WeekPactColors.pactTint(pactIndex),
        badge: WeekPactColors.pactBadge(pactIndex),
        iconKey: iconKey,
        onDone: () {
          if (_showing == entry) _showing = null;
          entry.remove();
        },
      ),
    );
    _showing = entry;
    overlay.insert(entry);
  }

  @override
  State<CheckInMomentBanner> createState() => _CheckInMomentBannerState();
}

class _CheckInMomentBannerState extends State<CheckInMomentBanner>
    with SingleTickerProviderStateMixin {
  static const _in = Duration(milliseconds: 360);
  static const _hold = Duration(milliseconds: 2400);
  static const _out = Duration(milliseconds: 260);

  late final _life = AnimationController(
    vsync: this,
    duration: _in + _hold + _out,
  );

  /// 1 while the card is up; the ends of the life ramp it in and out.
  late final Animation<double> _presence = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: _in.inMilliseconds.toDouble(),
    ),
    TweenSequenceItem(
      tween: ConstantTween(1.0),
      weight: _hold.inMilliseconds.toDouble(),
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: _out.inMilliseconds.toDouble(),
    ),
  ]).animate(_life);

  @override
  void initState() {
    super.initState();
    _life
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  /// Off early, from wherever the life has got to: the lift-out is the same
  /// length whether the hold ran or not.
  void _dismiss() {
    if (_life.status == AnimationStatus.completed) return;
    final outStart = 1 - _out.inMilliseconds / _life.duration!.inMilliseconds;
    if (_life.value < outStart) _life.value = outStart;
    _life.forward();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 12,
      right: 12,
      top: top + 8,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640 - 24),
          child: AnimatedBuilder(
            animation: _presence,
            builder: (context, child) {
              final presence = _presence.value.clamp(0.0, 1.2);
              return Transform.translate(
                offset: Offset(0, -24 * (1 - presence)),
                child: Opacity(opacity: presence.clamp(0.0, 1.0), child: child),
              );
            },
            child: Semantics(
              liveRegion: true,
              label: '${widget.moment.headline} ${widget.moment.detail}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: HomeSurface(
                  tint: widget.tint,
                  radius: WeekPactMetrics.cardCorner,
                  raised: true,
                  depth: WeekPactMetrics.cardDepth,
                  outlineColor: Color.lerp(widget.tint, Colors.black, .28),
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          PactIconBadge(
                            icon: PactIcon.find(widget.iconKey).data,
                            tint: widget.badge,
                            size: 44,
                          ),
                          // The done mark, as the card's own check-in wears it.
                          Positioned(
                            right: -5,
                            bottom: -5,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: WeekPactColors.doneMark,
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(
                                    color: WeekPactColors.cream,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: const Center(
                                child: AppIcon(
                                  icon: HugeIconsStrokeRounded.tick02,
                                  color: WeekPactColors.cream,
                                  size: 12,
                                  strokeWidth: 2.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.moment.headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: homeInk,
                                fontSize: 17,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.moment.detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: homeMutedInk,
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
