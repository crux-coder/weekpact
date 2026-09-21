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
import '../widgets/edge_bounce.dart';
import 'home_backend.dart';
import 'crew_member_list.dart';
import 'crew_today_strip.dart';

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

/// The caption's line box. 18 x 1.2 is 21.6, but a line lays out on whole
/// pixels, so the floor has to reserve the 22 it actually takes — the missing
/// .4 is enough to overflow the column.
const _countCaptionBox = 22.0;

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
    _countCaptionBox +
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
    ],
  );
}

/// The face of one crewmate beside the count, and the seat of one who has not
/// been in yet.
const _faceSize = 34.0;

/// The ring of card fill each face is drawn on, so an overlapping neighbour
/// still reads as a separate person.
const _faceRingWidth = 2.0;

/// The whole drawn face, ring included — the step the row is laid out on.
const _faceBox = _faceSize + _faceRingWidth * 2;

/// How far each face slides under the one before it.
const _faceOverlap = 9.0;

/// What one more face adds to the row's width.
const _faceStep = _faceBox - _faceOverlap;

/// How many faces the zone draws before the rest become a count. Four is what
/// fits beside the number on the narrowest phone the app supports.
const _maxFaces = 4;

/// Who in the crew has kept this pact today, in the space right of the count.
///
/// The card already knew this and never said it: [CrewWeek.checkIns] names the
/// pact, the person and the day for every check-in in the week, and
/// [CrewWeek.members] is the roster. It is the one thing the card can say that
/// the person cannot work out from their own numbers — and the reason a pact
/// lives in a crew rather than in a notes app.
///
/// The whole crew is counted, the viewer included, because the crew strip
/// higher up Home counts the same crew the same way — `n/${members.length} in
/// today`. Leaving the viewer out reads as an undercount rather than as a
/// different question: on a crew of three it says "0 of 2", and the only
/// sensible response to that is to wonder where the third person went.
///
/// A crew of one gets [_PactDaysToGo] instead, where there is no one to count.
class _PactCrewToday extends StatelessWidget {
  const _PactCrewToday({
    super.key,
    required this.members,
    required this.userId,
    required this.keptToday,
    required this.tint,
  });

  final List<WeekMember> members;

  /// The viewer, who leads the row the way they lead the crew strip's.
  final String userId;
  final Set<String> keptToday;

  /// The card's fill, which rings each face so overlapping ones stay apart.
  final Color tint;

