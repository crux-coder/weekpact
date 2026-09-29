import 'crew_pact_week_card.dart' show crewDateLabel;
import '../home/home_surface.dart';
import '../widgets/page_frame.dart';
import '../widgets/avatar_shape.dart';

import 'package:hugeicons/styles/stroke_rounded.dart';

import '../widgets/app_icon.dart';

import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import 'crew_backend.dart';

/// The track every crew row is drawn as: the same squircle, outline and raised
/// edge a pact bar uses, so the two lists read as one family.
class CrewBand extends StatelessWidget {
  const CrewBand({
    super.key,
    required this.builder,
    this.fillColor,
    this.resolveTone = true,
  });

  /// Built inside the surface, so `context.ink` and `context.muted` resolve
  /// against the pale card rather than the page's canvas theme.
  final WidgetBuilder builder;
  final Color? fillColor;
  final bool resolveTone;

  @override
  Widget build(BuildContext context) => AppSurface(
    fillColor: fillColor,
    resolveTone: resolveTone,
    borderRadius: WeekPactMetrics.cardCorner,
    builder: (context) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: builder(context),
    ),
  );
}

/// The crew as a stack of name bands: one pill per person, read top to bottom,
/// rather than a grid of square portraits.
class CrewRoster extends StatelessWidget {
  const CrewRoster({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, child) in children.indexed) ...[
        if (index > 0) const SizedBox(height: 8),
        child,
      ],
    ],
  );
}

/// A member's photo, or the first letter of their name when there is none.
class CrewFace extends StatelessWidget {
  const CrewFace({super.key, required this.member, this.fontSize = 16});
  final CrewMember member;
  final double fontSize;

  String get _name => member.displayName?.trim().isNotEmpty == true
      ? member.displayName!.trim()
      : 'Crew member';

