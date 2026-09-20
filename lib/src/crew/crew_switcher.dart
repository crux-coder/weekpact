import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

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
    this.curve = WeekPactMetrics.panelCurve,
  });

  final List<PactCrew> crews;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final bool compact;

  /// The control's corner.
  ///
  /// [WeekPactMetrics.panelCurve] is what a switcher standing on its own
  /// takes, and the fan's cards keep it whatever this is — they are small
  /// cards in their own right, not part of this surface.
  ///
  /// A page that stacks the switcher in a column of its own blocks passes
  /// that column's corner instead. Home does: the switcher sits directly above
  /// the crew panel at the same width, and two stacked blocks that share an
  /// edge have to share a corner or the pair reads as a mistake.
  final double curve;

  /// Loads a crew's week, for the faces and streak on its card in the fan. The
  /// switcher works without it; the cards then carry their names alone.
  final Future<CrewWeek> Function(String crewId)? loadWeek;

  /// The control's height. Public, so a header that hands the switcher a
  /// fixed slot hands it one the label and the name actually fit inside.
  static const height = 60.0;

  @override
  State<CrewSwitcher> createState() => _CrewSwitcherState();
}

class _CrewSwitcherState extends State<CrewSwitcher>
    with TickerProviderStateMixin {
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

  /// Deals the hand under the control. The cards take the switcher's own rect,
  /// so the fan reads as this control unfolded rather than as a menu that
  /// happens to be near it.
  void _openFan() {
    final box = context.findRenderObject() as RenderBox?;
    if (!_enabled || box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _headerRect = rect;
      _cards = CrewFanLayout.of(
        screen: MediaQuery.sizeOf(context),
        padding: MediaQuery.paddingOf(context),
        anchor: rect,
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

  void _tapped() => _open ? _close() : _openFan();

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
        hint: _enabled ? 'Fans out your crews' : null,
        child: InkWell(
          onTap: _enabled ? _tapped : null,
          // The ink follows the surface's own corner. It used to be a plain
          // `controlRadius` rounded rect under a continuous squircle.
          customBorder: ContinuousRectangleBorder(
            borderRadius: BorderRadius.circular(widget.curve),
          ),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: CrewSwitcher.height,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 4,
                vertical: 8,
              ),
              // The mark sits beside the whole control rather than beside the
              // name, so it is centred on the card's own face — the label
              // above the name would otherwise push it low.
              child: Row(
                children: [
                  Expanded(
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
                                fontWeight: FontWeight.w600,
                                color: context.ink,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The control opens on a tap, so it carries a mark saying
                  // so: the menu glyph, which is what the tap produces — the
                  // crews, one under another.
                  if (_enabled) ...[
                    const SizedBox(width: 6),
                    HugeIcon(
                      icon: HugeIconsStrokeRounded.menu01,
                      color: context.muted,
                      size: _markSize,
                      strokeWidth: 2,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The mark's glyph, at the size the crew week card gives its own chevron.
  static const _markSize = 26.0;

  /// The switcher as it is drawn on the page — and, while the hand is out, over
  /// the fan's scrim as well, so the control does not go dark with the page.
  Widget _surface() => widget.compact
      ? CrewHeaderSurface(curve: widget.curve, child: _header())
      : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CrewControlLabel('YOUR CREW'),
            const SizedBox(height: 4),
            DecoratedBox(
              decoration: ShapeDecoration(
                color: context.canvas,
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(widget.curve)),
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
      child: _surface(),
    );
  }
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
          fontWeight: FontWeight.w500,
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
