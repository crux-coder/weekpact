import '../widgets/app_components.dart';
import '../widgets/avatar_shape.dart';
import '../crew/crew_streak_card.dart';
import '../crew/crew_switcher.dart';

import 'home_surface.dart';
import 'pact_deck.dart';
import '../theme/weekpact_theme.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pacts_backend.dart';
import '../widgets/page_frame.dart';
import '../widgets/dashed_border.dart';
import 'home_backend.dart';
import '../notifications/notifications_page.dart';
import 'stories_rail.dart';

const _ink = homeInk;

/// A completed day or check-in: a cream inset with a green mark, legible on
/// every card tint. The raised edge is mixed per card from its own colour.
const _doneFill = WeekPactColors.cream;

/// One day of the week, on the pact card's progress bar.
const _segmentHeight = 16.0;
const _doneMark = WeekPactColors.doneMark;

/// What fills the done bar while undo is held: the grey of a check-in still to
/// come, the same on every card, so the day visibly drains back to not done.
const _undoFill = WeekPactColors.pendingCheckIns;

/// The card's measures above its body, shared with the crew week's cards
/// through [PactCardFace].
const _iconBadge = PactCardFace.iconBadge;
const _titleBudget = PactCardFace.titleBudget;
const _titleGap = PactCardFace.titleGap;

/// The count's own type: the kept-days number, and the caption under it.
const _countSize = 76.0;
const _countCaptionSize = 18.0;
const _countCaptionHeight = 1.2;

/// The gap between the caption and the bar, and between the bar and the
/// button. The bar belongs to the count, so the first is much the smaller of
/// the two — see the note where they are laid out.
const _captionToBar = 10.0;
const _barToAction = 26.0;

/// The card's action, in either state: the check-in button and the done bar
/// are both exactly this tall. The count and its bar sit on top of the
/// action, so if one state stood taller than the other they would shift by
/// the difference on every check-in and undo.
const _actionHeight = 56.0;

/// What the card's content needs at its natural size, added up from the parts
/// rather than tuned as one number. Every card in the stack scales from this
/// one figure, so it has to cover the tallest state of every piece; getting it
/// wrong by a few points does not look wrong, it overflows.
const _contentHeight =
    _titleBudget +
    _titleGap +
    _countSize +
    _captionToBar +
    _segmentHeight +
    _barToAction +
    _actionHeight;

/// The kept-days count: the days already kept in full ink, and the target
/// beside it in the muted tone. The target, the slash and the caption are the
/// frame around that number, not a second number.
class _CountRow extends StatelessWidget {
  const _CountRow({required this.completed, required this.target});
  final int completed;
  final int target;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        '$completed',
        style: const TextStyle(
          fontSize: _countSize,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: 6),
      Text(
        '/ $target',
        style: TextStyle(
          fontSize: 38,
          height: 1,
          fontWeight: FontWeight.w700,
          color: homeMutedInk,
        ),
      ),
      const SizedBox(width: 8),
      // The caption sits on the number's baseline rather than under it: one
      // line reads as one fact, and the card gives the line back to the bar.
      Text(
        'days this week',
        maxLines: 1,
        style: TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: _countCaptionSize,
          height: _countCaptionHeight,
          fontWeight: FontWeight.w500,
          color: homeMutedInk,
        ),
      ),
    ],
  );
}

/// The face of one crewmate beside the count, and the seat of one who has not
/// been in yet.
const _faceSize = 34.0;

/// The ring of card fill each face is drawn on, so an overlapping neighbour
/// still reads as a separate person.
const _faceRingWidth = 2.0;

/// One face. Kept today is a solid, paper-filled seat carrying the person's
/// picture; not yet is a hole cut in the card, on the same ink the unfilled
/// segments of the bar are — the two states then read alike wherever they
/// appear on the card, and both work on all ten tints because both are mixed
/// from the tint itself.
class _CrewFace extends StatelessWidget {
  const _CrewFace({
    super.key,
    this.member,
    required this.kept,
    required this.tint,
    this.size = _faceSize,
    this.ring,
  });

  final WeekMember? member;
  final bool kept;
  final Color tint;

  /// The drawn face, inside its ring. The card's row of crewmates keeps the
  /// default; the race track's faces are smaller, because a track carries the
  /// whole crew across one card rather than four of them beside a number.
  final double size;