  @override
  Widget build(BuildContext context) {
    // In first, and the viewer first within each group — the same order the
    // crew strip seats its faces in, so the two rows on one screen do not
    // disagree about where a person stands.
    final roster = [...members]
      ..sort((a, b) {
        if (a.id == b.id) return 0;
        if (a.id == userId) return -1;
        if (b.id == userId) return 1;
        return 0;
      });
    final inToday = roster.where((m) => keptToday.contains(m.id)).toList();
    final out = roster.where((m) => !keptToday.contains(m.id)).toList();
    final ordered = [...inToday, ...out];
    // The last slot becomes "+N" when the crew outruns the row, so a crew of
    // six shows three faces and a count rather than four faces and a lie.
    final overflow = ordered.length > _maxFaces
        ? ordered.length - (_maxFaces - 1)
        : 0;
    final shown = ordered
        .take(overflow > 0 ? _maxFaces - 1 : _maxFaces)
        .toList();
    final slots = shown.length + (overflow > 0 ? 1 : 0);
    return Semantics(
      label: '${inToday.length} of ${members.length} crew in today',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            // A Stack takes no size of its own, and the zone is not a flex
            // child, so the row states its width: one whole face, plus a step
            // for every one that slides under it.
            width: _faceBox + (slots - 1) * _faceStep,
            height: _faceBox,
            child: Stack(
              children: [
                // Drawn last to first, so each face laps over the one after
                // it rather than under.
                for (var slot = slots - 1; slot >= 0; slot--)
                  Positioned(
                    left: slot * _faceStep,
                    child: slot < shown.length
                        ? _CrewFace(
                            member: shown[slot],
                            kept: keptToday.contains(shown[slot].id),
                            tint: tint,
                          )
                        : _CrewFace(kept: false, tint: tint, more: overflow),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${inToday.length} of ${members.length} in today',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: WeekPactType.secondary,
              fontFamilyFallback: WeekPactType.secondaryFallback,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: homeMutedInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// One face. Kept today is a solid, paper-filled seat carrying the person's
/// picture; not yet is a hole cut in the card, on the same ink the unfilled
/// segments of the bar are — the two states then read alike wherever they
/// appear on the card, and both work on all ten tints because both are mixed
/// from the tint itself.
class _CrewFace extends StatelessWidget {
  const _CrewFace({
    this.member,
    required this.kept,
    required this.tint,
    this.more,
  });

  final WeekMember? member;
  final bool kept;
  final Color tint;

  /// Set instead of [member] for the "+2" that stands for the rest.
  final int? more;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      more != null ? '+$more' : member!.initials,
      style: TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: kept ? _ink : homeMutedInk,
      ),
    );
    final url = kept ? member?.avatarUrl : null;
    return Container(
      // The ring is the card's own fill, so a face that slides under the one
      // before it still reads as a separate person.
      padding: const EdgeInsets.all(2),
      decoration: ShapeDecoration(color: tint, shape: const AvatarShape()),
      child: AvatarClip(
        child: SizedBox.square(
          dimension: _faceSize,
          child: ColoredBox(
            color: kept ? homePaper : _ink.withValues(alpha: .14),
            child: Center(
              child: url == null
                  ? label
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: _faceSize,
                      height: _faceSize,
                      errorBuilder: (_, _, _) => Center(child: label),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the week still wants, for a crew of one.
///
/// The count says what has been done; this says what is left, which is the
/// number that decides whether today is a day you go.
class _PactDaysToGo extends StatelessWidget {
  const _PactDaysToGo({required this.remaining});
  final int remaining;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        remaining == 0 ? 'Week' : '$remaining',
        style: TextStyle(
          fontSize: 34,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: homeMutedInk,
        ),
      ),
      Text(
        remaining == 0 ? 'kept' : 'to go',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: homeMutedInk,
        ),
      ),
    ],
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
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.streakWeeks, this.selector});

  /// The crew switcher, or a plain name plate when there is nothing to switch.
  /// Null leaves the heading on its own, at [headingHeight].
  final Widget? selector;
  final int streakWeeks;

  static const titleHeight = 44.0;
  static const gap = 12.0;
  static const selectorHeight = CrewSwitcher.height;
  static const height = titleHeight + gap + selectorHeight;

  /// The heading and its streak alone, with nothing under them.
  static const headingHeight = titleHeight;

  @override
  Widget build(BuildContext context) {
    final title = SizedBox(
      height: titleHeight,
      child: Row(
        children: [
          const Expanded(
            child: PageHeading('Home', dotColor: WeekPactColors.salmon),
          ),
          const SizedBox(width: 10),
          CrewStreakPill(streakWeeks: streakWeeks),
        ],
      ),
    );
    final below = selector;
    return SizedBox(
      key: const ValueKey('home-header'),
      height: below == null ? headingHeight : height,
      child: below == null
          ? title
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: gap),
                SizedBox(height: selectorHeight, child: below),
              ],
            ),
    );
  }
}

/// The crew block's slot on Home, held empty: the surface, corner and height
/// the crew week card had, with nothing in it. Here so the space is kept and
/// laid out while what goes in it is worked out.
class HomeCrewPanel extends StatelessWidget {
  const HomeCrewPanel({
    super.key,
    required this.week,
    this.userId = '',
    this.onOpenWeek,
    this.backend,
    this.crewId,
    this.active = true,
  });

  /// The loading state: the same frame, card and day line, with their lines
  /// not yet filled in, so nothing on the page moves when the week arrives.
  const HomeCrewPanel.loading({super.key})
    : week = null,
      userId = '',
      onOpenWeek = null,
      backend = null,
      crewId = null,
      active = true;

  final CrewWeek? week;
  final String userId;

  /// Opens the crew week. The progress card is the way in — it is the week
  /// the page shows, at a glance — so the card carries the chevron and takes
  /// the tap rather than a row of its own.
  final VoidCallback? onOpenWeek;

  /// The day line's nudges, and the crew they are sent in.
  final HomeBackend? backend;
  final String? crewId;

  /// False while Home is off screen, which closes an open day panel.
  final bool active;

  /// The frame the panel keeps around its contents, as the crew week surface
  /// kept one around its tiles.
  static const pad = CrewWeekButton.pad;

  /// The progress card: a headline, so it takes only the height its own two
  /// lines need and leaves the rest of the block to the crew.
  static const cardHeight = 64.0;
  static const _cardGap = 8.0;

  /// The block's height. Fixed whatever the crew's size, because the day is
  /// one line of faces rather than a row per person.
  static const height = pad * 2 + cardHeight + _cardGap + CrewTodayStrip.height;

  /// The card's own inset. Wider than the frame around it, so the label and
  /// the bar sit off the card's edge rather than against it.
  static const _cardInset = homeCardInset;

  @override
  Widget build(BuildContext context) {
    final crew = week;
    final percent = crew?.percentCrew;
    // The crew week's own progress card reads the same way: sea glass once the
    // week is kept, citron while it is still being kept.
    final tint = percent != null && percent >= 100
        ? WeekPactColors.mintGreen
        : WeekPactColors.crewProgress;
    return SizedBox(
      height: height,
      child: CrewHeaderSurface(
        curve: CrewWeekButton.frameCurve,
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: cardHeight,
                child: HomeSurface(
                  tint: tint,
                  shape: WeekPactMetrics.pactCardShape,
                  radius: WeekPactMetrics.cardCorner,
                  raised: true,
                  // The inset sits inside the tap rather than around it, so
                  // the whole card face answers the finger.
                  child: Tooltip(
                    message: 'View week',
                    child: InkWell(
                      key: const ValueKey('open-crew-week'),
                      onTap: percent == null ? null : onOpenWeek,
                      child: Padding(
                        padding: _cardInset,
                        child: _scaled(
                          (context) => percent == null
                              ? _loadingCard(context)
                              : _progress(context, percent),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _cardGap),
              // The day runs the block's full width: it keeps its own inset on
              // the left and finishes hard on the right, under the card above.
              if (crew == null)
                _loadingDay(context)
              else
                CrewTodayStrip(
                  week: crew,
                  userId: userId,
                  backend: backend,
                  crewId: crewId,
                  active: active,
                  // The drawer comes out at the block's own width and
                  // finishes on the block's own corner.
                  bleed: pad,
                  curve: CrewWeekButton.frameCurve,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Home does not scroll, so larger system text is laid out at the room it
  /// wants and scaled back into its slot rather than growing one.
  Widget _scaled(WidgetBuilder child) => LayoutBuilder(
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

  /// The week as a headline: its label and the percentage on one line, and the
  /// bar under them. The label says what is being counted, so the card carries
  /// no icon of its own — only the chevron, which is its handle.
  Widget _progress(BuildContext context, int percent) => Semantics(
    container: true,
    button: onOpenWeek != null,
    label: 'Crew progress',
    value: "$percent per cent of this week's check-ins",
    hint: onOpenWeek == null ? null : 'Opens the crew week',
    onTap: onOpenWeek,
    child: ExcludeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'CREW PROGRESS · THIS WEEK',
                          style: TextStyle(
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
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '$percent'),
                          const TextSpan(
                            text: '%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      key: const ValueKey('crew-progress-percent'),
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 19,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 9,
                  borderRadius: WeekPactMetrics.pill,
                  color: _ink,
                  backgroundColor: _ink.withValues(alpha: .18),
                ),
              ],
            ),
          ),
          if (onOpenWeek != null) ...[
            const SizedBox(width: 6),
            // Big enough to be the card's own handle rather than a mark on
            // it: the card is the way into the week, and this says so.
            HugeIcon(
              icon: HugeIconsStrokeRounded.arrowRight01,
              color: context.muted,
              size: _chevronSize,
              strokeWidth: 2,
            ),
          ],
        ],
      ),
    ),
  );

  /// The chevron's glyph, and the room the loading card keeps for it so the
  /// bar under it does not move once the week arrives.
  static const _chevronSize = 30.0;

  Widget _loadingCard(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBar(width: 122, height: 13, color: _skeletonInk),
            ),
            const SizedBox(height: 7),
            Container(
              height: 9,
              decoration: const ShapeDecoration(
                color: _skeletonInk,
                shape: RoundedRectangleBorder(
                  borderRadius: WeekPactMetrics.pill,
                ),
              ),
            ),
          ],
        ),
      ),
      if (onOpenWeek != null) const SizedBox(width: 6 + _chevronSize),
    ],
  );

