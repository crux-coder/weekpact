import '../widgets/avatar_shape.dart';
import '../crew/crew_switcher.dart';

import 'dart:async';

import 'package:flutter/services.dart';

import 'home_surface.dart';
import '../theme/weekpact_theme.dart';

import 'package:card_swiper/card_swiper.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pact_icons.dart';
import '../pacts/pacts_backend.dart';
import '../widgets/pact_icon_badge.dart';
import '../widgets/page_frame.dart';
import '../widgets/dashed_border.dart';
import '../widgets/edge_bounce.dart';
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

/// The pact's icon badge on the card: the card tint is too quiet to tell two
/// pacts apart on its own, so this is what does. See [PactIconBadge].
const _iconBadge = 56.0;

/// The height the card keeps for a pact's name, whatever that name is.
///
/// A constant, not the title's natural height: the card scales its whole face
/// to whatever Home gives it, and the scale is computed from one content
/// height for every card in the stack. If the title box grew with the name,
/// a four-line pact would push the number and the button past the bottom of a
/// box sized for a one-line one. 80 is four lines at the size four lines end
/// up at, and a single line still sets at the full display size inside it.
const _titleBudget = 80.0;

/// The gap between the name and the count below it.
const _titleGap = 10.0;

/// The count's own type: the kept-days number, and the caption under it.
const _countSize = 76.0;
const _countCaptionSize = 18.0;
const _countCaptionHeight = 1.2;

/// The gap between the caption and the bar, and between the bar and the
/// button. The bar belongs to the count, so the first is much the smaller of
/// the two — see the note where they are laid out.
const _captionToBar = 10.0;
const _barToAction = 26.0;

/// The tallest the card's action gets. [_CompletedCheckIn] stands 8 taller
/// than the check-in button, and the card has to stand in the same box in
/// either state — a card that grew on check-in would jump the whole stack.
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

/// A title at the largest size that still fits the box it is given.
///
/// A pact is named by the person who made it, so the card cannot assume the
/// name is short. Holding one display size and cutting what does not fit means
/// "Walk the dog around the park before work" arrives as "Walk the dog around
/// the…" — the card keeps its type scale and loses the pact's meaning.
/// Stepping the size down keeps the whole name, and only a name too long to
/// fit even at [minFontSize] takes the ellipsis.
class _FittedTitle extends StatelessWidget {
  const _FittedTitle({required this.text, required this.style});

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
      // wide, and a round size keeps two cards in the same stack on the same
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

  static const railHeight = StoriesRail.height;
  static const gap = CrewSwitcher.gap;

  /// The title row. Tall enough for the bell's tap target, which is the taller
  /// of the two things standing in it; the name centres in whatever is left.
  static const selectorHeight = NotificationsBell.size;
  static const height = selectorHeight + gap + railHeight;

  /// The rail alone, with nothing over it.
  static const headingHeight = railHeight;

  @override
  Widget build(BuildContext context) {
    final above = selector;
    final corner = action;
    return SizedBox(
      key: const ValueKey('home-header'),
      height: above == null && corner == null ? headingHeight : height,
      child: above == null && corner == null
          ? rail
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: selectorHeight,
                  child: Stack(
                    children: [
                      if (above != null)
                        Positioned.fill(child: Center(child: above)),
                      if (corner != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(child: corner),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: gap),
                SizedBox(height: railHeight, child: rail),
              ],
            ),
    );
  }
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

  /// The row's height, which is the crew card's beneath it. The two are the
  /// same object read two ways — the week by day, then the week by member —
  /// and a row shorter than the card under it read as its caption rather than
  /// as its equal. Every point of it comes off the pact card.
  static const height = HomeCrewPanel.cardHeight;

  /// The inset the row keeps off the surface's edge. Tighter at the right,
  /// where the chevron already carries its own optical margin.
  static const _inset = EdgeInsets.fromLTRB(14, 12, 10, 12);

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

  /// The handle into the week, past the hairline that separates the picture
  /// from the thing you press.
  ///
  /// It carried today's count as `2/4` over `TODAY` and no longer does: the
  /// ringed column already draws that figure, and a number beside a picture of
  /// the same number is the sentence this row was built to replace, set
  /// smaller. What is left is where the press goes.
  Widget _door(BuildContext context, bool open) => Container(
    margin: const EdgeInsets.only(left: 11),
    padding: const EdgeInsets.only(left: 11),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: context.ink.withValues(alpha: .14)),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Crew week',
          maxLines: 1,
          style: TextStyle(
            color: context.muted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (open) ...[
          const SizedBox(width: 2),
          HugeIcon(
            icon: HugeIconsStrokeRounded.arrowRight01,
            color: context.muted,
            size: 18,
          ),
        ],
      ],
    ),
  );

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

/// The crew's week on Home: one card, and the way into the week behind it.
///
/// It was a framed block — this card over the day's pull-down, with the crew's
/// roster behind the grip. The day is the stories rail's now, and a frame
/// around a single card is a box drawn round one object, so both went and the
/// card stands on the canvas.
class HomeCrewPanel extends StatefulWidget {
  const HomeCrewPanel({super.key, required this.week, required this.userId});

  /// The loading state: the same card, with its lines not yet filled in, so
  /// nothing on the page moves when the week arrives.
  const HomeCrewPanel.loading({super.key}) : week = null, userId = '';

  final CrewWeek? week;

  /// Whose place the card reads. The track draws the whole crew; this is the
  /// one face on it ringed in ink, and the one the rank is about.
  final String userId;

  /// The card shut: the week's line, and the crew's track under it.
  ///
  /// It stood at 64 while it carried a label and a bar. The track is a row of
  /// faces rather than a rule, and a face needs its own height, so the card
  /// took the difference — which the crew switcher and the pact heading, both
  /// gone from the page, more than paid for.
  static const cardHeight = 80.0;

  /// The block's height, which is the shut card's own. The frame around it
  /// held the card over the day's pull-down, and with the day gone a frame
  /// around a single card was a box drawn round one object.
  ///
  /// The open card stands taller than this, and deliberately does not say so
  /// to the page: Home sizes itself off the card at rest, so opening the
  /// drawer takes its room from the pact card's own share rather than from
  /// every measurement on the page at once.
  static const height = cardHeight;

  /// The card's own inset. Wider than the frame around it, so the label and
  /// the bar sit off the card's edge rather than against it.
  static const _cardInset = homeCardInset;

