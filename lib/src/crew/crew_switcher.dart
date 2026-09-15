import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';

import '../pacts/pacts_backend.dart';
import '../theme/weekpact_theme.dart';

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

class _CrewSwitcherState extends State<CrewSwitcher> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  static const _background = Color(0xFF242424);
  static const _ink = Color(0xFFF4F4F4);
  bool _open = false;

  void _close() {
    _portal.hide();
    setState(() => _open = false);
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      setState(() => _open = true);
      _portal.show();
    }
  }

  @override
  void didUpdateWidget(covariant CrewSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_open &&
        (widget.selectedId != oldWidget.selectedId ||
            widget.onSelected == null)) {
      _portal.hide();
      _open = false;
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
        child: InkWell(
          onTap: widget.onSelected == null || widget.crews.length < 2
              ? null
              : _toggle,
          borderRadius: BorderRadius.circular(WeekPactMetrics.cardRadius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: widget.compact ? 44 : 60,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 4,
                vertical: widget.compact ? 3 : 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        selected?.name ?? 'Your crew',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
                  if (widget.crews.length > 1) ...[
                    const SizedBox(width: 8),
                    HugeIcon(
                      icon: HugeIconsStrokeRounded.unfoldMore,
                      color: _ink,
                      size: 20,
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _close,
                  behavior: HitTestBehavior.opaque,
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                offset: Offset(0, (widget.compact ? 44 : 60) + 22),
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: TapRegion(
                    onTapOutside: (_) => _close(),
                    child: Material(
                      color: _background,
                      borderRadius: BorderRadius.circular(
                        WeekPactMetrics.cardRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            builder: (context, value, child) => ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: value,
                                child: child,
                              ),
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: math.min(
                                  280,
                                  MediaQuery.sizeOf(context).height * .4,
                                ),
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(6),
                                children: [
                                  for (final crew in widget.crews)
                                    Semantics(
                                      selected: crew.id == widget.selectedId,
                                      child: ListTile(
                                        dense: true,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            WeekPactMetrics.controlRadius,
                                          ),
                                        ),
                                        tileColor: crew.id == widget.selectedId
                                            ? const Color(0xFF363636)
                                            : null,
                                        title: Text(
                                          crew.name,
                                          style: const TextStyle(
                                            color: _ink,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onTap: () {
                                          _close();
                                          widget.onSelected?.call(crew.id);
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CrewControlLabel('YOUR CREW'),
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.canvas,
                  borderRadius: BorderRadius.circular(
                    WeekPactMetrics.cardRadius,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: _header(),
                ),
              ),
            ],
          ),
        ),
      );
    },
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