  /// The day line before the week has arrived: the strip's one row, unfilled.
  /// It takes the strip's own insets and heights, so nothing in the row moves
  /// once the week lands.
  Widget _loadingDay(BuildContext context) => const SizedBox(
    height: CrewTodayStrip.height,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: CrewTodayStrip.leftInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: CrewTodayStrip.rowHeight,
            child: Row(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonBar(width: 104, height: 18),
                ),
                Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: SkeletonBar(width: 48, height: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
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

/// The crew's streak, as a pill beside the page's name. A readout, not a
/// control: the flame says what the number counts, and [CrewWeekButton] is
/// where the week is opened.
class CrewStreakPill extends StatelessWidget {
  const CrewStreakPill({super.key, required this.streakWeeks});
  final int streakWeeks;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Crew streak',
    value: '$streakWeeks ${streakWeeks == 1 ? 'week' : 'weeks'}',
    child: CrewHeaderSurface(
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIconsStrokeRounded.fire,
                    color: streakWeeks > 0
                        ? WeekPactColors.streak
                        : context.muted,
                    size: 24,
                    strokeWidth: 2,
                  ),
                  const SizedBox(width: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$streakWeeks'),
                        TextSpan(
                          text: streakWeeks == 1 ? ' week' : ' weeks',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    key: const ValueKey('crew-header-streak'),
                    style: TextStyle(
                      color: context.ink,
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

  /// The section's own heading, and the row of dots under the stack. What is
  /// left between them is the card's.
  static const _headingHeight = 24.0;
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
    final cardHeight = math.max(80.0, height - _headingHeight - footer);
    final visibleDots = math.min(5, pacts.length);
    final start = math.max(0, math.min(_index - 2, pacts.length - visibleDots));
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _headingHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'YOUR PACTS',
                      style: TextStyle(
                        color: context.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${pacts.length} ${pacts.length == 1 ? 'pact' : 'pacts'}',
                      key: const ValueKey('pact-position'),
                      style: TextStyle(
                        color: context.muted,
                        fontFamily: WeekPactType.secondary,
                        fontFamilyFallback: WeekPactType.secondaryFallback,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    // A crew of one has nobody to count, so the zone says what the week still
    // wants instead. Above that, the whole crew is shown and counted — see
    // [_PactCrewToday].
    final crew = week.members;
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
                            Row(
                              // The count and the crew sit on the same floor,
                              // so the faces line up with the caption rather
                              // than floating over it.
                              crossAxisAlignment: CrossAxisAlignment.end,
                              // Both sides are flex children, and the row is
                              // spaced between them. Each part of that matters:
                              // flex bounds them, so neither can outrun the row
                              // — an unbounded count runs "days this week" off
                              // the card at large text — and `spaceBetween`
                              // hands the slack to the gap rather than trailing
                              // it after the zone, which is what left the faces
                              // stopping short of the card's inset.
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: _CountRow(
                                          completed: completed,
                                          target: pact.daysPerWeek,
                                        ),
                                      ),
                                      Text(
                                        'days this week',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: WeekPactType.secondary,
                                          fontFamilyFallback:
                                              WeekPactType.secondaryFallback,
                                          fontSize: _countCaptionSize,
                                          height: _countCaptionHeight,
                                          fontWeight: FontWeight.w500,
                                          color: homeMutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // The box right of the count. Empty it read as
                                // a mistake; what goes in it is the one thing
                                // the card can say that the person cannot work
                                // out from their own numbers.
                                //
                                // It takes what the count leaves and sits
                                // flush with the card's inset, scaling itself
                                // down rather than overflowing when a narrow
                                // phone leaves it little.
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.bottomRight,
                                      child: crew.length < 2
                                          ? _PactDaysToGo(
                                              remaining: math.max(
                                                0,
                                                pact.daysPerWeek - completed,
                                              ),
                                            )
                                          : _PactCrewToday(
                                              key: ValueKey(
                                                'pact-crew-${pact.id}',
                                              ),
                                              members: crew,
                                              userId: userId,
                                              keptToday: week.keptToday(
                                                pact.id,
                                              ),
                                              tint: color,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
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
                                            : _ink.withValues(alpha: .20),
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

/// Who is in today and who is not, as two tiles the viewer can open.
class TodayCrewCard extends StatelessWidget {
  const TodayCrewCard({
    super.key,
    required this.week,
    required this.userId,
    required this.onOpen,
    this.crewName = '',
    this.height = groupHeight,
    this.showGroups = true,
    this.now,
  });
  final CrewWeek week;
  final String userId;
  final String crewName;
  final VoidCallback onOpen;
  final DateTime? now;
  final double height;
  final bool showGroups;
  // A count, its caption and a row of faces — no taller than that needs.
  static const groupHeight = 86.0;

  @override
  Widget build(BuildContext context) {
    final checked = week.members
        .where((m) => week.checkedToday(m.id).isNotEmpty)
        .toList();
    final pending = week.members
        .where((m) => week.checkedToday(m.id).isEmpty)
        .toList();
    return SizedBox(
      key: const ValueKey('crew-board'),
      height: height,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, space) {
                if (!showGroups) return const SizedBox.shrink();
                if (checked.isEmpty || pending.isEmpty) {
                  final allCheckedIn = checked.isNotEmpty;
                  return SizedBox(
                    key: ValueKey(
                      allCheckedIn ? 'checked-tile' : 'pending-tile',
                    ),
                    width: double.infinity,
                    child: CrewCheckInTile(
                      userId: userId,
                      onOpen: onOpen,
                      members: allCheckedIn ? checked : pending,
                      done: allCheckedIn,
                      awaitingFirstCheckIn: !allCheckedIn,
                      everyoneCheckedIn: allCheckedIn,
                    ),
                  );
                }
                final available = math.max(0.0, space.maxWidth);
                final total = checked.length + pending.length;
                final minimum = math.min(140.0, available / 2);
                final fraction = total == 0 ? .5 : checked.length / total;
                final targetWidth = (available * fraction).clamp(
                  minimum,
                  available - minimum,
                );
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: targetWidth, end: targetWidth),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, width, _) {
                    final checkedWidth = width.clamp(
                      minimum,
                      available - minimum,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          key: const ValueKey('checked-tile'),
                          width: checkedWidth,
                          child: CrewCheckInTile(
                            userId: userId,
                            onOpen: onOpen,
                            members: checked,
                            done: true,
                          ),
                        ),
                        SizedBox(
                          key: const ValueKey('pending-tile'),
                          width: available - checkedWidth,
                          child: CrewCheckInTile(
                            userId: userId,
                            onOpen: onOpen,
                            members: pending,
                            done: false,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CrewCheckInTile extends StatelessWidget {
  const CrewCheckInTile({
    super.key,
    required this.members,
    required this.done,
    required this.userId,
    required this.onOpen,
    this.awaitingFirstCheckIn = false,
    this.everyoneCheckedIn = false,
    this.expansion = 0,
    this.showDetails = false,
    this.expandedHeight = TodayCrewCard.groupHeight,
    this.backend,
    this.crewId,
  });
  final List<WeekMember> members;
  final bool done;
  final bool awaitingFirstCheckIn;
  final bool everyoneCheckedIn;
  final String userId;
  final VoidCallback onOpen;
  final double expansion;
  final bool showDetails;
  final double expandedHeight;
  final HomeBackend? backend;
  final String? crewId;

  /// The tile's raised edge, shared by its surface and its outline. The faces
  /// do not take it: they read as a flat stack, the way the crew roster's do,
  /// and the ring alone separates them.
  static Color _tileEdge(bool done) =>
      done ? WeekPactColors.mintEdge : WeekPactColors.pendingEdge;

  /// The tile's own fill, painted as a ring around each overlapping face. It
  /// disappears against the tile and shows only where one face crosses the
  /// next, which is the one place the stack needs a gap to be read as people
  /// rather than as a single smear.
  static Color _tileFill(bool done) =>
      done ? WeekPactColors.mintGreen : WeekPactColors.pendingCheckIns;

  /// The knockout between two overlapping faces.
  static const _faceRing = 2.0;

  /// The bore of the tap hint punched through each tile.
  static const _holeSize = 6.0;

  /// Beyond this the stack stops being faces and becomes a number.
  static const _maxFaces = 3;
  static const _faceSize = 34.0;
  static const _minFaceSize = 24.0;
  static const _overlap = .62;

  /// The words under the count.
  String get caption => everyoneCheckedIn
      ? 'whole crew is in'
      : awaitingFirstCheckIn
      ? 'be the first in today'
      : done
      ? 'checked in'
      : 'not yet';

  /// The tile's own words. When one side is empty the tile speaks for the whole
  /// crew, so a bare count would read as a scoreline nobody asked for.
  String get label => everyoneCheckedIn
      ? 'Whole crew is in'
      : awaitingFirstCheckIn
      ? 'Be the first in today'
      : '${done ? 'Checked in' : 'Not yet'} · ${members.length}';
  String get title => everyoneCheckedIn
      ? 'Whole crew is in today'
      : awaitingFirstCheckIn
      ? 'Nobody has checked in today · ${members.length} to go'
      : '${done ? 'Checked in today' : 'Not yet today'} · ${members.length}';

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: title,
    button: true,
    expanded: showDetails,
    onTap: onOpen,
    hint: showDetails ? 'Collapse members' : 'Show all members',
    child: MouseRegion(
      cursor: showDetails ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: showDetails ? null : onOpen,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: WeekPactMetrics.pactCardShape,
            shadows: [
              BoxShadow(
                color: _tileEdge(done),
                offset: WeekPactMetrics.raisedOffset,
              ),
            ],
          ),
          child: HomeSurface(
            tint: done
                ? WeekPactColors.mintGreen
                : WeekPactColors.pendingCheckIns,
            radius: WeekPactMetrics.cardCorner,
            shape: WeekPactMetrics.pactCardShape,
            outlined: true,
            outlineColor: _tileEdge(done),
            child: Stack(
              children: [
                // A tap hint, floating over the tile's own content so the
                // count and the faces keep the space they had. Each tile takes
                // the corner it shares with the other, so the pair reads as
                // one control with its handles meeting in the middle.
                if (!showDetails)
                  Positioned(
                    right: done ? 8 : null,
                    left: done ? null : 8,
                    bottom: 7,
                    child: Opacity(
                      opacity: (1 - expansion).clamp(0.0, 1.0),
                      child: _tapHole(context),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDetails)
                      SizedBox(
                        height: 36,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontFamily: WeekPactType.secondary,
                                        fontFamilyFallback:
                                            WeekPactType.secondaryFallback,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: showDetails
                          ? ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: expandedHeight - 36,
                                maxHeight: expandedHeight - 36,
                                child: Opacity(
                                  opacity: expansion,
                                  child: _memberList(context),
                                ),
                              ),
                            )
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onOpen,
                              child: _collapsed(context),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// The tap hint, drawn as a hole bored through the tile: the crew week
  /// surface the tiles sit in shows through the bore, the tile's own material
  /// darkens its top wall, and a lit rim sits under its bottom lip — the
  /// inverse of the raised edge every other surface carries, so the light
  /// still comes from above.
  Widget _tapHole(BuildContext context) {
    final bore = CrewHeaderSurface.faceColor(context);
    return SizedBox.square(
      dimension: _holeSize,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const CircleBorder(),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(bore, Colors.black, .45)!, bore],
            stops: const [0, .7],
          ),
          shadows: [
            BoxShadow(
              color: Color.lerp(_tileFill(done), Colors.white, .6)!,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  /// Collapsed, the tile leads with the count and lets faces fill the rest.
  /// Nobody on this side means the count would be a zero nobody asked for, so
  /// the state's own words take the whole tile instead.
  Widget _collapsed(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    child: members.isEmpty
        ? Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                done ? 'No one yet' : 'All checked in',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WeekPactColors.mutedLight,
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 12,
                ),
              ),
            ),
          )
        : Row(
            key: ValueKey(done ? 'checked-members' : 'pending-members'),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                // Scale the count and its caption together, so a large text
                // setting shrinks the block instead of overflowing the tile.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${members.length}',
                        key: ValueKey(done ? 'checked-count' : 'pending-count'),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: const TextStyle(
                          color: _ink,
                          fontFamily: WeekPactType.secondary,
                          fontFamilyFallback: WeekPactType.secondaryFallback,
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _faces(context)),
            ],
          ),
  );

  /// Overlapping faces, as many as the tile can hold, with the remainder as a
  /// “+n” chip. Past that the chip stands alone — the expanded list is where
  /// a big crew is actually read.
  Widget _faces(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      if (space.maxWidth < 24 || space.maxHeight < 20) {
        return const SizedBox.shrink();
      }
      // Faces overlap, so each extra one costs well under its own width. Fit as
      // many slots as the tile allows, shrinking the faces before dropping one,
      // and never below a size that still reads as a person.
      final maxSize = math.min(_faceSize, space.maxHeight);
      var slots = math.min(_maxFaces, members.length);
      var size = maxSize;
      while (slots > 0) {
        size = math.min(maxSize, space.maxWidth / (1 + (slots - 1) * _overlap));
        if (size >= _minFaceSize) break;
        slots--;
      }
      // Too narrow for a face: the count chip carries the whole crew.
      if (slots == 0) {
        if (space.maxWidth < 20) return const SizedBox.shrink();
        slots = 1;
        size = math.min(maxSize, space.maxWidth);
      }
      final shown = members.length <= slots ? members.length : slots - 1;
      final overflow = members.length - shown;
      slots = shown + (overflow > 0 ? 1 : 0);
      final step = size * _overlap;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: size + (slots - 1) * step,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < shown; i++)
                Positioned(
                  key: ValueKey('crew-member-${members[i].id}'),
                  left: i * step,
                  child: _avatar(context, members[i], done, size),
                ),
              if (overflow > 0)
                Positioned(
                  left: shown * step,
                  child: Tooltip(
                    message: shown == 0
                        ? 'View all ${members.length} members'
                        : 'View $overflow more members',
                    child: Container(
                      key: const ValueKey('crew-overflow'),
                      width: size,
                      height: size,
                      padding: const EdgeInsets.all(_faceRing),
                      decoration: ShapeDecoration(
                        color: _tileFill(done),
                        shape: const AvatarShape(),
                      ),
                      child: DecoratedBox(
                        decoration: const ShapeDecoration(
                          color: WeekPactColors.cream,
                          shape: AvatarShape(),
                        ),
                        child: Center(
                          child: FittedBox(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                '+$overflow',
                                style: const TextStyle(
                                  color: _ink,
                                  fontFamily: WeekPactType.secondary,
                                  fontFamilyFallback:
                                      WeekPactType.secondaryFallback,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _memberList(BuildContext context) => CrewMemberList(
    members: members,
    done: done,
    userId: userId,
    backend: backend,
    crewId: crewId,
  );

  Widget _avatar(
    BuildContext context,
    WeekMember member,
    bool done,
    double size,
  ) {
    final ink = _ink;
    final fallback = Center(
      child: Text(
        member.initials,
        style: TextStyle(
          color: ink,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Tooltip(
      message:
          '${member.displayName.isEmpty ? 'Crew member' : member.displayName}${member.id == userId ? ' (you)' : ''}: ${done ? 'Checked in' : 'Not yet'}',
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: ValueKey('crew-avatar-${member.id}'),
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      padding: const EdgeInsets.all(_faceRing),
                      decoration: ShapeDecoration(
                        shape: const AvatarShape(),
                        color: _tileFill(done),
                      ),
                      child: DecoratedBox(
                        decoration: const ShapeDecoration(
                          shape: AvatarShape(),
                          color: homePaper,
                        ),
                        child: AvatarClip(
                          child: member.avatarUrl == null
                              ? fallback
                              : Image.network(
                                  member.avatarUrl!,
                                  gaplessPlayback: true,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => fallback,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TodaySkeleton extends StatefulWidget {
  const TodaySkeleton({super.key, this.selector});

  /// The live crew switcher, where Home already has one. It rides the loading
  /// page rather than being drawn as bars, so switching crews neither cuts the
  /// hand's flight short nor moves the control it was pulled from. Null before
  /// the crews are in, which the skeleton draws as its own slot.
  final Widget? selector;
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
              SizedBox(
                height: HomeHeader.headingHeight,
                child: Row(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _line(104, 28),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 108,
                      child: CrewHeaderSurface(
                        child: Center(child: _line(64, 20)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HomeHeader.gap),
              // The switcher's own slot, at the height the heading gives it,
              // so nothing under it moves once the crews arrive.
              SizedBox(
                height: HomeHeader.selectorHeight,
                child:
                    widget.selector ??
                    const CrewHeaderSurface(
                      key: ValueKey('skeleton-crew-switcher'),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBar(width: 62, height: 8),
                            SizedBox(height: 8),
                            SkeletonBar(width: 145, height: 20),
                          ],
                        ),
                      ),
                    ),
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
