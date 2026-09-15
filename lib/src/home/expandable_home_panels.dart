import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'activity_history.dart';
import 'home_backend.dart';
import 'latest_activity_row.dart';
import 'today_widgets.dart';

enum _HomePanel { activity, checked, pending }

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
    this.active = true,
    this.showCrewCheckIns = false,
  });

  final HomeBackend backend;
  final String crewId;
  final CrewWeek week;
  final String userId;
  final double top;
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
                        label: _panel == _HomePanel.activity
                            ? 'Collapse activity history'
                            : 'Collapse crew check-ins',
                        button: true,
                        child: GestureDetector(
                          key: const ValueKey('activity-backdrop'),
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
    final activitySelected = _panel == _HomePanel.activity;
    final cards = <_HomePanel, Widget>{
      _HomePanel.activity: _position(
        _HomePanel.activity,
        Rect.fromLTWH(
          0,
          widget.top,
          space.maxWidth,
          LatestActivityRow.height +
              (space.maxHeight - widget.top - 64 - LatestActivityRow.height) *
                  (activitySelected ? progress : 0),
        ),
        progress,
        LatestActivityRow(
          week: widget.week,
          userId: widget.userId,
          onOpen: () => _toggle(_HomePanel.activity),
          expansion: activitySelected ? progress : 0,
          expandedHeight: space.maxHeight - widget.top - 64,
          history: activitySelected
              ? ActivityHistory(
                  backend: widget.backend,
                  crewId: widget.crewId,
                  week: widget.week,
                  userId: widget.userId,
                )
              : null,
        ),
      ),
    };
    if (!widget.showCrewCheckIns) return cards;
    final checked = widget.week.members
        .where((m) => widget.week.checkedToday(m.id).isNotEmpty)
        .toList();
    final pending = widget.week.members
        .where((m) => widget.week.checkedToday(m.id).isEmpty)
        .toList();
    final gap = checked.isEmpty || pending.isEmpty ? 0.0 : 6.0;
    final available = math.max(0.0, space.maxWidth - gap);
    final minimum = math.min(140.0, available / 2);
    final fraction = widget.week.members.isEmpty
        ? .5
        : checked.length / widget.week.members.length;
    final checkedWidth = checked.isEmpty
        ? 0.0
        : pending.isEmpty
        ? available
        : (available * fraction).clamp(minimum, available - minimum);
    final crewTop =
        widget.top +
        LatestActivityRow.height +
        12 +
        TodayCrewCard.headingHeight;
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
          done ? 0 : checkedWidth + gap,
          crewTop,
          done ? checkedWidth : available - checkedWidth,
          TodayCrewCard.groupHeight,
        ),
        Rect.fromLTWH(0, crewTop, space.maxWidth, expandedHeight),
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
