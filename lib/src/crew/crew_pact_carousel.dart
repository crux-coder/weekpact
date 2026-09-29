import 'package:flutter/material.dart';

import '../home/home_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'crew_pact_week_card.dart';

/// The crew's pacts as a swipeable deck of week cards, with a dot per pact
/// beneath it. The crew week page and the past-week sheet both draw one.
///
/// The deck runs full bleed: it is wider than the column it sits in by the
/// page inset either side, so the neighbouring pacts reach the screen's edges
/// instead of stopping short of them. Under a full viewport those neighbours
/// peek in, which is how the deck says it can be swiped.
class CrewPactCarousel extends StatefulWidget {
  const CrewPactCarousel({
    super.key,
    required this.week,
    required this.members,
    required this.userId,
    this.onIndexChanged,
  });

  final CrewWeek week;
  final List<WeekMember> members;
  final String userId;

  /// Told which pact is in front, for a counter beside the heading.
  final ValueChanged<int>? onIndexChanged;

  @override
  State<CrewPactCarousel> createState() => _CrewPactCarouselState();
}

class _CrewPactCarouselState extends State<CrewPactCarousel> {
  static const _peek = .88;
  final _pages = PageController(viewportFraction: _peek);
  int _index = 0;

  @override
  void didUpdateWidget(CrewPactCarousel old) {
    super.didUpdateWidget(old);
    if (identical(old.week, widget.week)) return;
    // The week was reread under the deck: stay on the pact that was in front,
    // wherever it now sits in the list.
    final previous = old.week.pacts.elementAtOrNull(_index)?.id;
    final selected = widget.week.pacts.indexWhere((p) => p.id == previous);
    final index = selected < 0 ? 0 : selected;
    if (index != _index) _setIndex(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) _pages.jumpToPage(index);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _setIndex(int index) {
    setState(() => _index = index);
    widget.onIndexChanged?.call(index);
  }

  void _showPact(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
      return;
    }
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final week = widget.week;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: week.pacts.isEmpty
              ? AppSurface(
                  builder: (_) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No pacts yet. Your crew’s weekly activity will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) => OverflowBox(
                    minWidth: box.maxWidth + 2 * WeekPactMetrics.pageInset,
                    maxWidth: box.maxWidth + 2 * WeekPactMetrics.pageInset,
                    child: PageView.builder(
                      key: const ValueKey('crew-pact-carousel'),
                      controller: _pages,
                      physics: MediaQuery.disableAnimationsOf(context)
                          ? const ClampingScrollPhysics()
                          : const _CarouselSpringPhysics(),
                      itemCount: week.pacts.length,
                      onPageChanged: _setIndex,
                      itemBuilder: (context, index) => Padding(
                        // The card's raised edge is painted below its own
                        // box, and the carousel clips its pages, so the page
                        // leaves that edge room to show.
                        padding: const EdgeInsets.fromLTRB(
                          5,
                          0,
                          5,
                          WeekPactMetrics.controlDepth + 1,
                        ),
                        child: CrewPactWeekCard(
                          key: ValueKey(week.pacts[index].id),
                          week: week,
                          pact: week.pacts[index],
                          tint: WeekPactColors.pactTint(index),
                          badge: WeekPactColors.pactBadge(index),
                          members: widget.members,
                          userId: widget.userId,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        if (week.pacts.length > 1)
          SizedBox(
            height: 44,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    for (var i = 0; i < week.pacts.length; i++)
                      Semantics(
                        selected: i == _index,
                        child: IconButton(
                          tooltip: 'Show ${week.pacts[i].title}',
                          onPressed: () => _showPact(i),
                          icon: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: i == _index ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: context.ink.withValues(
                                alpha: i == _index ? 1 : .25,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}

class _CarouselSpringPhysics extends BouncingScrollPhysics {
  const _CarouselSpringPhysics({super.parent});

  @override
  _CarouselSpringPhysics applyTo(ScrollPhysics? ancestor) =>
      _CarouselSpringPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: 0.75);
}
