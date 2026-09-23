import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';
import '../widgets/app_components.dart';

/// Which crew a page is about, and the way to change it: the crew's name at
/// the top of the page with a chevron after it, opening a plain list.
///
/// It is a page title first and a control second. Every crew-scoped page —
/// Home, Pacts, Crews — leads with it, so the name of the crew you are
/// reading about is in the same place wherever you are, and switching is the
/// same one gesture.
///
/// A member of one crew gets the name without the chevron and without a tap.
/// The title is still worth having — it says what the page is about — but a
/// chevron on a list of one is a promise the control cannot keep.
///
/// This replaced a fanned hand of cards: the control dealt every crew out as
/// a tilted card carrying its week's faces and streak, each one loaded on
/// open. It was a lot of machinery, and a lot of waiting, for a choice
/// between two or three names.
class CrewSwitcher extends StatefulWidget {
  const CrewSwitcher({
    super.key,
    required this.crews,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PactCrew> crews;
  final String? selectedId;

  /// Null while the page cannot take a switch — mid-save, mid-load — which
  /// leaves the title standing and the chevron inert rather than removing a
  /// line from the top of the page.
  final ValueChanged<String>? onSelected;

  /// The control's height. Public, so a page that hands the title a fixed
  /// slot hands it one the name actually fits inside.
  static const height = 40.0;

  /// The name's own type, and the chevron cut to match it.
  static const _nameSize = 22.0;
  static const _markSize = 22.0;

  /// The gap a page leaves under it before its own heading starts.
  static const gap = 8.0;

  @override
  State<CrewSwitcher> createState() => _CrewSwitcherState();
}

class _CrewSwitcherState extends State<CrewSwitcher>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  late final _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 110),
  );

  bool _showing = false;

  bool get _enabled => widget.onSelected != null && widget.crews.length > 1;

  PactCrew? get _selected =>
      widget.crews.where((crew) => crew.id == widget.selectedId).firstOrNull;

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CrewSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_showing &&
        (widget.selectedId != oldWidget.selectedId ||
            widget.onSelected == null)) {
      _close();
    }
  }

  void _toggle() {
    if (_showing) {
      _close();
      return;
    }
    if (!_enabled) return;
    unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    setState(() => _showing = true);
    _portal.show();
    if (MediaQuery.disableAnimationsOf(context)) {
      _open.value = 1;
    } else {
      _open.forward(from: 0);
    }
  }

  void _close() {
    if (!_showing) return;
    setState(() => _showing = false);
    if (MediaQuery.disableAnimationsOf(context)) {
      _open.value = 0;
      _portal.hide();
      return;
    }
    _open.reverse().whenComplete(() {
      if (mounted && !_showing) _portal.hide();
    });
  }

  void _pick(PactCrew crew) {
    _close();
    if (crew.id == widget.selectedId) return;
    unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
    widget.onSelected?.call(crew.id);
  }

  /// The title itself: the name, centred, with the chevron after it rather
  /// than out at the page's edge — the pair is one object to tap, and a mark
  /// parked in the corner reads as belonging to the page instead of to the
  /// name.
  Widget _title(BuildContext context) {
    final name = _selected?.name ?? 'Your crew';
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.ink,
              fontSize: CrewSwitcher._nameSize,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_enabled) ...[
          const SizedBox(width: 4),
          HugeIcon(
            icon: HugeIconsStrokeRounded.arrowDown01,
            color: context.muted,
            size: CrewSwitcher._markSize,
            strokeWidth: 2,
          ),
        ],
      ],
    );
    return SizedBox(
      height: CrewSwitcher.height,
      child: Center(
        child: _enabled
            ? Tooltip(
                message: 'Switch crew',
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(
                    WeekPactMetrics.controlRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: label,
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: label,
              ),
      ),
    );
  }

  /// The list, under the title: one row a crew, the one you are on ticked.
  Widget _menu(BuildContext context) {
    final width = math.min(260.0, MediaQuery.sizeOf(context).width - 48);
    final curve = CurvedAnimation(parent: _open, curve: Curves.easeOutCubic);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 4),
          child: FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: .96, end: 1).animate(curve),
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: AppSurface(
                  key: const ValueKey('crew-switcher-menu'),
                  fillColor: context.surface,
                  borderRadius: WeekPactMetrics.panelCurve,
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final crew in widget.crews)
                        _CrewOption(
                          crew: crew,
                          selected: crew.id == widget.selectedId,
                          onPicked: () => _pick(crew),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: _enabled,
    expanded: _enabled ? _showing : null,
    label: _selected?.name ?? 'Your crew',
    hint: _enabled ? 'Lists your crews' : null,
    excludeSemantics: true,
    onTap: _enabled ? _toggle : null,
    child: CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _menu,
        child: _title(context),
      ),
    ),
  );
}

/// One crew in the open list.
class _CrewOption extends StatelessWidget {
  const _CrewOption({
    required this.crew,
    required this.selected,
    required this.onPicked,
  });

  final PactCrew crew;
  final bool selected;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('crew-option-${crew.id}'),
    onTap: onPicked,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              crew.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.ink,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 10),
            HugeIcon(
              icon: HugeIconsStrokeRounded.tick02,
              color: context.ink,
              size: 18,
              strokeWidth: 2,
            ),
          ],
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
