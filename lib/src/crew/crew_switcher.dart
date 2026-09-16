import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

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
  });

  final List<PactCrew> crews;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final bool compact;

  @override
  State<CrewSwitcher> createState() => _CrewSwitcherState();
}

class _CrewSwitcherState extends State<CrewSwitcher>
    with SingleTickerProviderStateMixin {
  /// Long enough that a tap never deals the hand, short enough to feel direct.
  static const _holdDelay = Duration(milliseconds: 240);

  final _portal = OverlayPortalController();
  late final AnimationController _deal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  bool _open = false;

  /// True while the fan follows a finger that has not lifted yet.
  bool _dragging = false;
  Offset _anchor = Offset.zero;
  List<Rect> _cards = const [];
  int? _highlighted;

  bool get _enabled => widget.onSelected != null && widget.crews.length > 1;

  @override
  void dispose() {
    _deal.dispose();
    super.dispose();
  }

  void _buzz(Future<void> Function() haptic) =>
      unawaited(haptic().catchError((Object _) {}));

  void _openFan(Offset anchor, {required bool dragging}) {
    if (!_enabled) return;
    final screen = MediaQuery.sizeOf(context);
    setState(() {
      _dragging = dragging;
      _anchor = anchor;
      _cards = CrewFanLayout.of(
        screen: screen,
        padding: MediaQuery.paddingOf(context),
        anchor: anchor,
        count: widget.crews.length,
      );
      _highlighted = null;
      _open = true;
    });
    _portal.show();
    if (MediaQuery.disableAnimationsOf(context)) {
      _deal.value = 1;
    } else {
      _deal.forward(from: 0);
    }
    _buzz(HapticFeedback.mediumImpact);
  }

  void _close() {
    _portal.hide();
    _deal.value = 0;
    setState(() {
      _open = false;
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
          borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
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

  @override
  Widget build(BuildContext context) {
    final header = widget.compact
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
                    borderRadius: BorderRadius.all(Radius.circular(20)),
                  ),
                  shadows: const [
                    BoxShadow(
                      color: Color(0x40000000),
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

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => CrewFan(
        crews: widget.crews,
        selectedId: widget.selectedId,
        highlighted: _highlighted,
        cards: _cards,
        anchor: _anchor,
        animation: _deal,
        onPicked: _pick,
        onDismissed: _close,
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
        child: header,
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
                    borderRadius: BorderRadius.circular(2),
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
          fontFamily: 'Roboto',
          fontFamilyFallback: const ['Arial'],
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
          borderRadius: BorderRadius.all(Radius.circular(28)),
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
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Color.lerp(face, context.ink, .12)!),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