  /// What the face is ringed in. The card's own fill by default, so a face
  /// that laps over its neighbour still reads as a separate person — the race
  /// track rings the viewer in ink instead, so you find yourself on the track
  /// without reading a name.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      member!.initials,
      style: TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: size >= _faceSize ? 13 : 11,
        fontWeight: FontWeight.w500,
        // Card ink on both states. The seat under it already says which
        // one this is — paper, or a hole cut in the card — so letting the
        // initials down as well only made a name on the unkept seat hard to
        // read, at 3:1 against the very fill that was carrying the state.
        color: _ink,
      ),
    );
    final url = kept ? member?.avatarUrl : null;
    return Container(
      // The ring is the card's own fill, so a face that slides under the one
      // before it still reads as a separate person.
      padding: const EdgeInsets.all(_faceRingWidth),
      decoration: ShapeDecoration(
        color: ring ?? tint,
        shape: const AvatarShape(),
      ),
      child: AvatarClip(
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: kept ? homePaper : _ink.withValues(alpha: .24),
            child: Center(
              child: url == null
                  ? label
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      errorBuilder: (_, _, _) => Center(child: label),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Home's own heading: the page's name and dot, the way every other
/// destination announces itself, with the crew's streak on the right. The crew
/// selector sits below it rather than beside the name.
/// The top of Home: the crew's day, and the crew it belongs to.
///
/// It used to be the page's name and the crew streak. The name said which of
/// five destinations you were on, which the navigation bar under your thumb
/// already says in the same five colours; the streak said how the crew is
/// doing this week, which the crew week page says at length. What replaced
/// them answers the question the page is opened with — who has been out
/// today — and it is made of the crew rather than of the app.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.rail, this.selector, this.action});

  /// The crew's day: a [StoriesRail], or its skeleton while the week loads.
  final Widget rail;

  /// The crew's name, as a [CrewSwitcher]. It leads the page, as it leads
  /// Pacts and Crews — the title says which crew you are reading about, and
  /// the rail under it is that crew's day. Null until the crews are in.
  final Widget? selector;

  /// The one thing in the top corner: the notifications bell. It is laid over
  /// the title row rather than beside the name, so the name keeps the page's
  /// own middle — a row of three would push it left by half a bell.
  final Widget? action;

  static const gap = CrewSwitcher.gap;

  /// How far the rail runs past the page's own margin, so a long crew leaves
  /// at the screen's edge rather than at the card's.
  static const railBleed = 12.0;

  /// The rail's height on a page [width] wide. Its faces grow with the
  /// screen; see [StoriesRail.tileSizeFor].
  static double railHeightFor(double width) =>
      StoriesRail.heightFor(width, bleed: railBleed);

  /// The title row. Tall enough for the bell's tap target, which is the taller
  /// of the two things standing in it; the name centres in whatever is left.
  static const selectorHeight = NotificationsBell.size;
  static double heightFor(double width) =>
      selectorHeight + gap + railHeightFor(width);

  @override
  Widget build(BuildContext context) {
    final above = selector;
    final corner = action;
    return LayoutBuilder(
      builder: (context, space) {
        final railHeight = railHeightFor(space.maxWidth);
        return SizedBox(
          key: const ValueKey('home-header'),
          height: above == null && corner == null
              ? railHeight
              : heightFor(space.maxWidth),
          child: above == null && corner == null
              ? rail
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HomeTitleRow(selector: above, action: corner),
                    const SizedBox(height: gap),
                    SizedBox(height: railHeight, child: rail),
                  ],
                ),
        );
      },
    );
  }
}

/// Home's title row: the crew's name in the middle and the bell in the
/// corner. It stands above the page rather than in it, so it stays put while
/// the page under it loads, as Chat's heading does.
class HomeTitleRow extends StatelessWidget {
  const HomeTitleRow({super.key, this.selector, this.action});

  /// The crew switcher. Null until the crews are in.
  final Widget? selector;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: HomeHeader.selectorHeight,
    child: Stack(
      children: [
        if (selector != null) Positioned.fill(child: Center(child: selector)),
        if (action != null)
          Positioned(right: 0, top: 0, bottom: 0, child: Center(child: action)),
      ],
    ),
  );
}

/// The crew's week under the rail, and the way into the week behind it.
///
/// The rail above says who has been out — one face a member, in no order
/// anyone reads as a score. This says the same week the crew week page says,
/// drawn small: seven columns, one a day, each filled to the share of the
/// crew that was out on it. The door is a picture of the room behind it,
/// which is the one thing a line of type could not be.
///
/// It replaced that line — an icon, "3 of 5 checked in today" and a chevron.
/// The sentence was the only thing on Home the rail above had already said,
/// and it gave no sense of the week it opened; the count it carried is kept
/// at the right, where it reads as today's column labelled rather than as the
/// widget's whole content. It is still the page's door: the week card put its
/// chevron down when it became a race track, and a page nothing opens is a
/// page nobody has.
class CrewTodayBar extends StatelessWidget {
  const CrewTodayBar({super.key, required this.week, this.onOpenWeek});

  /// The loading state: the same surface with the week not yet filled in, so
  /// the rail above it and the crew card below it do not move when it arrives.
  const CrewTodayBar.loading({super.key}) : week = null, onOpenWeek = null;

  /// The crew's week, or null while it is still loading.
  final CrewWeek? week;

  /// Opens the crew week. Null leaves the row as a picture — a week that does
  /// nothing when it is pressed should not be wearing a handle.
  final VoidCallback? onOpenWeek;

  /// The row's height. It used to match the crew card beneath it; the card
  /// grew to carry a podium, and seven columns stretched to that height read
  /// as a chart rather than as the week's door, so the row kept its own.
  static const height = 80.0;

  /// The inset the row keeps off the surface's edge. The handle at the right
  /// is a solid shape with no optical margin of its own, so it gets the same
  /// room the first day does.
  static const _inset = EdgeInsets.fromLTRB(14, 12, 14, 12);

  /// One day's column, and the gap between it and its letter. The column takes
  /// the height the row gained: a taller bar is a finer reading of the day,
  /// and the letters would otherwise float off the week they name.
  static const _trackHeight = 38.0;
  static const _labelGap = 5.0;

  /// The edge a kept day stands on, and the room the trough keeps under the
  /// fill for it. The app draws depth as a crisp offset edge rather than a
  /// blur, so the block needs those points inside the trough or its edge would
  /// be clipped by the bottom it is sitting on.
  static const _depth = WeekPactMetrics.controlDepth;

  /// The height a day fills at its fullest: the trough, less the edge.
  static const _fillHeight = _trackHeight - _depth;

  /// The days, Monday first — the order [CrewWeek.weekDays] hands back. Two
  /// pairs share a letter, as every seven-column week does.
  static const _initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// A day's corner, given as the plain radius it should read as.
  static double get _dayCurve => WeekPactMetrics.curveFor(5);

  /// A kept day's fill and the edge it stands on.
  ///
  /// The palette already carries this green as a light-and-dark pair for a
  /// check-in, so a block is one object rather than a fill with a stroke mixed
  /// for it: sea glass over `mintEdge` on the recessed charcoal this sits on,
  /// and `mintEdge` over `doneMark` on a pale one, where sea glass is too
  /// faint to be a fill at all.
  static (Color fill, Color edge) _keptColors(BuildContext context) =>
      context.isDark
      ? (WeekPactColors.mintGreen, WeekPactColors.mintEdge)
      : (WeekPactColors.mintEdge, WeekPactColors.doneMark);

