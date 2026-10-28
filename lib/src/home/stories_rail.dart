import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';
import 'home_backend.dart';
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
/// Checking in belongs to the pact card below, photo and all, so the rail
/// never posts a check-in. What it does post is a photo outside any pact — an
/// achievement, or a plain story — which has no card to be made on. Your own
/// tile carries the "+" for it; a member who has posted an achievement wears
/// a trophy on theirs.
class StoriesRail extends StatelessWidget {
  const StoriesRail({
    super.key,
    required this.days,
    this.onOpen,
    this.onNudge,
    this.onProfile,
    this.onCompose,
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
  ///
  /// A dashed tile answers a long press with this, and a plain tap too when
  /// there is no [onProfile] to open instead.
  final void Function(MemberDay day)? onNudge;

  /// Opens the profile of a crewmate who is not in yet: a dashed tile's plain
  /// tap. The profile carries the nudge, beside what they have kept before,
  /// so a tap is a look at the person rather than a poke straight away.
  final void Function(MemberDay day)? onProfile;

  /// Starts a post — an achievement or a plain story. Reached from your own
  /// tile only: its "+", a long press, and a plain tap while you have nothing
  /// to open yet.
  final VoidCallback? onCompose;

  /// How far past the page's own padding the rail runs, so tiles leave the
  /// screen at its edge rather than at the page's margin.
  final double bleed;

  /// The gap from a face to its name, and the name's own line.
  static const _gap = 6.0;
  static const _labelHeight = 15.0;

  /// The space between two tiles.
  static const spacing = 8.0;

  /// How many faces a screen shows: four whole, and a sliver of a fifth, so
  /// the rail plainly runs on past the edge rather than looking like the
  /// whole crew.
  static const _visibleTiles = 4.3;

  /// The face for a rail [width] wide that runs [bleed] past it on each side.
  /// The first face starts at the page's margin and the rail leaves at the
  /// screen's edge, so that is the span the faces share. Held between a face
  /// still worth reading and one that would crowd a tablet.
  static double tileSizeFor(double width, {double bleed = 0}) =>
      ((width + bleed - _visibleTiles.floor() * spacing) / _visibleTiles).clamp(
        56.0,
        120.0,
      );

  /// The rail's height at [width]: a face and the name under it.
  static double heightFor(double width, {double bleed = 0}) =>
      tileSizeFor(width, bleed: bleed) + _gap + _labelHeight;

  /// The ring a member who is in wears, and the space it holds off the face.
  static const _ring = 3.0;
  static const _inset = 3.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final tile = tileSizeFor(space.maxWidth, bleed: bleed);
      return SizedBox(
        key: const ValueKey('home-stories'),
        height: tile + _gap + _labelHeight,
        child: OverflowBox(
          minWidth: space.maxWidth + bleed * 2,
          maxWidth: space.maxWidth + bleed * 2,
          child: _rail(tile),
        ),
      );
    },
  );

