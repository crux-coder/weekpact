import 'package:flutter/material.dart';

import '../theme/weekpact_theme.dart';

/// A thin dashed outline that leaves its child's fill unchanged.
///
/// It traces the same continuous squircle the surfaces underneath it are
/// drawn with, so a dashed tile sits flush beside solid cards instead of
/// reading as a tighter, squarer shape.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    required this.color,
    this.radius = WeekPactMetrics.cardCurve,
  });
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DashedOutline(color, radius),
    child: child,
  );
}

class _DashedOutline extends CustomPainter {
  const _DashedOutline(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ).getOuterPath((Offset.zero & size).deflate(.5));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 9) {
        canvas.drawPath(metric.extractPath(offset, offset + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