  @override
  Widget build(BuildContext context) {
    final crew = week;
    final out = crew == null
        ? 0
        : crew.members.where((m) => crew.checkedToday(m.id).isNotEmpty).length;
    final open = onOpenWeek;
    // The picture is the widget, so the sentence it replaced is what a screen
    // reader still hears: seven columns read out as numbers would be a table
    // nobody asked for, and the count is what the columns are there to say.
    final line = crew == null
        ? ''
        : '$out of ${crew.members.length} checked in today';
    return SizedBox(
      key: const ValueKey('crew-today-bar'),
      height: height,
      child: Semantics(
        container: true,
        button: open != null,
        label: crew == null
            ? "Loading this week's check-ins"
            : open == null
            ? line
            : '$line, open the crew week',
        child: ExcludeSemantics(
          // The card curve, not the panel one: this bar stands directly over
          // the race card at the same width, and two corners that close at
          // different rates on one column read as a mistake rather than as
          // two kinds of surface.
          child: CrewHeaderSurface(
            curve: WeekPactMetrics.cardCurve,
            child: InkWell(
              key: const ValueKey('open-crew-week'),
              onTap: open,
              child: Padding(
                padding: _inset,
                child: crew == null
                    ? _loadingRow(context)
                    : _scaledToBox(
                        (context) => Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _days(context, crew)),
                            _door(context, open != null),
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

  /// The week: seven columns, Monday at the left.
  Widget _days(BuildContext context, CrewWeek crew) {
    final days = crew.weekDays;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: _day(
              context,
              key: ValueKey('crew-week-day-${days[i]}'),
              label: _initials[i],
              share: crew.shareOut(days[i]),
              isToday: days[i] == crew.today,
              // A day still to come is drawn as an outline rather than as an
              // empty box, so the week reads as something being filled in and
              // Thursday does not accuse anyone of missing it.
              isAhead: days[i].compareTo(crew.today) > 0,
            ),
          ),
        ],
      ],
    );
  }

  /// One day: its column, and the letter under it.
  Widget _day(
    BuildContext context, {
    required Key key,
    required String label,
    required double share,
    required bool isToday,
    required bool isAhead,
  }) {
    final (fill, edge) = _keptColors(context);
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(_dayCurve),
    );
    final track = isAhead
        ? DashedBorder(
            // The palette's two greys for absence, each on the surface it was
            // drawn for: the pale one is invisible on cream.
            color: context.isDark
                ? WeekPactColors.pendingCheckIns.withValues(alpha: .55)
                : WeekPactColors.pendingEdge,
            radius: _dayCurve,
            child: const SizedBox.expand(),
          )
        : DecoratedBox(
            decoration: ShapeDecoration(
              // A day that has been and took nobody is an outline, not a
              // block: filled at the weight a trough wants, it read as a
              // column of something rather than as an empty one. Today is the
              // same outline taken heavier, at the app's selected weight, and
              // in ink rather than a colour of its own. It wore Home's salmon,
              // which on a row where some days are empty read as the alarm a
              // warm red always reads as — a day flagged rather than a day
              // arrived at. Where you are standing is a position, not a state.
              shape: shape.copyWith(
                side: isToday
                    ? BorderSide(
                        color: context.ink.withValues(alpha: .85),
                        width: WeekPactMetrics.selectedBorder,
                      )
                    : BorderSide(color: context.ink.withValues(alpha: .18)),
              ),
              color: context.ink.withValues(alpha: .05),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              // The block stands on its edge, so the trough keeps those points
              // clear under it. A day kept by the whole crew fills the rest
              // exactly, and the edge lands on the trough's own floor.
              child: Padding(
                padding: const EdgeInsets.only(bottom: _depth),
                child: SizedBox(
                  height: share <= 0
                      ? 0
                      // A single member of a large crew is a sliver; below four
                      // points it stops reading as a mark at all, so one person
                      // is never drawn as nobody.
                      : math.max(4, _fillHeight * share.clamp(0, 1)),
                  // The day as a raised block: fill, its own colour-matched
                  // outline, and the crisp offset edge every surface in the
                  // app stands on. A week kept is a week you can see stacked.
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: shape.copyWith(side: BorderSide(color: edge)),
                      color: fill,
                      shadows: [
                        BoxShadow(
                          color: edge,
                          offset: WeekPactMetrics.raisedOffset,
                        ),
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
    return Column(
      key: key,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: _trackHeight, child: track),
        const SizedBox(height: _labelGap),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            // The letter separates today the same way: full ink against the
            // rest in muted, at the emphasis weight rather than in a hue.
            color: isToday ? context.ink : context.muted,
            fontSize: 10,
            height: 1,
            letterSpacing: .6,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// The handle into the week: a raised squircle with an arrow, in the green
  /// a kept day wears, standing in the row as one more column with "WEEK"
  /// under it where a day has its letter.
  ///
  /// It was "Crew week" and a chevron behind a hairline, muted, and read as a
  /// caption rather than as something to press. The whole row still opens the
  /// week; this is where the eye is told so. A row that opens nothing draws no
  /// handle at all.
  Widget _door(BuildContext context, bool open) {
    if (!open) return const SizedBox.shrink();
    final (fill, _) = _keptColors(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Column(
        key: const ValueKey('crew-week-door'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The face is the track less its raised edge, so the edge lands on
          // the line the days' troughs stand on and the tops meet too.
          SizedBox(
            width: _doorWidth,
            height: _trackHeight - _depth,
            child: AppSurface(
              fillColor: fill,
              borderRadius: 10,
              builder: (context) => const Center(
                child: HugeIcon(
                  icon: HugeIconsStrokeRounded.arrowRight01,
                  color: WeekPactColors.black,
                  size: 26,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: _depth + _labelGap),
          Text(
            'WEEK',
            maxLines: 1,
            style: TextStyle(
              color: context.ink,
              fontSize: 10,
              height: 1,
              letterSpacing: .6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// The handle's width: wider than a day, so it reads as the row's control
  /// rather than as an eighth day.
  static const _doorWidth = 46.0;

  /// The row while the week loads: the seven columns' places, drawn as
  /// troughs, and the tally's. No handle — there is nothing yet to open.
  Widget _loadingRow(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: _trackHeight,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: ContinuousRectangleBorder(
                            borderRadius: BorderRadius.circular(_dayCurve),
                            side: BorderSide(
                              color: context.ink.withValues(alpha: .18),
                            ),
                          ),
                          color: context.ink.withValues(alpha: .05),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: _labelGap),
                    SkeletonBar(
                      width: 8,
                      height: 8,
                      radius: 3,
                      color: context.ink.withValues(alpha: .14),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      Container(
        margin: const EdgeInsets.only(left: 11),
        padding: const EdgeInsets.only(left: 11),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: context.ink.withValues(alpha: .14)),
          ),
        ),
        child: Center(
          child: SkeletonBar(
            width: 66,
            height: 13,
            color: context.ink.withValues(alpha: .14),
          ),
        ),
      ),
    ],
  );
}

/// Home does not scroll, so larger system text is laid out at the room it
/// wants and scaled back into its slot rather than growing one.
Widget _scaledToBox(WidgetBuilder child) => LayoutBuilder(
  builder: (context, box) {
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: math.max(1.0, box.maxWidth) * scale,
        height: math.max(1.0, box.maxHeight) * scale,
        child: child(context),
      ),
    );
  },
);

/// The crew's week as a podium, at the top of the crew week page.
///
/// It carried a headline — what was left of the week, and your place — and a
/// figure on every step. The podium says both on its own: the tallest bar is
/// the leader, and your face is the one ringed in ink. The words came off so
/// the bars could be the whole card.
class CrewPodiumPanel extends StatelessWidget {
  const CrewPodiumPanel({super.key, required this.week, required this.userId});

  /// The loading state: the same card, with its bars not yet filled in, so
  /// nothing on the page moves when the week arrives.
  const CrewPodiumPanel.loading({super.key}) : week = null, userId = '';

  final CrewWeek? week;

  /// Whose place the card reads. The podium draws the leading places; this is
  /// the one face on it ringed in ink, and the one kept beside the podium when
  /// it is not on it.
  final String userId;

  /// The card's height.
  ///
  /// It stood at 80 while it carried one track of small faces, which piled up
  /// exactly when a crew ran close. A podium needs room for a face over a bar,
  /// so the card took the difference from the pact card under it, which fills
  /// whatever the page has left.
  static const cardHeight = 148.0;

  /// The block's height, which is the card's own.
  static const height = cardHeight;

  static const _inset = EdgeInsets.all(WeekPactMetrics.pageInset);

  @override
  Widget build(BuildContext context) {
    final crew = week;
    return SizedBox(
      height: cardHeight,
      child: Semantics(
        container: true,
        label: 'Crew week',
        value: crew == null ? 'Loading' : _spoken(crew),
        child: ExcludeSemantics(
          // The crew week bar's own surface and corner: the two stand one over
          // the other at the same width, and read as one column of the crew.
          child: CrewHeaderSurface(
            curve: WeekPactMetrics.cardCurve,
            child: Padding(
              padding: _inset,
              child: _scaledToBox(
                (context) => crew == null
                    ? const _Podium.loading(key: ValueKey('crew-podium'))
                    : _Podium(
                        key: const ValueKey('crew-podium'),
                        standings: crew.standings(userId),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _suffix(int place) => switch (place % 100) {
    11 || 12 || 13 => 'th',
    _ => switch (place % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    },
  };

  static String _ordinal(int place) => '$place${_suffix(place)}';

  /// What a screen reader is told. The card has no words left on it, so this
  /// is where the week's standing is said at all.
  String _spoken(CrewWeek crew) {
    if (crew.members.length < 2) {
      return "${crew.percent(userId)} per cent of this week's check-ins";
    }
    final standings = crew.standings(userId);
    final mine = standings.where((s) => s.isViewer).firstOrNull;
    final level = standings.every((s) => s.percent == standings.first.percent);
    if (level) {
      return 'The crew is level, ${crew.percentCrew} per cent of the week kept';
    }
    final leaders = [
      for (final s in standings)
        if (s.place == 1)
          s.isViewer
              ? 'you'
              : s.member.displayName.trim().isEmpty
              ? 'a crewmate'
              : s.member.displayName.trim(),
    ];
    return 'You are ${_ordinal(mine?.place ?? standings.length)} '
        'of ${crew.members.length} this week, '
        '${leaders.join(' and ')} leading';
  }
}

/// The crew's week as a podium: the three leading places on their bars, and
/// you beside them when you are not one of them.
///
/// It replaced one track carrying the whole crew, which was unreadable at the
/// moment it mattered most: a crew running close lands inside a few points of
/// each other, and the track answered that by piling the faces on one mark.
///
/// Each bar is that member's week, standing as tall as the share of it they
/// have kept, with that share written on it and drawn in the colour of how
/// far along it is. Up to three places share the card's width, so a crew of
/// one is a single bar. The leader stands in the middle,
/// second on the left and third on the right, the way every podium is read,
/// and the order alone already puts the tallest bar in the middle. A crew that
/// is level stands at one height and wears no crown.
class _Podium extends StatelessWidget {
  const _Podium({super.key, required this.standings}) : loading = false;

  /// Three empty bars, standing where the week's will.
  const _Podium.loading({super.key}) : standings = const [], loading = true;

  final List<CrewStanding> standings;

  final bool loading;

  /// The scale a bar's colour is read off, from an empty week to one kept
  /// all but the last check-in: red, through orange, amber, yellow and lime,
  /// to green. A bar between two stops takes the blend of them, so every
  /// point of progress shows. The tints stay pale enough for the card's dark
  /// figure to read on all of them, in either theme.
  static const _scale = [
    (0, Color(0xFFFF7B6E)), // Red.
    (20, Color(0xFFFF9966)), // Orange.
    (40, Color(0xFFFBB863)), // Amber.
    (60, Color(0xFFF2F0B0)), // Pale yellow, so gold stands apart.
    (80, Color(0xFFBBDC99)), // Lime.
    (99, Color(0xFF86CFA0)), // Green.
  ];

  /// A week fully kept is gold, and nothing short of it is: the scale ends on
  /// green, so gold only ever means 100%.
  static const _kept = WeekPactColors.gold;

  /// The colour of a week [percent] along.
  static Color colourFor(int percent) {
    if (percent >= 100) return _kept;
    final p = percent.clamp(0, 99);
    for (var i = 1; i < _scale.length; i++) {
      final (to, toColour) = _scale[i];
      if (p <= to) {
        final (from, fromColour) = _scale[i - 1];
        return Color.lerp(fromColour, toColour, (p - from) / (to - from))!;
      }
    }
    return _scale.last.$2;
  }

  Color _fillOf(CrewStanding standing) => colourFor(standing.percent);

  /// A bar at an empty week and at a kept one. An empty week still stands
  /// tall enough to carry its figure, so a member who has not started is a
  /// short bar reading 0% rather than nobody.
  /// A bar at a kept week, which reaches the top of the podium under the
  /// crown's row, and the sliver an empty week still stands at so it can be
  /// seen. Between the two a bar is exactly its share of the full height.
  static const _barMax = 102.0;
  static const _barSliver = 6.0;

  /// The share at which a face moves into its bar. Under it a bar is too
  /// short to hold a face and its figure, so they stand on top of it.
  static const _inside = 50;

  /// The dashed bar a viewer off the podium stands in.
  static const _offHeight = 72.0;

  /// The bars the loading card draws, in the order the podium stands.
  static const _loadingBars = [_barMax * .7, _barMax, _barMax * .45];

  static const _barGap = 8.0;
  static final _barShape = ContinuousRectangleBorder(
    borderRadius: BorderRadius.circular(WeekPactMetrics.curveFor(8)),
  );

  /// The face inside a bar, the gap between it and the figure under it, and
  /// the crown standing over the leader's bar.
  static const _face = 24.0;
  static const _faceGap = 4.0;
  static const _crownSize = 16.0;
  static const _crownGap = 4.0;

  /// The column a viewer off the podium stands in.
  static const _offWidth = 56.0;

  static double _barFor(int percent) =>
      math.max(_barSliver, _barMax * percent.clamp(0, 100) / 100);

  @override
  Widget build(BuildContext context) {
    if (loading) return _loadingBarsRow(context);
    final level = standings.every((s) => s.percent == standings.first.percent);
    final top = standings.take(3).toList();
    final viewer = standings.indexWhere((s) => s.isViewer);
    // A viewer tied with the last place on the podium takes that place: the
    // roster's order is not a place, and a podium holding someone on your
    // own figure while you stand beside it would say otherwise.
    if (viewer >= 3 && standings[viewer].place <= top[2].place) {
      top[2] = standings[viewer];
    }
    final order = [
      if (top.length > 1) top[1],
      top.first,
      if (top.length > 2) top[2],
    ];
    final off = viewer >= 3 && !top.contains(standings[viewer])
        ? standings[viewer]
        : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, standing) in order.indexed) ...[
          if (i > 0) const SizedBox(width: _barGap),
          // The places share the card's width between them, so a crew of
          // one is one bar across the card and a crew of three is three.
          Expanded(
            child: _place(
              context,
              standing,
              crowned: !level && standing.place == 1,
            ),
          ),
        ],
        if (off != null) ...[
          const SizedBox(width: _barGap),
          // A rule sets you off from the podium, so your bar does not read as
          // a fourth place standing on it.
          Container(
            width: 1,
            height: _crownSize + _crownGap + _barMax,
            color: context.ink.withValues(alpha: .14),
          ),
          const SizedBox(width: _barGap),
          SizedBox(
            key: const ValueKey('podium-viewer'),
            width: _offWidth,
            child: _offPodium(context, off),
          ),
        ],
      ],
    );
  }

  /// One member: their bar, at exactly their share of the full height, with
  /// their face and figure on it under half a week and in it from half, and
  /// the crown standing over it when it leads.
  Widget _place(
    BuildContext context,
    CrewStanding standing, {
    required bool crowned,
  }) {
    final fill = _fillOf(standing);
    final edge = Color.lerp(fill, Colors.black, .32)!;
    final inside = standing.percent >= _inside;
    return Column(
      key: ValueKey('podium-step-${standing.member.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (crowned) ...[
          Center(
            child: HugeIcon(
              key: ValueKey('podium-crown-${standing.member.id}'),
              icon: HugeIconsStrokeRounded.crown,
              color: context.ink,
              size: _crownSize,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(height: _crownGap),
        ],
        // Under half a week the face and its figure stand on the bar, where
        // the surface is under them; from half they move into it.
        if (!inside) ...[
          _member(
            standing,
            CrewHeaderSurface.faceColor(context),
            ink: context.ink,
            // On the surface your ring is your bar's colour: the card's ink
            // is pale in the dark theme, and vanished against the face.
            ring: standing.isViewer ? fill : null,
          ),
          const SizedBox(height: _faceGap),
        ],
        // The bar as a raised block: its fill and the crisp offset edge every
        // surface in the app stands on. It wore an outline of the edge's
        // colour too, which on the warmer tints read as a dark rim drawn
        // round the bar rather than as the bar's own side.
        Padding(
          padding: const EdgeInsets.only(bottom: WeekPactMetrics.controlDepth),
          child: Container(
            key: ValueKey('podium-bar-${standing.member.id}'),
            height: _barFor(standing.percent),
            decoration: ShapeDecoration(
              color: fill,
              shape: _barShape,
              shadows: [
                BoxShadow(color: edge, offset: WeekPactMetrics.raisedOffset),
              ],
            ),
            child: inside ? _member(standing, fill) : null,
          ),
        ),
      ],
    );
  }

  /// A face over its figure, as a bar carries them.
  ///
  /// Everyone's face is ringed in their bar's own fill, so it sits in the bar
  /// rather than on it; yours is ringed in the card's dark ink, which every
  /// bar is pale enough to show.
  Widget _member(
    CrewStanding standing,
    Color fill, {
    String? place,
    Color ink = WeekPactColors.black,
    Color? ring,
  }) => Padding(
    // Larger system text is scaled back into the bar rather than spilling
    // out of its shortest height.
    padding: const EdgeInsets.all(3),
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CrewFace(
              key: ValueKey('podium-face-${standing.member.id}'),
              member: standing.member,
              kept: true,
              size: _face,
              tint: fill,
              ring: ring ?? (standing.isViewer ? WeekPactColors.black : fill),
            ),
            const SizedBox(height: _faceGap),
            if (place != null) ...[
              _figure(place, color: ink),
              const SizedBox(height: 3),
            ],
            _figure('${standing.percent}%', color: ink),
          ],
        ),
      ),
    ),
  );

  /// A figure on a bar. The bars are all pale tints, so it is the card's dark
  /// ink in either theme.
  static Widget _figure(String text, {Color color = WeekPactColors.black}) =>
      Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          color: color,
          fontSize: 13,
          height: 1,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  /// The viewer, when the podium has no room for them: a dashed bar carrying
  /// their face, their place and their figure. Dashed, like a day still to
  /// come above it, so it reads as where you stand rather than as a fourth
  /// step on the podium.
  Widget _offPodium(BuildContext context, CrewStanding standing) {
    final fill = _fillOf(standing);
    return Padding(
      key: ValueKey('podium-step-${standing.member.id}'),
      padding: const EdgeInsets.only(bottom: WeekPactMetrics.controlDepth),
      child: SizedBox(
        key: ValueKey('podium-bar-${standing.member.id}'),
        height: _offHeight,
        child: DashedBorder(
          color: fill,
          radius: WeekPactMetrics.curveFor(8),
          // Off a bar there is no pale fill under the figures, so they take
          // the surface's own ink, and the face its progress colour's ring.
          child: _member(
            standing,
            fill,
            place: CrewPodiumPanel._ordinal(standing.place),
            ink: context.ink,
            ring: fill,
          ),
        ),
      ),
    );
  }

  Widget _loadingBarsRow(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (final (i, bar) in _loadingBars.indexed) ...[
        if (i > 0) const SizedBox(width: _barGap),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              bottom: WeekPactMetrics.controlDepth,
            ),
            child: Container(
              height: bar,
              decoration: ShapeDecoration(
                color: context.ink.withValues(alpha: .08),
                shape: _barShape,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class TodayPactsCard extends StatelessWidget {
  const TodayPactsCard({
    super.key,
    required this.week,
    this.height,
    required this.userId,
    required this.savingPact,
    required this.onToggle,
  });

  final double? height;
  final CrewWeek week;
  final String userId;
  final String? savingPact;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context) {
    final pacts = week.pacts;
    if (pacts.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final deckHeight = height ?? (248 + math.max(0.0, scale - 1) * 200);
    return SizedBox(
      height: deckHeight,
      child: PactDeck(
        deckKey: const ValueKey('pact-stack'),
        ids: [for (final pact in pacts) pact.id],
        itemBuilder: (context, index) => _PactCard(
          key: ValueKey(pacts[index].id),
          pact: pacts[index],
          week: week,
          userId: userId,
          color: WeekPactColors.pactTint(index),
          badge: WeekPactColors.pactBadge(index),
          busy: savingPact == pacts[index].id,
          onToggle: savingPact != null || onToggle == null
              ? null
              : () => onToggle!(pacts[index].id),
        ),
      ),
    );
  }
}

class _PactCard extends StatelessWidget {
  const _PactCard({
    super.key,
    required this.pact,
    required this.week,
    required this.userId,
    required this.color,
    required this.badge,
    required this.busy,
    required this.onToggle,
  });
  final CrewPact pact;
  final CrewWeek week;
  final String userId;

  /// The card's tint, and the deeper companion its icon badge is drawn in.
  /// Both come from the pact's place in the crew's list, so they stay a pair.
  final Color color;
  final Color badge;
  final bool busy;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final checked = week.checkedToday(userId).contains(pact.id);
    final completed = week.days(pact.id, userId);
    // Completion reads as a cream inset with a green mark, so the cue works on
    // every card tint instead of fighting the warm ones. Its edge is mixed from
    // the card's own colour, which keeps the raised edge in family.
    final doneEdge = Color.lerp(color, Colors.black, .35)!;
    return PactCardFace(
      pact: pact,
      tint: color,
      badge: badge,
      bodyHeight:
          _contentHeight - PactCardFace.titleBudget - PactCardFace.titleGap,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(
              // The count and its bar sit down against the button,
              // not centred in what the title leaves them: the bar
              // is the button's own tally, so the two read as one
              // block and a card that stands taller opens above
              // them rather than between them.
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The count line, and nothing beside it. The
                  // box to its right carried the crew's faces and
                  // then a days-to-go figure, both of which repeated
                  // what the rail and the bar already say; the
                  // count scales down rather than overflowing when
                  // large text runs the caption past the card.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _CountRow(
                      completed: completed,
                      target: pact.daysPerWeek,
                    ),
                  ),
                  const SizedBox(height: _captionToBar),
                  Semantics(
                    key: ValueKey('pact-progress-${pact.id}'),
                    label: 'Weekly pact progress',
                    value: '$completed of ${pact.daysPerWeek} days',
                    child: Row(
                      children: List.generate(
                        pact.daysPerWeek,
                        // Segments are cut to the same squircle as
                        // the cards and cells around them, held to
                        // half their height: a continuous corner
                        // overshoots once it outgrows the box it is
                        // cutting, and leaves ticks at the ends.
                        (i) => Expanded(
                          child: Container(
                            height: _segmentHeight,
                            margin: EdgeInsets.only(
                              right: i == pact.daysPerWeek - 1 ? 0 : 5,
                            ),
                            decoration: ShapeDecoration(
                              color: i < completed
                                  ? _ink
                                  : _ink.withValues(alpha: .32),
                              shape: ContinuousRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  math.min(
                                    WeekPactMetrics.curveFor(
                                      WeekPactMetrics.controlRadius,
                                    ),
                                    _segmentHeight / 2,
                                  ),
                                ),
                                side: i < completed
                                    ? const BorderSide(
                                        color: WeekPactColors.inkEdge,
                                      )
                                    : BorderSide.none,
                              ),
                              // A day that is kept is raised on the
                              // same edge as the check-in button.
                              shadows: i < completed
                                  ? const [
                                      BoxShadow(
                                        color: WeekPactColors.inkEdge,
                                        offset: WeekPactMetrics.raisedOffset,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The bar belongs to the count, not to the control: it is
          // the same fact the number states, drawn. So it sits with
          // the number and clears the button. This has to beat the
          // ~17px of air the caption's descender already leaves
          // above the bar — at 18 the two gaps matched and the bar
          // floated between them, reading as neither.
          const SizedBox(height: _barToAction),
          // The control eases between its two states rather than cutting:
          // an undo in particular is a bar emptying and the button coming
          // back, and a cut there read as the card flinching.
          // Pinned to the action's height, so the swap and the fade across
          // it move nothing above.
          SizedBox(
            height: _actionHeight,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: .96, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: checked
                  ? KeyedSubtree(
                      key: const ValueKey('checked'),
                      child: _CompletedCheckIn(
                        pactTitle: pact.title,
                        busy: busy,
                        onUndo: onToggle,
                        edge: doneEdge,
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('unchecked'),
                      child: _checkInButton(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The check-in button: ink on the tint, raised on the same edge as the
  /// kept days above it.
  Widget _checkInButton() => Container(
    width: double.infinity,
    height: _actionHeight,
    decoration: const ShapeDecoration(
      shape: WeekPactMetrics.buttonShape,
      shadows: [
        BoxShadow(
          color: WeekPactColors.inkEdge,
          offset: WeekPactMetrics.raisedOffset,
        ),
      ],
    ),
    child: FilledButton.icon(
      key: ValueKey('check-in-${pact.title}'),
      onPressed: onToggle,
      style: FilledButton.styleFrom(
        backgroundColor: _ink,
        foregroundColor: homePaper,
        minimumSize: const Size(0, _actionHeight),
        shape: WeekPactMetrics.buttonShape.copyWith(
          side: const BorderSide(color: WeekPactColors.inkEdge),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : HugeIcon(icon: HugeIconsStrokeRounded.circle, size: 22),
      label: Text(
        'Check in',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 17,
        ),
      ),
    ),
  );
}

class _CompletedCheckIn extends StatefulWidget {
  const _CompletedCheckIn({
    required this.pactTitle,
    required this.busy,
    required this.onUndo,
    required this.edge,
  });

  final Color edge;

  final String pactTitle;
  final bool busy;
  final VoidCallback? onUndo;

  @override
  State<_CompletedCheckIn> createState() => _CompletedCheckInState();
}

/// Undo sits a thumb's width from the check-in it takes back, so it has to be
/// held rather than tapped: the pending grey fills the bar from the left
/// while the finger stays down, and the check-in only comes off once it is
/// full. Letting go, or swiping the deck, drains it again.
class _CompletedCheckInState extends State<_CompletedCheckIn>
    with SingleTickerProviderStateMixin {
  static const _holdFor = Duration(milliseconds: 900);

  /// How many of the lightest taps run under the finger while the bar fills,
  /// about one every 60ms: close enough together to feel like one continuous
  /// hum rather than a count.
  static const _hum = 15;

  late final _hold =
      AnimationController(
          vsync: this,
          duration: _holdFor,
          reverseDuration: const Duration(milliseconds: 200),
        )
        ..addListener(_onHoldTick)
        ..addStatusListener(_onHoldStatus);

  int _humStep = 0;

  bool get _enabled => !widget.busy && widget.onUndo != null;

  void _start() {
    if (!_enabled) return;
    _humStep = 0;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    _hold.forward();
  }

  void _onHoldTick() {
    if (_hold.status != AnimationStatus.forward) return;
    final step = (_hold.value * _hum).floor();
    // The last step is the completion's own, firmer tap.
    if (step <= _humStep || step >= _hum) return;
    _humStep = step;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
  }

  void _release() {
    if (_hold.status == AnimationStatus.completed) return;
    _hold.reverse();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    widget.onUndo?.call();
    // A failed undo leaves the card checked in, so the bar empties again.
    _hold.value = 0;
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Undo check-in',
    hint: 'Hold to undo',
    onTap: _enabled ? widget.onUndo : null,
    child: GestureDetector(
      key: ValueKey('check-in-${widget.pactTitle}'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _start(),
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      // The fill is painted by the bar's own decoration, under its border,
      // so it meets the outline exactly instead of being clipped to it.
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, child) {
          final fill = _hold.value;
          return Container(
            height: _actionHeight,
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                colors: [_undoFill, _undoFill, _doneFill, _doneFill],
                stops: [0, fill, fill, 1],
              ),
              shape: WeekPactMetrics.buttonShape.copyWith(
                side: BorderSide(color: widget.edge),
              ),
              shadows: [
                BoxShadow(
                  color: widget.edge,
                  offset: WeekPactMetrics.raisedOffset,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HugeIcon(
                        icon: HugeIconsStrokeRounded.tickDouble03,
                        color: _doneMark,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Checked in today',
                          style: TextStyle(
                            color: _ink,
                            fontFamily: WeekPactType.secondary,
                            fontFamilyFallback: WeekPactType.secondaryFallback,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 20,
                color: _ink.withValues(alpha: .10),
              ),
              SizedBox(
                width: 96,
                child: Center(
                  child: widget.busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _doneMark,
                          ),
                        )
                      : ExcludeSemantics(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            // Faint enough to read as a note, not a button.
                            child: Text(
                              'Hold to undo',
                              style: TextStyle(
                                color: _ink.withValues(alpha: .38),
                                fontFamily: WeekPactType.secondary,
                                fontFamilyFallback:
                                    WeekPactType.secondaryFallback,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class TodaySkeleton extends StatefulWidget {
  /// The page under Home's title row while the week loads. The title row
  /// itself is not drawn: it stands above the page, live, through the load.
  const TodaySkeleton({super.key});

  @override
  State<TodaySkeleton> createState() => _TodaySkeletonState();
}

class _TodaySkeletonState extends State<TodaySkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final _opacity = Tween<double>(
    begin: .65,
    end: 1,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your home',
    liveRegion: true,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _opacity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The rail's own slot: five faces' worth, which is more crew
              // than most have, so the row is full whatever arrives. It runs
              // off the edge on a narrow phone exactly as the rail itself
              // does, rather than squeezing to fit and then jumping.
              LayoutBuilder(
                builder: (context, space) {
                  final tile = StoriesRail.tileSizeFor(
                    space.maxWidth,
                    bleed: HomeHeader.railBleed,
                  );
                  return SizedBox(
                    height: HomeHeader.railHeightFor(space.maxWidth),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 5,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: StoriesRail.spacing),
                      itemBuilder: (_, _) => Column(
                        children: [
                          SkeletonBar(
                            width: tile,
                            height: tile,
                            shape: const AvatarShape(),
                          ),
                          const SizedBox(height: 6),
                          const SkeletonBar(width: 36, height: 9),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // The streak card's silhouette, at its own height, so nothing on
              // the page moves when the week arrives.
              const SizedBox(
                key: ValueKey('skeleton-streak-card'),
                height: CrewStreakCard.height,
                child: SkeletonBar(
                  height: double.infinity,
                  shape: WeekPactMetrics.pactCardShape,
                ),
              ),
              const SizedBox(height: 12),
              const CrewTodayBar.loading(
                key: ValueKey('skeleton-crew-today-bar'),
              ),
              const SizedBox(height: 12),
              // The pacts' slot, drawn as the cover flow draws it: the
              // focused card at full width, a sliver of the next one past the
              // content's edge, and the dots under them.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, space) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: space.maxWidth + 4,
                        top: space.maxHeight * .07,
                        width: space.maxWidth * .86,
                        height: space.maxHeight * .86,
                        child: Opacity(
                          opacity: .65,
                          child: HomeSurface(
                            tint: WeekPactColors.pactTint(1),
                            shape: WeekPactMetrics.pactCardShape,
                            raised: true,
                            depth: WeekPactMetrics.cardDepth,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: HomeSurface(
                          key: const ValueKey('skeleton-pact-card'),
                          tint: WeekPactColors.pactTint(0),
                          shape: WeekPactMetrics.pactCardShape,
                          raised: true,
                          depth: WeekPactMetrics.cardDepth,
                          padding: homeCardInset,
                          child: const _SkeletonPactFace(),
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
          ),
        ),
      ),
    ),
  );
}

/// A pact card's face while the week loads: the title, badge, count, bar and
/// button in the places [_PactCard] puts them, from the same measures and
/// scaled to the box the same way, so nothing moves when the week arrives.
class _SkeletonPactFace extends StatelessWidget {
  const _SkeletonPactFace();

  /// A bar in the card's own ink, as faint as the empty days on its bar.
  static final _fill = _ink.withValues(alpha: .14);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = math.max(_contentHeight, constraints.maxHeight);
      final shrink = constraints.maxHeight / height;
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: constraints.maxWidth / shrink,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: _titleBudget,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: SkeletonBar(width: 170, height: 24, color: _fill),
                    ),
                    const Spacer(),
                    SkeletonBar(
                      width: _iconBadge,
                      height: _iconBadge,
                      shape: WeekPactMetrics.buttonShape,
                      color: WeekPactColors.pactBadge(0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: _titleGap),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(
                        width: 200,
                        height: 56,
                        radius: 12,
                        color: _fill,
                      ),
                      const SizedBox(height: _captionToBar + 10),
                      Row(
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 5),
                            Expanded(
                              child: SkeletonBar(
                                height: _segmentHeight,
                                radius: 6,
                                color: _fill,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: _barToAction),
              SkeletonBar(
                height: _actionHeight,
                shape: WeekPactMetrics.buttonShape,
                color: _ink.withValues(alpha: .8),
              ),
            ],
          ),
        ),
      );
    },
  );
}
