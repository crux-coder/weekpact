import 'package:flutter/material.dart';

import '../home/home_backend.dart';
import '../home/pact_deck.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
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