  Widget _initial(BuildContext context) => ColoredBox(
    color: WeekPactColors.black.withValues(alpha: .10),
    child: Center(
      child: Text(
        _name == 'Crew member' ? '?' : _name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: WeekPactColors.black,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AvatarClip(
    child: member.avatarUrl?.trim().isNotEmpty != true
        ? _initial(context)
        : Image.network(
            member.avatarUrl!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null ? child : _initial(context),
            errorBuilder: (context, error, stack) => _initial(context),
          ),
  );
}

class CrewPersonBand extends StatelessWidget {
  const CrewPersonBand({
    super.key,
    required this.member,
    required this.isCurrentUser,
    required this.color,
    this.onRemove,
  });
  final CrewMember member;
  final bool isCurrentUser;
  final Color color;
  final VoidCallback? onRemove;

  String get _name => member.displayName?.trim().isNotEmpty == true
      ? member.displayName!.trim()
      : 'Crew member';

  String get _role => member.isOwner ? 'OWNER' : 'MEMBER';

  /// Your own band says so in words as well as in colour.
  ///
  /// The tint marked *you* and the label said `OWNER`, and on the crew you
  /// started those land on the same row — so the two read as one fact, and on
  /// a crew you did not start they are different rows with nothing saying
  /// which is which. Naming the tint settles it.
  String get _standing => isCurrentUser ? 'YOU · $_role' : _role;

  Widget _roleLabel(BuildContext context) => Text(
    _standing,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    // Colour alone marked your own band, which a screen reader cannot read.
    semanticsLabel: isCurrentUser ? 'You, ${_role.toLowerCase()}' : _role,
    style: TextStyle(
      color: context.muted,
      fontSize: 11,
      letterSpacing: .8,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Past a large text scale the name and the role cannot share a line
    // without one of them losing most of its characters, so the role drops
    // under the name instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return CrewBand(
      fillColor: color,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            SizedBox.square(dimension: 40, child: CrewFace(member: member)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: _name,
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (stacked) _roleLabel(context),
                ],
              ),
            ),
            if (!stacked) ...[const SizedBox(width: 10), _roleLabel(context)],
            // The slot and its gap are held whether or not the row has a
            // button, so every role label lines up down the roster and none of
            // them runs under the button.
            const SizedBox(width: 12),
            SizedBox.square(
              dimension: _bandSlot,
              child: onRemove == null
                  ? null
                  // A person-minus glyph: the one control on the band says
                  // what it does, where three dots said only that something
                  // was hidden behind them.
                  : BandGlyph(
                      icon: HugeIconsStrokeRounded.userMinus01,
                      face: context.ink,
                      glyph: color,
                      tooltip: 'Remove $_name',
                      onPressed: onRemove,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one band that is not a person: ink-filled, so adding someone reads as
/// the end of the stack rather than another member of it.
class CrewInviteBand extends StatelessWidget {
  const CrewInviteBand({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => CrewBand(
    fillColor: WeekPactColors.black,
    resolveTone: false,
    builder: (context) => InkWell(
      onTap: onPressed,
      child: Padding(
        // The same right edge a person band keeps, so the plus lands in the
        // column the remove buttons stand in rather than opposite them.
        padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'INVITE SOMEONE',
                style: TextStyle(
                  color: WeekPactColors.cream,
                  fontSize: 17,
                  letterSpacing: .4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // The band itself is the button, so the glyph is only its face.
            const SizedBox.square(
              dimension: _bandSlot,
              child: BandGlyph(
                icon: HugeIconsStrokeRounded.add01,
                face: WeekPactColors.cream,
                glyph: WeekPactColors.black,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The square at the end of a band. Every one is the same size on the same
/// squircle, so a remove and an invite read as one control repeated down the
/// roster rather than two shapes that happen to sit in the same corner.
const _bandSlot = 36.0;

class BandGlyph extends StatelessWidget {
  const BandGlyph({
    super.key,
    required this.icon,
    required this.face,
    required this.glyph,
    this.tooltip,
    this.onPressed,
  });

  final List<List<dynamic>> icon;

  /// The square's fill, and the colour its outline and raised edge are mixed
  /// from — not the band's, so the control sits on the band rather than in it.
  final Color face;
  final Color glyph;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final mark = Center(
      child: AppIcon(icon: icon, color: glyph, size: 20),
    );
    final square = AppSurface(
      fillColor: face,
      resolveTone: false,
      // The panel curve, not `buttonShape`. That one caps its corner at half
      // the shortest side, which a wide button never reaches but a 36pt square
      // hits immediately: it came out at a continuous 18, and a continuous
      // radius reads at roughly `cardCorner / cardCurve` of its number, so the
      // square wore a corner of about 8 while the 56pt band around it wore 18.
      // `panelCurve` is the value the system already keeps for a small tile
      // stepping down from a card, and it lands the two in proportion.
      shape: const ContinuousRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(WeekPactMetrics.panelCurve),
        ),
      ),
      builder: (_) =>
          onPressed == null ? mark : InkWell(onTap: onPressed, child: mark),
    );
    return tooltip == null ? square : Tooltip(message: tooltip!, child: square);
  }
}

/// The crew itself, above the people in it: when it started and where its week
/// is cut, then the three figures that say how it is going.
///
/// It stands where a caption used to — a stack of the crew's own faces beside
/// `HANGBOARDASI · 3 PEOPLE`, under a header already reading *Hangboardasi*,
/// over a list of the very faces the stack was showing. Two things said twice
/// and nothing said once. The page knew all three of these figures already:
/// [CrewPage] fetches the week for member profiles and was throwing the rest of
/// it away.
class CrewSummaryCard extends StatelessWidget {
  const CrewSummaryCard({
    super.key,
    required this.people,
    this.startedAt,
    this.pacts,
    this.streakWeeks,
    this.weekFailed = false,
    this.onRetry,
    this.now,
  });

  /// The loading state: the card at its own height with its figures not yet
  /// filled in, so the roster under it does not move when they arrive.
  const CrewSummaryCard.loading({super.key})
    : people = null,
      startedAt = null,
      pacts = null,
      streakWeeks = null,
      weekFailed = false,
      onRetry = null,
      now = null;

  /// How many are in the crew. This one the page has from the roster itself.
  ///
  /// It is also how the card knows whether it is loading: a crew always has at
  /// least the person reading the page in it, so a null here is an answer that
  /// has not arrived rather than a crew of nobody.
  final int? people;

  /// When the crew was started. The card carried the crew's timezone beside
  /// this and no longer does: a zone nobody picks, on a page nobody administers
  /// it from, is a fact with nothing to do — and `Europe/Sarajevo` in small
  /// caps took more of the line than everything else on it put together.
  final DateTime? startedAt;

  /// The week's own figures, which arrive with the member profiles. Null while
  /// they are still coming, or where the page was given no week backend to ask.
  final int? pacts;
  final int? streakWeeks;

  /// Whether the week was asked for and did not come.
  ///
  /// Distinct from the figures simply being null, and it has to be: a bar that
  /// never fills is a card that says "any moment now" for as long as the page
  /// is open, and the crew page's own error sits below the roster where nobody
  /// reading these two figures is looking. Failed, the figures are a dash and
  /// the card says so with the door back in it.
  final bool weekFailed;
  final VoidCallback? onRetry;

  /// Today, for deciding whether the start date needs its year. Passed in so a
  /// test can stand in a different year without moving the clock.
  final DateTime? now;

  /// The card's height with type at its ordinary size, held whether the
  /// figures have landed or not so the roster does not move when they do.
  ///
  /// A floor rather than a fixture: at a large text scale the caption and the
  /// three figures need more than this, and the crew page scrolls — so the
  /// card grows there instead of clipping its own labels. Home's cards cannot
  /// do that, which is why they scale their content into a fixed slot; this
  /// one has somewhere to grow into.
  static const height = 92.0;

  /// The line the date stands on, held whether it has one or not.
  static const _captionHeight = 14.0;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: height),
    child: AppSurface(
      key: const ValueKey('crew-summary-card'),
      fillColor: WeekPactColors.stone,
      resolveTone: false,
      borderRadius: WeekPactMetrics.cardCorner,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          // Sized by what it holds, with the floor above doing the rest. Given
          // the room instead — `spaceBetween` on a column free to grow — the
          // card took every point its parent would offer, which in a scrolling
          // page is all of them.
          mainAxisSize: MainAxisSize.min,
          children: [
            _caption(context),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _figure(
                  context,
                  people?.toString(),
                  people == 1 ? 'PERSON' : 'PEOPLE',
                ),
                _figure(
                  context,
                  _weekFigure(pacts),
                  pacts == 1 ? 'PACT' : 'PACTS',
                ),
                // The label names the measure rather than agreeing with the
                // count, so a crew that has not got a streak going reads as
                // `0 · WEEK STREAK` rather than `0 · WEEKS RUNNING`, which
                // says a thing is running that is not. The flame elsewhere in
                // the app is spent only while a streak is up; a figure in a
                // row of figures is different, and a nought here is where the
                // crew actually stands.
                _figure(context, _weekFigure(streakWeeks), 'WEEK STREAK'),
              ],
            ),
            if (weekFailed) _retryLine(context),
          ],
        ),
      ),
    ),
  );

  /// When the crew began.
  ///
  /// Three states, not two. Still loading, and it is a bar. Loaded with a
  /// date, and it is the date. Loaded without one — a crew made before the
  /// column was read, or a fixture that never set it — and the line is left
  /// empty rather than stood in for, because `SINCE —` is worse than not
  /// mentioning when the crew started. The slot keeps its height through all
  /// three, so the figures under it do not move.
  Widget _caption(BuildContext context) {
    final started = startedAt;
    final loading = people == null;
    return SizedBox(
      height: _captionHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: loading
            ? const SkeletonBar(width: 132, height: 11, color: _summaryGhost)
            : started == null
            ? const SizedBox.shrink()
            : Text(
                'SINCE '
                '${crewDateLabel(started, now: now ?? DateTime.now()).toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: homeMutedInk,
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 11,
                  letterSpacing: .9,
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }

  /// A figure the week was meant to supply: the number, a bar while it is on
  /// its way, and a dash once the asking has failed. A bar left standing there
  /// would keep promising an answer nobody is still fetching.
  String? _weekFigure(int? value) =>
      value?.toString() ?? (weekFailed ? '—' : null);

  /// What the card says when the week did not come, and the way back.
  ///
  /// Short, because the two dashes above it have already said which figures
  /// are missing, and on the card rather than under the roster — this is the
  /// only part of the page that went wrong, and the retry belongs beside it.
  Widget _retryLine(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Text(
          'Couldn’t load',
          style: TextStyle(
            color: homeMutedInk,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: homeInk,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
            ),
          ),
          child: const Text('RETRY'),
        ),
      ],
    ),
  );

  /// One figure and what it counts. A figure still coming is a bar rather than
  /// a zero — nobody has a crew of nobody, and a 0 that turns into a 3 reads
  /// as the crew having grown in the half-second you were looking at it.
  Widget _figure(BuildContext context, String? value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          child: value == null
              ? const Align(
                  alignment: Alignment.bottomLeft,
                  child: SkeletonBar(
                    width: 26,
                    height: 19,
                    radius: 5,
                    color: _summaryGhost,
                  ),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: homeInk,
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: homeMutedInk,
            fontFamily: WeekPactType.secondary,
            fontFamilyFallback: WeekPactType.secondaryFallback,
            fontSize: 10,
            height: 1,
            letterSpacing: .6,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// The card's own skeleton ink, mixed from its fill rather than the canvas.
const _summaryGhost = Color(0x24191B19);
