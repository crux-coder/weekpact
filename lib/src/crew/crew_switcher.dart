import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../home/home_backend.dart';
import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import 'crew_fan.dart';

class CrewSwitcher extends StatefulWidget {
  const CrewSwitcher({
    super.key,
    required this.crews,
    required this.selectedId,
    required this.onSelected,
    this.compact = false,
    this.loadWeek,
  });

  final List<PactCrew> crews;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final bool compact;

  /// Loads a crew's week, for the faces and streak on its card in the fan. The
  /// switcher works without it; the cards then carry their names alone.
  final Future<CrewWeek> Function(String crewId)? loadWeek;

  /// The control's height. Public, so a header that hands the switcher a fixed
  /// slot hands it one the grip's pull band actually fits inside.
  static const height = 70.0;

  @override
  State<CrewSwitcher> createState() => _CrewSwitcherState();
}

class _CrewSwitcherState extends State<CrewSwitcher>
    with TickerProviderStateMixin {
  /// A pull this far down deals the hand. Short enough that the fan feels
  /// pulled rather than dragged, long enough that a tap's wobble misses it.
  static const _pullThreshold = 4.0;

  /// The grip's row: the pill, with room around it for a finger.
  static const _gripBand = 16.0;
  final _portal = OverlayPortalController();

  /// The deal runs a beat longer for each extra crew, so every card keeps the
  /// same pace. [CrewFan.dealDuration] owns that arithmetic.
  late final AnimationController _deal = AnimationController(
    vsync: this,
    duration: CrewFan.dealDuration(widget.crews.length),
  );

  /// The hand leaves faster than it arrives, the way dismissals should.
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );

  bool _open = false;

  /// True while the cards are on their way back off the top of the screen.
  bool _closing = false;

  List<Rect> _cards = const [];

  /// Where the switcher itself sits while the hand is out, so the fan can leave
  /// it out of its scrim.
  Rect? _headerRect;

  /// Each crew's week once it has arrived, and the ones still on their way.
  /// Kept for the switcher's life: a hand is dealt often, and a week that is a
  /// minute old still says who is in the crew and how the streak stands.
  final Map<String, CrewWeek> _previews = {};
  final Set<String> _loadingPreviews = {};

  bool get _enabled => widget.onSelected != null && widget.crews.length > 1;

  /// The hand, the crew you are on first. The top card lands directly under
  /// the switcher, so the one it is already showing is the one it unfolds
  /// into; the rest keep the order they came in.
  List<PactCrew> get _hand => [
    ...widget.crews.where((crew) => crew.id == widget.selectedId),
    ...widget.crews.where((crew) => crew.id != widget.selectedId),
  ];

  @override
  void dispose() {
    _deal.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _buzz(Future<void> Function() haptic) =>
      unawaited(haptic().catchError((Object _) {}));

  /// How far the finger has come down before the hand is dealt. An upward
  /// drag never reaches the threshold, so it leaves scrolling alone.
  double _pull = 0;

  void _pullUpdate(DragUpdateDetails details) {
    if (_open) return;
    _pull += details.delta.dy;
    if (_pull > _pullThreshold) _openFan(details.globalPosition);
  }

  void _openFan(Offset anchor) {
    if (!_enabled) return;
    final screen = MediaQuery.sizeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    setState(() {
      _headerRect = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      _cards = CrewFanLayout.of(
        screen: screen,
        padding: MediaQuery.paddingOf(context),
        anchor: _headerRect ?? (anchor & Size.zero),
        count: widget.crews.length,
      );
      _open = true;
    });
    _loadPreviews();
    _portal.show();
    _exit.value = 0;
    _closing = false;
    _deal.duration = CrewFan.dealDuration(widget.crews.length);
    if (MediaQuery.disableAnimationsOf(context)) {
      _deal.value = 1;
    } else {
      _deal.forward(from: 0);
    }
    _buzz(HapticFeedback.mediumImpact);
  }

  /// Fill in the cards' faces and streaks, one crew at a time. A preview is a
  /// nicety: a crew whose week will not load keeps its name and nothing else.
  void _loadPreviews() {
    final load = widget.loadWeek;
    if (load == null) return;
    for (final crew in widget.crews) {
      if (_previews.containsKey(crew.id) || !_loadingPreviews.add(crew.id)) {
        continue;
      }
      unawaited(() async {
        try {
          final week = await load(crew.id);
          if (mounted) setState(() => _previews[crew.id] = week);
        } catch (_) {
          // Nothing to say and nothing to fix: the card stays as it is.
        } finally {
          _loadingPreviews.remove(crew.id);
        }
      }());
    }
  }

  /// Send the cards back up, then take the overlay down once they are gone.
  void _close() {
    if (!_open || _closing) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _hide();
      return;
    }
    setState(() => _closing = true);
    _exit.forward(from: 0).whenComplete(() {
      if (mounted && _closing) _hide();
    });
  }

  void _hide() {
    _portal.hide();
    _deal.value = 0;
    _exit.value = 0;
    setState(() {
      _open = false;
      _closing = false;
    });
  }

  void _pick(int index) {
    final crew = _hand[index];
    _close();
    if (crew.id == widget.selectedId) return;
    _buzz(HapticFeedback.lightImpact);
    widget.onSelected?.call(crew.id);
  }

  void _tapped() {
    if (_open) {
      _close();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    _openFan(
      box.localToGlobal(box.size.centerLeft(Offset.zero)) +
          Offset(box.size.width / 2, box.size.height - 8),
    );
  }

  @override
  void didUpdateWidget(covariant CrewSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_open &&
        (widget.selectedId != oldWidget.selectedId ||
            widget.onSelected == null)) {
      _close();
    }
  }

  Widget _header() {
    final selected = widget.crews
        .where((crew) => crew.id == widget.selectedId)
        .firstOrNull;
    return Tooltip(
      message: 'Switch crew',
      child: Semantics(
        button: true,
        expanded: _open,
        hint: _enabled ? 'Pull down to fan out your crews' : null,
        child: InkWell(
          onTap: _enabled ? _tapped : null,
          borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: CrewSwitcher.height,
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.compact ? 10 : 4,
                right: widget.compact ? 10 : 4,
                top: 8,
                bottom: 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.compact) ...[
                    const CrewControlLabel('YOUR CREW'),
                    const SizedBox(height: 2),
                  ],
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        selected?.name ?? 'Your crew',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: context.ink,
                        ),
                      ),
                    ),
                  ),
                  if (widget.crews.length > 1)
                    SizedBox(
                      height: _gripBand,
                      child: Center(
                        child: _FanGrip(open: _open, colour: context.ink),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The switcher as it is drawn on the page — and, while the hand is out, over
  /// the fan's scrim as well, so the control does not go dark with the page.
  Widget _surface() => widget.compact
      ? CrewHeaderSurface(child: _header())
      : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CrewControlLabel('YOUR CREW'),
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: ShapeDecoration(
                color: context.canvas,
                shape: const ContinuousRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(WeekPactMetrics.panelCurve),
                  ),
                ),
                shadows: const [
                  BoxShadow(
                    color: WeekPactColors.castShadow,
                    offset: WeekPactMetrics.raisedOffset,
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: _header(),
              ),
            ),
          ],
        );

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => CrewFan(
        crews: _hand,
        selectedId: widget.selectedId,
        cards: _cards,
        animation: _deal,
        exit: _exit,
        onPicked: _pick,
        onDismissed: _close,
        switcher: _surface(),
        switcherRect: _headerRect,
        previews: _previews,
      ),
      // The pull works anywhere on the card, not only on the grip: the whole
      // face is the drawer front, and the grip only says which way it opens.
      child: RawGestureDetector(
        gestures: _enabled
            ? {
                VerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      VerticalDragGestureRecognizer
                    >(VerticalDragGestureRecognizer.new, (recognizer) {
                      // The pull is measured from the finger's own landing, so
                      // a quick flick arrives as movement to read rather than
                      // as slack the recogniser has already eaten.
                      recognizer.dragStartBehavior = DragStartBehavior.down;
                      recognizer.onStart = (_) => _pull = 0;
                      recognizer.onUpdate = _pullUpdate;
                      recognizer.onEnd = (_) => _pull = 0;
                      recognizer.onCancel = () => _pull = 0;
                    }),
              }
            : const {},
        child: _surface(),
      ),
    );
  }
}

