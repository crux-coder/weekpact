import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../crew/crew_switcher.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/avatar_shape.dart';
import 'crew_member_list.dart';
import 'home_backend.dart';

/// The crew's day, on one line: how many are in, and the crew as faces with a
/// tick on whoever has checked in.
///
/// One line rather than a row per person, so the block stays the same height
/// whatever the crew's size — Home does not scroll, and a list that grew with
/// the crew would spend the page on people you are not waiting for.
///
/// The faces are the crew who are in, and only those: the ticks are what the
/// strip is saying, and the score beside them already counts everyone else.
/// They sit to the right, hard against the block's edge, so the day reads left
/// to right as a number and then the people behind it. Past [maxFaces] the
/// rest of them collapse into a single count.
///
/// The whole roster is a pull away. The strip is a drawer front: it carries
/// the same grip the crew switcher does, the pull runs it open pixel for
/// pixel under the finger, and it opens downward over the page rather than as
/// a card floating above it — the block itself is what grows.
class CrewTodayStrip extends StatefulWidget {
  const CrewTodayStrip({
    super.key,
    required this.week,
    required this.userId,
    this.backend,
    this.crewId,
    this.active = true,
    this.bleed = 0,
    this.curve = WeekPactMetrics.panelCurve,
  });

  final CrewWeek week;
  final String userId;

  /// The nudges. Without a backend the strip still reads the day; it simply
  /// has nothing to open.
  final HomeBackend? backend;
  final String? crewId;

  /// False while Home is off screen, which shuts an open drawer behind it.
  final bool active;

  /// How far the open drawer reaches past the strip on either side, so it
  /// comes out at the width of the block holding it rather than at the width
  /// of the strip's own text.
  final double bleed;

  /// The drawer's bottom corner. It takes over the foot of the block it opens
  /// out of, so it wears that block's curve.
  final double curve;

  /// Faces before the rest become a count.
  static const maxFaces = 3;

  static const labelHeight = 12.0;
  static const labelGap = 8.0;
  static const faceSize = 34.0;
  static const stripHeight = 38.0;

  /// The grip's row at the foot of the strip: the pill, with room around it
  /// for a finger. The switcher's own band, so the two pulls feel alike.
  static const gripHeight = 14.0;

  /// What the day occupies under the progress card, closed.
  static const height = labelHeight + labelGap + stripHeight + gripHeight;

  /// A pull this far down opens the drawer. Short enough that it feels pulled
  /// rather than dragged, long enough that a tap's wobble misses it.
  static const _pullThreshold = 4.0;

  /// How much has to be out for a lifted finger to finish the pull, or how
  /// fast it has to be leaving. The switcher's own thresholds.
  static const _pullCommit = .25;
  static const _flickVelocity = 320.0;

  /// The gap the open drawer keeps from the foot of the screen.
  static const _bottomInset = 12.0;

  /// One person's row in the open drawer, at the height [CrewMemberList]
  /// gives it — a 36pt face in 3pt of padding either side — plus the list's
  /// own foot. The drawer runs exactly this far, so it neither clips its last
  /// name nor opens onto empty floor.
  static const _rowHeight = 44.0;
  static const _listInset = 8.0;

  @override
  State<CrewTodayStrip> createState() => _CrewTodayStripState();
}

