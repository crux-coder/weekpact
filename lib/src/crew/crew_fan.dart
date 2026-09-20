import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';

/// Geometry for the crew fan: full-width cards stacked below the thumb.
///
/// Kept separate from the widgets so the same rectangles decide where a card is
/// painted and which card a finger is currently over.
abstract final class CrewFanLayout {
  static const cardHeight = 76.0;
  static const _gap = 12.0;

  /// The hand hangs off the switcher rather than off the finger: it opens
  /// directly under the control it belongs to, the same gap a card keeps from
  /// its neighbour.
  static const _gapBelowSwitcher = _gap;

  /// One rectangle per crew, in global coordinates, ordered like [crews].
  ///
  /// [anchor] is the switcher's own rect: the cards take its width and line up
  /// under it, so the hand reads as that control unfolded.
  static List<Rect> of({
    required Size screen,
    required EdgeInsets padding,
    required Rect anchor,
    required int count,
  }) {
    if (count == 0) return const [];
    final top = anchor.bottom + _gapBelowSwitcher;
    // Tighten the spacing rather than run off the bottom when a crew list grows.
    final room = screen.height - padding.bottom - 12 - top;
    final step = math.min(
      cardHeight + _gap,
      count > 1 ? (room - cardHeight) / (count - 1) : cardHeight + _gap,
    );
    return [
      for (var i = 0; i < count; i++)
        Rect.fromLTWH(anchor.left, top + step * i, anchor.width, cardHeight),
    ];
  }

