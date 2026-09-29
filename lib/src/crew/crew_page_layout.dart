import 'crew_switcher.dart';
import '../widgets/avatar_shape.dart';

import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/page_frame.dart';
import 'crew_roster.dart';

/// Shared heading geometry for every crew-scoped management screen: the crew
/// this page is about, and what the page can be asked to do, on one line.
///
/// It carried the destination's name too — `Crews.`, `Pacts.`, with the full
/// stop in that destination's own tint — on a line of its own under the crew.
/// The name is gone: every one of these pages is reached by tapping its own
/// tab, which is lit and labelled at the bottom of the screen the whole time,
/// so the title spent 48 points and the first thing the eye landed on telling
/// people where they had just chosen to go. What is left is the crew, which
/// the page could not be read without, and the page's own controls beside it.
class CrewPageHeading extends StatelessWidget {
  const CrewPageHeading({
    super.key,
    this.leading = const [],
    this.actions = const [],
    this.switcher,
  });

  /// What stands at the start of the line, before the crew's name. Crews puts
  /// making another one here and keeps its invites at the far end: the two do
  /// different things to different crews, and a pair of icons side by side in
  /// one corner reads as one control with two halves.
  final List<Widget> leading;

  /// What the page can be asked to do, at the end of the line. They sat under
  /// the crew, on the title's row; with the title gone they come up beside it,
  /// which is where a control belongs anyway — level with the thing it acts on
  /// rather than under it.
  final List<Widget> actions;

  /// The width one control stands in — an `IconButton`'s own tap target. The
  /// row keeps the same width clear at *both* ends, whichever end the controls
  /// are actually on, so the crew's name is centred on the page rather than on
  /// whatever they left over. Without it a crew moves sideways as you cross
  /// from Pacts, which carries no controls, to Crews, which carries one at
  /// either end.
  static const _actionSlot = 48.0;

  /// The row's height, which has to be given rather than grown into: every
  /// child of the stack below is positioned, so the stack has no size of its
  /// own to offer a column that is not offering it one either. The taller of
  /// the two things standing in the row, which is the control.
  static const _rowHeight = _actionSlot > CrewSwitcher.height
      ? _actionSlot
      : CrewSwitcher.height;

  /// The crew this page is about. It used to sit in the page's body under the
  /// heading, as one more block in the column; it is the page's subject, so it
  /// leads, and it leads in the same place on every page that carries one.
  /// Null where there is no crew to name yet.
  final Widget? switcher;

  /// The room kept clear at each end: enough for whichever end carries more.
  double get _margin =>
      (leading.length > actions.length ? leading.length : actions.length) *
      _actionSlot;

  @override
  Widget build(BuildContext context) {
    final crew = switcher;
    return SizedBox(
      // The row stands at this height whether or not there is a crew to name,
      // so a page does not jump as one loads.
      height: _rowHeight,
      child: Stack(
        children: [
          // The controls are laid over the row rather than set beside the
          // name, which is how Home hangs its bell and for the same reason:
          // the name keeps the page's own middle, and a row of two would push
          // it left by half a control. The padding is what stops a long crew
          // running underneath them.
          if (crew != null)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: _margin),
                child: Center(child: crew),
              ),
            ),
          if (leading.isNotEmpty)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Row(mainAxisSize: MainAxisSize.min, children: leading),
            ),
          if (actions.isNotEmpty)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
        ],
      ),
    );
  }
}

/// The shared loading shell: the same progress line on Pacts and Crews, so
/// switching tabs mid-load does not shift the page. Below that each page
/// stands in for its own content — [body] — because a skeleton that shows the
/// wrong shapes is a worse promise than none.
///
/// It used to stand a card in for the crew selector as well. The selector is
/// the page's title now and lives in the header, above this entirely, so a
/// placeholder here would be a block promising something that lands somewhere
/// else.
class CrewPageSkeleton extends StatelessWidget {
  const CrewPageSkeleton({super.key, this.label = 'Loading crews', this.body});

  final String label;

  /// What is loading under the progress line. Defaults to the crew roster.
  final Widget? body;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            minHeight: 2,
            color: WeekPactColors.coolGrey,
            backgroundColor: context.ink.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          ),
          const SizedBox(height: 16),
          body ?? const CrewRosterSkeleton(),
        ],
      ),
    ),
  );
}

/// A heading over a group on the crew page: a small-caps word and the rule
/// that carries it across to the edge, so the roster reads as a named group
/// rather than as the page's only content.
///
/// It lives here rather than beside the roster it heads because the loading
/// shapes below need the very same row: the label is chrome the page knows
/// before any answer arrives, so the skeleton shows the real one instead of a
/// bar standing in for a word it could already have written.
class CrewSectionLabel extends StatelessWidget {
  const CrewSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.muted,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Divider(
          height: 1,
          thickness: 1,
          color: context.ink.withValues(alpha: .14),
        ),
      ),
    ],
  );
}

/// The crew page's own loading shapes: the summary card at its own height,
/// the heading over the roster, then the stack of bands.
///
/// It used to be a 120pt caption bar over the bands, which is what the page
/// used to open with. The caption is gone — [CrewSummaryCard] stands there
/// now, four times its height — so a skeleton still drawing the old bar
/// promised a page that no longer exists and dropped the roster by some 80
/// points the moment the answer landed.
class CrewRosterSkeleton extends StatelessWidget {
  const CrewRosterSkeleton({super.key});

  /// One band's ghost: the face, the name, the standing and the square at the
  /// end, in the padding and the gaps [CrewPersonBand] lays them out with, so
  /// nothing on the row moves sideways when the people arrive.
  Widget _band(bool isCurrentUser) => CrewBand(
    fillColor: isCurrentUser ? WeekPactColors.coolGrey : WeekPactColors.cream,
    builder: (context) => const Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: SkeletonBar(height: 40, shape: AvatarShape()),
          ),
          SizedBox(width: 12),
          Expanded(child: SkeletonBar(height: 15)),
          SizedBox(width: 10),
          SkeletonBar(width: 54, height: 10),
          SizedBox(width: 12),
          // The band's control is a squircle the size of the slot it stands
          // in, not the 30pt circle this used to draw.
          SizedBox.square(
            dimension: 36,
            child: SkeletonBar(
              height: 36,
              shape: ContinuousRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(WeekPactMetrics.panelCurve),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CrewSummaryCard.loading(),
      const SizedBox(height: 18),
      const CrewSectionLabel('IN THE CREW'),
      const SizedBox(height: 10),
      CrewRoster(children: [for (var i = 0; i < 4; i++) _band(i == 0)]),
    ],
  );
}
