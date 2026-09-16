import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';

/// Geometry for the crew fan: a hand of cards dealt downward from the thumb.
///
/// Kept separate from the widgets so the same rectangles decide where a card is
/// painted and which card a finger is currently over.
abstract final class CrewFanLayout {
  static const cardHeight = 76.0;
  static const _gap = 10.0;
  static const _sideInset = 16.0;
  static const _reachBelowThumb = 30.0;

  static double cardWidth(Size screen) =>
      math.min(300.0, screen.width - _sideInset * 2);

  /// One rectangle per crew, in global coordinates, ordered like [crews].
  static List<Rect> of({
    required Size screen,
    required EdgeInsets padding,
    required Offset anchor,
    required int count,
  }) {
    if (count == 0) return const [];
    final width = cardWidth(screen);
    final top = anchor.dy + _reachBelowThumb;
    // Tighten the spacing rather than run off the bottom when a crew list grows.
    final room = screen.height - padding.bottom - 12 - top;
    final step = math.min(
      cardHeight + _gap,
      count > 1 ? (room - cardHeight) / (count - 1) : cardHeight + _gap,
    );
    return [
      for (var i = 0; i < count; i++)
        Rect.fromLTWH(
          _left(screen, anchor, width, i, count),
          top + step * i,
          width,
          cardHeight,
        ),
    ];
  }

  /// A gentle bulge away from the thumb, so the stack reads as a fanned hand.
  static double _left(
    Size screen,
    Offset anchor,
    double width,
    int index,
    int count,
  ) {
    final t = count > 1 ? index / (count - 1) : .5;
    final sway = math.sin(t * math.pi) * 16;
    return (anchor.dx - width / 2 + sway).clamp(
      _sideInset,
      math.max(_sideInset, screen.width - width - _sideInset),
    );
  }

  /// The tilt each card carries, so the hand splays instead of stacking square.
  static double rotation(int index, int count) {
    if (count < 2) return 0;
    return ((index / (count - 1)) - .5) * .075;
  }

  /// The card under [point], or null when the finger is off the hand.
  static int? hit(List<Rect> cards, Offset point) {
    for (var i = cards.length - 1; i >= 0; i--) {
      if (cards[i].inflate(4).contains(point)) return i;
    }
    return null;
  }
}

/// The overlay itself: a scrim, then one card per crew dealt from the thumb.
class CrewFan extends StatelessWidget {
  const CrewFan({
    super.key,
    required this.crews,
    required this.selectedId,
    required this.highlighted,
    required this.cards,
    required this.anchor,
    required this.animation,
    required this.onPicked,
    required this.onDismissed,
  });

  final List<PactCrew> crews;
  final String? selectedId;
  final int? highlighted;
  final List<Rect> cards;
  final Offset anchor;
  final Animation<double> animation;
  final ValueChanged<int> onPicked;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onDismissed,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(
                color: WeekPactColors.black.withValues(
                  alpha: .62 * animation.value,
                ),
              ),
            ),
          ),
          for (var i = 0; i < crews.length; i++) _card(context, i),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, int index) {
    final rect = cards[index];
    final crew = crews[index];
    final current = crew.id == selectedId;
    final active = index == highlighted;
    // Each card leaves the thumb a beat after the one before it.
    final start = (index * .08).clamp(0.0, .4);
    final progress = Curves.easeOutBack.transform(
      ((animation.value - start) / (1 - start)).clamp(0.0, 1.0),
    );
    final travel = Offset.lerp(
      Offset(anchor.dx - rect.center.dx, anchor.dy - rect.center.dy),
      Offset.zero,
      progress.clamp(0.0, 1.0),
    )!;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        ignoring: animation.value < .2,
        child: Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: travel,
            child: Transform.rotate(
              angle: CrewFanLayout.rotation(index, crews.length),
              child: Transform.scale(
                scale: active ? 1.05 : 1,
                child: _CrewFanCard(
                  crew: crew,
                  colour: WeekPactColors.pactTint(index),
                  current: current,
                  active: active,
                  onTap: () => onPicked(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewFanCard extends StatelessWidget {
  const _CrewFanCard({
    required this.crew,
    required this.colour,
    required this.current,
    required this.active,
    required this.onTap,
  });

  final PactCrew crew;
  final Color colour;
  final bool current;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: current,
      label: 'Switch to ${crew.name}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? WeekPactColors.black : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: WeekPactColors.black.withValues(
                  alpha: active ? .5 : .32,
                ),
                blurRadius: active ? 22 : 12,
                offset: Offset(0, active ? 10 : 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crew.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WeekPactColors.black,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (current)
                      Text(
                        'Current crew',
                        style: TextStyle(
                          color: WeekPactColors.black.withValues(alpha: .62),
                          fontFamily: 'Roboto',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (current)
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: WeekPactColors.black,
                    shape: BoxShape.circle,
                  ),
                  child: HugeIcon(
                    icon: HugeIconsStrokeRounded.tick02,
                    size: 16,
                    color: colour,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
