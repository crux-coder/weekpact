import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';

/// Geometry for the crew fan: full-width cards stacked below the thumb.
///
/// Kept separate from the widgets so the same rectangles decide where a card is
/// painted and which card a finger is currently over.
abstract final class CrewFanLayout {
  static const cardHeight = 76.0;
  static const _gap = 12.0;
  static const _sideInset = 16.0;
  static const _reachBelowThumb = 30.0;

  /// Full bleed: a card is as wide as the screen allows, so a finger anywhere
  /// along it still leaves the crew name and its state in view.
  static double cardWidth(Size screen) =>
      math.max(0.0, screen.width - _sideInset * 2);

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
        Rect.fromLTWH(_sideInset, top + step * i, width, cardHeight),
    ];
  }

  /// The card under [point], or null when the finger is off the hand.
  static int? hit(List<Rect> cards, Offset point) {
    for (var i = cards.length - 1; i >= 0; i--) {
      if (cards[i].inflate(4).contains(point)) return i;
    }
    return null;
  }
}

/// The overlay itself: the backdrop, then one card per crew dealt from the thumb.
class CrewFan extends StatelessWidget {
  const CrewFan({
    super.key,
    required this.crews,
    required this.selectedId,
    required this.highlighted,
    required this.cards,
    required this.animation,
    required this.exit,
    required this.onPicked,
    required this.onDismissed,
  });

  final List<PactCrew> crews;
  final String? selectedId;
  final int? highlighted;
  final List<Rect> cards;
  final Animation<double> animation;

  /// 0 while the hand is out, 1 once it has left the top of the screen again.
  final Animation<double> exit;
  final ValueChanged<int> onPicked;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, exit]),
      builder: (context, _) {
        final offsets = _offsets();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onDismissed,
                behavior: HitTestBehavior.opaque,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            for (var i = crews.length - 1; i >= 0; i--)
              _card(context, i, offsets[i]),
          ],
        );
      },
    );
  }

  /// Where each card sits this frame, relative to its slot.
  ///
  /// A card that is still falling is held no more than one slot above the card
  /// before it. Without that, a late card would still be up at the top of the
  /// screen while the ones above it had landed — reading as the third crew
  /// sitting above the first. Held this way it stays hidden behind its
  /// neighbour (cards paint in reverse) and slides out from under it.
  List<double> _offsets() {
    final distance = cards.last.bottom + 24;
    if (exit.value > 0) {
      // Leaving, the stack travels as one: same distance for every card, so the
      // spacing that held on the way in cannot close up on the way out.
      final leaving = Curves.easeInCubic.transform(exit.value);
      return [for (var _ in cards) -distance * leaving];
    }
    final step = cards.length > 1 ? cards[1].top - cards[0].top : 0.0;
    final offsets = <double>[];
    for (var i = 0; i < cards.length; i++) {
      final progress = _progress(i);
      final own = progress <= 1
          ? -distance * (1 - progress)
          : (progress - 1) * _overshoot;
      offsets.add(i == 0 ? own : math.max(own, offsets[i - 1] - step));
    }
    return offsets;
  }

  /// The page behind goes soft rather than dark, so the crews read as cards
  /// held above it.
  static const _maxBlur = 16.0;
  double get _blur =>
      _maxBlur * (animation.value * 2).clamp(0.0, 1.0) * (1 - exit.value);

  /// Spring seconds one card's drop covers, and how far it dips past its
  /// resting place on the bounce. The window runs long enough for the spring to
  /// be flush at the end, or the cards park a pixel or two low.
  static const _settle = .5;
  static const _overshoot = 220.0;

  /// Spring seconds between one card's drop and the next.
  static const _lag = .05;

  /// Wall time one card's drop takes. Every card keeps this pace however many
  /// crews there are; the deal just runs on a beat longer for each one.
  static const _cardDuration = Duration(milliseconds: 320);

  static final _spring = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: .58),
    0,
    1,
    0,
  );

  /// A long crew list tightens its beat rather than dragging the deal out.
  static double _beat(int count) =>
      count > 1 ? math.min(_lag, .2 / (count - 1)) : 0;

  static double _window(int count) => _settle + _beat(count) * (count - 1);

  /// How long the whole deal runs for [count] crews, at one fixed pace per card.
  static Duration dealDuration(int count) => Duration(
    microseconds: (_cardDuration.inMicroseconds * _window(count) / _settle)
        .round(),
  );

  /// 0 above the screen, 1 landed, a little past 1 at the top of the bounce.
  double _progress(int index) {
    final count = crews.length;
    final time = animation.value * _window(count) - index * _beat(count);
    return time <= 0 ? 0 : _spring.x(time);
  }

  Widget _card(BuildContext context, int index, double dy) {
    final rect = cards[index];
    final crew = crews[index];
    final current = crew.id == selectedId;
    final active = index == highlighted;
    final progress = _progress(index);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        ignoring: animation.value < .2 || exit.value > 0,
        child: Opacity(
          opacity: (progress * 8).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: _CrewFanCard(
              crew: crew,
              current: current,
              active: active,
              onTap: () => onPicked(index),
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
    required this.current,
    required this.active,
    required this.onTap,
  });

  /// The pact cards' own sticker language: a flat fill inside a black outline,
  /// standing on a hard black shadow. The crew you are on is the mint one.
  static const _fill = WeekPactColors.cream;
  static const _fillCurrent = WeekPactColors.mintGreen;
  static const _ink = WeekPactColors.black;

  /// A finger covers most of a card, so the cue is the shadow it throws and a
  /// brighter face — not a colour swap that would be hidden under the thumb.
  static const _fillActive = Color(0xFFFFFFFF);
  static const _fillCurrentActive = Color(0xFFA8E9C2);

  /// Depth at rest and under a finger. The card shifts by exactly the growth,
  /// so its shadow stays pinned and only the gap beneath it opens up — 3px of
  /// travel, nowhere near the 12px between one card and the next.
  static const _depth = Offset(4, 5);
  static const _depthActive = Offset(8, 9);

  final PactCrew crew;
  final bool current;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final depth = active ? _depthActive : _depth;
    return Semantics(
      button: true,
      selected: current,
      label: 'Switch to ${crew.name}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: still ? Duration.zero : const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(
            _depth.dx - depth.dx,
            _depth.dy - depth.dy,
            0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: ShapeDecoration(
            color: current
                ? (active ? _fillCurrentActive : _fillCurrent)
                : (active ? _fillActive : _fill),
            shape: const ContinuousRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              side: BorderSide(color: _ink, width: 2),
            ),
            shadows: [BoxShadow(color: _ink, offset: depth)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                crew.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (current)
                Text(
                  'CURRENT CREW',
                  style: TextStyle(
                    color: _ink.withValues(alpha: .6),
                    fontFamily: 'Roboto',
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
