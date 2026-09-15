import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Adds elastic edge drags to a card stack that clamps its own navigation.
class EdgeBounce extends StatefulWidget {
  const EdgeBounce({
    super.key,
    required this.atStart,
    required this.atEnd,
    required this.child,
  });

  final bool atStart;
  final bool atEnd;
  final Widget child;

  @override
  State<EdgeBounce> createState() => _EdgeBounceState();
}

class _EdgeBounceState extends State<EdgeBounce>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);
  int? _pointer;
  Offset _distance = Offset.zero;
  bool? _horizontal;
  bool _atStart = false;
  bool _atEnd = false;

  void _start(PointerDownEvent event) {
    if (_pointer != null) return;
    _offset.stop();
    _pointer = event.pointer;
    _distance = Offset.zero;
    _horizontal = null;
    _atStart = widget.atStart;
    _atEnd = widget.atEnd;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _distance += event.delta;
    if (_horizontal == null && _distance.distance > kTouchSlop) {
      _horizontal = _distance.dx.abs() > _distance.dy.abs();
    }
    if (_horizontal != true) return;
    final dx = _distance.dx;
    final beyondEdge =
        (dx > 0 && _atStart && widget.atStart) ||
        (dx < 0 && _atEnd && widget.atEnd);
    // Resistance increases with distance, limiting even very long pulls.
    _offset.value = beyondEdge
        ? dx.sign * 88 * (1 - math.exp(-dx.abs() / 220))
        : 0;
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (_offset.value == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = 0;
      return;
    }
    _offset.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 220, ratio: .75),
        _offset.value,
        0,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _start,
    onPointerMove: _move,
    onPointerUp: _release,
    onPointerCancel: _release,
    child: AnimatedBuilder(
      animation: _offset,
      child: widget.child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_offset.value, 0), child: child),
    ),
  );
}
