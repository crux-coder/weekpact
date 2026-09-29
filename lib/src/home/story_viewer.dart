import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import 'clap_control.dart';
import '../pacts/pact_icons.dart';
import '../theme/weekpact_theme.dart';
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

  static Future<void> open(
    BuildContext context, {
    required List<MemberDay> days,
    required String viewerId,
    int initial = 0,
    HomeBackend? backend,
    void Function(Story story)? onSeen,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryViewer(
        days: days,
        viewerId: viewerId,
        initial: initial,
        backend: backend,
        onSeen: onSeen,
      ),
    ),
  );

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
      final count = await backend.setClap(
        pactId: story.checkIn.pactId,
        userId: story.checkIn.userId,
        day: story.checkIn.day,
        clapped: clapped,
      );
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                          _PactWash(
                            key: const ValueKey('story-wash'),
                            story: story,
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
                            child: _PactChip(
                              key: const ValueKey('story-pact'),
                              story: story,
                            ),
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
    this.onPressed,
  });

  final int count;
  final bool clapped;
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
      hint: clapped ? 'Take your clap back' : 'Clap for this check-in',
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
  });

  final MemberDay day;
  final String name;
  final Story story;
  final DateTime? kept;
  final VoidCallback onClose;

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
              // The pact is named on the shot itself, and the check-in is
              // today's by definition. What is left to say is the hour.
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

/// The frame a check-in kept without a photo fills — most of them, since most
/// pacts do not ask for one.
///
/// Not a card standing in for a photo: a wash that fills the frame the way a
/// photo does, so the page is the same page whether or not the pact asked for
/// a picture and the chip in the corner always sits on something. Two soft
/// lights over a dark fall, mixed from the pact's own tint and badge, so a run
/// and a reading night are different weather rather than different layouts.
///
/// Where the lights sit is drawn from the check-in's own name — the same
/// number every time, since a story that looked different each time it was
/// opened would read as a picture that changed.
class _PactWash extends StatelessWidget {
  const _PactWash({super.key, required this.story});

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
      label: 'No photo with this check-in',
      image: true,
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

  final Story story;

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
      semanticLabel: 'Check-in photo',
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
