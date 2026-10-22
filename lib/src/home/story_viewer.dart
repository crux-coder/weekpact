import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import 'clap_control.dart';
import '../pacts/pact_icons.dart';
import '../theme/status_bar_blur.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import '../widgets/avatar_shape.dart';
import '../widgets/pact_icon_badge.dart';
import 'home_backend.dart';
import 'stories.dart';

/// One member's day, full screen, with the rest of the crew behind it.
///
/// Tapping the right of the page moves on and the left goes back, through a
/// member's check-ins and then into the next member's, the way the rail is
/// read. There is no clock: a story here is not a thing that expires while you
/// look at it, and a page that advances itself takes the photo away from
/// whoever is still reading the caption.
class StoryViewer extends StatefulWidget {
  const StoryViewer({
    super.key,
    required this.days,
    required this.viewerId,
    this.initial = 0,
    this.backend,
    this.onSeen,
  });

  /// The crew's day in rail order, members with nothing to show left out.
  final List<MemberDay> days;
  final String viewerId;
  final int initial;

  /// Claps are written through this. Null leaves the clap out, which is what
  /// a preview or a test without a backend gets.
  final HomeBackend? backend;

  /// Called once for each story as it is shown, so the rail's ring can go
  /// grey. Fires on the way in as well as on every move.
  final void Function(Story story)? onSeen;