  Widget _rail(double tile) => ListView.separated(
    key: const ValueKey('stories-rail'),
    scrollDirection: Axis.horizontal,
    padding: EdgeInsets.symmetric(horizontal: bleed),
    itemCount: days.length,
    separatorBuilder: (_, _) => const SizedBox(width: spacing),
    itemBuilder: (context, index) => _StoryTile(
      key: ValueKey('story-tile-${days[index].member.id}'),
      day: days[index],
      size: tile,
      onOpen: days[index].isIn && onOpen != null
          ? () => onOpen!(days[index])
          : null,
      onNudge: !days[index].isIn && !days[index].isViewer && onNudge != null
          ? () => onNudge!(days[index])
          : null,
      onProfile: !days[index].isIn && !days[index].isViewer && onProfile != null
          ? () => onProfile!(days[index])
          : null,
      onCompose: days[index].isViewer ? onCompose : null,
    ),
  );
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    super.key,
    required this.day,
    required this.size,
    this.onOpen,
    this.onNudge,
    this.onProfile,
    this.onCompose,
  });

  final MemberDay day;

  /// The face's side. See [StoriesRail.tileSizeFor].
  final double size;
  final VoidCallback? onOpen;
  final VoidCallback? onNudge;
  final VoidCallback? onProfile;
  final VoidCallback? onCompose;

  /// The corner marks: a trophy for an achievement today, a "+" for posting
  /// one. Small enough to sit inside the tile's corner without covering the
  /// face.
  static const _pip = 24.0;

  /// The name under the face. Your own tile says so rather than repeating a
  /// name you know, which is also the only label in the rail that never
  /// changes position.
  ///
  /// Everyone else goes by their first name, as they do in the crew roster: a
  /// tile is under a hundred points wide and a crew is on first-name terms. The whole name stays
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
    final kept = day.stories
        .map(
          (s) => switch (s) {
            PactStory(:final pact) => pact.title,
            AchievementStory(kind: PostKind.achievement) => 'an achievement',
            AchievementStory() => 'a story',
          },
        )
        .toSet()
        .join(', ');
    return day.seen ? '$name, $kept, seen' : '$name, $kept, new';
  }

  @override
  Widget build(BuildContext context) {
    final face = SizedBox.square(
      dimension: size,
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
              child: _Face(day: day, size: size),
            )
          : Container(
              padding: const EdgeInsets.all(StoriesRail._inset),
              decoration: const ShapeDecoration(shape: _DashedAvatarShape()),
              child: Opacity(
                opacity: .55,
                child: _Face(day: day, size: size),
              ),
            ),
    );
    final tap = onOpen ?? onProfile ?? onNudge ?? onCompose;
    final press = onNudge ?? onCompose;
    final pressHint = onNudge != null
        ? 'Nudge them'
        : onCompose != null
        ? 'Post a story'
        : null;
    return Semantics(
      button: tap != null,
      label: _semantics,
      onTap: tap,
      // Neither gesture has a glyph a screen reader can find, so this is the
      // only place either is announced.
      onTapHint: onProfile != null
          ? 'Open their profile'
          : onOpen == null
          ? pressHint
          : null,
      onLongPressHint: pressHint,
      onLongPress: press,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: day.isViewer ? 'You' : _fullName,
              child: InkWell(
                // A dashed tile has no story, so its plain tap opens the
                // crewmate's profile, where the nudge stands beside what they
                // have kept. The press stays the quick nudge; the tile itself
                // carries no nudge mark and should not — a rail of dashed
                // squares each wearing a button would read as a page about
                // who is behind.
                onTap: tap,
                onLongPress: press == null
                    ? null
                    : () {
                        unawaited(
                          HapticFeedback.mediumImpact().catchError(
                            (Object _) {},
                          ),
                        );
                        press();
                      },
                customBorder: const AvatarShape(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    face,
                    if (day.hasAchievement)
                      const Positioned(
                        top: 0,
                        right: 0,
                        child: _Pip(
                          key: ValueKey('story-tile-achievement'),
                          icon: achievementIcon,
                          size: _pip,
                          color: WeekPactColors.achievementBadge,
                        ),
                      ),
                    if (onCompose != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          key: const ValueKey('story-tile-compose'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onCompose,
                          child: const _Pip(
                            icon: HugeIconsStrokeRounded.add01,
                            size: _pip,
                            color: WeekPactColors.cream,
                          ),
                        ),
                      ),
                  ],
                ),
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
                  fontSize: 12,
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

/// A small round mark in a tile's corner, ringed in the canvas so it reads as
/// set on the tile rather than cut into it.
class _Pip extends StatelessWidget {
  const _Pip({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  final List<List<dynamic>> icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: context.canvas, width: 2),
    ),
    child: Center(
      child: HugeIcon(
        icon: icon,
        color: WeekPactColors.black,
        size: size - 8,
        strokeWidth: 2.2,
      ),
    ),
  );
}

class _Face extends StatelessWidget {
  const _Face({required this.day, required this.size});

  final MemberDay day;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      day.member.initials,
      style: TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: size * .29,
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
                  width: size,
                  height: size,
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