  /// What the shut card holds, inside that inset.
  static const _shutContent = cardHeight - WeekPactMetrics.pageInset * 2;

  /// The headline's line, and the gap under it. The open card keeps both, so
  /// it is the shut card with its track swapped out rather than a second
  /// layout that happens to start the same way.
  static const _headline = 21.0;
  static const _trackGap = 8.0;

  /// One member's own lane when the card is open, and the gap between two.
  static const _laneFace = 16.0;
  static const _laneBox = _laneFace + _faceRingWidth * 2;
  static const _laneGap = 5.0;

  /// What the open card holds with [lanes] members on it.
  static double _openContent(int lanes) =>
      _headline + _trackGap + lanes * _laneBox + (lanes - 1) * _laneGap;

  /// How long the drawer takes.
  static const _openDuration = Duration(milliseconds: 260);

  @override
  State<HomeCrewPanel> createState() => _HomeCrewPanelState();

  /// The week as a headline: what is left of it on one line, and under it
  /// either the crew on one track or the crew in lanes of their own.
  ///
  /// It used to be a label and one percentage over a bar. A percentage of a
  /// four-person week is the one number about a crew nobody can act on — it
  /// averages the four of them into a figure no member can move on their own,
  /// and it is the visual language of a project tracker, which is not what
  /// four friends keeping pacts together are doing. A place can be moved, and
  /// a track says who is where without averaging anyone away.
  static Widget _week(
    BuildContext context,
    CrewWeek crew, {
    required String userId,
    required List<CrewStanding> standings,
    required bool canOpen,
    required bool open,
  }) {
    final solo = crew.members.length < 2;
    final mine = standings.where((s) => s.isViewer).firstOrNull;
    // Everyone on the same figure is not a first, a second and a third
    // decided by the roster's order; it is a crew that is level, and the
    // headline says nothing about a place rather than inventing one.
    final level =
        standings.isNotEmpty &&
        standings.every((s) => s.percent == standings.first.percent);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${solo ? 'YOUR WEEK' : 'THIS WEEK'} · ${_left(crew.today)}',
                  key: const ValueKey('crew-week-line'),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    height: 1.1,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (crew.streakWeeks > 0) ...[
              _StreakMark(weeks: crew.streakWeeks),
              const SizedBox(width: 8),
            ],
            if (solo)
              _figure('${crew.percent(userId)}', '%')
            else if (!level)
              _figure(
                '${mine?.place ?? standings.length}',
                _suffix(mine?.place ?? standings.length),
                lead: "YOU'RE ",
              ),
            // The handle the card put down when it stopped being a way into
            // the crew week, picked back up for a different job: it opens the
            // card where it stands rather than leaving the page, and it takes
            // its width from the headline, which has it, rather than from the
            // track, which was why the old one had to go.
            if (canOpen) ...[
              const SizedBox(width: 6),
              _OpenMark(key: const ValueKey('crew-panel-mark'), open: open),
            ],
          ],
        ),
        const SizedBox(height: _trackGap),
        if (solo)
          _SoloTrack(
            key: const ValueKey('crew-solo-track'),
            percent: crew.percent(userId),
          )
        else if (open)
          _MemberLanes(
            key: const ValueKey('crew-member-lanes'),
            standings: standings,
            tint: _tintOf(crew),
            faceSize: _laneFace,
            gap: _laneGap,
          )
        else
          _RaceTrack(
            key: const ValueKey('crew-race-track'),
            standings: standings,
            tint: _tintOf(crew),
          ),
      ],
    );
  }

  /// The figure on the right of the line, where the percentage stood: a
  /// number at the headline size with its unit or its ordinal beside it, and
  /// an optional word in front saying whose it is.
  static Widget _figure(String value, String? tail, {String? lead}) =>
      Text.rich(
        TextSpan(
          children: [
            if (lead != null)
              TextSpan(
                text: lead,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w500,
                  color: homeMutedInk,
                ),
              ),
            TextSpan(text: value),
            if (tail != null)
              TextSpan(
                text: tail,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        key: const ValueKey('crew-week-figure'),
        style: const TextStyle(
          color: _ink,
          fontSize: 19,
          height: 1.1,
          fontWeight: FontWeight.w600,
        ),
      );

  /// How much of the week is still to run, today included. Today counts
  /// because today is still a day you can go, which is the whole reason the
  /// line is on the page.
  static String _left(String today) {
    final days = 8 - DateTime.parse(today).weekday;
    return days <= 1 ? 'LAST DAY' : '$days DAYS LEFT';
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

  static Color _tintOf(CrewWeek crew) => crew.percentCrew >= 100
      ? WeekPactColors.mintGreen
      : WeekPactColors.crewProgress;

  static Widget _loadingCard(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Align(
        alignment: Alignment.centerLeft,
        child: SkeletonBar(width: 122, height: 13, color: _skeletonInk),
      ),
      const SizedBox(height: _trackGap),
      // The track's own box, with nobody on it yet: the lane and the flag at
      // the end of it. Standing at the track's full height rather than the
      // lane's keeps the line above it where it will be once the week lands,
      // so nothing on the card moves.
      SizedBox(
        height: _Track.height,
        child: LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              _Track.lane(box.maxWidth, filled: 0, empty: _skeletonInk),
              const _FinishLine(color: _skeletonInk),
            ],
          ),
        ),
      ),
    ],
  );
}

class _HomeCrewPanelState extends State<HomeCrewPanel> {
  /// Whether the crew's own lanes are showing.
  ///
  /// One track carrying the whole crew is unreadable at the moment it matters
  /// most: a crew running close lands inside a few points of each other, and
  /// the track answers that by nudging the faces apart, which is a drawing of
  /// a race rather than the race. Opening the card unstacks that one lane into
  /// one per member, at the positions the nudging had to fudge.
  ///
  /// It is not remembered between visits. The card's job is to answer "where
  /// is everyone" in a glance, and a card that opens already open has spent
  /// the glance before the page is looked at.
  bool _showLanes = false;

  /// The crew on the track, which is also the crew in the lanes: opening the
  /// card unstacks the faces it was already showing, so it would be a strange
  /// drawer that held somebody the track in front of it never did.
  List<CrewStanding> _standings(CrewWeek crew) =>
      _RaceTrack.shownIn(crew.standings(widget.userId));