/// The pull at the foot of the switcher: a drawer grip, so the control reads
/// as something to pull open rather than something to read an instruction off.
/// It slackens while the hand is out, since the pull has already been spent.
class _FanGrip extends StatelessWidget {
  const _FanGrip({required this.open, required this.colour});
  final bool open;
  final Color colour;

  /// Wide enough to read as the card's own handle rather than a tick under the
  /// name — the pull is the whole card, and this says so.
  static const _width = 96.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: open ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Center(
        child: Container(
          width: _width - 28 * value,
          height: 4,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .38 - .2 * value),
            borderRadius: WeekPactMetrics.pill,
          ),
        ),
      ),
    ),
  );
}

class CrewControlLabel extends StatelessWidget {
  const CrewControlLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 12,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: context.muted,
          fontFamily: WeekPactType.secondary,
          fontFamilyFallback: WeekPactType.secondaryFallback,
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// Compact Home header surface, with labels and controls inside its raised face.
class CrewHeaderSurface extends StatelessWidget {
  const CrewHeaderSurface({
    super.key,
    required this.child,
    this.curve = WeekPactMetrics.panelCurve,
  });
  final Widget child;

  /// The surface's corner. A surface that frames cards of its own takes a
  /// larger one, so its corner stays outside theirs instead of cutting across
  /// them; on its own it keeps the panel curve.
  final double curve;

  /// The surface's own fill. Recessed against the canvas by the same amount in
  /// either theme, so the header keeps its relationship when the canvas colour
  /// changes. Exposed so what sits inside the surface can borrow it.
  static Color faceColor(BuildContext context) => context.isDark
      ? Color.lerp(context.canvas, Colors.black, .3)!
      : Color.lerp(context.canvas, context.ink, .07)!;

  @override
  Widget build(BuildContext context) {
    final face = faceColor(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(curve)),
        ),
        shadows: [
          BoxShadow(
            color: Color.lerp(face, context.ink, .22)!,
            offset: WeekPactMetrics.raisedOffset,
          ),
        ],
      ),
      child: Material(
        color: face,
        shape: ContinuousRectangleBorder(
          borderRadius: BorderRadius.circular(curve),
          side: BorderSide(color: Color.lerp(face, context.ink, .12)!),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
