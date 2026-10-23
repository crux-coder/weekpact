import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/pact_icon_badge.dart';
import 'home_surface.dart';

/// The crew's pacts as a cover flow: the focused card is exactly as wide as
/// the cards above it, and the ones either side shrink and dim, with only a
/// sliver of each showing in the page's margin. Home's pact cards and the
/// crew week's both stand in one, so a pact is the same card wherever it is.
class PactDeck extends StatefulWidget {
  const PactDeck({
    super.key,
    required this.deckKey,
    required this.ids,
    required this.itemBuilder,
    this.onIndexChanged,
  });

  /// The row of dots under the cards, and the gap above it: how many pacts
  /// there are and which one is in front. The loading skeleton keeps the same
  /// room, so the cards stand in the same place either way.
  static const dotsHeight = 8.0;
  static const dotsGap = 12.0;

  /// The key the deck's [PageView] carries.
  final Key deckKey;

  /// One per card, so the deck can stay on the same pact when the list
  /// changes under it.
  final List<String> ids;
  final IndexedWidgetBuilder itemBuilder;

  /// Told which pact is in front, for a counter beside a heading.
  final ValueChanged<int>? onIndexChanged;

  @override
  State<PactDeck> createState() => _PactDeckState();
}

class _PactDeckState extends State<PactDeck> {
  /// How much a neighbour shrinks, and how far past the content's edge it
  /// starts. The page margin is 12, so 4 in leaves an 8pt sliver showing.
  static const _shrink = .14;
  static const _gap = 4.0;

  /// Each page a hair narrower than the box, so the pages either side reach
  /// into it and get painted: a page wholly outside its viewport is not
  /// drawn, and the slivers would never show. The card itself is still laid
  /// out at the full width, over its page.
  static const _fraction = .98;
  final _controller = PageController(viewportFraction: _fraction);
  int _index = 0;

