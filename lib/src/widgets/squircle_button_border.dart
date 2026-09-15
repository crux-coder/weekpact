import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps continuous corners from overlapping on compact button faces.
class SquircleButtonBorder extends ContinuousRectangleBorder {
  const SquircleButtonBorder({super.side});

  ContinuousRectangleBorder _fitted(Rect rect) => ContinuousRectangleBorder(
    side: side,
    borderRadius: BorderRadius.circular(math.min(24, rect.shortestSide / 2)),
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _fitted(rect).getOuterPath(rect, textDirection: textDirection);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _fitted(rect).getInnerPath(rect, textDirection: textDirection);

  @override
  SquircleButtonBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => SquircleButtonBorder(side: side ?? this.side);
}
