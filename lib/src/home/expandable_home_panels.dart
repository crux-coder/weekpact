import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_backend.dart';

import 'today_widgets.dart';

enum _HomePanel { checked, pending }

/// Keeps home cards mounted while the selected surface unfolds over its peers.
class ExpandableHomePanels extends StatefulWidget {
  const ExpandableHomePanels({
    super.key,
    required this.backend,
    required this.crewId,
    required this.week,
    required this.userId,
    required this.top,
    required this.child,
    this.inset = 0,
    this.active = true,
    this.showCrewCheckIns = false,
  });

  final HomeBackend backend;
  final String crewId;
  final CrewWeek week;
  final String userId;
  final double top;

  /// The frame the crew's surface keeps around the tiles, so the panels line up
  /// with the space reserved for them inside it.
  final double inset;
  final Widget child;
  final bool active;
  final bool showCrewCheckIns;

  @override
  State<ExpandableHomePanels> createState() => _ExpandableHomePanelsState();
}

class _ExpandableHomePanelsState extends State<ExpandableHomePanels>
    with SingleTickerProviderStateMixin {
  late final _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
        reverseDuration: const Duration(milliseconds: 280),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && mounted) {
          setState(() => _panel = null);
        }
      });
  _HomePanel? _panel;
  bool _expanded = false;
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant ExpandableHomePanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasChecked = widget.week.members.any(
      (member) => widget.week.checkedToday(member.id).isNotEmpty,
    );
    final hasPending = widget.week.members.any(
      (member) => widget.week.checkedToday(member.id).isEmpty,
    );
    if ((_panel == _HomePanel.checked && !hasChecked) ||
        (_panel == _HomePanel.pending && hasChecked && !hasPending)) {
      _expanded = false;
      _panel = null;
      _animation.reset();
      _focus.unfocus();
    }
    if (!widget.active && oldWidget.active) _collapse();
  }

  @override
  void dispose() {
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggle(_HomePanel panel) {
    if (_expanded && _panel == panel) {
      _collapse();
      return;
    }
    setState(() {
      _expanded = true;
      _panel = panel;
    });
    _focus.requestFocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 0;
    } else {
      _animation.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_expanded,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _collapse();
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _collapse},
      child: Focus(
        focusNode: _focus,
        child: LayoutBuilder(
          builder: (context, space) => AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              final progress = Curves.easeInOutCubic.transform(
                _animation.value,
              );
              final cards = _cards(context, space, progress);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _panel != null,
                      child: ExcludeSemantics(
                        excluding: _panel != null,
                        child: ImageFiltered(
                          key: const ValueKey('home-panels-background'),
                          enabled: progress > 0,
                          imageFilter: ImageFilter.blur(
                            sigmaX: 6 * progress,
                            sigmaY: 6 * progress,
                          ),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                  for (final entry in cards.entries)
                    if (entry.key != _panel) entry.value,
                  if (_panel != null)
                    Positioned.fill(
                      child: Semantics(
                        label: 'Collapse crew check-ins',
                        button: true,
                        child: GestureDetector(
                          key: const ValueKey('crew-panel-backdrop'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _collapse,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ),
                  if (_panel != null) cards[_panel]!,
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Map<_HomePanel, Widget> _cards(
    BuildContext context,
    BoxConstraints space,
    double progress,
  ) {
    final cards = <_HomePanel, Widget>{};
    if (!widget.showCrewCheckIns) return cards;
    final checked = widget.week.members
        .where((m) => widget.week.checkedToday(m.id).isNotEmpty)
        .toList();
    final pending = widget.week.members
        .where((m) => widget.week.checkedToday(m.id).isEmpty)
        .toList();
    // The two tiles sit flush against each other: their own fills are the
    // only line between them.
    const gap = 0.0;
    final available = math.max(0.0, space.maxWidth - widget.inset * 2 - gap);
    final minimum = math.min(140.0, available / 2);
    final fraction = widget.week.members.isEmpty
        ? .5
        : checked.length / widget.week.members.length;
    final checkedWidth = checked.isEmpty
        ? 0.0
        : pending.isEmpty
        ? available
        : (available * fraction).clamp(minimum, available - minimum);
    final crewTop = widget.top;
    for (final panel in [
      if (checked.isNotEmpty) _HomePanel.checked,
      if (pending.isNotEmpty || checked.isEmpty) _HomePanel.pending,
    ]) {
      final done = panel == _HomePanel.checked;
      final members = done ? checked : pending;
      final selected = _panel == panel;
      final expandedHeight = math.min(
        space.maxHeight - crewTop - 64,
        math.max(
          160.0,
          46 + members.length * 52 * MediaQuery.textScalerOf(context).scale(1),
        ),
      );
      final rect = Rect.lerp(
        Rect.fromLTWH(
          widget.inset + (done ? 0 : checkedWidth + gap),
          crewTop,
          done ? checkedWidth : available - checkedWidth,
          TodayCrewCard.groupHeight,
        ),
        Rect.fromLTWH(widget.inset, crewTop, available, expandedHeight),
        selected ? progress : 0,
      )!;
      cards[panel] = _position(
        panel,
        rect,
        progress,
        SizedBox(
          key: ValueKey(done ? 'checked-tile' : 'pending-tile'),
          child: CrewCheckInTile(
            backend: widget.backend,
            crewId: widget.crewId,
            members: members,
            done: done,
            awaitingFirstCheckIn: checked.isEmpty,
            everyoneCheckedIn: checked.isNotEmpty && pending.isEmpty,
            userId: widget.userId,
            onOpen: () => _toggle(panel),
            expansion: selected ? progress : 0,
            showDetails: selected,
            expandedHeight: expandedHeight,
          ),
        ),
      );
    }
    return cards;
  }

  Widget _position(_HomePanel panel, Rect rect, double progress, Widget child) {
    final obscured = _panel != null && _panel != panel;
    return Positioned.fromRect(
      key: ValueKey('home-panel-${panel.name}'),
      rect: rect,
      child: IgnorePointer(
        ignoring: obscured,
        child: ExcludeSemantics(
          excluding: obscured,
          child: ImageFiltered(
            enabled: obscured && progress > 0,
            imageFilter: ImageFilter.blur(
              sigmaX: 6 * progress,
              sigmaY: 6 * progress,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