class _CrewTodayStripState extends State<CrewTodayStrip>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();

  late final AnimationController _drawer =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 240),
      )..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.dismissed) _hide();
        // The drawer lands: the same beat the crew switcher's hand gets when
        // it finishes dealing, so a pull that has run its course says so.
        if (status == AnimationStatus.completed) {
          _buzz(HapticFeedback.mediumImpact);
        }
      });

  bool _open = false;

  /// Where the strip sits on screen, and how far the drawer runs from there.
  Rect? _anchor;
  double _travel = 0;

  /// The finger's own measure of the pull: where it landed, and how far the
  /// drawer was already out when it did.
  double _pullOrigin = 0;
  double _pullFrom = 0;
  bool _scrubbing = false;

  bool get _canOpen =>
      widget.backend != null &&
      widget.crewId != null &&
      widget.week.members.isNotEmpty;

  @override
  void didUpdateWidget(covariant CrewTodayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) _close();
  }

  @override
  void dispose() {
    _drawer.dispose();
    super.dispose();
  }

  /// The strip's rect on screen, and the drawer's run from it. Home scales its
  /// whole composition to fit a short screen, so the box's own size is not
  /// what it occupies — the drawer opens from where it actually is.
  bool _measure() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final anchor = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final wanted =
        anchor.height +
        CrewTodayStrip._listInset +
        widget.week.members.length * CrewTodayStrip._rowHeight * scale;
    final room =
        screen.height -
        padding.bottom -
        CrewTodayStrip._bottomInset -
        anchor.top;
    _anchor = anchor;
    _travel = math.max(0, math.min(wanted, room) - anchor.height);
    return _travel > 0;
  }

  void _showDrawer() {
    if (_open) return;
    if (!_measure()) return;
    setState(() => _open = true);
    _portal.show();
  }

  void _hide() {
    if (_portal.isShowing) _portal.hide();
    if (mounted && _open) setState(() => _open = false);
  }

  /// A tap runs the pull straight through, either way.
  void _toggle() {
    if (!_canOpen) return;
    if (_drawer.value > 0) {
      _close();
      return;
    }
    _showDrawer();
    if (!_open) return;
    _buzz(HapticFeedback.lightImpact);
    if (MediaQuery.disableAnimationsOf(context)) {
      _drawer.value = 1;
    } else {
      _drawer.forward(from: 0);
    }
  }

  void _close() {
    if (!_open) return;
    _scrubbing = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _drawer.value = 0;
      _hide();
      return;
    }
    _drawer.reverse();
  }

  void _buzz(Future<void> Function() haptic) {
    unawaited(haptic().catchError((Object _) {}));
  }

  void _pullStart(DragStartDetails details) {
    _pullOrigin = details.globalPosition.dy;
    _pullFrom = _drawer.value;
    _scrubbing = _open;
  }

  void _pullUpdate(DragUpdateDetails details) {
    if (!_canOpen) return;
    // The pull is read in global pixels: the drawer runs in them, and Home may
    // have scaled the control this gesture started on.
    final pulled = details.globalPosition.dy - _pullOrigin;
    if (!_scrubbing) {
      if (pulled <= CrewTodayStrip._pullThreshold) return;
      _showDrawer();
      if (!_open) return;
      _buzz(HapticFeedback.lightImpact);
      _scrubbing = !MediaQuery.disableAnimationsOf(context);
      if (!_scrubbing) {
        _drawer.value = 1;
        return;
      }
    }
    if (_travel <= 0) return;
    // The drawer sits where the finger has dragged it to, pixel for pixel.
    _drawer.value = (_pullFrom + pulled / _travel).clamp(0.0, 1.0);
  }

  /// A lifted finger either finishes the pull from where it left the drawer or
  /// hands it back. Either way it carries on from that point rather than
  /// restarting.
  void _pullEnd(double velocity) {
    if (!_scrubbing) return;
    _scrubbing = false;
    if (_drawer.value >= CrewTodayStrip._pullCommit ||
        velocity >= CrewTodayStrip._flickVelocity) {
      _drawer.animateTo(
        1,
        duration: _drawer.duration! * (1 - _drawer.value),
        curve: Curves.easeOut,
      );
      return;
    }
    _close();
  }

  GestureRecognizerFactory get _pull =>
      GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
        VerticalDragGestureRecognizer.new,
        (recognizer) {
          // Measured from the finger's own landing, so a quick flick arrives
          // as movement to read rather than as slack the recogniser has
          // already eaten.
          recognizer.dragStartBehavior = DragStartBehavior.down;
          recognizer.onStart = _pullStart;
          recognizer.onUpdate = _pullUpdate;
          recognizer.onEnd = (details) =>
              _pullEnd(details.primaryVelocity ?? 0);
          recognizer.onCancel = () => _pullEnd(0);
        },
      );

  /// The whole crew, as the open drawer reads it: you first, then whoever is
  /// in, then whoever the day is still waiting on — the rows worth acting on
  /// last, where the nudge is.
  List<WeekMember> get _ordered => [...widget.week.members]
    ..sort((a, b) {
      if (a.id == b.id) return 0;
      if (a.id == widget.userId) return -1;
      if (b.id == widget.userId) return 1;
      final byState = (_done(b) ? 1 : 0).compareTo(_done(a) ? 1 : 0);
      return byState != 0
          ? byState
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  /// The faces the closed strip shows: today's check-ins, yours first.
  List<WeekMember> get _inToday => _ordered.where(_done).toList();

  bool _done(WeekMember member) =>
      widget.week.checkedToday(member.id).isNotEmpty;

  int get _inCount => widget.week.members.where(_done).length;

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: _drawerOverlay,
    child: PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      // The pull works anywhere on the strip, not only on the grip: the whole
      // face is the drawer front, and the grip only says which way it opens.
      child: RawGestureDetector(
        gestures: _canOpen ? {VerticalDragGestureRecognizer: _pull} : const {},
        child: _front(context),
      ),
    ),
  );

  /// The drawer front: the day, and the grip that says it pulls.
  ///
  /// Open, the grip rides at the foot of the drawer rather than the foot of
  /// the front — the handle belongs to the bottom edge of the body being
  /// pulled, wherever that edge has got to. [grip] leaves it off here so the
  /// drawer can carry it down there itself.
  Widget _front(
    BuildContext context, {
    bool inDrawer = false,
    bool grip = true,
  }) {
    final inToday = _inToday;
    final shown = inToday.take(CrewTodayStrip.maxFaces).toList();
    final hidden = inToday.length - shown.length;
    return Semantics(
      container: true,
      button: _canOpen,
      expanded: _canOpen ? _open : null,
      label: 'Today',
      value: '$_inCount of ${widget.week.members.length} checked in',
      hint: _canOpen ? 'Pull down for the crew, where you can nudge' : null,
      onTap: _canOpen ? _toggle : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: inDrawer ? null : const ValueKey('crew-today-strip'),
          behavior: HitTestBehavior.opaque,
          onTap: _canOpen ? _toggle : null,
          child: SizedBox(
            height: grip
                ? CrewTodayStrip.height
                : CrewTodayStrip.height - CrewTodayStrip.gripHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(
                  height: CrewTodayStrip.labelHeight,
                  child: CrewControlLabel('TODAY'),
                ),
                const SizedBox(height: CrewTodayStrip.labelGap),
                SizedBox(
                  height: CrewTodayStrip.stripHeight,
                  child: Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: _count(context),
                        ),
                      ),
                      const Spacer(),
                      for (final member in shown)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _Face(
                            key: inDrawer
                                ? null
                                : ValueKey('crew-today-face-${member.id}'),
                            member: member,
                            done: _done(member),
                          ),
                        ),
                      if (hidden > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _MoreFace(
                            key: inDrawer
                                ? null
                                : const ValueKey('crew-today-more'),
                            hidden: hidden,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_canOpen && grip) _grip(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The handle's row, wherever the body it belongs to currently ends.
  Widget _grip(BuildContext context) => SizedBox(
    height: CrewTodayStrip.gripHeight,
    child: AnimatedBuilder(
      animation: _drawer,
      builder: (context, _) => _Grip(open: _drawer.value, colour: context.ink),
    ),
  );

  /// The day as a score, in the page's own weight: the number that has been
  /// kept over the number owed.
  Widget _count(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        '$_inCount',
        key: const ValueKey('crew-today-count'),
        style: TextStyle(
          color: context.ink,
          fontSize: 28,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(
        '/${widget.week.members.length}',
        style: TextStyle(
          color: context.muted,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        'in today',
        style: TextStyle(
          color: context.muted,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  /// The drawer, open over the page.
  ///
  /// It is the block's own face carried further down rather than a card laid
  /// on top of it: the front rides at its head, the roster comes out
  /// underneath, and nothing behind is dimmed. A tap anywhere else shuts it.
  Widget _drawerOverlay(BuildContext context) {
    final anchor = _anchor;
    if (anchor == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _drawer,
      builder: (context, _) {
        // Under the finger the drawer is linear — it has to keep pace with it.
        final progress = _scrubbing
            ? _drawer.value
            : Curves.easeOutCubic.transform(_drawer.value);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('crew-today-barrier'),
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fromRect(
              rect: Rect.fromLTWH(
                anchor.left - widget.bleed,
                anchor.top,
                anchor.width + widget.bleed * 2,
                anchor.height + _travel * progress,
              ),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _close,
                },
                child: Focus(
                  autofocus: true,
                  child: RawGestureDetector(
                    gestures: {VerticalDragGestureRecognizer: _pull},
                    child: _Drawer(
                      key: const ValueKey('crew-today-drawer'),
                      progress: progress,
                      bleed: widget.bleed,
                      curve: widget.curve,
                      front: _front(context, inDrawer: true, grip: false),
                      grip: _grip(context),
                      members: _ordered,
                      userId: widget.userId,
                      backend: widget.backend!,
                      crewId: widget.crewId!,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The open drawer: the strip at its head and the roster sliding out from
/// under it, on the block's own face so the two read as one body.
class _Drawer extends StatelessWidget {
  const _Drawer({
    super.key,
    required this.progress,
    required this.bleed,
    required this.curve,
    required this.front,
    required this.grip,
    required this.members,
    required this.userId,
    required this.backend,
    required this.crewId,
  });

  final double progress;
  final double bleed;
  final double curve;
  final Widget front;
  final Widget grip;
  final List<WeekMember> members;
  final String userId;
  final HomeBackend backend;
  final String crewId;

  @override
  Widget build(BuildContext context) {
    final face = CrewHeaderSurface.faceColor(context);
    // Square at the head and curved at the foot: the drawer is the block's
    // own body carried further down, so it meets the block flush and takes
    // over the corner the block would have finished on.
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(curve)),
    );
    return DecoratedBox(
      // The lifted edge every raised surface here carries, arriving with the
      // drawer rather than sitting under a closed one.
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          BoxShadow(
            color: Color.lerp(face, WeekPactColors.darkBorder, progress)!,
            offset: WeekPactMetrics.raisedOffset,
          ),
        ],
      ),
      child: Material(
        color: face,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The front keeps the strip's own margins inside the wider body.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: bleed),
              child: front,
            ),
            Expanded(
              child: ClipRect(
                child: Opacity(
                  // The roster arrives once the drawer has somewhere to put
                  // it.
                  opacity: Curves.easeIn.transform(progress),
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: SizedBox(
                      height: math.max(
                        1,
                        members.length * CrewTodayStrip._rowHeight +
                            CrewTodayStrip._listInset,
                      ),
                      child: CrewMemberList(
                        members: members,
                        done: false,
                        userId: userId,
                        backend: backend,
                        crewId: crewId,
                        onDark: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // The handle sits on the drawer's own bottom edge, so it travels
            // with it as it comes out instead of staying where it started.
            grip,
          ],
        ),
      ),
    );
  }
}

/// The pull at the foot of the strip, as the crew switcher wears it: a drawer
/// grip, so the block reads as something to pull open rather than something to
/// read an instruction off. It slackens once the drawer is out, since the pull
/// has already been spent.
class _Grip extends StatelessWidget {
  const _Grip({required this.open, required this.colour});
  final double open;
  final Color colour;

  /// Wide enough to read as the block's own handle rather than a tick under
  /// the faces — the pull is the whole strip, and this says so.
  static const _width = 96.0;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: _width - 28 * open,
      height: 4,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .38 - .2 * open),
        borderRadius: WeekPactMetrics.pill,
      ),
    ),
  );
}

/// One crew face on the strip, lifted on its edge once the day is kept and
/// sitting flat before it, with the tick Home answers a day with.
class _Face extends StatelessWidget {
  const _Face({super.key, required this.member, required this.done});
  final WeekMember member;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      member.initials,
      style: const TextStyle(
        color: WeekPactColors.black,
        fontFamily: WeekPactType.secondary,
        fontFamilyFallback: WeekPactType.secondaryFallback,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
    final url = member.avatarUrl;
    return Padding(
      // The raised face carries its edge below its own box, so the flat one
      // keeps the same centre rather than sitting a shade lower.
      padding: EdgeInsets.only(bottom: done ? 0 : WeekPactMetrics.controlDepth),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              shape: const AvatarShape(),
              shadows: done
                  ? const [
                      BoxShadow(
                        color: WeekPactColors.mintEdge,
                        offset: WeekPactMetrics.raisedOffset,
                      ),
                    ]
                  : null,
            ),
            child: Opacity(
              opacity: done ? 1 : .5,
              child: AvatarClip(
                child: SizedBox.square(
                  dimension: CrewTodayStrip.faceSize,
                  child: ColoredBox(
                    color: done
                        ? WeekPactColors.mintGreen
                        : WeekPactColors.pendingCheckIns,
                    child: Center(
                      child: url == null
                          ? initials
                          : Image.network(
                              url,
                              fit: BoxFit.cover,
                              width: CrewTodayStrip.faceSize,
                              height: CrewTodayStrip.faceSize,
                              errorBuilder: (_, _, _) => initials,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (done)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: CrewHeaderSurface.faceColor(context),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(
                  dimension: 13,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: WeekPactColors.mintGreen,
                      shape: CircleBorder(
                        side: BorderSide(color: WeekPactColors.mintEdge),
                      ),
                    ),
                    child: Center(
                      child: HugeIcon(
                        icon: HugeIconsStrokeRounded.tick03,
                        color: WeekPactColors.black,
                        size: 9,
                        strokeWidth: 3,
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
}

/// The crew the strip could not fit, as one more face: a count, in the flat
/// state, since it stands for people whose day the strip is not saying.
class _MoreFace extends StatelessWidget {
  const _MoreFace({super.key, required this.hidden});
  final int hidden;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WeekPactMetrics.controlDepth),
    child: AvatarClip(
      child: SizedBox.square(
        dimension: CrewTodayStrip.faceSize,
        child: ColoredBox(
          color: WeekPactColors.pendingCheckIns,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '+$hidden',
                style: const TextStyle(
                  color: WeekPactColors.black,
                  fontFamily: WeekPactType.secondary,
                  fontFamilyFallback: WeekPactType.secondaryFallback,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
