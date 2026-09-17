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

  @override
  State<CrewSwitcher> createState() => _CrewSwitcherState();
}

class _CrewSwitcherState extends State<CrewSwitcher>
    with TickerProviderStateMixin {
  /// Long enough that a tap never deals the hand, short enough to feel direct.
  static const _holdDelay = Duration(milliseconds: 240);

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

  /// True while the fan follows a finger that has not lifted yet.
  bool _dragging = false;
  List<Rect> _cards = const [];

  /// Where the switcher itself sits while the hand is out, so the fan can leave
  /// it out of its scrim.
  Rect? _headerRect;
  int? _highlighted;

  /// Each crew's week once it has arrived, and the ones still on their way.
  /// Kept for the switcher's life: a hand is dealt often, and a week that is a
  /// minute old still says who is in the crew and how the streak stands.
  final Map<String, CrewWeek> _previews = {};
  final Set<String> _loadingPreviews = {};

  bool get _enabled => widget.onSelected != null && widget.crews.length > 1;

  @override
  void dispose() {
    _deal.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _buzz(Future<void> Function() haptic) =>
      unawaited(haptic().catchError((Object _) {}));

  void _openFan(Offset anchor, {required bool dragging}) {
    if (!_enabled) return;
    final screen = MediaQuery.sizeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    setState(() {
      _dragging = dragging;
      _headerRect = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      _cards = CrewFanLayout.of(
        screen: screen,
        padding: MediaQuery.paddingOf(context),
        anchor: _headerRect ?? (anchor & Size.zero),
        count: widget.crews.length,
      );
      _highlighted = null;
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
    setState(() {
      _closing = true;
      _dragging = false;
      _highlighted = null;
    });
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
      _dragging = false;
      _highlighted = null;
    });
  }

  void _track(Offset point) {
    if (!_open) return;
    final over = CrewFanLayout.hit(_cards, point);
    if (over == _highlighted) return;
    setState(() => _highlighted = over);
    if (over != null) _buzz(HapticFeedback.selectionClick);
  }

  void _pick(int index) {
    final crew = widget.crews[index];
    _close();
    if (crew.id == widget.selectedId) return;
    _buzz(HapticFeedback.lightImpact);
    widget.onSelected?.call(crew.id);
  }

  /// A lifted finger takes the card under it, or dismisses if it is off the hand.
  void _release() {
    if (!_dragging) return;
    final chosen = _highlighted;
    if (chosen == null) {
      _close();
      return;
    }
    _pick(chosen);
  }

  void _tapped() {
    if (_open) {
      _close();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // A tap leaves the hand dealt, so the fan is reachable without the gesture.
    _openFan(
      box.localToGlobal(box.size.centerLeft(Offset.zero)) +
          Offset(box.size.width / 2, box.size.height - 8),
      dragging: false,
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
        hint: _enabled ? 'Hold to fan out your crews' : null,
        child: InkWell(
          onTap: _enabled ? _tapped : null,
          borderRadius: BorderRadius.circular(WeekPactMetrics.controlRadius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 4,
                vertical: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.compact) ...[
                    CrewControlLabel(
                      _enabled ? 'YOUR CREW · HOLD TO SWITCH' : 'YOUR CREW',
                    ),
                    const SizedBox(height: 4),
                  ],
                  Expanded(
                    child: Row(
                      children: [
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
                        if (widget.crews.length > 1) ...[
                          const SizedBox(width: 8),
                          _FanHint(open: _open, colour: context.ink),
                        ],
                      ],
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
        crews: widget.crews,
        selectedId: widget.selectedId,
        highlighted: _highlighted,
        cards: _cards,
        animation: _deal,
        exit: _exit,
        onPicked: _pick,
        onDismissed: _close,
        switcher: _surface(),
        switcherRect: _headerRect,
        previews: _previews,
      ),
      child: RawGestureDetector(
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: _holdDelay),
                (recognizer) {
                  recognizer.onLongPressStart = (details) =>
                      _openFan(details.globalPosition, dragging: true);
                  recognizer.onLongPressMoveUpdate = (details) =>
                      _track(details.globalPosition);
                  recognizer.onLongPressEnd = (_) => _release();
                  recognizer.onLongPressCancel = () {
                    if (_dragging) _close();
                  };
                },
              ),
        },
        child: _surface(),
      ),
    );
  }
}

/// Three stacked lines that splay apart while the hand is dealt.
class _FanHint extends StatelessWidget {
  const _FanHint({required this.open, required this.colour});
  final bool open;
  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20,
    height: 20,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: open ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, value, _) => Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.rotate(
              angle: (i - 1) * .34 * value,
              child: Transform.translate(
                offset: Offset(0, (i - 1) * 4.5 * (1 - value * .4)),
                child: Container(
                  width: 16,
                  height: 3,
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: i == 1 ? .95 : .55),
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
  const CrewHeaderSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Recessed against the canvas by the same amount in either theme, so the
    // header keeps its relationship when the canvas colour changes.
    final face = context.isDark
        ? Color.lerp(context.canvas, Colors.black, .3)!
        : Color.lerp(context.canvas, context.ink, .07)!;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(WeekPactMetrics.panelCurve),
          ),
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
          borderRadius: BorderRadius.circular(WeekPactMetrics.panelCurve),
          side: BorderSide(color: Color.lerp(face, context.ink, .12)!),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
