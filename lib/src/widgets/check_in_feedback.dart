import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A one-shot completion pop. Initial/restored check-ins stay still.
class CheckInFeedback extends StatefulWidget {
  const CheckInFeedback({
    super.key,
    required this.checked,
    required this.color,
    required this.child,
  });
  final bool checked;
  final Color color;
  final Widget child;
  @override
  State<CheckInFeedback> createState() => _CheckInFeedbackState();
}

class _CheckInFeedbackState extends State<CheckInFeedback>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.025,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.025,
        end: .99,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: .99,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
  ]).animate(_controller);
  @override
  void didUpdateWidget(covariant CheckInFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.checked &&
        widget.checked &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else if (!widget.checked) {
      _controller.reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _controller.reset();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => CustomPaint(
      foregroundPainter: _CompletionBurst(_controller.value, widget.color),
      child: Transform.scale(scale: _scale.value, child: child),
    ),
  );
}

class _CompletionBurst extends CustomPainter {
  const _CompletionBurst(this.progress, this.color);
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress) * .9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);

    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final radius =
          math.min(
            size.width / (2 * math.max(direction.dx.abs(), .001)),
            size.height / (2 * math.max(direction.dy.abs(), .001)),
          ) +
          2 +
          progress * 5;
      canvas.drawLine(
        center + direction * radius,
        center + direction * (radius + 4 * (1 - progress)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CompletionBurst oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
