import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';
import 'home_surface.dart';
import 'stories.dart';

/// The crew's day, along the top of Home: one squircle a member, ringed in the
/// colour of the pact they kept.
///
/// It stands where the page's name and the streak used to. A title told you
/// which page you were on, which the navigation bar under your thumb already
/// says; this says who has been out today, which is the reason to open the app
/// at all.
///
/// The rail does not post. Checking in belongs to the pact card below, photo
/// and all, so there is no "+" here — a tile only ever opens what is already
/// there, and your own tile stays dark until you have kept something.
class StoriesRail extends StatelessWidget {
  const StoriesRail({
    super.key,
    required this.days,
    this.onOpen,
    this.onNudge,
    this.bleed = 0,
  });

  /// The crew, in rail order. See [MemberDay.read].
  final List<MemberDay> days;

  /// Opens a member's stories. Never called for a member who is not in yet:
  /// their tile has nothing behind it, and a tap that opens nothing is worse
  /// than a tile that plainly does not take one.
  final void Function(MemberDay day)? onOpen;

  /// Offers a nudge for a member who is not in yet. Only a dashed tile takes
  /// it: a member who is in has a story, so the tap is already spoken for,
  /// and a member who is not is the tile the thought is about. Never called
  /// for the viewer — you cannot nudge yourself out of bed.
  final void Function(MemberDay day)? onNudge;

  /// How far past the page's own padding the rail runs, so tiles leave the
  /// screen at its edge rather than at the page's margin.
  final double bleed;

  /// The tile, and the two lines under it. Sized so the rail costs Home about
  /// what the heading did: a name a member is known by, over a face big enough
  /// to be one.
  static const tileSize = 56.0;
  static const _gap = 5.0;
  static const _labelHeight = 13.0;
  static const height = tileSize + _gap + _labelHeight;

  /// The ring a member who is in wears, and the space it holds off the face.
  static const _ring = 2.5;
  static const _inset = 2.0;