  /// Whether there is anything to open. A crew of one has no race to unstack,
  /// and a handle that opens a single lane is a handle that lies.
  bool _canOpen(CrewWeek? crew) => crew != null && crew.members.length >= 2;

  void _toggle() {
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    setState(() => _showLanes = !_showLanes);
  }

  @override
  void didUpdateWidget(HomeCrewPanel old) {
    super.didUpdateWidget(old);
    // A crew that shrank to one, or a week that went back to loading, would
    // otherwise leave the card standing open on nothing.
    if (_showLanes && !_canOpen(widget.week)) _showLanes = false;
  }

  @override
  Widget build(BuildContext context) {
    final crew = widget.week;
    // The crew week's own progress card reads the same way: sea glass once the
    // week is kept, citron while it is still being kept.
    final tint = crew == null
        ? WeekPactColors.crewProgress
        : HomeCrewPanel._tintOf(crew);
    final canOpen = _canOpen(crew);
    final open = _showLanes && canOpen;
    final standings = crew == null
        ? const <CrewStanding>[]
        : crew.members.length < 2
        ? const <CrewStanding>[]
        : _standings(crew);
    return HomeSurface(
      tint: tint,
      shape: WeekPactMetrics.pactCardShape,
      radius: WeekPactMetrics.cardCorner,
      raised: true,
      // The card still goes nowhere. It carried a chevron into the crew week
      // while it was a headline and a bar, and that handle came off because
      // the track wanted the width it was standing in. This one opens the card
      // where it is, and stands in the headline, which has width to spare.
      child: Semantics(
        container: true,
        button: canOpen,
        label: 'Crew week',
        value: crew == null ? 'Loading' : _spoken(crew, open: open),
        onTap: canOpen ? _toggle : null,
        child: ExcludeSemantics(
          child: InkWell(
            key: const ValueKey('crew-panel-toggle'),
            onTap: canOpen ? _toggle : null,
            child: Padding(
              padding: HomeCrewPanel._cardInset,
              child: AnimatedSize(
                duration: HomeCrewPanel._openDuration,
                curve: Curves.easeOutCubic,
                // The card grows downward, so the headline stays where the eye
                // left it and only the drawer moves.
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: open
                      ? HomeCrewPanel._openContent(standings.length)
                      : HomeCrewPanel._shutContent,
                  child: _scaledToBox(
                    (context) => crew == null
                        ? HomeCrewPanel._loadingCard(context)
                        : HomeCrewPanel._week(
                            context,
                            crew,
                            userId: widget.userId,
                            standings: standings,
                            canOpen: canOpen,
                            open: open,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What a screen reader is told, which is the standing rather than the
  /// drawing of it — and, once the card is open, that the crew is now listed.
  String _spoken(CrewWeek crew, {required bool open}) {
    if (crew.members.length < 2) {
      return "${crew.percent(widget.userId)} per cent of this week's check-ins";
    }
    final standings = crew.standings(widget.userId);
    final mine = standings.where((s) => s.isViewer).firstOrNull;
    final level = standings.every((s) => s.percent == standings.first.percent);
    final where = level
        ? 'The crew is level, ${crew.percentCrew} per cent of the week kept'
        : 'You are ${HomeCrewPanel._ordinal(mine?.place ?? standings.length)} '
              'of ${crew.members.length} this week';
    return open ? '$where, each member shown' : where;
  }
}

/// The handle on the crew card: a chevron that turns over when the card opens.
///
/// It is the card's only mark that anything happens on a tap, so it is drawn
/// in the card's full ink rather than let down — a handle nobody sees is a
/// card nobody opens.
class _OpenMark extends StatelessWidget {
  const _OpenMark({super.key, required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? .5 : 0,
    duration: HomeCrewPanel._openDuration,
    curve: Curves.easeOutCubic,
    child: HugeIcon(
      icon: HugeIconsStrokeRounded.arrowDown01,
      color: _ink,
      size: 18,
      strokeWidth: 2,
    ),
  );
}

/// The crew unstacked: one lane a member, in the order they stand.
///
/// The track in front of this draws everyone on one line and has to nudge
/// faces apart when two are close, which is the only place that card tells a
/// small lie. A lane each tells the truth — every face sits at its own share
/// with nothing to collide with — and has room at the end for the figure the
/// track could never carry.
///
/// The lanes run themselves in as the card opens: each face leaves the start
/// and travels to its own share, one lane after another down the order. The
/// card is not showing a new fact when it opens, it is spreading a fact the
/// track had piled up, and a field that arrives already standing still reads
/// as a second chart rather than as the first one unstacked. It is also the
/// one moment the week is legible as a *race*, which is what the card has
/// always claimed to be.
class _MemberLanes extends StatefulWidget {
  const _MemberLanes({
    super.key,
    required this.standings,
    required this.tint,
    required this.faceSize,
    required this.gap,
  });

  final List<CrewStanding> standings;
  final Color tint;
  final double faceSize;
  final double gap;

  /// The room the figure at the end of a lane keeps for itself, and the gap
  /// before it. Fixed, so every lane's rail ends on the same line and the
  /// crew reads as a field rather than as rows of different lengths.
  static const _figureWidth = 34.0;
  static const _figureGap = 8.0;

  /// How long the whole field takes to set off and settle, and how far apart
  /// two lanes start. The stagger is small on purpose: the crew should read as
  /// leaving together and arriving apart, which is the race, rather than as a
  /// list being dealt out one row at a time.
  static const _runDuration = Duration(milliseconds: 460);
  static const _stagger = .08;

  /// The share of the run one lane takes, once the last one has started.
  static const _laneRun = .62;

  @override
  State<_MemberLanes> createState() => _MemberLanesState();
}

class _MemberLanesState extends State<_MemberLanes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: _MemberLanes._runDuration,
  );

  @override
  void initState() {
    super.initState();
    // The lanes are built only while the card is open, so mounting is the
    // opening: there is nothing to drive this from outside.
    _run.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Someone who has asked for less motion gets the field standing where it
    // finished, which is the fact; the run is the flourish.
    if (MediaQuery.disableAnimationsOf(context)) _run.value = 1;
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  /// How far along lane [i] is, at the moment it is asked.
  double _at(int i) => Interval(
    math.min(i * _MemberLanes._stagger, 1 - _MemberLanes._laneRun),
    math.min(i * _MemberLanes._stagger + _MemberLanes._laneRun, 1),
    curve: Curves.easeOutCubic,
  ).transform(_run.value);

  @override
  Widget build(BuildContext context) {
    final box = widget.faceSize + _faceRingWidth * 2;
    return AnimatedBuilder(
      animation: _run,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.standings.length; i++) ...[
            if (i > 0) SizedBox(height: widget.gap),
            SizedBox(
              height: box,
              child: Opacity(
                // The lane's own ground arrives before its rider does, so the
                // face runs along a rail rather than painting one behind it.
                opacity: (_at(i) * 3).clamp(0.0, 1.0),
                child: _MemberLane(
                  key: ValueKey('crew-lane-${widget.standings[i].member.id}'),
                  standing: widget.standings[i],
                  tint: widget.tint,
                  faceSize: widget.faceSize,
                  figureWidth: _MemberLanes._figureWidth,
                  figureGap: _MemberLanes._figureGap,
                  run: _at(i),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One member's week: their own rail, their face standing at their share of
/// it, and that share spelled out where the rail ends.
class _MemberLane extends StatelessWidget {
  const _MemberLane({
    super.key,
    required this.standing,
    required this.tint,
    required this.faceSize,
    required this.figureWidth,
    required this.figureGap,
    this.run = 1,
  });

  final CrewStanding standing;
  final Color tint;
  final double faceSize;
  final double figureWidth;
  final double figureGap;

  /// How much of this member's run has been drawn, from the start line at 0
  /// to their own share of the week at 1. The lanes drive it as the card
  /// opens; at rest it is simply 1.
  final double run;

  /// The rail a face runs along. Thinner than the track's lane: there are
  /// several of these stacked and a lane's weight repeated four times reads as
  /// a chart of rules rather than as a field of runners.
  static const _railHeight = 4.0;

  @override
  Widget build(BuildContext context) {
    final box = faceSize + _faceRingWidth * 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = math.max(
          0.0,
          constraints.maxWidth - figureWidth - figureGap,
        );
        // The face's left edge, so a week fully kept puts its right edge on
        // the rail's end rather than hanging off it — the same reading the
        // track takes for the finish.
        final travel = math.max(0.0, railWidth - box);
        final x =
            standing.percent.clamp(0, 100) / 100 * travel * run.clamp(0.0, 1.0);
        return Row(
          children: [
            SizedBox(
              width: railWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (box - _railHeight) / 2,
                    height: _railHeight,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: _ink.withValues(alpha: .18),
                        shape: const RoundedRectangleBorder(
                          borderRadius: WeekPactMetrics.pill,
                        ),
                      ),
                    ),
                  ),
                  // The ground this member has covered, ending under their own
                  // face — the fill and the face are one fact, so they finish
                  // in the same place here as they do on the track.
                  Positioned(
                    left: 0,
                    top: (box - _railHeight) / 2,
                    height: _railHeight,
                    width: (x + box / 2).clamp(_railHeight, railWidth),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: _ink.withValues(alpha: .55),
                        shape: const RoundedRectangleBorder(
                          borderRadius: WeekPactMetrics.pill,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x,
                    top: 0,
                    child: _CrewFace(
                      member: standing.member,
                      kept: true,
                      size: faceSize,
                      tint: tint,
                      ring: standing.isViewer ? _ink : tint,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: figureGap),
            SizedBox(
              width: figureWidth,
              child: Text(
                // The figure counts up with the face rather than standing at
                // the answer while its rider is still on the way: two readings
                // of one run, arriving together.
                '${(standing.percent * run.clamp(0.0, 1.0)).round()}%',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  color: standing.isViewer ? _ink : homeMutedInk,
                  fontSize: 12,
                  height: 1,
                  fontWeight: standing.isViewer
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What the week is run over: a lane, and the flag at the end of it.
///
/// Both the crew's track and a single member's bar are laid out on this, so
/// the two read as the same object with a different field on it — and so the
/// card does not change height when a crew of one becomes a crew of two.
class _Track {
  /// The face on the track, inside its ring, and the box that holds it.
  static const faceSize = 22.0;
  static const faceBox = faceSize + _faceRingWidth * 2;
  static const height = faceBox;

  /// The lane itself, and the flag standing past the end of it.
  static const laneHeight = 7.0;
  static const flagSize = 18.0;
  static const flagGap = 6.0;

  /// How far the lane runs before the flag takes over. The week ends at the
  /// flag, so a member on a kept week stands against it rather than under it.
  static double laneWidth(double width) =>
      math.max(0.0, width - flagSize - flagGap);

  /// The run a face is placed along: the lane, less the face's own box, so a
  /// week fully kept puts the face's right edge on the finish rather than its
  /// left edge.
  static double travel(double width) =>
      math.max(0.0, laneWidth(width) - faceBox);

  /// The lane, with the covered part of it filled in.
  ///
  /// The fill is what the bar used to be and is still the same ink: it is the
  /// ground already run, which is why it ends under the leading face rather
  /// than at some figure of its own.
  static Widget lane(double width, {required double filled, Color? empty}) =>
      Positioned(
        left: 0,
        top: (height - laneHeight) / 2,
        child: SizedBox(
          width: laneWidth(width),
          height: laneHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: empty ?? _ink.withValues(alpha: .18),
                    shape: const RoundedRectangleBorder(
                      borderRadius: WeekPactMetrics.pill,
                    ),
                  ),
                ),
              ),
              if (filled > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: filled.clamp(laneHeight, laneWidth(width)),
                  child: const DecoratedBox(
                    decoration: ShapeDecoration(
                      color: _ink,
                      shape: RoundedRectangleBorder(
                        borderRadius: WeekPactMetrics.pill,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// The chequered flag at the end of the lane: where the week is won.
///
/// The card lost its chevron when it stopped being a way into anything, and
/// the line it draws needed an end — a rule that simply stops is a bar, and a
/// bar is what this card was before.
class _FinishLine extends StatelessWidget {
  const _FinishLine({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => Positioned(
    right: 0,
    top: (_Track.height - _Track.flagSize) / 2,
    child: HugeIcon(
      key: const ValueKey('crew-week-finish'),
      icon: HugeIconsStrokeRounded.racingFlag,
      color: color ?? _ink,
      size: _Track.flagSize,
      strokeWidth: 2,
    ),
  );
}

/// One member's week, where there is no crew to race: the lane filled to
/// their own share of it, running at the same flag.
class _SoloTrack extends StatelessWidget {
  const _SoloTrack({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _Track.height,
    child: LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          _Track.lane(
            box.maxWidth,
            filled:
                percent.clamp(0, 100) / 100 * _Track.laneWidth(box.maxWidth),
          ),
          const _FinishLine(),
        ],
      ),
    ),
  );
}

/// The crew's week as a race: everyone on one track, at their own standing.
///
/// A member sits at the share of their own week they have kept, so the track
/// is read as a field rather than as an average — who is out in front, who is
/// still on the line, and how far apart they are. The viewer is ringed in ink
/// rather than in the card's fill, which is how you find yourself without
/// reading a name.
///
/// Nobody is marked out as last. The palette has a colour for waiting and the
/// track pointedly does not use it: a crew's one shared card is not the place
/// to put a ring round whoever is behind, and the position already says it.
class _RaceTrack extends StatelessWidget {
  const _RaceTrack({super.key, required this.standings, required this.tint});

  final List<CrewStanding> standings;

  /// The card's fill, which rings every face but the viewer's.
  final Color tint;

  /// The most faces the track draws. A track cannot end in a "+3" the way a
  /// row of faces can — a count has no position — so a crew past this keeps
  /// the leader and the viewer and fills the rest from the places around the
  /// viewer, which is the neighbourhood the standing is actually about.
  static const maxFaces = 6;

  /// Who a track of [limit] places draws, out of [standings].
  ///
  /// The card's lanes read the same list: opening the card unstacks the faces
  /// that were on the one lane, so it would be a strange drawer that held
  /// somebody the track in front of it had never shown.
  static List<CrewStanding> shownIn(
    List<CrewStanding> standings, {
    int limit = maxFaces,
  }) {
    if (standings.length <= limit) return standings;
    final viewer = standings.indexWhere((s) => s.isViewer);
    // No viewer on this track — an unlikely week, but the leading places are
    // the ones worth keeping if it happens.
    if (viewer < 0) return standings.take(limit).toList();
    final keep = <int>{0, viewer};
    for (var reach = 1; keep.length < limit; reach++) {
      for (final index in [viewer - reach, viewer + reach]) {
        if (index >= 0 && index < standings.length && keep.length < limit) {
          keep.add(index);
        }
      }
    }
    return [for (final index in keep.toList()..sort()) standings[index]];
  }

  /// How close two faces may be drawn before the second is nudged along.
  /// Well under a face's width: members who are level should read as a pile
  /// on one mark, not as a field spread across the card.
  static const _minStep = 9.0;

  /// Each face's left edge, in the order they are handed in.
  ///
  /// A face starts at its own share of the track and is then pushed just far
  /// enough right to clear the one before it, and the whole row is pulled back
  /// from the right edge if that push ran it off the end. Ties therefore read
  /// as a tight overlapping cluster on one mark rather than as a single face
  /// standing for four people.
  static List<double> placements(List<int> percents, double width) {
    final travel = _Track.travel(width);
    final x = [
      for (final share in percents) share.clamp(0, 100) / 100 * travel,
    ];
    for (var i = 1; i < x.length; i++) {
      x[i] = math.max(x[i], x[i - 1] + _minStep);
    }
    for (var i = x.length - 1; i > 0; i--) {
      if (x[i] > travel) x[i] = travel;
      x[i - 1] = math.min(x[i - 1], x[i] - _minStep);
    }
    return [for (final value in x) value.clamp(0.0, travel)];
  }

  @override
  Widget build(BuildContext context) {
    final shown = shownIn(standings);
    return SizedBox(
      height: _Track.height,
      child: LayoutBuilder(
        builder: (context, box) {
          // Furthest along first is the order places are read in; the track is
          // drawn left to right, so it walks the list backwards.
          final drawn = shown.reversed.toList();
          final x = placements([
            for (final standing in drawn) standing.percent,
          ], box.maxWidth);
          // The ground the crew has covered, which ends under the leading
          // face rather than at a figure of its own — the fill and the front
          // runner are the same fact, so they have to end in the same place.
          final covered = x.isEmpty ? 0.0 : x.last + _Track.faceBox / 2;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              _Track.lane(box.maxWidth, filled: covered),
              const _FinishLine(),
              // The viewer goes on last, so their face is never the one
              // buried under a neighbour's.
              for (final i in [
                for (var i = 0; i < drawn.length; i++)
                  if (!drawn[i].isViewer) i,
                for (var i = 0; i < drawn.length; i++)
                  if (drawn[i].isViewer) i,
              ])
                Positioned(
                  left: x[i],
                  top: 0,
                  child: _CrewFace(
                    key: ValueKey('race-face-${drawn[i].member.id}'),
                    member: drawn[i].member,
                    kept: true,
                    size: _Track.faceSize,
                    tint: tint,
                    ring: drawn[i].isViewer ? _ink : tint,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A running crew streak, beside the week's line. The palette's one loud
/// colour, spent only while the streak is actually running.
class _StreakMark extends StatelessWidget {
  const _StreakMark({required this.weeks});
  final int weeks;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('crew-week-streak'),
    mainAxisSize: MainAxisSize.min,
    children: [
      HugeIcon(
        icon: HugeIconsStrokeRounded.fire,
        color: WeekPactColors.streak,
        size: 15,
        strokeWidth: 2.4,
      ),
      const SizedBox(width: 2),
      Text(
        '$weeks',
        style: const TextStyle(
          color: WeekPactColors.streak,
          fontSize: 15,
          height: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

/// Skeleton lines on Home's pale panels, which keep dark content whatever the
/// canvas is doing.
const _skeletonInk = Color(0x24191B19);

/// A crew that cannot be switched: its name, on the selector's own surface.
class CrewNamePlate extends StatelessWidget {
  const CrewNamePlate({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => CrewHeaderSurface(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CrewControlLabel('YOUR CREW'),
          const SizedBox(height: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                style: TextStyle(
                  color: context.ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The crew's week as one surface: the check-in tiles sit in its top, held by
/// a thin frame, and the labelled row underneath is the way in. Keeping them in
/// the same container says the tiles and the week are the same thing.
class CrewWeekButton extends StatelessWidget {
  const CrewWeekButton({super.key, required this.onOpen, this.checkIns});
  final VoidCallback? onOpen;

  /// The crew's check-in tiles. The unfolding panels paint their own copy over
  /// this space, so what sits here holds the place and sets the width.
  final Widget? checkIns;

  /// The frame the surface keeps around the tiles: enough to read as a
  /// container, not enough to become a margin.
  static const pad = 6.0;
  static const height = 38.0;

  /// The gap under the tiles. Shorter than the frame's own padding, so the row
  /// reads as part of the same surface as the cards rather than a strip parked
  /// beneath them.
  static const rowGap = 1.0;

  /// The frame's own corner. The tiles inside keep the card curve, so this one
  /// steps up by the padding between them and stays concentric with theirs
  /// instead of cutting across them.
  static const frameCurve = WeekPactMetrics.cardCurve + pad;

  @override
  Widget build(BuildContext context) => CrewHeaderSurface(
    curve: frameCurve,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (checkIns != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(pad, pad, pad, rowGap),
            child: checkIns,
          ),
        // The tooltip keeps the old control's wording: the one place that opens
        // the week is still named the same thing.
        Tooltip(
          message: 'View week',
          child: SizedBox(
            height: height,
            child: InkWell(
              key: const ValueKey('open-crew-week'),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    HugeIcon(
                      icon: HugeIconsStrokeRounded.calendar03,
                      color: context.ink,
                      size: 20,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'CREW WEEK',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.ink,
                          fontSize: 14,
                          letterSpacing: .6,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    HugeIcon(
                      icon: HugeIconsStrokeRounded.arrowRight01,
                      color: context.muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class TodayPactsCard extends StatefulWidget {
  const TodayPactsCard({
    super.key,
    required this.week,
    this.height,
    this.horizontalBleed = 0,
    required this.userId,
    required this.savingPact,
    required this.onToggle,
  });

  /// How much of the next card shows past the front one: enough to say there
  /// is another card behind this one, and no more. The strip carries nothing —
  /// no icon, no score — because a card you cannot act on has nothing to say,
  /// and what it used to say was read off the corner of the card in front.
  static double peekOf(double width) => math.min(14.0, width * .045);

  final double? height;
  final double horizontalBleed;
  final CrewWeek week;
  final String userId;
  final String? savingPact;
  final ValueChanged<String>? onToggle;
  @override
  State<TodayPactsCard> createState() => _TodayPactsCardState();
}

class _TodayPactsCardState extends State<TodayPactsCard> {
  final _controller = SwiperController();
  int _index = 0;
  List<CrewPact> get _pacts => widget.week.pacts;

  @override
  void didUpdateWidget(covariant TodayPactsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_pacts.isEmpty) {
      _index = 0;
      return;
    }
    final previousId = _index < oldWidget.week.pacts.length
        ? oldWidget.week.pacts[_index].id
        : null;
    final retainedIndex = _pacts.indexWhere((pact) => pact.id == previousId);
    final nextIndex = retainedIndex >= 0
        ? retainedIndex
        : math.min(_index, _pacts.length - 1);
    if (nextIndex != _index) {
      _index = nextIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pacts.isNotEmpty) {
          _controller.move(_index, animation: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _controller.move(
      index,
      animation: !MediaQuery.disableAnimationsOf(context),
    );
  }

  /// The row of dots under the stack. What is left above them is the card's.
  ///
  /// There used to be a heading over it too — "YOUR PACTS" on the left and a
  /// count of them on the right. The card under it is unmistakably a pact, and
  /// the dots already say how many there are, so the line was a label naming
  /// the one thing on the page that never needed naming.
  static const _dotsHeight = 24.0;

  @override
  Widget build(BuildContext context) {
    final pacts = _pacts;
    if (pacts.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final height = widget.height ?? (248 + math.max(0.0, scale - 1) * 200);
    // The card takes everything the heading and the dots do not. It used to
    // stop at a fixed ceiling, which left the page short under it once Home
    // had room to spare.
    final footer = pacts.length > 1 ? _dotsHeight : 0.0;
    final cardHeight = math.max(80.0, height - footer);
    final visibleDots = math.min(5, pacts.length);
    final start = math.max(0, math.min(_index - 2, pacts.length - visibleDots));
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: cardHeight,
            child: LayoutBuilder(
              builder: (context, space) {
                final previewCount = math.min(1, pacts.length - 1);
                final peek = TodayPactsCard.peekOf(space.maxWidth);
                // Keep card width stable even when there is no next card.
                final reserve = peek;
                final width = space.maxWidth - reserve * 2;
                final viewportWidth =
                    space.maxWidth + widget.horizontalBleed * 2;
                // Park the outgoing card right out of the box. One card is in
                // front and one peeks in behind it; a sliver of a third at the
                // left edge would read as an artefact of the page's padding
                // rather than as a card.
                final previousTravel = width + 12 + peek;
                return OverflowBox(
                  minWidth: space.maxWidth + widget.horizontalBleed * 2,
                  maxWidth: space.maxWidth + widget.horizontalBleed * 2,
                  // Reserve paint space for the stacked cards during transitions.
                  minHeight: cardHeight + 48,
                  maxHeight: cardHeight + 48,
                  child: EdgeBounce(
                    atStart: _index == 0,
                    atEnd: _index == pacts.length - 1,
                    child: Swiper(
                      key: const ValueKey('pact-stack'),
                      controller: _controller,
                      itemCount: pacts.length,
                      layout: SwiperLayout.STACK,
                      itemWidth: width,
                      itemHeight: cardHeight - 20,
                      axisDirection: AxisDirection.right,
                      scrollDirection: Axis.horizontal,
                      loop: false,
                      autoplay: false,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 280,
                      onIndexChanged: (index) {
                        if (index == _index) return;
                        setState(() => _index = index);
                        unawaited(
                          HapticFeedback.mediumImpact().catchError(
                            (Object _) {},
                          ),
                        );
                      },
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 2,
                        ),
                        child: Builder(
                          builder: (context) {
                            // Follow the stack's interpolated transforms, rather
                            // than snapping offsets when the selected index changes.
                            var stackScale = 1.0;
                            var stackX = 0.0;
                            var transforms = 0;
                            context.visitAncestorElements((element) {
                              final ancestor = element.widget;
                              if (ancestor is Transform) {
                                if (transforms == 0) {
                                  stackScale = ancestor.transform.storage[0];
                                } else {
                                  stackX = ancestor.transform.storage[12];
                                }
                                transforms++;
                              }
                              return transforms < 2;
                            });
                            // The stack only scales the cards behind the
                            // front one, so the card sliding out reads its
                            // strip progress from how far it has travelled.
                            final depth = stackScale >= 1
                                ? (-stackX / viewportWidth).clamp(0.0, 1.0)
                                : ((1 - stackScale) / .1).clamp(0.0, 3.0);
                            // The swiper scales around the right edge. Cancel its
                            // native offset so each rear card exposes one strip.
                            return Transform.translate(
                              key: ValueKey('pact-slide-stack-$index'),
                              offset: stackScale >= 1
                                  // The front card rests dead centre (stackX is
                                  // 0 there) and slides out to `previousTravel`.
                                  ? Offset(
                                      stackX *
                                          (previousTravel / viewportWidth - 1),
                                      0,
                                    )
                                  : Offset(
                                      (depth * peek - stackX) / stackScale,
                                      (depth * 6 -
                                              (cardHeight - 20) *
                                                  (1 - stackScale) /
                                                  2) /
                                          stackScale,
                                    ),
                              child: IgnorePointer(
                                ignoring: stackX < -.01,
                                child: ExcludeSemantics(
                                  excluding: stackX < -.01,
                                  child: Opacity(
                                    opacity: (previewCount + 1 - depth).clamp(
                                      0.0,
                                      1.0,
                                    ),
                                    child: SizedBox.expand(
                                      child: _PactCompletionEffect(
                                        key: ValueKey(
                                          'completion-${pacts[index].id}',
                                        ),
                                        completed: widget.week
                                            .checkedToday(widget.userId)
                                            .contains(pacts[index].id),
                                        child: _PactCard(
                                          depth: depth,
                                          key: ValueKey(pacts[index].id),
                                          pact: pacts[index],
                                          week: widget.week,
                                          userId: widget.userId,
                                          color: WeekPactColors.pactTint(index),
                                          badge: WeekPactColors.pactBadge(
                                            index,
                                          ),
                                          busy:
                                              widget.savingPact ==
                                              pacts[index].id,
                                          onToggle:
                                              widget.savingPact != null ||
                                                  widget.onToggle == null
                                              ? null
                                              : () => widget.onToggle!(
                                                  pacts[index].id,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (pacts.length > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var dot = start; dot < start + visibleDots; dot++)
                  Semantics(
                    selected: dot == _index,
                    child: IconButton(
                      tooltip: 'Pact ${dot + 1} of ${pacts.length}',
                      onPressed: () => _goTo(dot),
                      style: IconButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints(minHeight: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 6,
                      ),
                      icon: Container(
                        width: dot == _index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot == _index
                              ? context.ink
                              : context.ink.withValues(alpha: .3),
                          borderRadius: WeekPactMetrics.pill,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Celebrates a confirmed state change, never the tap or an initial load.
class _PactCompletionEffect extends StatefulWidget {
  const _PactCompletionEffect({
    super.key,
    required this.completed,
    required this.child,
  });
  final bool completed;
  final Widget child;
  @override
  State<_PactCompletionEffect> createState() => _PactCompletionEffectState();
}

/// One short pop when a check-in lands. It runs after the check-in drawer has
/// finished closing, and the buzz comes from the save itself.
class _PactCompletionEffectState extends State<_PactCompletionEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.06,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.06,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_animation);

  @override
  void didUpdateWidget(covariant _PactCompletionEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.completed) _animation.stop();
    if (widget.completed &&
        !oldWidget.completed &&
        !MediaQuery.disableAnimationsOf(context)) {
      _animation.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _animation.stop();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) => Transform.scale(
      scale: _animation.isAnimating ? _scale.value : 1.0,
      child: child,
    ),
  );
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
    this.depth = 0,
  });
  final double depth;
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
    return HomeSurface(
      tint: color,
      radius: WeekPactMetrics.cardCorner,
      raised: true,
      depth: WeekPactMetrics.cardDepth,
      shape: WeekPactMetrics.pactCardShape,
      outlineColor: Color.lerp(color, Colors.black, .28),
      padding: homeCardInset,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // What the card's content stands in before it is scaled to the
          // height Home gives it. One number for every card, whatever state
          // it is in: two cards in the same stack have to scale alike.
          final minimumHeight =
              _contentHeight +
              math.max(0.0, MediaQuery.textScalerOf(context).scale(1) - 1) *
                  228;
          final shrink =
              constraints.maxHeight /
              math.max(minimumHeight, constraints.maxHeight);
          final reveal = (1 - depth).clamp(0.0, 1.0);
          final content = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              // Compensate for height scaling so the calendar and
              // action still span the entire inner width of the active card.
              width: constraints.maxWidth / shrink,
              height: math.max(minimumHeight, constraints.maxHeight),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: _ink),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _titleBudget,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: pact.title,
                              child: _FittedTitle(
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
                          const SizedBox(width: _iconBadge + 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: _titleGap),
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
                                        right: i == pact.daysPerWeek - 1
                                            ? 0
                                            : 5,
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
                                                  offset: WeekPactMetrics
                                                      .raisedOffset,
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
                    if (checked)
                      _CompletedCheckIn(
                        pactTitle: pact.title,
                        busy: busy,
                        onUndo: onToggle,
                        edge: doneEdge,
                      )
                    else
                      Container(
                        width: double.infinity,
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
                            minimumSize: const Size(0, 48),
                            shape: WeekPactMetrics.buttonShape.copyWith(
                              side: const BorderSide(
                                color: WeekPactColors.inkEdge,
                              ),
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
                              : HugeIcon(
                                  icon: HugeIconsStrokeRounded.circle,
                                  size: 22,
                                ),
                          label: Text(
                            'Check in',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontFamily: WeekPactType.secondary,
                              fontFamilyFallback:
                                  WeekPactType.secondaryFallback,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          // The badge is the card's own, at one size, and it scales with the
          // rest of the face. It fades as the card falls back into the stack —
          // the strip behind the front card carries nothing.
          final iconSize = _iconBadge * shrink;
          // The card tint stays put; only its foreground follows the stack.
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              ExcludeSemantics(
                excluding: reveal < 1,
                child: IgnorePointer(
                  ignoring: reveal < 1,
                  child: Opacity(
                    key: ValueKey('pact-content-opacity-${pact.id}'),
                    opacity: reveal,
                    child: content,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: reveal,
                    child: PactIconBadge(
                      key: ValueKey('pact-icon-${pact.id}'),
                      icon: PactIcon.find(pact.iconKey).data,
                      tint: badge,
                      size: iconSize,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompletedCheckIn extends StatelessWidget {
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
  Widget build(BuildContext context) => Container(
    height: 56,
    decoration: ShapeDecoration(
      color: _doneFill,
      shape: WeekPactMetrics.buttonShape.copyWith(
        side: BorderSide(color: edge),
      ),
      shadows: [BoxShadow(color: edge, offset: WeekPactMetrics.raisedOffset)],
    ),
    padding: const EdgeInsets.only(left: 10),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 10),
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
        ),
        Container(width: 1, height: 20, color: _ink.withValues(alpha: .10)),
        SizedBox(
          width: 80,
          height: 56,
          child: Tooltip(
            message: 'Undo check-in',
            child: TextButton(
              key: ValueKey('check-in-$pactTitle'),
              onPressed: busy ? null : onUndo,
              style: TextButton.styleFrom(
                foregroundColor: _ink,
                minimumSize: const Size(80, 56),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                shape: const ContinuousRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(WeekPactMetrics.panelCurve),
                  ),
                ),
              ),
              child: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _doneMark,
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          fontFamily: WeekPactType.secondary,
                          fontFamilyFallback: WeekPactType.secondaryFallback,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
  );
}

class TodaySkeleton extends StatefulWidget {
  const TodaySkeleton({super.key, this.selector, this.action});

  /// The live crew switcher, where Home already has one. It rides the loading
  /// page rather than being drawn as bars, so switching crews neither cuts the
  /// hand's flight short nor moves the control it was pulled from. Null before
  /// the crews are in, which the skeleton draws as its own slot.
  final Widget? selector;

  /// The bell, which does not wait for the crews: it counts what the crew has
  /// told you, not what this week holds, so it stands in the corner from the
  /// first frame rather than arriving with the week.
  final Widget? action;
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

  Widget _line(double width, double height, {Color? color}) => Align(
    alignment: Alignment.centerLeft,
    child: SkeletonBar(width: width, height: height, color: color),
  );

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
              // The title row, drawn exactly as the loaded page draws it: the
              // live control rather than a bar, so switching neither blinks
              // the title out nor moves it, and the bell in the corner from
              // the first frame. The name itself is not drawn on spec — it
              // only appears once the page knows which crew it is about.
              if (widget.selector != null || widget.action != null) ...[
                SizedBox(
                  height: HomeHeader.selectorHeight,
                  child: Stack(
                    children: [
                      if (widget.selector != null)
                        Positioned.fill(child: Center(child: widget.selector)),
                      if (widget.action != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(child: widget.action),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: HomeHeader.gap),
              ],
              // The rail's own slot: five faces' worth, which is more crew
              // than most have, so the row is full whatever arrives. It runs
              // off the edge on a narrow phone exactly as the rail itself
              // does, rather than squeezing to fit and then jumping.
              SizedBox(
                height: HomeHeader.headingHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, _) => const Column(
                    children: [
                      SkeletonBar(
                        width: StoriesRail.tileSize,
                        height: StoriesRail.tileSize,
                        shape: AvatarShape(),
                      ),
                      SizedBox(height: 5),
                      SkeletonBar(width: 28, height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const CrewTodayBar.loading(
                key: ValueKey('skeleton-crew-today-bar'),
              ),
              const SizedBox(height: 12),
              // The crew panel is empty either way, so the skeleton holds the
              // same surface rather than promising something to load into it.
              const HomeCrewPanel.loading(key: ValueKey('skeleton-crew-panel')),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 24,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          SkeletonBar(width: 88, height: 14),
                          SkeletonBar(width: 42, height: 12),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: LayoutBuilder(
                          builder: (context, bounds) {
                            final peek = TodayPactsCard.peekOf(bounds.maxWidth);
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // The card behind, showing the same sliver the
                                // stack shows and carrying nothing, as it
                                // carries nothing once the week has loaded.
                                Positioned(
                                  left: peek * 4,
                                  right: 0,
                                  top: 6,
                                  bottom: 6,
                                  child: HomeSurface(
                                    tint: WeekPactColors.pactPalette[1],
                                    shape: WeekPactMetrics.pactCardShape,
                                    raised: true,
                                    depth: WeekPactMetrics.cardDepth,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                Positioned.fill(
                                  left: peek,
                                  right: peek,
                                  child: HomeSurface(
                                    key: const ValueKey('skeleton-pact-card'),
                                    tint: WeekPactColors.pactPalette.first,
                                    shape: WeekPactMetrics.pactCardShape,
                                    raised: true,
                                    depth: WeekPactMetrics.cardDepth,
                                    padding: homeCardInset,
                                    child: LayoutBuilder(
                                      builder: (context, space) => Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(child: _line(150, 20)),
                                                const SizedBox(width: 12),
                                                SkeletonBar(
                                                  width: math.min(
                                                    44,
                                                    space.maxHeight * .16,
                                                  ),
                                                  height: math.min(
                                                    44,
                                                    space.maxHeight * .16,
                                                  ),
                                                  shape: WeekPactMetrics
                                                      .buttonShape,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                _line(
                                                  110,
                                                  math.min(
                                                    58,
                                                    space.maxHeight * .18,
                                                  ),
                                                ),
                                                SizedBox(
                                                  height: space.maxHeight * .02,
                                                ),
                                                _line(
                                                  100,
                                                  math.min(
                                                    13,
                                                    space.maxHeight * .05,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              for (var i = 0; i < 5; i++) ...[
                                                if (i > 0)
                                                  const SizedBox(width: 5),
                                                Expanded(
                                                  child: SkeletonBar(
                                                    height: math.min(
                                                      10,
                                                      space.maxHeight * .04,
                                                    ),
                                                    radius: 3,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Spacer(),
                                          Expanded(
                                            flex: 2,
                                            child: Row(
                                              children: [
                                                for (
                                                  var day = 0;
                                                  day < 7;
                                                  day++
                                                ) ...[
                                                  if (day > 0)
                                                    const SizedBox(width: 5),
                                                  Expanded(
                                                    child: SkeletonBar(
                                                      height: double.infinity,
                                                      radius: 8,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            height: space.maxHeight * .04,
                                          ),
                                          SkeletonBar(
                                            height: math.min(
                                              48,
                                              space.maxHeight * .16,
                                            ),
                                            shape: WeekPactMetrics.buttonShape,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 24,
                      child: Center(child: SkeletonBar(width: 32, height: 6)),
                    ),
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
