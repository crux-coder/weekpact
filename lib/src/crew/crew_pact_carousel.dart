import 'package:flutter/material.dart';

import '../home/home_backend.dart';
import '../home/pact_deck.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/page_frame.dart';
import 'crew_pact_week_card.dart';

/// The crew's pacts as the same deck Home shows its pacts in: the card in
/// front as wide as the page's column, its neighbours shrunk into the margin,
/// and a dot per pact underneath. The crew week page and the past-week sheet
/// both draw one.
///
/// The card stands as tall as the deck is given, which on the crew week is
/// taller than Home's: it carries the whole crew's days, not one person's.
class CrewPactCarousel extends StatelessWidget {
  const CrewPactCarousel({
    super.key,
    required this.week,
    required this.members,
    required this.userId,
    this.onIndexChanged,
  });

  /// The deck's height for a crew of [count]: the card at full rows, the
  /// room under it for its raised edge, and the dots.
  static double heightFor(int count) =>
      CrewPactWeekCard.heightFor(count) +
      WeekPactMetrics.controlDepth +
      1 +
      PactDeck.dotsGap +
      PactDeck.dotsHeight;

  final CrewWeek week;
  final List<WeekMember> members;
  final String userId;

  /// Told which pact is in front, for a counter beside the heading.
  final ValueChanged<int>? onIndexChanged;

  @override
  Widget build(BuildContext context) {
    if (week.pacts.isEmpty) {
      return AppSurface(
        builder: (_) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No pacts yet. Your crew’s weekly activity will appear here.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return PactDeck(
      deckKey: const ValueKey('crew-pact-carousel'),
      ids: [for (final pact in week.pacts) pact.id],
      onIndexChanged: onIndexChanged,
      itemBuilder: (context, index) => Padding(
        // The card's raised edge is painted below its own box, so the page
        // leaves that edge room to show.
        padding: const EdgeInsets.only(
          bottom: WeekPactMetrics.controlDepth + 1,
        ),
        child: CrewPactWeekCard(
          key: ValueKey(week.pacts[index].id),
          week: week,
          pact: week.pacts[index],
          tint: WeekPactColors.pactTint(index),
          badge: WeekPactColors.pactBadge(index),
          members: members,
          userId: userId,
        ),
      ),
    );
  }
}

/// The "Crew pacts" line while the week loads: a bar where the heading is
/// and one where the pact counter is, each as wide as its words and centred
/// on them, in a row exactly as tall as the real one. The crew week page and
/// the past-week sheet both stand one over their deck.
class CrewPactsHeadingSkeleton extends StatelessWidget {
  const CrewPactsHeadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: _WordsBar(
            'Crew pacts',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            // The ink of a capital and a descender, not the line's leading.
            share: .66,
          ),
        ),
      ),
      _WordsBar(
        '1 / 3',
        style: TextStyle(color: context.muted, fontWeight: FontWeight.w500),
        // Figures alone, with nothing reaching above or below them.
        share: .6,
      ),
    ],
  );
}

/// A bar over the room [text] would take, as tall as [share] of its line.
///
/// The words are laid out, never painted, so the bar is exactly as wide as
/// they would be, and the line exactly as tall, at any text size.
class _WordsBar extends StatelessWidget {
  const _WordsBar(this.text, {required this.style, required this.share});
  final String text;
  final TextStyle style;
  final double share;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Opacity(opacity: 0, child: Text(text, style: style)),
      Positioned.fill(
        child: FractionallySizedBox(
          heightFactor: share,
          child: const SkeletonBar(height: double.infinity),
        ),
      ),
    ],
  );
}

/// The deck while the week loads, drawn as [CrewPactCarousel] draws it in
/// the same box: the front card at full width with room under it for its
/// raised edge, a sliver of the next one past the content's edge, and the
/// dots. Its surfaces are the card's own, so their outline, corner and
/// raised edge are the loaded card's to the pixel.
class CrewPactCarouselSkeleton extends StatelessWidget {
  const CrewPactCarouselSkeleton({super.key});

  /// What [PactDeck] does to the card either side of the front one: shrunk
  /// about its own centre, its near edge a few points past the front card's.
  static const _shrink = .14;
  static const _gap = 4.0;

  /// The room the real deck leaves under each card for its raised edge.
  static const _edge = WeekPactMetrics.controlDepth + 1;

  static Widget _card() => AppSurface(
    shape: WeekPactMetrics.pactCardShape,
    borderWidth: 1,
    builder: (_) => const SizedBox.expand(),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, space) => Stack(
            clipBehavior: Clip.none,
            children: [
              // The deck shrinks the whole page, its edge room too, so the
              // card's top comes down by half of what the page lost.
              Positioned(
                left: space.maxWidth + _gap,
                top: space.maxHeight * _shrink / 2,
                width: space.maxWidth * (1 - _shrink),
                height: (space.maxHeight - _edge) * (1 - _shrink),
                child: KeyedSubtree(
                  key: const ValueKey('crew-pact-carousel-skeleton-next'),
                  child: _card(),
                ),
              ),
              Positioned.fill(
                bottom: _edge,
                child: KeyedSubtree(
                  key: const ValueKey('crew-pact-carousel-skeleton-card'),
                  child: _card(),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: PactDeck.dotsGap),
      SizedBox(
        height: PactDeck.dotsHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              SkeletonBar(
                width: i == 0 ? 18 : PactDeck.dotsHeight,
                height: PactDeck.dotsHeight,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