  /// Completes with true when the viewer took down one of their own
  /// achievements, so the page behind knows its day has changed.
  static Future<bool> open(
    BuildContext context, {
    required List<MemberDay> days,
    required String viewerId,
    int initial = 0,
    HomeBackend? backend,
    void Function(Story story)? onSeen,
  }) async =>
      await Navigator.of(context).push(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) => StoryViewer(
            days: days,
            viewerId: viewerId,
            initial: initial,
            backend: backend,
            onSeen: onSeen,
          ),
        ),
      ) ??
      false;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> {
  late int _member = widget.initial.clamp(0, widget.days.length - 1);
  int _story = 0;

  /// Claps the viewer has given, and the count each check-in carries. Both are
  /// seeded from the week the page was opened with and then kept in step with
  /// whatever the server answers a tap with. They used to start empty, which
  /// made the pill a tally of this session rather than of the crew: a check-in
  /// with five claps read "Clap", and a clap given yesterday looked ungiven.
  final _clapped = <String>{};
  final _counts = <String, int>{};
  bool _clapping = false;

  MemberDay get _day => widget.days[_member];
  Story get _current => _day.stories[_story];

  @override
  void initState() {
    super.initState();
    // Seeded before the first build, so a story opened on a clap the viewer
    // already gave arrives filled rather than popping — see [ClapPop].
    for (final day in widget.days) {
      for (final story in day.stories) {
        _counts[story.id] = story.clapCount;
        if (story.viewerClapped) _clapped.add(story.id);
      }
    }
    widget.onSeen?.call(_current);
  }

  void _move(int step) {
    final story = _story + step;
    if (story >= 0 && story < _day.stories.length) {
      setState(() => _story = story);
    } else {
      final member = _member + (step > 0 ? 1 : -1);
      if (member < 0) return; // The first story stays put rather than closing.
      if (member >= widget.days.length) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _member = member;
        _story = step > 0 ? 0 : widget.days[member].stories.length - 1;
      });
    }
    widget.onSeen?.call(_current);
  }

  Future<void> _clap() async {
    final backend = widget.backend;
    final story = _current;
    if (backend == null || _clapping) return;
    final clapped = !_clapped.contains(story.id);
    final before = _counts[story.id] ?? 0;
    setState(() {
      _clapping = true;
      if (clapped) {
        _clapped.add(story.id);
        _counts[story.id] = before + 1;
      } else {
        _clapped.remove(story.id);
        _counts[story.id] = math.max(0, before - 1);
      }
    });
    try {
      final count = switch (story) {
        PactStory(:final checkIn) => await backend.setClap(
          pactId: checkIn.pactId,
          userId: checkIn.userId,
          day: checkIn.day,
          clapped: clapped,
        ),
        AchievementStory(:final achievement) =>
          await backend.setAchievementClap(
            achievementId: achievement.id,
            clapped: clapped,
          ),
      };
      if (mounted) setState(() => _counts[story.id] = count);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _counts[story.id] = before;
        if (clapped) {
          _clapped.remove(story.id);
        } else {
          _clapped.add(story.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(clapped ? 'Could not clap.' : 'Could not unclap.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _clapping = false);
    }
  }

  /// Takes down one of the viewer's own achievements, after asking. The page
  /// closes on it rather than stepping over a gap: the day it was opened on
  /// is no longer the crew's day, and Home rereads it on the way back.
  Future<void> _delete(AchievementStory story) async {
    final backend = widget.backend;
    if (backend == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        key: const ValueKey('delete-achievement-dialog'),
        icon: HugeIconsStrokeRounded.delete02,
        iconColor: WeekPactColors.salmon,
        title: 'Delete this ${story.kind.label.toLowerCase()}?',
        message: 'It comes off the crew’s day, claps and all.',
        actions: [
          AppButton(
            key: const ValueKey('confirm-delete-achievement'),
            label: 'DELETE',
            onPressed: () => Navigator.pop(context, true),
          ),
          const AppDialogDismiss(label: 'Keep it'),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await backend.deleteAchievement(story.achievement.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _current;
    final mine = _day.member.id == widget.viewerId;
    final name = mine ? 'You' : _day.member.displayName;
    final kept = story.keptAt?.toLocal();
    return Scaffold(
      backgroundColor: WeekPactColors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _move(
            details.localPosition.dx <
                    MediaQuery.sizeOf(context).width * _backShare
                ? -1
                : 1,
          ),
          // A flick moves a whole member, so a crew is walked at the speed of
          // people rather than of check-ins.
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 200) return;
            setState(() {
              _member = (_member + (velocity < 0 ? 1 : -1)).clamp(
                0,
                widget.days.length - 1,
              );
              _story = 0;
            });
            widget.onSeen?.call(_current);
          },
          child: Padding(
            // The progress and the name start where the status bar's blur has
            // trailed off, so they read sharp rather than frosted.
            padding: const EdgeInsets.fromLTRB(12, StatusBarBlur.fade, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Segments(count: _day.stories.length, at: _story),
                const SizedBox(height: 10),
                _Head(
                  day: _day,
                  name: name,
                  story: story,
                  kept: kept,
                  onClose: () => Navigator.of(context).maybePop(),
                  onDelete:
                      mine &&
                          story is AchievementStory &&
                          widget.backend != null
                      ? () => _delete(story)
                      : null,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ClipPath(
                    clipper: const ShapeBorderClipper(
                      shape: ContinuousRectangleBorder(
                        borderRadius: BorderRadius.all(
                          Radius.circular(WeekPactMetrics.cardCurve),
                        ),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (story.hasPhoto)
                          _Photo(
                            key: const ValueKey('story-photo'),
                            url: story.photoUrl!,
                          )
                        else
                          _Wash(
                            key: const ValueKey('story-wash'),
                            story: story,
                          ),
                        if (story case AchievementStory(:final text))
                          story.hasPhoto
                              ? _AchievementCaption(
                                  key: const ValueKey(
                                    'story-achievement-caption',
                                  ),
                                  text: text,
                                )
                              : _AchievementText(
                                  key: const ValueKey('story-achievement-text'),
                                  text: text,
                                  kind: story.kind,
                                ),
                        // Bounded on both sides, so a long pact name
                        // ellipsizes inside the shot rather than running off
                        // it.
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: switch (story) {
                              PactStory() => _PactChip(
                                key: const ValueKey('story-pact'),
                                story: story,
                              ),
                              AchievementStory(:final kind) => _AchievementChip(
                                key: const ValueKey('story-achievement'),
                                kind: kind,
                              ),
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (widget.backend != null)
                      _ClapPill(
                        key: const ValueKey('story-clap'),
                        count: _counts[story.id] ?? 0,
                        clapped: _clapped.contains(story.id),
                        what: switch (story) {
                          AchievementStory(:final kind) =>
                            kind.label.toLowerCase(),
                          PactStory() => 'check-in',
                        },
                        onPressed: _clapping ? null : _clap,
                      ),
                    const Spacer(),
                    Text(
                      '${_member + 1} of ${widget.days.length}',
                      style: const TextStyle(
                        fontFamily: WeekPactType.secondary,
                        fontFamilyFallback: WeekPactType.secondaryFallback,
                        fontSize: 11,
                        color: WeekPactDarkCard.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The left-hand share of the page that goes back. A third rather than a
  /// half: moving on is the gesture, and going back is the correction.
  static const _backShare = 1 / 3;
}

/// The clap, as the one thing this page asks of the reader.
///
/// A story is one check-in filling the screen rather than a row in a list, so
/// the clap is a pill with the word on it: wide enough to find with a thumb
/// while the other hand holds the phone.
///
/// It wears `clapInk` only once it has been given, as everywhere else in the
/// app: brass is the colour of a clap you made, so an unclapped pill is an
/// outline and a clapped one is filled. The count is the week's own — the
/// snapshot carries every check-in's claps — and a check-in nobody has
/// clapped yet says `Clap` rather than standing a nought there.
class _ClapPill extends StatelessWidget {
  const _ClapPill({
    super.key,
    required this.count,
    required this.clapped,
    this.what = 'check-in',
    this.onPressed,
  });

  final int count;
  final bool clapped;

  /// What is being clapped, for the hint a screen reader reads.
  final String what;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = clapped ? WeekPactColors.black : WeekPactDarkCard.ink;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      checked: clapped,
      label: switch (count) {
        0 => 'Clap',
        1 => '1 clap',
        _ => '$count claps',
      },
      hint: clapped ? 'Take your clap back' : 'Clap for this $what',
      excludeSemantics: true,
      child: Material(
        color: clapped ? clapInk : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: WeekPactMetrics.pill,
          side: BorderSide(
            color: clapped
                ? clapInk
                : WeekPactDarkCard.ink.withValues(alpha: .32),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: WeekPactMetrics.pill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClapPop(
                  clapped: clapped,
                  child: HugeIcon(icon: clapIcon, color: ink, size: 20),
                ),
                const SizedBox(width: 8),
                Text(
                  count > 0 ? '$count' : 'Clap',
                  style: TextStyle(
                    color: ink,
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One bar per check-in, filled up to the one being shown.
class _Segments extends StatelessWidget {
  const _Segments({required this.count, required this.at});

  final int count;
  final int at;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 2.5,
            decoration: BoxDecoration(
              borderRadius: WeekPactMetrics.pill,
              color: i <= at
                  ? WeekPactColors.cream
                  : WeekPactColors.cream.withValues(alpha: .3),
            ),
          ),
        ),
      ],
    ],
  );
}

class _Head extends StatelessWidget {
  const _Head({
    required this.day,
    required this.name,
    required this.story,
    required this.kept,
    required this.onClose,
    this.onDelete,
  });

  final MemberDay day;
  final String name;
  final Story story;
  final DateTime? kept;
  final VoidCallback onClose;

  /// Takes down the story on show. Only the viewer's own achievements offer
  /// it: a check-in is undone on its pact card, and nobody deletes a
  /// crewmate's.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      day.member.initials,
      style: const TextStyle(
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: 13,
        color: WeekPactDarkCard.ink,
      ),
    );
    final url = day.member.avatarUrl;
    final time = kept == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(kept!),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    return Row(
      children: [
        SizedBox.square(
          dimension: 32,
          child: Container(
            decoration: ShapeDecoration(
              color: story.badge,
              shape: const AvatarShape(),
            ),
            padding: const EdgeInsets.all(1.5),
            child: AvatarClip(
              child: ColoredBox(
                color: WeekPactColors.activitySurface,
                child: Center(
                  child: url == null
                      ? initials
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: 32,
                          height: 32,
                          errorBuilder: (_, _, _) => Center(child: initials),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WeekPactDarkCard.ink,
                ),
              ),
              // The pact or the achievement is named on the shot itself, and
              // the story is today's by definition. What is left to say is
              // the hour.
              if (time != null)
                Text(
                  time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: WeekPactType.secondary,
                    fontFamilyFallback: WeekPactType.secondaryFallback,
                    fontSize: 11,
                    color: WeekPactDarkCard.muted,
                  ),
                ),
            ],
          ),
        ),
        if (onDelete != null)
          IconButton(
            key: const ValueKey('delete-achievement'),
            onPressed: onDelete,
            tooltip: story is AchievementStory
                ? 'Delete ${(story as AchievementStory).kind.label.toLowerCase()}'
                : 'Delete',
            icon: const HugeIcon(
              icon: HugeIconsStrokeRounded.delete02,
              color: WeekPactDarkCard.ink,
            ),
          ),
        IconButton(
          key: const ValueKey('close-stories'),
          onPressed: onClose,
          tooltip: 'Close',
          icon: const HugeIcon(
            icon: HugeIconsStrokeRounded.cancel01,
            color: WeekPactDarkCard.ink,
          ),
        ),
      ],
    );
  }
}

/// The frame a story without a photo fills — most check-ins, since most pacts
/// do not ask for one, and every achievement, which is words rather than a
/// shot.
///
/// Not a card standing in for a photo: a wash that fills the frame the way a
/// photo does, so the page is the same page whether or not the pact asked for
/// a picture and the chip in the corner always sits on something. Two soft
/// lights over a dark fall, mixed from the story's own tint and badge, so a run
/// and a reading night are different weather rather than different layouts —
/// and an achievement, in gold, is a different weather again.
///
/// Where the lights sit is drawn from the check-in's own name — the same
/// number every time, since a story that looked different each time it was
/// opened would read as a picture that changed.
class _Wash extends StatelessWidget {
  const _Wash({super.key, required this.story});

  final Story story;

  /// A stable number for [Story.id]. `hashCode` would do it for one run of the
  /// app and a different one for the next.
  int get _seed =>
      story.id.codeUnits.fold(0, (sum, unit) => (sum * 31 + unit) & 0xFFFF);

  @override
  Widget build(BuildContext context) {
    final random = math.Random(_seed);
    double near(double centre) => centre + (random.nextDouble() - .5) * .5;
    // The fall: the pact's badge taken down into the dark the rest of the
    // page is drawn on, so the wash ends where the screen does.
    final deep = Color.lerp(story.badge, WeekPactColors.black, .58)!;
    return Semantics(
      label: story is AchievementStory ? null : 'No photo with this check-in',
      image: story is! AchievementStory,
      excludeSemantics: story is AchievementStory,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-.2, -1),
            end: const Alignment(.2, 1),
            colors: [
              deep,
              WeekPactColors.activitySurface,
              WeekPactColors.black,
            ],
            stops: const [0, .58, 1],
          ),
        ),
        child: DecoratedBox(
          // The warm light, high on one side.
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(near(-.55), near(-.7)),
              radius: 1.15,
              colors: [
                story.tint.withValues(alpha: .5),
                story.tint.withValues(alpha: 0),
              ],
              stops: const [0, .62],
            ),
          ),
          child: DecoratedBox(
            // The cooler one, opposite it and smaller, so the two read as
            // light in a room rather than as a symmetrical pattern.
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(near(.7), near(-.45)),
                radius: .9,
                colors: [
                  story.badge.withValues(alpha: .45),
                  story.badge.withValues(alpha: 0),
                ],
                stops: const [0, .58],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Which pact the shot is of, on the shot.
///
/// A photo of a run and a photo of a book are both just a photo; the chip is
/// what makes a story a check-in. It is the pact card in miniature — the
/// card's tint with the pact's own badge on it — cut to
/// [WeekPactMetrics.buttonShape], the squircle every compact face in the app
/// is cut to, so it reads as an object off the same set as the rail's tiles
/// rather than as a pill borrowed from somewhere else.
class _PactChip extends StatelessWidget {
  const _PactChip({super.key, required this.story});

  final PactStory story;

  @override
  Widget build(BuildContext context) => Semantics(
    label: story.pact.title,
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: ShapeDecoration(
        color: story.tint,
        shape: WeekPactMetrics.buttonShape,
        shadows: [
          // The shot behind it can be any colour at all, so the chip carries
          // the same lifted edge a card on the page would.
          BoxShadow(
            color: Color.lerp(story.tint, Colors.black, .24)!,
            offset: WeekPactMetrics.raisedOffset,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PactIconBadge(
            icon: PactIcon.find(story.pact.iconKey).data,
            tint: story.badge,
            size: 24,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              story.pact.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WeekPactColors.black,
                fontSize: 13.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// An achievement's own words, set large in the middle of the shot.
///
/// The words are the whole of an achievement, so they take the place a photo
/// takes, rather than a caption's. Scaled down, never cut, so a full 160
/// characters still fits a short phone.
class _AchievementText extends StatelessWidget {
  const _AchievementText({super.key, required this.text, required this.kind});

  final String text;
  final PostKind kind;

  @override
  Widget build(BuildContext context) => Padding(
    // Clear of the chip along the foot.
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: kind.icon, color: kind.tint, size: 40),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WeekPactDarkCard.ink,
                  fontSize: 28,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// An achievement's words over its own photo: a caption along the foot, on a
/// shade deep enough to read over any picture, standing above the chip. The
/// photo is the shot here, so the words step down from the middle.
class _AchievementCaption extends StatelessWidget {
  const _AchievementCaption({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00191B19), Color(0xCC191B19)],
        ),
      ),
      child: Padding(
        // Clear of the chip along the foot.
        padding: const EdgeInsets.fromLTRB(16, 48, 16, 60),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            text,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WeekPactDarkCard.ink,
              fontSize: 20,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}

/// What the shot is, on the shot: an achievement or a plain story rather
/// than a pact.
///
/// The pact chip's twin — the same squircle and lifted edge, in the same
/// corner — so they read as one family, with the kind's own colour and glyph
/// where a pact puts its sorbet and badge. That corner is the one place a
/// story says which kind it is, and it says it the same way for all three.
class _AchievementChip extends StatelessWidget {
  const _AchievementChip({super.key, required this.kind});

  final PostKind kind;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
    decoration: ShapeDecoration(
      color: kind.tint,
      shape: WeekPactMetrics.buttonShape,
      shadows: [
        BoxShadow(
          color: Color.lerp(kind.tint, Colors.black, .24)!,
          offset: WeekPactMetrics.raisedOffset,
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PactIconBadge(icon: kind.icon, tint: kind.badge, size: 24),
        const SizedBox(width: 8),
        Text(
          kind.label,
          style: const TextStyle(
            color: WeekPactColors.black,
            fontSize: 13.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Keeps the photo slot filled while it loads, and honest when a signed URL
/// has expired.
class _Photo extends StatelessWidget {
  const _Photo({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: Image.network(
      url,
      fit: BoxFit.cover,
      semanticLabel: 'Story photo',
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _PhotoPlaceholder(),
      errorBuilder: (_, _, _) => const _PhotoPlaceholder(failed: true),
    ),
  );
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.failed = false});

  final bool failed;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: WeekPactColors.activitySurface,
    child: Center(
      child: failed
          ? HugeIcon(
              icon: HugeIconsStrokeRounded.image01,
              color: WeekPactDarkCard.ink.withValues(alpha: .35),
              size: 26,
            )
          : const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WeekPactDarkCard.muted,
                semanticsLabel: 'Loading check-in photo',
              ),
            ),
    ),
  );
}