  /// How far the hand travels on its way in: from above the screen down to
  /// the foot of the last card.
  static double drop(List<Rect> cards) =>
      cards.isEmpty ? 0 : cards.last.bottom + 24;

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
    required this.cards,
    required this.animation,
    required this.exit,
    required this.onPicked,
    required this.onDismissed,
    this.switcher,
    this.switcherRect,
    this.previews = const {},
  });

  final List<PactCrew> crews;
  final String? selectedId;
  final List<Rect> cards;
  final Animation<double> animation;

  /// 0 while the hand is out, 1 once it has left the top of the screen again.
  final Animation<double> exit;
  final ValueChanged<int> onPicked;
  final VoidCallback onDismissed;

  /// The switcher itself, redrawn over the scrim at [switcherRect], so the
  /// control the hand came from keeps its own light while the page behind it
  /// goes dark. Taps on it fall through to the scrim and dismiss.
  final Widget? switcher;
  final Rect? switcherRect;

  /// Each crew's week, by crew id, once it has loaded: the faces and the streak
  /// a card shows. A crew that has none yet keeps its name alone.
  final Map<String, CrewWeek> previews;

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
                child: CustomPaint(
                  painter: _FanScrim(dim: _dim),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (switcher != null && switcherRect != null)
              Positioned.fromRect(
                rect: switcherRect!,
                child: IgnorePointer(child: switcher),
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
    final distance = CrewFanLayout.drop(cards);
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

  /// The page behind goes dark rather than soft: the crews read as cards held
  /// above it, and the switcher they came from keeps its own light.
  static const _maxDim = .55;
  double get _dim =>
      _maxDim * (animation.value * 2).clamp(0.0, 1.0) * (1 - exit.value);

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
    if (time <= 0) return 0;
    return _spring.x(time);
  }

  Widget _card(BuildContext context, int index, double dy) {
    final rect = cards[index];
    final crew = crews[index];
    final current = crew.id == selectedId;
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
              preview: previews[crew.id],
              onTap: () => onPicked(index),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewFanCard extends StatefulWidget {
  const _CrewFanCard({
    required this.crew,
    required this.current,
    required this.preview,
    required this.onTap,
  });

  final PactCrew crew;
  final bool current;

  /// The crew's week, once it is in. Null while it loads, or when the caller
  /// has no way to load one.
  final CrewWeek? preview;
  final VoidCallback onTap;

  @override
  State<_CrewFanCard> createState() => _CrewFanCardState();
}

class _CrewFanCardState extends State<_CrewFanCard> {
  /// True while a finger is down on this card. Picking is a tap now, so the
  /// card answers for its own press rather than being told it is the one under
  /// a finger crossing the hand.
  bool _pressed = false;

  /// The app's own card language rather than a sticker: a flat fill, a hairline
  /// outline mixed from that fill and the short raised edge every surface
  /// stands on. The crew you are on is the mint one; the rest take the charcoal
  /// card, so the hand reads as one current crew among graphite peers.
  static const _fill = WeekPactDarkCard.fill;
  static const _fillCurrent = WeekPactColors.mintGreen;
  static const _ink = WeekPactDarkCard.ink;
  static const _inkCurrent = WeekPactColors.black;
  static const _edge = WeekPactDarkCard.outline;
  static const _edgeCurrent = WeekPactColors.mintEdge;

  /// A finger covers most of a card, so the cue is the shadow it throws and a
  /// brighter face — not a colour swap that would be hidden under the thumb.
  static const _fillPressed = Color(0xFF3A3F3A);
  static const _fillCurrentPressed = Color(0xFFA8E9C2);

  /// Depth at rest and under a finger. The card shifts by exactly the growth,
  /// so its shadow stays pinned and only the gap beneath it opens up — far less
  /// travel than the 12px between one card and the next.
  static const _depth = WeekPactMetrics.raisedOffset;
  static const _depthPressed = Offset(0, 5);

  PactCrew get crew => widget.crew;
  bool get current => widget.current;
  CrewWeek? get preview => widget.preview;

  int get _streak => preview?.streakWeeks ?? 0;

  String get _streakWords => _streak == 0
      ? 'no streak yet'
      : '$_streak week${_streak == 1 ? '' : 's'} running';

  /// The line under the name: which crew you are on, and how its streak stands.
  /// Until the week is in there is nothing honest to say, so it stays empty.
  Widget _meta(Color ink) {
    final muted = ink.withValues(alpha: .6);
    return Row(
      children: [
        if (current) ...[
          Text('CURRENT CREW', style: _caption(muted)),
          if (preview != null) Text('  ·  ', style: _caption(muted)),
        ],
        if (preview != null) ...[
          HugeIcon(
            icon: HugeIconsStrokeRounded.fire,
            color: _streak > 0 ? WeekPactColors.streak : muted,
            size: 14,
            strokeWidth: 2,
          ),
          const SizedBox(width: 4),
          Text(
            _streak == 0
                ? 'NO STREAK YET'
                : '$_streak WEEK${_streak == 1 ? '' : 'S'}',
            style: _caption(muted),
          ),
        ],
      ],
    );
  }

  static TextStyle _caption(Color colour) => TextStyle(
    color: colour,
    fontFamily: WeekPactType.secondary,
    fontFamilyFallback: WeekPactType.secondaryFallback,
    fontSize: 10,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final depth = _pressed ? _depthPressed : _depth;
    final ink = current ? _inkCurrent : _ink;
    final edge = current ? _edgeCurrent : _edge;
    final fill = current
        ? (_pressed ? _fillCurrentPressed : _fillCurrent)
        : (_pressed ? _fillPressed : _fill);
    final members = preview?.members ?? const <WeekMember>[];
    return Semantics(
      button: true,
      selected: current,
      label: 'Switch to ${crew.name}',
      value: members.isEmpty
          ? null
          : '${members.length} ${members.length == 1 ? 'member' : 'members'}, '
                '$_streakWords',
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
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
            color: fill,
            shape: ContinuousRectangleBorder(
              borderRadius: const BorderRadius.all(
                Radius.circular(WeekPactMetrics.panelCurve),
              ),
              side: BorderSide(color: edge, width: WeekPactMetrics.border),
            ),
            shadows: [BoxShadow(color: edge, offset: depth)],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crew.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _meta(ink),
                  ],
                ),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(width: 12),
                _CrewFaces(members: members, ring: fill),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The page behind the hand, darkened.
class _FanScrim extends CustomPainter {
  const _FanScrim({required this.dim});
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    if (dim <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: dim),
    );
  }

  @override
  bool shouldRepaint(_FanScrim old) => old.dim != dim;
}

/// The crew's members, as the same overlapping squircle faces the check-in
/// tiles use. The ring between them is the card's own fill, so the stack reads
/// as people rather than one smear whichever card it sits on.
class _CrewFaces extends StatelessWidget {
  const _CrewFaces({required this.members, required this.ring});
  final List<WeekMember> members;
  final Color ring;

  static const _size = 30.0;
  static const _overlap = .62;
  static const _ring = 2.0;

  /// Beyond this the stack stops being faces and becomes a number.
  static const _max = 3;

  @override
  Widget build(BuildContext context) {
    final shown = members.length <= _max ? members.length : _max - 1;
    final overflow = members.length - shown;
    final slots = shown + (overflow > 0 ? 1 : 0);
    final step = _size * _overlap;
    return SizedBox(
      width: _size + (slots - 1) * step,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown; i++)
            Positioned(left: i * step, child: _face(members[i])),
          if (overflow > 0)
            Positioned(left: shown * step, child: _overflowChip(overflow)),
        ],
      ),
    );
  }

  Widget _face(WeekMember member) {
    final fallback = Center(child: Text(member.initials, style: _initials));
    return _shell(
      AvatarClip(
        child: member.avatarUrl == null
            ? fallback
            : Image.network(
                member.avatarUrl!,
                gaplessPlayback: true,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  Widget _overflowChip(int overflow) =>
      _shell(Center(child: Text('+$overflow', style: _initials)));

  Widget _shell(Widget child) => Container(
    width: _size,
    height: _size,
    padding: const EdgeInsets.all(_ring),
    decoration: ShapeDecoration(color: ring, shape: const AvatarShape()),
    child: DecoratedBox(
      decoration: const ShapeDecoration(
        color: WeekPactColors.cream,
        shape: AvatarShape(),
      ),
      child: child,
    ),
  );

  static const _initials = TextStyle(
    color: WeekPactColors.black,
    fontFamily: WeekPactType.secondary,
    fontFamilyFallback: WeekPactType.secondaryFallback,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
}