  @override
  Widget build(BuildContext context) {
    final rail = ListView.separated(
      key: const ValueKey('stories-rail'),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: bleed),
      itemCount: days.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) => _StoryTile(
        key: ValueKey('story-tile-${days[index].member.id}'),
        day: days[index],
        onOpen: days[index].isIn && onOpen != null
            ? () => onOpen!(days[index])
            : null,
        onNudge: !days[index].isIn && !days[index].isViewer && onNudge != null
            ? () => onNudge!(days[index])
            : null,
      ),
    );
    return SizedBox(
      key: const ValueKey('home-stories'),
      height: height,
      child: bleed == 0
          ? rail
          : LayoutBuilder(
              builder: (context, space) => OverflowBox(
                minWidth: space.maxWidth + bleed * 2,
                maxWidth: space.maxWidth + bleed * 2,
                child: rail,
              ),
            ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({super.key, required this.day, this.onOpen, this.onNudge});

  final MemberDay day;
  final VoidCallback? onOpen;
  final VoidCallback? onNudge;

  /// The name under the face. Your own tile says so rather than repeating a
  /// name you know, which is also the only label in the rail that never
  /// changes position.
  ///
  /// Everyone else goes by their first name, as they do in the crew roster: a
  /// tile is 56pt wide and a crew is on first-name terms. The whole name stays
  /// in the tooltip and in what a screen reader reads.
  String get _label {
    if (day.isViewer) return 'You';
    final full = day.member.displayName.trim();
    return full.isEmpty ? 'Crew member' : full.split(RegExp(r'\s+')).first;
  }

  String get _fullName {
    final full = day.member.displayName.trim();
    return full.isEmpty ? 'Crew member' : full;
  }

  /// What a screen reader is told. The ring's colour and the dashes carry this
  /// for everyone else, and neither survives being read aloud.
  String get _semantics {
    final name = day.isViewer ? 'You' : _fullName;
    if (!day.isIn) return '$name, not in yet';
    final pacts = day.stories.map((s) => s.pact.title).toSet().join(', ');
    return day.seen ? '$name, $pacts, seen' : '$name, $pacts, new';
  }

  @override
  Widget build(BuildContext context) {
    final face = SizedBox.square(
      dimension: StoriesRail.tileSize,
      child: day.isIn
          ? Container(
              padding: const EdgeInsets.all(StoriesRail._inset),
              decoration: ShapeDecoration(
                shape: AvatarShape(
                  side: BorderSide(
                    // Unseen wears the pact's own badge colour, so the rail
                    // says what was kept before it is opened; seen falls back
                    // to the palette's plain grey, which is the same absence
                    // of colour a check-in not yet made is drawn in.
                    color: day.seen
                        ? WeekPactColors.pendingCheckIns
                        : day.stories.last.badge,
                    width: StoriesRail._ring,
                  ),
                ),
              ),
              child: _Face(day: day),
            )
          : Container(
              padding: const EdgeInsets.all(StoriesRail._inset),
              decoration: const ShapeDecoration(shape: _DashedAvatarShape()),
              child: Opacity(opacity: .55, child: _Face(day: day)),
            ),
    );
    return Semantics(
      button: onOpen != null,
      label: _semantics,
      // The press has no glyph, so this is the only place it is announced.
      onLongPressHint: onNudge == null ? null : 'Nudge them',
      onLongPress: onNudge,
      excludeSemantics: true,
      child: SizedBox(
        width: StoriesRail.tileSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: day.isViewer ? 'You' : _fullName,
              child: InkWell(
                onTap: onOpen,
                // A press, not a tap: the tile carries no nudge mark and
                // should not: a rail of dashed squares each wearing a button
                // would read as a page about who is behind. The press is
                // found the way a press is always found, and the roster
                // behind the crew strip's pull still lists every nudge for
                // anyone who never finds it.
                onLongPress: onNudge == null
                    ? null
                    : () {
                        unawaited(
                          HapticFeedback.mediumImpact().catchError(
                            (Object _) {},
                          ),
                        );
                        onNudge!();
                      },
                customBorder: const AvatarShape(),
                child: face,
              ),
            ),
            const SizedBox(height: StoriesRail._gap),
            SizedBox(
              height: StoriesRail._labelHeight,
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: day.isViewer ? FontWeight.w600 : FontWeight.w400,
                  // Canvas ink, not card ink: the label sits on the page
                  // itself, which is dark in the dark theme, so the pale
                  // card's near-black would be a name nobody can read.
                  color: day.isIn ? context.ink : context.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.day});

  final MemberDay day;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      day.member.initials,
      style: TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: homeInk,
      ),
    );
    final url = day.member.avatarUrl;
    return AvatarClip(
      child: ColoredBox(
        // The face sits on paper whether or not it carries a photo, so the
        // ring is the only thing between the two states.
        color: WeekPactColors.cream,
        child: Center(
          child: url == null
              ? initials
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: StoriesRail.tileSize,
                  height: StoriesRail.tileSize,
                  errorBuilder: (_, _, _) => Center(child: initials),
                ),
        ),
      ),
    );
  }
}

/// The outline a member who has not checked in wears: the story ring's own
/// shape, drawn as dashes.
///
/// A solid ring in grey still reads as a ring, and the rail's whole job is to
/// separate who is in from who is not at a glance. Dashes read as a seat
/// waiting rather than as a quieter version of a seat taken.
class _DashedAvatarShape extends ShapeBorder {
  const _DashedAvatarShape({
    this.color = WeekPactColors.pendingEdge,
    this.width = 1.5,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final double width;
  final double dash;
  final double gap;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      const AvatarShape().getOuterPath(rect, textDirection: textDirection);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      const AvatarShape().getOuterPath(
        rect.deflate(width),
        textDirection: textDirection,
      );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty) return;
    final outline = const AvatarShape().getOuterPath(rect.deflate(width / 2));
    final brush = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final metric in outline.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = start + dash < metric.length ? start + dash : metric.length;
        canvas.drawPath(metric.extractPath(start, end), brush);
        start = end + gap;
      }
    }
  }

  @override
  ShapeBorder scale(double t) => _DashedAvatarShape(
    color: color,
    width: width * t,
    dash: dash * t,
    gap: gap * t,
  );
}