  @override
  void didUpdateWidget(covariant PactDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.ids;
    if (ids.isEmpty) {
      _index = 0;
      return;
    }
    // Stay on the same pact when the list changes under it.
    final previousId = oldWidget.ids.elementAtOrNull(_index);
    final retainedIndex = ids.indexOf(previousId ?? '');
    final nextIndex = retainedIndex >= 0
        ? retainedIndex
        : math.min(_index, ids.length - 1);
    if (nextIndex != _index) {
      _index = nextIndex;
      widget.onIndexChanged?.call(_index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(_index);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.ids.length;
    if (count == 0) return const SizedBox.shrink();
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => PageView.builder(
              key: widget.deckKey,
              controller: _controller,
              // The card's raised edge and its completion pop reach past its box.
              clipBehavior: Clip.none,
              itemCount: count,
              onPageChanged: (index) {
                setState(() => _index = index);
                widget.onIndexChanged?.call(index);
                unawaited(
                  HapticFeedback.mediumImpact().catchError((Object _) {}),
                );
              },
              itemBuilder: (context, index) => AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final ready =
                      _controller.hasClients &&
                      _controller.position.haveDimensions;
                  final page = ready ? _controller.page! : _index.toDouble();
                  final d = index - page;
                  final away = d.abs().clamp(0.0, 1.0);
                  // Shrunk about its centre, then moved so its near edge sits
                  // [_gap] past the focused card's, which holds mid-swipe too.
                  final width = box.maxWidth;
                  return Transform.translate(
                    offset: Offset(
                      d * (width * (1 - _fraction - _shrink / 2) + _gap),
                      0,
                    ),
                    child: Transform.scale(
                      scale: 1 - _shrink * away,
                      child: Opacity(
                        opacity: 1 - .35 * away,
                        child: IgnorePointer(
                          ignoring: away > .5,
                          child: ExcludeSemantics(
                            excluding: away > .5,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: OverflowBox(
                  minWidth: box.maxWidth,
                  maxWidth: box.maxWidth,
                  child: widget.itemBuilder(context, index),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: PactDeck.dotsGap),
        _PactDots(controller: _controller, count: count, index: _index),
      ],
    );
  }
}

/// One dot per pact under the cards, the front one drawn long. It follows the
/// swipe as it happens rather than snapping on release, and a dot is a way to
/// its pact as well as a mark of it. A single pact gets no dots, but keeps
/// their room.
class _PactDots extends StatelessWidget {
  const _PactDots({
    required this.controller,
    required this.count,
    required this.index,
  });

  final PageController controller;
  final int count;
  final int index;

  static const _dot = PactDeck.dotsHeight;
  static const _long = 18.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _dot,
    child: count < 2
        ? null
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final page =
                  controller.hasClients && controller.position.haveDimensions
                  ? controller.page!
                  : index.toDouble();
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < count; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      Tooltip(
                        message: 'Pact ${i + 1} of $count',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => MediaQuery.disableAnimationsOf(context)
                              ? controller.jumpToPage(i)
                              : controller.animateToPage(
                                  i,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                ),
                          child: _mark(
                            context,
                            (1 - (i - page).abs()).clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
  );

  /// A dot at [front] of the way to being the front one: longer and fully
  /// inked at 1, a short faint dot at 0.
  Widget _mark(BuildContext context, double front) => Container(
    width: _dot + (_long - _dot) * front,
    height: _dot,
    decoration: BoxDecoration(
      color: context.ink.withValues(alpha: .25 + .75 * front),
      borderRadius: WeekPactMetrics.pill,
    ),
  );
}

/// One pact's card: its tint, its raised edge, its name and its icon badge,
/// with [body] under the name. What the body holds is the page's own — Home
/// puts the viewer's count and check-in there, the crew week the crew's days
/// — but the card around it is the same on both.
///
/// The face is laid out at its natural height and scaled to the box it is
/// given, so every card in a deck shares one type scale.
class PactCardFace extends StatelessWidget {
  const PactCardFace({
    super.key,
    required this.pact,
    required this.tint,
    required this.badge,
    required this.bodyHeight,
    required this.body,
    this.bodyTextGrowth = 228,
  });

  /// The pact's icon badge on the card: the card tint is too quiet to tell two
  /// pacts apart on its own, so this is what does. See [PactIconBadge].
  static const iconBadge = 56.0;

  /// The height the card keeps for a pact's name, whatever that name is.
  ///
  /// A constant, not the title's natural height: the card scales its whole
  /// face to whatever it is given, and the scale is computed from one content
  /// height for every card in the deck. If the title box grew with the name,
  /// a four-line pact would push the body past the bottom of a box sized for
  /// a one-line one. 80 is four lines at the size four lines end up at, and a
  /// single line still sets at the full display size inside it.
  static const titleBudget = 80.0;

  /// The gap between the name and the body below it.
  static const titleGap = 10.0;

  final CrewPact pact;

  /// The card's tint, and the deeper companion its icon badge is drawn in.
  /// Both come from the pact's place in the crew's list, so they stay a pair.
  final Color tint;
  final Color badge;

  /// What the body needs at its natural size, and how much more it needs for
  /// each step of text scale past 1. Every card in a deck scales from these,
  /// so they have to cover the body's tallest state.
  final double bodyHeight;
  final double bodyTextGrowth;
  final Widget body;

  @override
  Widget build(BuildContext context) => HomeSurface(
    tint: tint,
    radius: WeekPactMetrics.cardCorner,
    raised: true,
    depth: WeekPactMetrics.cardDepth,
    shape: WeekPactMetrics.pactCardShape,
    outlineColor: Color.lerp(tint, Colors.black, .28),
    padding: homeCardInset,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final minimumHeight =
            titleBudget +
            titleGap +
            bodyHeight +
            math.max(0.0, MediaQuery.textScalerOf(context).scale(1) - 1) *
                bodyTextGrowth;
        final shrink =
            constraints.maxHeight /
            math.max(minimumHeight, constraints.maxHeight);
        final content = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            // Compensate for height scaling so the body still spans the
            // entire inner width of the card.
            width: constraints.maxWidth / shrink,
            height: math.max(minimumHeight, constraints.maxHeight),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: homeInk),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: titleBudget,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: pact.title,
                            child: FittedTitle(
                              text: pact.title,
                              style: const TextStyle(
                                fontSize: 25,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        // What the badge takes out of the title's lines: its
                        // box, and the gap before it. Nothing more — it is
                        // drawn flush to the card's inset, so anything extra
                        // here would be a word stolen from the name to hold
                        // air.
                        const SizedBox(width: iconBadge + 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: titleGap),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        );
        // The badge is the card's own, at one size, and it scales with the
        // rest of the face.
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            content,
            Positioned(
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: PactIconBadge(
                  key: ValueKey('pact-icon-${pact.id}'),
                  icon: PactIcon.find(pact.iconKey).data,
                  tint: badge,
                  size: iconBadge * shrink,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// A title at the largest size that still fits the box it is given.
///
/// A pact is named by the person who made it, so the card cannot assume the
/// name is short. Holding one display size and cutting what does not fit means
/// "Walk the dog around the park before work" arrives as "Walk the dog around
/// the…" — the card keeps its type scale and loses the pact's meaning.
/// Stepping the size down keeps the whole name, and only a name too long to
/// fit even at [minFontSize] takes the ellipsis.
class FittedTitle extends StatelessWidget {
  const FittedTitle({super.key, required this.text, required this.style});

  final String text;

  /// The title's type, at the size a short name gets. [TextStyle.fontSize]
  /// must be set: it is the ceiling the fit steps down from.
  final TextStyle style;

  static const maxLines = 4;

  /// The floor. Below this the title stops being the card's headline, so a
  /// name that still does not fit is cut instead.
  static const minFontSize = 15.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      var size = style.fontSize!;
      // A whole point at a time, not a binary search: the range is ten points
      // wide, and a round size keeps two cards in the same deck on the same
      // type scale instead of landing on 21.4 and 21.9.
      while (size > minFontSize &&
          !_fits(context, scaler, size, constraints.biggest)) {
        size -= 1;
      }
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(fontSize: size),
      );
    },
  );

  /// Both bounds have to hold. [maxLines] alone would let four lines of 25pt
  /// through, which is half again the height the card keeps for a name;
  /// height alone would let a name set as one endless line.
  bool _fits(BuildContext context, TextScaler scaler, double size, Size box) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: maxLines,
    )..layout(maxWidth: box.width);
    final fits = !painter.didExceedMaxLines && painter.height <= box.height;
    painter.dispose();
    return fits;
  }
}
