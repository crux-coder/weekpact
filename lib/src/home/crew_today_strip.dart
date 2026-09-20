import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../crew/crew_switcher.dart';
import '../theme/weekpact_theme.dart';
import 'crew_member_list.dart';
import 'home_backend.dart';

/// The crew's day, on one line: how many are in, and how long is left to run.
///
/// One line rather than a row per person, so the block stays the same height
/// whatever the crew's size — Home does not scroll, and a list that grew with
/// the crew would spend the page on people you are not waiting for.
///
/// It used to carry the crew as faces too. The pact cards now show who has
/// kept each pact today, which is the same faces answering a sharper question,
/// so the row here is a score and a clock and nothing else. What the strip
/// still has that the cards do not: the day rolled up across every pact, the
/// time left, and the roster a pull below.
///
/// The whole roster is a pull away. The strip is a drawer front: a grip says
/// so, the pull runs it open pixel for pixel under the finger, and it opens
/// downward over the page rather than as a card floating above it — the block
/// itself is what grows. It is the one pull in the app; the crew switcher
/// above it opens on a tap.
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
    this.now,
  });

  final CrewWeek week;
  final String userId;

  /// Fixed in tests, so what the day has left never depends on when the suite
  /// runs.
  final DateTime? now;

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

  /// What the day has left to run, at the tail of the day's own row: hours
  /// while there is more than one, minutes once the day is nearly out. It is
  /// a nudge, not a clock, so it is coarse and never counts below a minute.
  ///
  /// The crew's day ends at midnight in the crew's timezone, and the snapshot
  /// carries that day as a date rather than as a clock — so this reads the
  /// device's own midnight, and says nothing at all when the device's date
  /// and the crew's have parted (a member abroad, or the minutes either side
  /// of a rollover). A wrong countdown is worse than none.
  static String? timeLeft(CrewWeek week, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final date =
        '${at.year.toString().padLeft(4, '0')}-'
        '${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')}';
    if (date != week.today) return null;
    final minutes = DateTime(
      at.year,
      at.month,
      at.day + 1,
    ).difference(at).inMinutes;
    if (minutes >= 60) return '${minutes ~/ 60}H LEFT';
    return '${math.max(1, minutes)}M LEFT';
  }

  /// The day's one row: the score at its head, the time left at its tail.
  static const rowHeight = 28.0;

  /// The row's own inset from the block's left edge. Its right edge is the
  /// block's own, so the time left lines up under the card above it rather
  /// than stopping short of it.
  static const leftInset = 6.0;

  /// The grip's row at the foot of the strip: the pill, with room around it
  /// for a finger.
  static const gripHeight = 14.0;

  /// What the day occupies under the progress card, closed.
  static const height = rowHeight + gripHeight;

  /// A pull this far down opens the drawer. Short enough that it feels pulled
  /// rather than dragged, long enough that a tap's wobble misses it.
  static const _pullThreshold = 4.0;

  /// How much has to be out for a lifted finger to finish the pull, or how
  /// fast it has to be leaving.
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

  /// The roster's head: a hairline where the day's row ends, and the air under
  /// it that keeps the first face off that line. It lives inside the drawer's
  /// own clip, so nothing of it shows until the drawer is actually out.
  ///
  /// The drawer's run has to include it. It is part of what the list measures,
  /// and a drawer sized to the rows alone would clip its last name by exactly
  /// this much.
  static const _listHead = 13.0;

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
        // The drawer lands: a pull that has run its course says so.
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
        CrewTodayStrip._listHead +
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
    final waiting = _inCount < widget.week.members.length;
    final left = CrewTodayStrip.timeLeft(widget.week, now: widget.now);
    return Semantics(
      container: true,
      button: _canOpen,
      expanded: _canOpen ? _open : null,
      label: 'Today',
      value:
          '$_inCount of ${widget.week.members.length} checked in'
          '${left == null || !waiting ? '' : ', ${left.toLowerCase()} today'}',
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
            // Inset on the left; the right edge is the block's own, so the
            // time left lines up under the card above it.
            child: Padding(
              padding: const EdgeInsets.only(
                left: CrewTodayStrip.leftInset,
                right: CrewTodayStrip.leftInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: CrewTodayStrip.rowHeight,
                    child: Row(
                      children: [
                        // The score takes the whole of the rest of the row and
                        // sits at the head of it, so the time left finishes on
                        // the row's own right edge. A `Flexible` score beside a
                        // `Spacer` would split the free space between them and
                        // leave the slack the score did not use standing to the
                        // right of the clock.
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _count(context),
                          ),
                        ),
                        // Gone once the crew is all in — there is nothing left
                        // for the time to be left for.
                        if (left != null && waiting)
                          CrewControlLabel(
                            left,
                            key: inDrawer
                                ? null
                                : const ValueKey('crew-today-left'),
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
          fontSize: 19,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        '/${widget.week.members.length}',
        style: TextStyle(
          color: context.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
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
          fontWeight: FontWeight.w500,
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
                        CrewTodayStrip._listHead +
                            members.length * CrewTodayStrip._rowHeight +
                            CrewTodayStrip._listInset,
                      ),
                      child: CrewMemberList(
                        head: CrewTodayStrip._listHead,
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

/// The pull at the foot of the strip: a drawer grip, so the block reads as
/// something to pull open rather than something to read an instruction off. It
/// slackens once the drawer is out, since the pull has already been spent.
class _Grip extends StatelessWidget {
  const _Grip({required this.open, required this.colour});
  final double open;
  final Color colour;

  /// Wide enough to read as the block's own handle rather than a tick under
  /// the day's row — the pull is the whole strip, and this says so.
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
